#!/usr/bin/env python3
"""Build the bundled on-device embedding model ("PSM1" container).

Converts a Model2Vec *static embedding* checkpoint (``model.safetensors`` holding a single
``embeddings`` matrix + a BERT WordPiece ``tokenizer.json``) into one compact binary that the
pure-Dart ``neural_brain`` package can load without any native dependency.

Why int8? The float32 matrix of ``potion-base-8M`` is ~29 MB. Row-wise symmetric int8
quantisation brings it to ~7.5 MB while keeping cosine similarity to the float32 embedding
above 0.999 (verified at the end of this script).

Container layout (little endian)::

    0   4   magic  "PSM1"
    4   4   u32    header length N
    8   N   utf-8  JSON header (see below)
    ..  ..  pad    to a 4-byte boundary, then the sections named in header["sections"]:
                   vocab   utf-8 tokens separated by "\\n" (line index == token id)
                   scales  float32 x vocab_size (per-row dequantisation scale)
                   matrix  int8    x vocab_size * dim (row major)

Usage::

    pip install model2vec numpy safetensors
    python tool/build_static_model.py --src /path/to/potion-base-8M \
        --out assets/models/potion-base-8m.psm \
        --fixtures packages/neural_brain/test/fixtures/potion_reference.json

The model is MIT licensed (MinishLab/potion-base-8M, distilled from BAAI/bge-base-en-v1.5).
"""
from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

import numpy as np

FIXTURE_TEXTS = [
    "milk and eggs",
    "groceries",
    "Buy bread, pasta and tomatoes",
    "Remind me to call mom tomorrow at 5pm",
    "Dentist appointment Tuesday 4pm",
    "Idea: an app that reminds me to water plants",
    "Café crème brûlée recipe — très facile",
    "perché la città è così bella d'estate",
    "Meet at 5:30pm on 12/10/2026 (room #4)",
    "https://example.com/articles/neural-nets?ref=abc&x=1",
    "URGENT!!! Pay the electricity bill before Friday",
    "don't forget it's John's birthday",
    "state-of-the-art vector databases for on-device search",
    "你好 world 東京",
    "naïve Zoë fiancée Müller Ångström",
    "emoji 🚀 launch day 🎉",
    "x" * 130,
    "",
    "   \t\n  ",
    "Quarterly budget review with finance team",
    "Learn about neural networks and transformers",
    "Book flights to Lisbon for October",
    "Clean the apartment this weekend",
    "C++ / C# / F# & Rust: which one for the graph engine?",
    "100% sure; $5.99 + tax = 6.47",
    "a",
    "The quick brown fox jumps over the lazy dog. " * 6,
]


