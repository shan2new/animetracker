# Genre art — Discover's Apple Music tiles

Discover → Genres draws Apple Music's Browse tiles (`ios/Sources/Features/Discover/DiscoverGenres.swift`):
16:9, the picture full-bleed and graded into ONE colour, the genre's name in white at the bottom-left.
Each genre has an **anime** picture (an illustration), a **TV** picture (a photograph), or both,
and the app shows the one that fits the viewer: the Anime scope shows anime art, the TV scope TV
art, and All shows the viewer's leaning (anime until the personalisation toggle exists).

## The job

Generate the **31 images** below and save each as

```
icon/genres/src/anime/<key>.png      e.g. icon/genres/src/anime/slice-of-life.png
icon/genres/src/tv/<key>.png         e.g. icon/genres/src/tv/crime.png
```

then run

```bash
python3 icon/genres/import.py
```

It crops to 16:9, **grades every picture into its genre's colour** (a duotone, the way Apple Music
treats its photos — you do not choose colours; they live in `GENRES` in `import.py`, shared by a
genre's two pictures), writes the asset catalogue, reports what is missing, and draws a preview of
the tiles as the app draws them: `icon/genres/sheet-anime.png` and `icon/genres/sheet-tv.png`.
**Look at the sheets.** Please do not edit Swift files.

What is in `src/` now is the first, square generation, centre-cropped as a stopgap: replace all of
it. (`prompts.json`, `preview.html` and `qa/` describe that first round; refresh them for this one.)

## Spec (every image)

- **16:9 landscape**, at least **1536 × 864** (1920 × 1080 is ideal). If the generator only offers
  3:2, keep everything that matters inside the middle 16:9 band — the importer centre-crops.
- **One subject, large, in the RIGHT half** of the frame. It may bleed off the top, right or bottom
  edge (Apple's portraits are cut at the shoulders).
- **The bottom-left ~45 % × 40 % belongs to the name**: plain background there — no detail, no
  bright spots, nothing the eye has to read.
- **Light and dark, not colour.** The grade keeps only the values, so the subject must separate
  from its background by light alone (squint: can you still see it?). Black and white is ideal.
- **No text, letters, logos or watermarks**; no border, rounded corners, vignette or frame.
- **Original only**: no existing characters, franchises, studios or brands, and no real people —
  TV photos show fictional people who resemble no actor or public figure.

## Style blocks (repeat with every prompt)

**Anime:**

> 16:9 landscape anime key-art illustration: bold cel shading, crisp line work, dramatic
> single-source lighting, strong light–dark contrast, rendered in black and white (greyscale). One
> subject, large, in the right half of the frame; the lower-left area is plain background. Original
> design — no existing characters, no logos, no text or lettering, no watermark.

**TV:**

> 16:9 landscape cinematic film still: live-action photography, dramatic single-source lighting,
> strong light–dark contrast, black and white. One subject, large, in the right half of the frame;
> the lower-left area is plain background. Fictional people only — nobody real or famous. No text,
> no logos, no watermark.

## The 31 images

Keys are the server's (`server/src/discover/genres.ts`); the file name must be the key exactly.
Seven genres are in both catalogues and need both pictures; the rest need one — a genre only one
catalogue holds gets only that picture (the importer skips the other). Subjects are suggestions;
the anime ones are the first round's, which read well — recompose them for 16:9.

| key | Genre | anime (illustration) | TV (photograph) |
| --- | --- | --- | --- |
| `action` | Action | a katana mid-swing throwing sparks | a stunt rider's motorcycle skidding, sparks flying |
| `adventure` | Adventure | a traveller's backpack and compass on a cliff above a valley | a lone hiker on a ridge above a misty valley |
| `comedy` | Comedy | a giant laughing sweat drop bursting into confetti | a person mid-laugh, head thrown back |
| `drama` | Drama | an umbrella in the rain under a streetlight | a woman at a rain-streaked window |
| `fantasy` | Fantasy | a small dragon curled around a glowing spellbook | a knight in armour in a misty forest |
| `sci-fi` | Sci-Fi | a starship crossing a ringed planet | an astronaut's visor reflecting a planet |
| `mystery` | Mystery | a magnifying glass over glowing footprints | a figure with a flashlight in a dark corridor |
| `romance` | Romance | two hands almost touching under falling blossoms | — |
| `horror` | Horror | a red lantern in fog beside a torii gate | — |
| `thriller` | Thriller | a toppling chess king lit from one side | — |
| `psychological` | Psychological | a shattered mirror reflecting a spiral | — |
| `supernatural` | Supernatural | a fox-spirit mask wreathed in flame | — |
| `slice-of-life` | Slice of Life | a cat asleep by a cup of tea in a sunny window | — |
| `sports` | Sports | a volleyball at the top of its arc | — |
| `mecha` | Mecha | a giant robot's head, one glowing eye | — |
| `music` | Music | a microphone under stage lights | — |
| `mahou-shoujo` | Mahou Shoujo | a magical-girl wand with ribbons and stars | — |
| `crime` | Crime | — | a detective in a trench coat under a streetlight, rain |
| `documentary` | Documentary | — | a wildlife camera operator behind a long lens |
| `family` | Family | — | a parent carrying a child on their shoulders |
| `reality` | Reality | — | a contestant alone on a lit studio stage |
| `war-politics` | War & Politics | — | a speaker at a podium before a bank of microphones |
| `western` | Western | — | a rider on horseback against a desert sky |
| `animation` | Animation | — | an animator's hand drawing on a light table |

## Checking the result

Run the importer and read both sheets: every subject reads at a glance, every name sits on calm
ground. Then build (`zsh ios/build/run/build-sim.sh <tag>`) and launch with `-openTab discover`
(the Genres tab); add `-genreArt tv` to see the TV pictures in All. A local server shows only the
17 anime genres (TV is off without `TMDB_ACCESS_TOKEN`); production shows all 24.
