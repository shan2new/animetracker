"""Arrange exact native screenshots for visual review; does not repaint any app UI."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"
REGULAR = ImageFont.truetype(FONT, 19)
SMALL = ImageFont.truetype(FONT, 15)
BOLD = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 21)

def board(items, columns, width, name):
    shot_h = round(width * 800 / 369)
    gap, header, foot, top = 22, 84, 16, 70
    rows = (len(items) + columns - 1) // columns
    canvas = Image.new("RGB", (gap + columns * (width + gap), top + rows * (header + shot_h + foot)), "#171719")
    draw = ImageDraw.Draw(canvas)
    draw.text((gap, 22), name, font=BOLD, fill="#F5F2EA")
    for i, (file, title, note) in enumerate(items):
        x = gap + (i % columns) * (width + gap)
        y = top + (i // columns) * (header + shot_h + foot)
        draw.text((x, y), title, font=REGULAR, fill="#F5F2EA")
        draw.text((x, y + 29), note, font=SMALL, fill="#B5B1AA")
        shot = Image.open(HERE / file)
        shot = shot.resize((width, shot_h), Image.Resampling.LANCZOS)
        canvas.paste(shot, (x, y + header))
    return canvas

board([
    ("01-library-empty-before.jpg", "Before", "Existing empty Library"),
    ("12-library-empty-after.jpg", "After", "Small original illustration"),
], 2, 369, "Previously. — native Library example").save(HERE / "library-before-after.jpg", quality=94)

board([
    ("12-library-empty-after.jpg", "Previous direction", "Cream cards and fabric"),
    ("15-library-flap-v2.jpg", "Theme revision", "Graphite split-flap panels"),
], 2, 369, "Previously. — artwork theme revision").save(HERE / "library-theme-v2.jpg", quality=94)

board([
    ("01-library-empty-before.jpg", "Original Library", "Existing stack glyph"),
    ("15-library-flap-v2.jpg", "Current local example", "Small cinema-frame illustration"),
], 2, 369, "Previously. — current native Library example").save(HERE / "library-native-v2.jpg", quality=94)

board([
    ("01-library-empty-before.jpg", "1. Empty Library", "Best fit — implemented"),
    ("02-schedule-empty-before.jpg", "2. Empty Schedule", "Secondary — small cue only"),
    ("03-home-empty.jpg", "3. Empty Home", "Optional — smaller, quieter"),
    ("04-home-populated.jpg", "4. Home with shows", "Show artwork already fills it"),
    ("05-library-populated.jpg", "5. Library with shows", "Shelves already carry character"),
    ("06-schedule-populated.jpg", "6. Schedule with shows", "Existing hero owns the moment"),
    ("07-feed.jpg", "7. Feed", "Let posts keep attention"),
    ("09-discover.jpg", "8. Discover", "Keep browsing focused"),
    ("08-profile.jpg", "9. Profile", "Own library art is personal"),
    ("10-discover-genres.jpg", "10. Genres", "Existing art already abundant"),
    ("11-show-detail.jpg", "11. Show detail", "Artwork belongs to the show"),
    ("13-library-accessibility.jpg", "12. Larger text", "Simpler layout; art omitted"),
], 3, 260, "Previously. — visual artwork scout").save(HERE / "screen-scout.jpg", quality=94)
