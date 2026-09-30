# Knowledge graph

An Obsidian-style, force-directed graph where **notes are nodes** and **the brain draws the edges**.

## Data

| Element | Source |
|---|---|
| Node | one per live note; radius from priority, pinned state and degree; colour from the category |
| Edge | AI relatedness (see [AI_ENGINE.md](AI_ENGINE.md#5-related-notes-and-graph-edges)) stored in the `edges` table with a human-readable *reason*; optional tag-hub edges (`#tag` nodes) |
| Cluster | weighted **label propagation** over the edges; named after the dominant tag's ontology concept (e.g. "Clients & sales") or the dominant category |

`GraphBuilder` is pure Dart: it de-duplicates edges, applies the strength threshold, optionally adds tag
hubs, detects communities (deterministic: seeded visiting order, ties break towards the smaller label) and
labels them.

## Layout: Barnes-Hut force simulation

`ForceLayout` keeps positions, velocities and forces in flat `Float64List`s, so a tick allocates nothing.

* **Repulsion**: Barnes-Hut quadtree over arrays (`theta = 0.9`), inverse-square with softening, plus a
  short-range collision push so nodes don't overlap.
* **Springs**: rest length `74·(1.5 - 0.9·weight) + radii - 8`, stiffness scaled by weight and biased by degree
  (hubs stay put, leaves move) like d3-force.
* **Gravity** towards the origin and towards the node's **cluster centroid**, which is what visually groups ideas.
* **Cooling** (`alpha`) with reheating on interaction; the simulation **sleeps** when settled, so an idle graph
  costs no battery. Initial positions are a golden-angle phyllotaxis per cluster, so the first frame is
  already readable, and a pre-warm of 70 ticks runs before it is shown.
* Refreshing data keeps the positions of existing nodes - adding a note doesn't shake the picture.

Measured: **~1.1 ms per tick for 1,000 nodes / 2,000 edges** (VM, JIT) against a 16 ms frame.
Tests check: no NaN, linked nodes end up closer than unlinked ones, clusters separate, nodes don't overlap,
determinism for a seed, pinned nodes stay, Barnes-Hut stays inside the frame budget.

## Rendering

`GraphPainter` is a `CustomPainter` whose `repaint:` listenable is the controller - a tick repaints the
canvas **without rebuilding any widget**.

* Edges are batched into three `drawRawPoints` calls by strength plus one for highlighted edges.
* Off-screen nodes are culled; label `TextPainter`s are laid out once and cached; `Paint` objects are reused.
* **Level of detail**: zoomed out, cluster "islands" (name pills) and only hub labels are shown; zoomed in,
  more labels appear. Labels are placed greedily in priority order (cluster pills, selection and its
  neighbours, hubs, the rest) and **skipped if they would overlap** an already placed one.
* Selecting a node focuses the picture: its neighbourhood stays bright, everything else dims, incident
  edges turn accent-blue.

## Interaction

| Gesture | Result |
|---|---|
| Pinch | zoom around the focal point (0.12x - 6x) |
| Drag on empty space | pan, with inertia (exponential friction) |
| Drag a node | moves and **pins** it while the simulation stays live, so neighbours follow; released on lift |
| Tap a node | select + bottom card with snippet, tags, link count, **Open** |
| Tap a cluster pill | sheet listing the ideas in that cluster (open / focus each) |
| Double tap | animated zoom in |
| Trackpad / wheel | zoom (web and desktop) |
| "Show in graph" (note detail) | selects and frames that note |
| **Links** slider | connection strength threshold (rebuilds clusters live); `#` toggles tag hubs; target button fits everything |

The camera is a critically damped follower (`1 - exp(-dt·9)`), so every move eases in and out.
