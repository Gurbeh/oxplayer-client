#!/usr/bin/env python3
"""Normalize logo (2).svg to 1024x1024 with ~200px padding."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "logo (2).svg"
OUT_ICON = ROOT / "icons" / "oxplayer_icon.svg"
OUT_OUTLINE = ROOT / "icons" / "oxplayer_icon_outline.svg"
CANVAS = 1024
PADDING = 200
SAFE = CANVAS - 2 * PADDING  # 624


def parse_path_bbox(d: str) -> tuple[float, float, float, float]:
    coords: list[tuple[float, float]] = []
    tokens = re.findall(r"[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d*\.\d+|\d+)", d)
    i = 0
    cmd = None
    cx = cy = sx = sy = 0.0
    while i < len(tokens):
        t = tokens[i]
        if re.match(r"^[A-Za-z]$", t):
            cmd = t
            if cmd in ("Z", "z"):
                cx, cy = sx, sy
            i += 1
            continue
        if cmd in ("M", "m"):
            x, y = float(tokens[i]), float(tokens[i + 1])
            if cmd == "m":
                x += cx
                y += cy
            cx = cy = sx = sy = x, y
            coords.append((x, y))
            i += 2
            cmd = "L" if cmd == "M" else "l"
        elif cmd in ("L", "l"):
            x, y = float(tokens[i]), float(tokens[i + 1])
            if cmd == "l":
                x += cx
                y += cy
            cx, cy = x, y
            coords.append((x, y))
            i += 2
        elif cmd in ("H", "h"):
            x = float(tokens[i]) + (cx if cmd == "h" else 0)
            cx = x
            coords.append((x, cy))
            i += 1
        elif cmd in ("V", "v"):
            y = float(tokens[i]) + (cy if cmd == "v" else 0)
            cy = y
            coords.append((cx, y))
            i += 1
        else:
            i += 1
    xs = [p[0] for p in coords]
    ys = [p[1] for p in coords]
    return min(xs), min(ys), max(xs), max(ys)


def main() -> None:
    src_path = Path(sys.argv[1]) if len(sys.argv) > 1 else SRC
    svg = src_path.read_text(encoding="utf-8")

    paths = re.findall(
        r'(<path\b[^>]*\bd="([^"]+)"[^>]*/>)',
        svg,
        flags=re.DOTALL,
    )
    if not paths:
        raise SystemExit("no paths found")

    bboxes = [parse_path_bbox(d) for _, d in paths]
    min_x = min(b[0] for b in bboxes)
    min_y = min(b[1] for b in bboxes)
    max_x = max(b[2] for b in bboxes)
    max_y = max(b[3] for b in bboxes)
    cw, ch = max_x - min_x, max_y - min_y
    cx, cy = (min_x + max_x) / 2, (min_y + max_y) / 2
    scale = SAFE / max(cw, ch)

    body = re.sub(r"^<svg[^>]*>|</svg>\s*$", "", svg.strip(), flags=re.DOTALL)
    # Strip outer svg only — keep defs + paths
    transform = (
        f'transform="translate({CANVAS / 2:.6f} {CANVAS / 2:.6f}) '
        f"scale({scale:.6f}) translate({-cx:.6f} {-cy:.6f})\""
    )

    colored = (
        f'<svg width="{CANVAS}" height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}" '
        f'fill="none" xmlns="http://www.w3.org/2000/svg">\n'
        f"<g {transform}>\n{body}\n</g>\n</svg>\n"
    )

    outline_body = body
    outline_body = re.sub(r'fill="url\([^"]+\)"', 'fill="#000000"', outline_body)
    outline_body = re.sub(r'fill="#[0-9A-Fa-f]+"', 'fill="#000000"', outline_body)
    outline_body = re.sub(r"<defs>.*?</defs>\s*", "", outline_body, flags=re.DOTALL)

    outline = (
        f'<svg width="{CANVAS}" height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}" '
        f'fill="none" xmlns="http://www.w3.org/2000/svg">\n'
        f"<g {transform}>\n{outline_body}\n</g>\n</svg>\n"
    )

    OUT_ICON.write_text(colored, encoding="utf-8")
    OUT_OUTLINE.write_text(outline, encoding="utf-8")

    # Verify padding on transformed bbox
    pad_l = CANVAS / 2 - (cx - min_x) * scale
    pad_r = CANVAS / 2 - (max_x - cx) * scale
    pad_t = CANVAS / 2 - (cy - min_y) * scale
    pad_b = CANVAS / 2 - (max_y - cy) * scale
    print(f"wrote {OUT_ICON.name} and {OUT_OUTLINE.name}")
    print(f"scale={scale:.4f}  content={cw * scale:.1f}x{ch * scale:.1f}")
    print(f"padding L/R/T/B: {pad_l:.0f} / {pad_r:.0f} / {pad_t:.0f} / {pad_b:.0f}")


if __name__ == "__main__":
    main()
