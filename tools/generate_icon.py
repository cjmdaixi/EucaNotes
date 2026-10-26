from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "SynoApps" / "Assets.xcassets" / "AppIcon.appiconset"
OUT.mkdir(parents=True, exist_ok=True)
size = 1024
image = Image.new("RGB", (size, size), (231, 100, 56))
draw = ImageDraw.Draw(image)
# A quiet, code-drawn paper mark; no reference-app artwork is reused.
draw.rounded_rectangle((252, 208, 772, 816), radius=70, fill=(255, 251, 246))
draw.rounded_rectangle((334, 354, 690, 386), radius=16, fill=(231, 100, 56))
draw.rounded_rectangle((334, 478, 690, 510), radius=16, fill=(231, 100, 56))
draw.rounded_rectangle((334, 602, 586, 634), radius=16, fill=(231, 100, 56))
import json

icons = []
def add(idiom, points, scale, filename=None):
    pixels = round(points * scale)
    resized = image.resize((pixels, pixels), Image.Resampling.LANCZOS)
    name = filename or f"AppIcon-{points}@{scale}x.png"
    resized.save(OUT / name)
    icons.append({
        "filename": name,
        "idiom": idiom,
        "scale": f"{scale}x",
        "size": f"{points}x{points}"
    })

for points in [20, 29, 40, 60]:
    for scale in [2, 3]:
        add("iphone", points, scale)
for points, scales in [(20, [1, 2]), (29, [1, 2]), (40, [1, 2]), (76, [1, 2]), (83.5, [2])]:
    for scale in scales:
        add("ipad", points, scale)
image.save(OUT / "AppIcon-1024.png")
icons.append({"filename": "AppIcon-1024.png", "idiom": "ios-marketing", "scale": "1x", "size": "1024x1024"})
(OUT / "Contents.json").write_text(json.dumps({"images": icons, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n", encoding="utf-8")
print(f"Generated {len(icons)} icons in {OUT}")
