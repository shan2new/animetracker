# Latest direction — user-selected references

The earlier editorial implementation below was rejected by the user as visually weird. It is retained as research history, not the accepted recommendation. The user then explicitly supplied **Netflix India** and **Apple TV** as the visual references.

## Direct inspection, 5 September 2026

| Reference | Measured at 1280 × 720 | Applied interpretation |
| --- | --- | --- |
| [Netflix India](https://www.netflix.com/in/) | 56px/70px, weight700 Netflix Sans H1,588px text width;1280×744 perspective artwork backdrop; centered proposition and primary action. Current backdrop asset dated2026-08-31. | A broad wall of genuine artwork supplies entertainment atmosphere. Use a clear centered proposition and one primary action. |
| [Apple TV](https://tv.apple.com/) |52px top navigation;1280×720 featured-media frame;17px/22px700 system-font section labels in the inspected US page; horizontal show shelves. | Keep supporting labels modest, use neutral sans typography and large unobstructed images. |

The implementation uses Previously's own bookmark/amber identity, genuine TV/anime posters and tracking copy. It does not reuse the references' branding, promises, prices, membership forms or video. The visual choices below are original implementation decisions, not conversion claims: near-black#090a0d; local poster grid rotated−10deg;62px desktop heading/58px at983px;34–51px mobile heading;54px primary action;28px secondary heading; landscape collection row with a scrollable mobile shelf. The prior Barlow style, single-title hero and floating progress panel are removed.

New poster provenance is recorded in [artwork-2026-09-05.json](artwork-2026-09-05.json). Existing sources remain in the original spike log. Neither reference is evidence that these choices improve conversion; no such claim is made.

## Validation of the Netflix / Apple TV direction

- Production build, application lint, and TypeScript checks passed.
- Inspected the opening at 983px and 1280px desktop widths and 390px phone width. Checked page overflow at 320px and 600px; the mobile shelf scrolls within its own container.
- Verified independent sample progress for Severance, The Bear, and Frieren; mark/undo, show selection, release updates, and spoiler reveal work. Tracking controls remain inside the 320px layout.
- Browser reported no warning/error logs and no failed image loads in the inspected page.
- Reduced-motion emulation reported `animation-name: none`, `transition-duration: 0s`, and `scroll-behavior: auto`. Emulation and viewport overrides were removed after verification.
- Server HTML contains one H1, the product FAQ, the new artwork references, and valid SoftwareApplication JSON-LD. All five routes returned 200; the four information/legal routes remain noindex as before.
- Current public deployment is unchanged. The local privacy, terms and deletion drafts retain the previously documented launch blockers.

The user subsequently called this the most welcome improvement so far and “extremely close,” requesting a more premium, modern finish. This is acceptance of the visual direction, not evidence of conversion performance.

## Finish refinement after acceptance

**Subsequent brand correction:** The user explicitly confirmed Outfit as the product typeface. The system-font override was an implementation mistake. The page now inherits Outfit globally, with accurately declared static 400/500/600 faces and the native app's actual 700 Bold face for the hero. Section headings and controls use 600. The accepted composition and short copy remain. Browser font inspection confirmed the headline renders `Outfit-Bold`, rather than a fallback or synthetic weight. Collection focus now stays inside the artwork, and the next-show action cycles through Severance → The Bear → Frieren → Severance.

Preserved the composition, typography and concise copy. Raised poster visibility at the edges while retaining a dark central scrim; added a finite, gentle opening settle. Refined the amber action and availability pill. Collection images now use their original 16:9 framing, fine edge highlights and image-only hover motion. Captions stay stationary. The segmented navigation has a sliding warm-white selection and actual 44px touch targets. Progress, calendar and updates use consistent neutral surfaces, amber accents and rounded controls.

An independent source review identified a keyboard defect: opening updates removed the focused control. The updates view now focuses its Back button and restores focus to the release-updates button on return. Reopening the same show still focuses its tracking action and preserves sample progress.

Validation: inspected the 983px opening, 1280px collection/detail views and 390px mobile opening; checked the 320px calendar and tracking panel for overflow and clipped controls. Verified keyboard entry/return, save/undo, retained Frieren progress, spoiler reveal/hide and all three tabs. All tab buttons measure 44px high. Reduced-motion emulation reports no hero animations, zero CTA/slider transition duration and automatic scrolling. Lint, TypeScript and production build passed. No product copy or public deployment changed.

---

# Previously. — entertainment landing-page spike

Research and direct browser inspection: 5 September 2026. This supersedes the incremental styling direction in the earlier spike log.

## Question

How can a concise TV/anime tracking landing page feel authored and visually compelling, without becoming a streaming-site imitation or a decorative dashboard?

## Method

Parallel searches covered entertainment leaders, consumer app presentations, open-source typography, resource loading, and counterexamples. The official Sequel, Flighty, MUBI and Letterboxd pages were opened in a browser and measured at **1280 × 720 CSS pixels**. Source inspection supplemented rendered measurements. MUBI redirected to its India page. Measurements describe these pages on this date; they are not timeless design rules. No independent conversion evidence was established, and no conversion statistics are used.

## Key findings and evidence

| Reference | Directly observed / measured | Useful implication for Previously. |
| --- | --- | --- |
| [MUBI](https://mubi.com/en/in) | Full-viewport 1280 × 720 video, muted and looping; 60px / 84px, weight 500 Riforma uppercase heading. Source uses 100vh at desktop widths ≥1186px and separate assets at 1186/810px. | Artwork can constitute the opening environment. A small illustration below a slogan cannot reproduce this composition. |
| [Letterboxd](https://letterboxd.com/) | 1200 × 675 backdrop, starting at x40/y0; page background #14181c. Main proposition is 36px / 48px TiemposHeadlineWeb, placed at y440 over the image fade. | Deliberate foreground/background placement and contrast matter more than headline scale. The image and the proposition belong to one scene. |
| [Sequel](https://www.getsequel.app/) | Manrope 800 heading, 42px / 50.4px desktop, #1d1d1f; source has 38/34px narrower variants. Media occupies a 900px-wide composition with three 1970 × 1421 layers. Mobile artwork width is 176% of its container. | A deliberately composed product image can carry the page. Equal-sized cards are not the only way to display a collection. |
| [Flighty](https://flighty.com/) | 65px / 78px, weight 700 system headline. A 1023 × 416 media layer starts at y420, combined with a 422.7 × 576 phone/hand image at y440 and concrete notification examples. | Pair emotional presentation with evidence of the product doing one useful thing. For Previously., this is remembering an episode and advancing to the next. |
| [Serializd source CSS](https://www.serializd.com/_next/static/css/ea9816a166bff5bb.css) | #0d0f12 background, 420px orb, blur(80px), infinite 5s pulse, centered 3.25rem / 700 Roboto headline, 10px CTA radius and 28px glow. | Counter-reference: these mechanics closely resemble the direction already rejected. Another glow treatment would not supply a distinct composition. |

These are source-supported observations. The implications in the last column are design judgments, not claims about which site converts better.

## Recommendation and implementation specification

**One editorial opening: a show-sized image, a concise title and a visible saved place.** Take the integrated image composition from MUBI/Letterboxd and the concrete product moment from Flighty. Keep Sequel's counterexample in mind: larger type alone is not the solution.

Original choices for Previously. (not measurements copied from another app):

- Replace the centered introduction and isolated preview box with an asymmetric opening scene. Use existing, genuine Severance/The Bear/Frieren artwork; selection changes the scene, title and saved progress together.
- State **TV + anime tracker** immediately above the headline. Use the five-word **Stay in the story.** title, with the existing Previously. bookmark and wordmark.
- Introduce Barlow Condensed 600 for display text, paired with existing Outfit for the brand and smaller copy. The font is available from [Google Fonts' source repository](https://github.com/google/fonts/tree/main/ofl/barlowcondensed) under the included [SIL Open Font License](https://github.com/google/fonts/blob/main/ofl/barlowcondensed/OFL.txt).
- Use near-black #101412, off-white #f4f2eb, and amber #efb767. The lower product spread uses #efeee8 to create a clear change in visual rhythm. Remove ambient orbs and repeated gradient-card treatments.
- Make the show index compact and labeled. Keep its action distinct: choose a scene. The saved-progress object opens that show's functional preview. Mark/undo remains in the preview, using the same state as the hero.
- Crossfade scenes in 400ms only after selection. No autoplay, scroll trapping, looping effects, or hidden introductory text. Disable transitions for reduced-motion users, following [MDN's current documentation](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/@media/prefers-reduced-motion).
- Serve the first scene as an eager, high-priority HTML image. Google's [LCP guidance](https://web.dev/articles/optimize-lcp) was re-opened and verified in this research (last updated March 2025): expose the image in initial HTML and avoid lazy-loading the LCP candidate. This is an implementation precaution, not a measured performance claim.

## Boundaries

Preserve the existing collection, progress, schedule, spoiler controls and FAQ. Sample progress stays local to the preview; schedule dates remain explicitly illustrative. Keep iPhone availability honest. No invented App Store links, reviews, pricing or streaming capabilities. Privacy/terms/deletion drafts and their launch blockers remain unchanged.

## Source scrutiny

Official sites are used as primary evidence of their own rendered design and code. Their marketing claims, user counts and testimonials are not used as evidence of effectiveness. MUBI's source has a fixed mobile scene with a 2600px scroll holder; that mechanism is deliberately not transferred. Asset provenance remains in [the original spike log](../spike.md); a source URL is not a blanket artwork licence.
