"""Package the generated portrait background. Resize and JPEG encode only."""
import json
from pathlib import Path
from PIL import Image

HERE = Path(__file__).resolve().parent.parent
NAME = "login-cozy-backdrop-v3"
DEST = HERE.parents[1] / "ios/Resources/Assets.xcassets" / f"{NAME}.imageset"
DEST.mkdir(parents=True, exist_ok=True)
source = Image.open(HERE / "source" / f"{NAME}.png").convert("RGB")
entries = [{"idiom": "universal", "scale": "1x"}]
# One phone-sized decode per display scale; preserve portrait composition exactly.
for scale, max_width in ((2, 780), (3, 1170)):
    filename = f"{NAME}@{scale}x.jpg"
    output = source.copy()
    output.thumbnail((max_width, 2600), Image.Resampling.LANCZOS)
    output.save(DEST / filename, quality=90, optimize=True)
    entries.append({"idiom": "universal", "scale": f"{scale}x", "filename": filename})
    print(filename, output.size, (DEST / filename).stat().st_size)
(DEST / "Contents.json").write_text(json.dumps({"images": entries,
    "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
