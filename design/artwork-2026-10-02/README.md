# Quiet original artwork for Previously.

The current direction follows the user's correction: visually scout the actual app first;
character should feel immersive, fun and premium without being flashy or distracting.

[Expanded placement map and three native examples](expanded/SCOPE.md).
[Original visual scout](scout/SCOUT.md).
[Login follow-up and cozy welcome revision](login/REVIEW.md).
[Current welcome backdrop](login/BACKDROP.md).

The empty Library, first-use Schedule and successfully loaded empty Saved posts receive original
artwork: graphite episode frames, a hinged calendar and bookmark panels. All use the app's
split-flap materials, ivory marks and small coral accents. Each transparent image appears in a bounded
128 × 100 point slot above the existing message. Copy, centered layout, navigation and the
Add a show action remain intact. Error states keep their symbols. Accessibility text sizes
use the simpler symbol layout.

The login follow-up adds an original softly lit welcome room with compact branding and no slogan.
The current portrait scene fills the welcome background, with dark veils protecting the brand and action.
The earlier inline vignette is retired. The credential sheet keeps
focused forms, with its retired ribbon logo replaced locally by the current split-flap mark.
Sources, native captures, prompts and verification are in `login/`.

The Library original is `source/empty-library-episode-frames-v2.png`; its exact prompt and tool
metadata are in `quiet-artwork-prompt-v2.json`. Schedule and Saved originals are in `source/`,
with prompts in `expanded/prompts.json`. Built-in Image Gen was used. It exposes no model
selector, so Sunburst was not selectable or verified. The subject has blank cards and no show
characters, actor likenesses, fictional locations or studio marks. The earlier cream/fabric
archive object was rejected by the user as a mismatch for the app's theme and character. Its
source, prompt, captures and packaged images are retained; its imageset is in `retired-library-v1/`.

`package-quiet-art.py` crops excess transparent padding and resamples the generated alpha image
to @2x/@3x PNGs, with no color grade or semantic edits. Final asset:
`ios/Resources/Assets.xcassets/empty-library-episode-frames-v2.imageset/` (144,883 image bytes).
`expanded/package-artwork.py` packages Schedule and Saved in the same 128 × 100-point slot
(324,305 additional image bytes across @2x/@3x).

The v2 Debug AniTrack build passed on iPhone 14 Pro / iOS 27.0; `scout/15-library-flap-v2.jpg`
is its actual native rendering. The earlier v1 captures checked the unchanged accessibility
fallback and populated-library layout; those checks were not repeated for this asset-only revision. The review
boards arrange exact native screenshots without repainting the UI; sources are retained.

The local build used `API_BASE_URL=http://localhost:18789` and `CLERK_PUBLISHABLE_KEY=`.
Production project settings are unchanged. `preview-server.py` serves loopback snapshots;
mutations are refused and the visit handshake is inert. Catalogue/library export scripts verify
PostgreSQL read-only mode before reading real catalogue, library and feed records. The library
snapshot is local-only and ignored by Git. Simulator sign-in uses a local shell without production
credentials. No production backend changed.

Deterministic DEBUG launch arguments rendered the screens. Semantic taps reported success but
did not navigate: captures prove rendering, not verified touch navigation. No real-device
validation or distribution is claimed. The three-example build passed, with a fresh larger-text
Schedule check. Current evidence is in `expanded/verification.json` and `expanded/build.log`;
earlier Library-only evidence remains in `verification.json` and `quiet-build-v2.log`.

The earlier four Adventure/Drama replacements were premature. They are preserved under
`retired-genre-experiment/`, including sources, prompts and old verification. None is in the app's
asset catalogue or selected by GenreArt. Its packaging script writes only to the retired folder.
The previous genre artwork is restored.

The temporary Discover capture hook was removed from app code. Its patch remains at
`scout/DiscoverExplore.capture.patch` solely to reproduce that capture.
