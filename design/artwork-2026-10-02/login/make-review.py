"""Arrange exact native screenshots. Labels remain outside app UI."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
FONT = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 22)
SMALL = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 17)

def board(items, title, name):
    gap, width, height, top = 22, 369, 800, 126
    canvas = Image.new("RGB", (gap + len(items) * (width + gap), top + height + gap), "#171719")
    draw = ImageDraw.Draw(canvas)
    draw.text((gap, 20), title, font=FONT, fill="#F4F1EC")
    for i, (path, label, note) in enumerate(items):
        x = gap + i * (width + gap)
        draw.text((x, 61), label, font=FONT, fill="#F4F1EC")
        draw.text((x, 94), note, font=SMALL, fill="#AAA6A0")
        canvas.paste(Image.open(HERE / path), (x, top))
    canvas.save(HERE / name, quality=94)

board([
    ("03-welcome-after.jpg", "Previous direction", "Graphite product sculpture"),
    ("05-welcome-cozy-v2.jpg", "Cozy revision", "Soft textures and warm lamplight"),
], "Previously. — welcome artwork revision", "welcome-v1-v2.jpg")
board([
    ("01-welcome-before.jpg", "Before", "Brand and sign-in action"),
    ("05-welcome-cozy-v2.jpg", "Current local welcome", "A little home for your shows"),
], "Previously. — native welcome before and after", "welcome-before-after.jpg")
board([
    ("05-welcome-cozy-v2.jpg", "1. Welcome", "Quiet artwork belongs here"),
    ("04-provider-current-mark.jpg", "2. Credential sheet", "Current P. mark; focused forms"),
    ("06-welcome-accessibility.jpg", "3. Larger text", "Art omitted; action stays visible"),
], "Previously. — public login surfaces", "login-flow.jpg")

board([
    ("05-welcome-cozy-v2.jpg", "Inline illustration", "Previous cozy treatment"),
    ("08-welcome-backdrop.jpg", "Room backdrop", "Current native welcome"),
], "Previously. — cozy background placement", "welcome-backdrop-comparison.jpg")
board([
    ("08-welcome-backdrop.jpg", "Ordinary text", "Brand and action over the room"),
    ("09-backdrop-accessibility.jpg", "Larger text", "Additional dimming behind the words"),
], "Previously. — backdrop text checks", "backdrop-text-checks.jpg")
