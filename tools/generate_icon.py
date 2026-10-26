from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "SynoApps" / "Assets.xcassets" / "AppIcon.appiconset"
OUT.mkdir(parents=True, exist_ok=True)
size = 1024
image = Image.new("RGB", (size, size), (64, 122, 99))
draw = ImageDraw.Draw(image)
# An original diary-card mark; no reference-app artwork is reused.
draw.rounded_rectangle((224, 154, 800, 870), radius=92, fill=(244, 241, 224))
draw.rounded_rectangle((224, 154, 800, 348), radius=92, fill=(219, 229, 205))
draw.rectangle((224, 256, 800, 348), fill=(219, 229, 205))
draw.ellipse((326, 410, 544, 628), fill=(174, 196, 158))
draw.polygon([(366, 692), (690, 452), (690, 692)], fill=(100, 145, 114))
draw.polygon([(294, 692), (526, 520), (690, 692)], fill=(132, 166, 126))
draw.rounded_rectangle((326, 748, 698, 784), radius=18, fill=(64, 122, 99))
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
