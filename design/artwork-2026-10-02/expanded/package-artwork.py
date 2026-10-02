"""Package generated alpha assets. Only crop transparent padding and resample."""
import json
from pathlib import Path
from PIL import Image

HERE = Path(__file__).resolve().parent.parent
CATALOG = HERE.parents[1] / "ios/Resources/Assets.xcassets"
for name in ("empty-schedule-flap-calendar-v1", "empty-saved-bookmark-frames-v1"):
    dest = CATALOG / f"{name}.imageset"
    dest.mkdir(parents=True, exist_ok=True)
    source = Image.open(HERE / "source" / f"{name}.png").convert("RGBA")
    box = source.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    assert box, "Generated asset must contain visible alpha"
    left, top, right, bottom = box
    art = source.crop((left - 20, top - 20, right + 20, bottom + 20))
    entries = [{"idiom": "universal", "scale": "1x"}]
    for scale in (2, 3):
        filename = f"{name}@{scale}x.png"
        output = art.copy()
        output.thumbnail((128 * scale, 100 * scale), Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", (128 * scale, 100 * scale))
        canvas.alpha_composite(output, ((canvas.width - output.width) // 2,
                                        (canvas.height - output.height) // 2))
        canvas.save(dest / filename, optimize=True)
        entries.append({"idiom": "universal", "scale": f"{scale}x", "filename": filename})
        print(filename, canvas.size, (dest / filename).stat().st_size)
    (dest / "Contents.json").write_text(json.dumps({"images": entries,
        "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
