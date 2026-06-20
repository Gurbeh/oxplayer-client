#!/usr/bin/env python3
"""Export TV banner, notification, monochrome, launcher PNGs, and dev icon copies."""
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ICON_SVG = ROOT / "icons" / "oxplayer_icon.svg"
OUTLINE_SVG = ROOT / "icons" / "oxplayer_icon_outline.svg"
PROD = ROOT / "icons" / "production"
DEV = ROOT / "icons" / "development"
ANDROID_RES = ROOT / "android" / "app" / "src" / "main" / "res"
BRAND = "#210000"
BANNER_SIZE = (320, 180)
ICON_CANVAS = 1024
# Adaptive-icon safe zone: keep artwork inside the inner ~50% of the canvas.
ICON_PADDING = 256


def run_resvg(svg: Path, out: Path, *, fit_width: int | None = None) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    cmd = ["npx", "--yes", "@resvg/resvg-js-cli", str(svg), str(out)]
    if fit_width is not None:
        cmd.extend(["--fit-width", str(fit_width)])
    subprocess.run(cmd, cwd=ROOT, check=True, shell=True)


def render_rgba(svg: Path, fit_width: int | None = None) -> Image.Image:
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        tmp_path = Path(tmp.name)
    try:
        run_resvg(svg, tmp_path, fit_width=fit_width)
        return Image.open(tmp_path).convert("RGBA")
    finally:
        tmp_path.unlink(missing_ok=True)


def repad_icon(img: Image.Image, padding: int = ICON_PADDING) -> Image.Image:
    """Center artwork with side padding so adaptive launcher icons are not cropped."""
    size = img.width
    alpha = img.split()[3]
    bbox = alpha.getbbox()
    if not bbox:
        return img

    cropped = img.crop(bbox)
    inner = size - 2 * padding
    cw, ch = cropped.size
    scale = min(inner / cw, inner / ch)
    nw = max(1, round(cw * scale))
    nh = max(1, round(ch * scale))
    resized = cropped.resize((nw, nh), Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(resized, ((size - nw) // 2, (size - nh) // 2), resized)
    return canvas


def launcher_icon(svg: Path, padding: int = ICON_PADDING) -> Image.Image:
    return repad_icon(render_rgba(svg), padding)


def save_launcher_icon(svg: Path, out: Path, width: int) -> None:
    icon = launcher_icon(svg)
    if width != ICON_CANVAS:
        icon = icon.resize((width, width), Image.Resampling.LANCZOS)
    out.parent.mkdir(parents=True, exist_ok=True)
    icon.save(out, "PNG")
    print(f"wrote {out.relative_to(ROOT)}")


def white_silhouette(img: Image.Image) -> Image.Image:
    alpha = img.split()[3]
    white = Image.new("RGBA", img.size, (255, 255, 255, 255))
    white.putalpha(alpha)
    return white


def tv_banner() -> None:
    logo = launcher_icon(ICON_SVG, padding=72).resize((140, 140), Image.Resampling.LANCZOS)
    banner = Image.new("RGBA", BANNER_SIZE, BRAND)
    x = (BANNER_SIZE[0] - logo.width) // 2
    y = (BANNER_SIZE[1] - logo.height) // 2
    banner.paste(logo, (x, y), logo)
    out = ANDROID_RES / "drawable-nodpi" / "app_banner.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    banner.save(out, "PNG")
    print(f"wrote {out.relative_to(ROOT)}")


def monochrome_adaptive() -> None:
    img = repad_icon(render_rgba(OUTLINE_SVG))
    out = PROD / "oxplayer_adaptive_icon.png"
    white_silhouette(img).save(out, "PNG")
    print(f"wrote {out.relative_to(ROOT)}")


def notification_master() -> None:
    img = render_rgba(OUTLINE_SVG, fit_width=192)
    out = ROOT / "icons" / "oxplayer_notification_icon.png"
    white_silhouette(img).save(out, "PNG")
    print(f"wrote {out.relative_to(ROOT)}")


def production_launcher_pngs() -> None:
    exports = [
        ("oxplayer_icon.png", ICON_CANVAS),
        ("oxplayer_macos_icon.png", ICON_CANVAS),
        ("oxplayer_icon_512.png", 512),
        ("oxplayer_icon_desktop.png", 512),
        ("oxplayer_store_icon.png", 512),
    ]
    for name, width in exports:
        save_launcher_icon(ICON_SVG, PROD / name, width)


def sync_dev_icons() -> None:
    DEV.mkdir(parents=True, exist_ok=True)
    names = [
        "oxplayer_icon.png",
        "oxplayer_icon_512.png",
        "oxplayer_icon_desktop.png",
        "oxplayer_macos_icon.png",
        "oxplayer_store_icon.png",
        "oxplayer_adaptive_icon.png",
    ]
    for name in names:
        src = PROD / name
        if src.exists():
            shutil.copy2(src, DEV / name)
    print(f"synced {len(names)} files to icons/development/")


def main() -> None:
    if not ICON_SVG.exists():
        sys.exit(f"missing {ICON_SVG}")
    production_launcher_pngs()
    monochrome_adaptive()
    notification_master()
    tv_banner()
    sync_dev_icons()
    print("done")


if __name__ == "__main__":
    main()
