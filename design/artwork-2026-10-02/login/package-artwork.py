"""Crop transparent padding and resize the generated alpha, without semantic edits."""
import json
from pathlib import Path
from PIL import Image

HERE = Path(__file__).resolve().parent.parent
NAME = "login-cozy-viewing-nook-v2"
DEST = HERE.parents[1] / "ios/Resources/Assets.xcassets" / f"{NAME}.imageset"
DEST.mkdir(parents=True, exist_ok=True)
source = Image.open(HERE / "source" / f"{NAME}.png").convert("RGBA")
left, top, right, bottom = source.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
art = source.crop((left - 20, top - 20, right + 20, bottom + 20))
entries = [{"idiom": "universal", "scale": "1x"}]
for scale in (2, 3):
    name = f"{NAME}@{scale}x.png"
    output = art.copy()
    output.thumbnail((260 * scale, 156 * scale), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (260 * scale, 156 * scale))
    canvas.alpha_composite(output, ((canvas.width - output.width) // 2,
                                    (canvas.height - output.height) // 2))
    canvas.save(DEST / name, optimize=True)
    entries.append({"idiom": "universal", "scale": f"{scale}x", "filename": name})
    print(name, canvas.size, (DEST / name).stat().st_size)
(DEST / "Contents.json").write_text(json.dumps({"images": entries,
    "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