def quantize(emb: np.ndarray):
    scales = np.abs(emb).max(axis=1) / 127.0
    safe = np.where(scales == 0, 1.0, scales)
    q = np.clip(np.rint(emb / safe[:, None]), -127, 127).astype(np.int8)
    return q, scales.astype(np.float32)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, type=Path, help="Model2Vec checkpoint directory")
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--fixtures", type=Path, help="write a reference fixture for Dart parity tests")
    args = ap.parse_args()

    from model2vec import StaticModel
    from safetensors.numpy import load_file

    tensors = load_file(str(args.src / "model.safetensors"))
    emb = tensors["embeddings"].astype(np.float32)
    assert "weights" not in tensors and "mapping" not in tensors, "unsupported Model2Vec variant"
    vocab_size, dim = emb.shape

    tok = json.loads((args.src / "tokenizer.json").read_text(encoding="utf-8"))
    vocab_map = tok["model"]["vocab"]
    assert len(vocab_map) == vocab_size, (len(vocab_map), vocab_size)
    tokens = [None] * vocab_size
    for token, idx in vocab_map.items():
        tokens[idx] = token
    assert all(t is not None and "\n" not in t for t in tokens)
    norm = tok["normalizer"]
    cfg = json.loads((args.src / "config.json").read_text(encoding="utf-8"))

    q, scales = quantize(emb)
    vocab_blob = "\n".join(tokens).encode("utf-8")

    def pad4(n: int) -> int:
        return (4 - n % 4) % 4

    header = {
        "name": "potion-base-8M",
        "source": "https://huggingface.co/minishlab/potion-base-8M",
        "license": "MIT",
        "dim": dim,
        "vocab_size": vocab_size,
        "unk_id": vocab_map[tok["model"]["unk_token"]],
        "unk_token": tok["model"]["unk_token"],
        "continuing_prefix": tok["model"]["continuing_subword_prefix"],
        "max_chars_per_word": tok["model"]["max_input_chars_per_word"],
        "lowercase": bool(norm.get("lowercase", True)),
        "strip_accents": True if norm.get("strip_accents") is None else bool(norm["strip_accents"]),
        "handle_chinese_chars": bool(norm.get("handle_chinese_chars", True)),
        "normalize": bool(cfg.get("normalize", True)),
        "max_tokens": 512,
        "quant": "int8-rowscale",
    }
    # Two passes: section offsets depend on the header length, which depends on the offsets.
    header["sections"] = {"vocab": [0, 0], "scales": [0, 0], "matrix": [0, 0]}
    for _ in range(3):
        raw = json.dumps(header, separators=(",", ":")).encode("utf-8")
        cur = 8 + len(raw)
        cur += pad4(cur)
        sections = {}
        for name, blob_len in (("vocab", len(vocab_blob)), ("scales", scales.nbytes), ("matrix", q.nbytes)):
            sections[name] = [cur, blob_len]
            cur += blob_len
            cur += pad4(cur)
        if sections == header["sections"]:
            break
        header["sections"] = sections
    raw = json.dumps(header, separators=(",", ":")).encode("utf-8")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("wb") as f:
        f.write(b"PSM1")
        f.write(struct.pack("<I", len(raw)))
        f.write(raw)
        for name, blob in (("vocab", vocab_blob), ("scales", scales.tobytes()), ("matrix", q.tobytes())):
            off = header["sections"][name][0]
            f.write(b"\0" * (off - f.tell()))
            f.write(blob)
    print(f"wrote {args.out} ({args.out.stat().st_size/1e6:.2f} MB), dim={dim}, vocab={vocab_size}")

    # ---- quantisation quality check + Dart parity fixtures -------------------------------------
    ref = StaticModel.from_pretrained(str(args.src))
    deq = q.astype(np.float32) * scales[:, None]
    worst = 1.0
    fixtures = []
    for text in FIXTURE_TEXTS:
        ids = ref.tokenize([text])[0]  # UNK already removed, same as StaticModel.encode
        vec_f = ref.encode([text])[0]
        if ids:
            m = deq[ids].mean(axis=0)
            vec_q = m / (np.linalg.norm(m) + 1e-32)
        else:
            vec_q = np.zeros(dim, dtype=np.float32)
        if np.linalg.norm(vec_f) > 0:
            worst = min(worst, float(vec_f @ vec_q / (np.linalg.norm(vec_f) * np.linalg.norm(vec_q) + 1e-32)))
        fixtures.append({"text": text, "ids": [int(i) for i in ids],
                         "head": [round(float(x), 5) for x in vec_f[:16]],
                         "norm": round(float(np.linalg.norm(vec_f)), 5)})
    print(f"worst float32-vs-int8 cosine over fixtures: {worst:.5f}")
    assert worst > 0.998, "quantisation too lossy"
    if args.fixtures:
        args.fixtures.parent.mkdir(parents=True, exist_ok=True)
        args.fixtures.write_text(json.dumps({"model": header["name"], "dim": dim, "cases": fixtures},
                                            ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"wrote fixtures -> {args.fixtures} ({len(fixtures)} cases)")


if __name__ == "__main__":
    main()
