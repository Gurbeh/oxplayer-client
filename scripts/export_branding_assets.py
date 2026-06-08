#!/usr/bin/env python3
"""Export TV banner, notification, monochrome, and dev icon copies from master SVGs."""
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


def run_resvg(svg: Path, out: Path, width: int, height: int | None = None) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    cmd = ["npx", "--yes", "@resvg/resvg-js-cli", str(svg), str(out), "--fit-width", str(width)]
    if height is not None:
        cmd.extend(["--fit-height", str(height)])
    subprocess.run(cmd, cwd=ROOT, check=True, shell=True)


def render_rgba(svg: Path, width: int) -> Image.Image:
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        tmp_path = Path(tmp.name)
    try:
        run_resvg(svg, tmp_path, width)
        return Image.open(tmp_path).convert("RGBA")
    finally:
        tmp_path.unlink(missing_ok=True)


def white_silhouette(img: Image.Image) -> Image.Image:
    alpha = img.split()[3]
    white = Image.new("RGBA", img.size, (255, 255, 255, 255))
    white.putalpha(alpha)
    return white


def tv_banner() -> None:
    logo = render_rgba(ICON_SVG, 140)
    banner = Image.new("RGBA", BANNER_SIZE, BRAND)
    x = (BANNER_SIZE[0] - logo.width) // 2
    y = (BANNER_SIZE[1] - logo.height) // 2
    banner.paste(logo, (x, y), logo)
    out = ANDROID_RES / "drawable-nodpi" / "app_banner.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    banner.save(out, "PNG")
    print(f"wrote {out.relative_to(ROOT)}")


def monochrome_adaptive() -> None:
    img = render_rgba(OUTLINE_SVG, 1024)
    out = PROD / "oxplayer_adaptive_icon.png"
    white_silhouette(img).save(out, "PNG")
    print(f"wrote {out.relative_to(ROOT)}")


def notification_master() -> None:
    img = render_rgba(OUTLINE_SVG, 192)
    out = ROOT / "icons" / "oxplayer_notification_icon.png"
    white_silhouette(img).save(out, "PNG")
    print(f"wrote {out.relative_to(ROOT)}")


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


def regen_macos_if_needed() -> None:
    mac = PROD / "oxplayer_macos_icon.png"
    if not mac.exists() or mac.stat().st_size > 400_000:
        run_resvg(ICON_SVG, mac, 1024)
        print(f"wrote {mac.relative_to(ROOT)}")


def main() -> None:
    if not ICON_SVG.exists():
        sys.exit(f"missing {ICON_SVG}")
    regen_macos_if_needed()
    monochrome_adaptive()
    notification_master()
    tv_banner()
    sync_dev_icons()
    print("done")


if __name__ == "__main__":
    main()
