"""Arrange exact native captures; labels sit outside UI. No UI repainting."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
SCOUT = HERE.parent / "scout"
TITLE = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 22)
SMALL = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 17)

def board(items, columns, width, name, output):
    gap, top, header, foot = 20, 62, 68, 18
    height = round(width * 800 / 369)
    rows = (len(items) + columns - 1) // columns
    canvas = Image.new("RGB", (gap + columns * (width + gap),
        top + rows * (header + height + foot)), "#171719")
    draw = ImageDraw.Draw(canvas)
    draw.text((gap, 20), name, font=TITLE, fill="#F4F1EC")
    for i, (path, title, note) in enumerate(items):
        x = gap + i % columns * (width + gap)
        y = top + i // columns * (header + height + foot)
        draw.text((x, y), title, font=TITLE, fill="#F4F1EC")
        draw.text((x, y + 30), note, font=SMALL, fill="#AAA6A0")
        image = Image.open(path).resize((width, height), Image.Resampling.LANCZOS)
        canvas.paste(image, (x, y + header))
    canvas.save(HERE / output, quality=94)

examples = [
    (HERE / "06-library-current.jpg", "Library", "Graphite episode frames"),
    (HERE / "03-schedule-after.jpg", "Schedule", "A quiet flip calendar"),
    (HERE / "04-saved-after.jpg", "Saved", "Bookmark keepsakes"),
]
board(examples, 3, 369, "Previously. — three real native examples", "native-examples.jpg")
board([
    (SCOUT / "01-library-empty-before.jpg", "Library — before", "Existing stack glyph"),
    (SCOUT / "02-schedule-empty-before.jpg", "Schedule — before", "Existing calendar glyph"),
    (HERE / "01-saved-empty-before.jpg", "Saved — before", "Existing bookmark glyph"),
] + examples, 3, 300, "Previously. — native before and after", "native-before-after.jpg")
board([
    (SCOUT / "03-home-empty.jpg", "Home — first use", "Optional smaller viewing cue"),
    (HERE / "02-activity-empty-before.jpg", "Activity", "Candidate quiet bell / signal"),
    (SCOUT / "04-home-populated.jpg", "Home — with shows", "Show art already supplies immersion"),
    (SCOUT / "05-library-populated.jpg", "Library — with shows", "Keep personal covers prominent"),
    (SCOUT / "06-schedule-populated.jpg", "Schedule — with shows", "Keep the premiere hero clear"),
    (SCOUT / "07-feed.jpg", "Feed", "Let posts hold the attention"),
    (SCOUT / "09-discover.jpg", "Discover", "Posters already carry the page"),
    (SCOUT / "10-discover-genres.jpg", "Genres", "Existing original art is sufficient"),
    (SCOUT / "08-profile.jpg", "Profile", "Own library is the personal character"),
    (SCOUT / "11-show-detail.jpg", "Show detail", "Respect the show's identity"),
    (HERE / "05-schedule-accessibility.jpg", "Accessibility text", "Glyph fallback keeps the action visible"),
], 3, 260, "Previously. — broader placement scout", "broader-scout.jpg")
