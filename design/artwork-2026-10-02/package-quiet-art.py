"""Package the selected generated asset with its alpha; only crop padding and resample."""
import json
from pathlib import Path
from PIL import Image

HERE = Path(__file__).resolve().parent
NAME = "empty-library-episode-frames-v2"
DEST = HERE.parents[1] / "ios/Resources/Assets.xcassets" / f"{NAME}.imageset"
DEST.mkdir(parents=True, exist_ok=True)
source = Image.open(HERE / "source" / f"{NAME}.png").convert("RGBA")
# Ignore isolated near-transparent pixels when measuring padding; keep the generated alpha.
left, top, right, bottom = source.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
art = source.crop((left - 20, top - 20, right + 20, bottom + 20))
entries = [{"idiom": "universal", "scale": "1x"}]
for scale in (2, 3):
    filename = f"{NAME}@{scale}x.png"
    output = art.copy()
    output.thumbnail((128 * scale, 100 * scale), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (128 * scale, 100 * scale))
    canvas.alpha_composite(output, ((canvas.width - output.width) // 2, (canvas.height - output.height) // 2))
    canvas.save(DEST / filename, optimize=True)
    entries.append({"idiom": "universal", "scale": f"{scale}x", "filename": filename})
    print(filename, canvas.size, (DEST / filename).stat().st_size)
(DEST / "Contents.json").write_text(json.dumps({"images": entries, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
