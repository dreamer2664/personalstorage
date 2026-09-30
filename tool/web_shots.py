#!/usr/bin/env python3
"""Drive the Flutter *web* build in headless Chromium and capture screenshots of key flows.

Usage:  python tool/web_shots.py [--url http://127.0.0.1:8080] [--out docs/screenshots] [--dark]

Flutter paints into a canvas, so the script turns on Flutter's accessibility semantics and
clicks widgets *by label* (the same labels a screen reader announces). The graph canvas has no
semantics; it is driven with the mouse. Requires: `pip install playwright` and a Chromium binary.
"""
import argparse
import asyncio
import pathlib

from playwright.async_api import async_playwright

CHROMIUM = "/usr/bin/chromium"
W, H = 390, 844


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8080")
    ap.add_argument("--out", default="docs/screenshots")
    ap.add_argument("--dark", action="store_true")
    ap.add_argument("--steps", default="all", help="comma list: capture,library,search,tasks,detail,graph,settings")
    args = ap.parse_args()
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    suffix = "-dark" if args.dark else ""
    steps = set(args.steps.split(",")) if args.steps != "all" else {"capture", "library", "search", "tasks", "detail", "graph", "settings"}

    async with async_playwright() as p:
        browser = await p.chromium.launch(executable_path=CHROMIUM, headless=True, args=[
            "--no-sandbox", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
            "--ignore-gpu-blocklist", "--enable-webgl", "--disable-dev-shm-usage"])
        ctx = await browser.new_context(viewport={"width": W, "height": H}, device_scale_factor=2,
                                        color_scheme="dark" if args.dark else "light", locale="en-US")
        page = await ctx.new_page()
        logs = []
        page.on("console", lambda m: logs.append(f"[{m.type}] {m.text}"))
        page.on("pageerror", lambda e: logs.append(f"[pageerror] {e}"))

        async def shot(name):
            await page.screenshot(path=str(out / f"{name}{suffix}.png"))
            print("saved", name + suffix, flush=True)

        async def tap(text, nth=0, wait=900):
            loc = page.locator('flt-semantics[role="button"]').filter(has_text=text)
            await loc.nth(nth).click(timeout=8000)
            await page.wait_for_timeout(wait)

        async def tap_xy(x, y, wait=700):
            await page.mouse.click(x, y)
            await page.wait_for_timeout(wait)

        async def focus_field():
            # the composer / search field: click its semantics node or fall back to a coordinate
            await page.wait_for_timeout(200)

        async def step(name, fn):
            try:
                await fn()
            except Exception as e:  # keep going: a failed step must not hide the others
                print(f"!! step {name} failed: {type(e).__name__}: {str(e)[:160]}", flush=True)

        await page.goto(args.url)
        await page.wait_for_timeout(8000)
        await page.evaluate("() => { const p = document.querySelector('flt-semantics-placeholder'); if (p) p.click(); }")
        await page.wait_for_timeout(1200)

        async def capture_flow_after():
            await tap("Capture", wait=1200)
            await page.keyboard.type("Remind me to call mom tomorrow at 5pm", delay=6)
            await page.wait_for_timeout(900)
            await shot("01-capture-insights")
            await tap("Save note", wait=700)
            await shot("02-capture-saved-toast")
            await page.keyboard.type("Buy bread, pasta and tomatoes", delay=6)
            await page.wait_for_timeout(700)
            await shot("03-capture-checklist")
            await tap("Save note", wait=900)
            await page.keyboard.type("milk and eggs", delay=6)
            await page.wait_for_timeout(700)
            await shot("04-capture-suggestion")
            await tap("Save note", wait=900)

        async def library_flow():
            await tap("Library", wait=1200)
            await shot("05-library-notes")

        async def samples_flow():
            # Empty library -> "Try with sample notes" fills it with the demo corpus.
            await tap("Library", wait=1200)
            await shot("05-library-empty")
            await tap("Try with sample notes", wait=11000)
            await shot("07-library-samples")

        async def search_flow():
            await tap("Library", wait=1000)
            await tap_xy(195, 101, wait=500)          # the search field
            await page.keyboard.type("groceries", delay=30)
            await page.wait_for_timeout(2000)
            await shot("08-search-groceries")
            await page.keyboard.press("Control+A")
            await page.keyboard.type("trip", delay=30)
            await page.wait_for_timeout(2000)
            await shot("09-search-trip")
            await page.keyboard.press("Control+A")
            await page.keyboard.type("spesa", delay=30)
            await page.wait_for_timeout(2000)
            await shot("10-search-spesa-italian")

        async def tasks_flow():
            await tap("Tasks", wait=1200)
            await shot("11-tasks")

        async def detail_flow():
            await tap("Library", wait=900)
            await tap_xy(195, 101, wait=500)
            await page.keyboard.press("Control+A")
            await page.keyboard.type("lisbon", delay=30)
            await page.wait_for_timeout(2000)
            await page.locator('flt-semantics[role="button"]').filter(has_text="Lisbon itinerary").first.click(timeout=8000)
            await page.wait_for_timeout(1800)
            await shot("12-note-detail")
            await page.mouse.move(195, 500)
            await page.mouse.wheel(0, 650)
            await page.wait_for_timeout(900)
            await shot("13-note-detail-related")
            await tap("Show in graph", wait=4500)

        async def graph_flow():
            await shot("14-graph-selected")
            await tap_xy(195, 352, wait=800)           # tap the focused node again: selection card stays
            await tap("Fit to screen", wait=2500)
            await shot("15-graph-overview")
            await page.mouse.move(195, 420)
            for _ in range(4):
                await page.mouse.wheel(0, -120)
                await page.wait_for_timeout(120)
            await page.wait_for_timeout(700)
            await shot("16-graph-zoomed")
            await page.mouse.move(250, 500)
            await page.mouse.down()
            await page.mouse.move(150, 420, steps=8)
            await page.mouse.up()
            await page.wait_for_timeout(900)
            await shot("17-graph-panned")

        async def settings_flow():
            await tap("Library", wait=900)
            await tap("Settings", wait=1200)
            await shot("18-settings")
            await page.mouse.move(195, 500)
            await page.mouse.wheel(0, 700)
            await page.wait_for_timeout(800)
            await shot("19-settings-scrolled")

        if "library" in steps:
            await step("samples", samples_flow)
        if "search" in steps:
            await step("search", search_flow)
        if "tasks" in steps:
            await step("tasks", tasks_flow)
        if "detail" in steps:
            await step("detail", detail_flow)
        if "graph" in steps:
            await step("graph", graph_flow)
        if "capture" in steps:
            await step("capture", capture_flow_after)
        if "settings" in steps:
            await step("settings", settings_flow)

        errors = [l for l in logs if "error" in l.lower() or "exception" in l.lower()]
        print("\nconsole errors:", len(errors))
        for e in errors[:10]:
            print("  ", e[:220])
        await browser.close()


asyncio.run(main())
