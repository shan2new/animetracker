"""Package the four original Image Gen outputs; no colour grade or semantic edits.

Run from any directory. Only writes the four versioned imagesets, retaining the
previous genre artwork. The broad icon/genres importer removes absent sources,
so it must not be used for this partial collection.
"""
import json
from pathlib import Path
from PIL import Image, ImageOps

HERE = Path(__file__).resolve().parent
DEST = HERE / "imagesets"

for key in ("adventure", "drama"):
    for flavour in ("anime", "tv"):
        name = f"genre-{key}-{flavour}-cinematic-v1"
        folder = DEST / f"{name}.imageset"
        folder.mkdir(parents=True, exist_ok=True)
        image = Image.open(HERE / "source" / f"{key}-{flavour}.png").convert("RGB")
        entries = [{"idiom": "universal", "scale": "1x"}]
        for scale in (2, 3):
            filename = f"{name}@{scale}x.jpg"
            ImageOps.fit(image, (240 * scale, 135 * scale), method=Image.Resampling.LANCZOS).save(
                folder / filename, quality=92, optimize=True, subsampling=0
            )
            entries.append({"idiom": "universal", "scale": f"{scale}x", "filename": filename})
        (folder / "Contents.json").write_text(json.dumps({
            "images": entries, "info": {"author": "xcode", "version": 1}
        }, indent=2) + "\n")
        print(name)
