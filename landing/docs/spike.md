# Previously. landing page — research report

Researched 5 September 2026, before implementation. Scope: public introduction to Previously., the TV and anime companion, separate from the tracker itself.

## Key findings

1. **Show the product in context.** Linear's current homepage puts a rendered product example directly beneath its positioning and continues with concrete workflows. Use an illustrative tracking scene alongside the hero, then one working progress example. This is an observable presentation pattern, not a claim about conversion. [Linear](https://linear.app/)
2. **Keep the hierarchy calm.** Linear's March 2026 design note explains reducing visual noise, softening borders and making hierarchy more consistent. For Previously., restrained surfaces let television art and the amber bookmark carry the identity. [Linear design refresh](https://linear.app/now/behind-the-latest-design-refresh)
3. **Use a real category comparison.** Sequel's current developer-authored listing describes episode tracking, Watch Next, upcoming releases and reminders. Those are recognizable category concepts; Previously.'s distinctive story is continuity across long breaks and seasons. No competitor feature is treated as evidence that Previously. supports it. [Sequel listing](https://apps.apple.com/us/app/sequel-media-tracker/id1630746993)
4. **AI search depends on ordinary discoverability.** Google requires indexability/snippet eligibility and emphasizes textual content, internal links and visible content matching structured data. No special AI text file or schema is required. Implement semantic server-rendered HTML with descriptive metadata and truthful software identity; do not add invented ratings, prices or FAQs for rich-result promises. [Google Search Central](https://developers.google.com/search/docs/appearance/ai-features)
5. **Allow search crawlers.** OpenAI documents OAI-SearchBot as the crawler for ChatGPT search, independent of GPTBot's training purpose. Keep the public page accessible to search crawlers. Authentication on a review deployment is still an indexing barrier. [OpenAI crawler documentation](https://developers.openai.com/api/docs/bots)
6. **Prioritize the leading artwork.** The current web.dev LCP guide says not to lazy-load the likely LCP image and recommends `fetchpriority="high"` for it. Use fixed dimensions and lazy-load below-fold images. This documentation was re-read in 2026 to verify its continued applicability. [web.dev](https://web.dev/articles/optimize-lcp)
7. **Respect motion preferences.** MDN's current CSS guide documents `@media (prefers-reduced-motion: reduce)`. All entrance/hover motion and smooth scrolling are disabled in that preference. [MDN, updated June 2026](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/%40media/prefers-reduced-motion)

## Evidence and implementation values

| Decision             | Concrete value                                                                     | Source                                                                                                                                     |
| -------------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| Product name         | Previously. including the period                                                   | [Current project source](https://github.com/shan2new/animetracker/blob/main/ios/project.yml), local version verified                       |
| Brand                | #09090B canvas, #F4F1EC text, #AAA6A0 secondary, #F0A24E accent                    | [ThemeTokens.swift](https://github.com/shan2new/animetracker/blob/main/ios/Sources/DesignSystem/ThemeTokens.swift), local version verified |
| Typeface             | Existing bundled Outfit, 400/500/600                                               | [AppFont.swift](https://github.com/shan2new/animetracker/blob/main/ios/Sources/DesignSystem/AppFont.swift)                                 |
| Mark                 | Existing bookmark with one progress point                                          | [PreviouslyMark.swift](https://github.com/shan2new/animetracker/blob/main/ios/Sources/DesignSystem/PreviouslyMark.swift)                   |
| Image loading        | Hero `fetchPriority="high"`; explicit width/height; later artwork `loading="lazy"` | [web.dev](https://web.dev/articles/optimize-lcp)                                                                                           |
| Motion accessibility | `@media(prefers-reduced-motion:reduce)`                                            | [MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/%40media/prefers-reduced-motion)                                 |
| Search               | Crawlable HTML, canonical, robots, sitemap, SoftwareApplication identity           | [Google](https://developers.google.com/search/docs/appearance/ai-features), [Schema.org](https://schema.org/SoftwareApplication)           |

## Recommendation

Use a cinematic editorial composition with a 1280px maximum width, 98px maximum desktop headline, a 59–84px mobile headline, 16px body copy, 7–12px surface radii, and 200–350ms hover transitions. These sizes and durations are original design choices for this composition, not measured values copied from Linear or evidence of superior conversion. Keep the verified Previously. palette and typeface. Show real television art, progress and a clearly labelled interactive example. Use restrained 850ms entrance motion and a complete reduced-motion override.

No independent conversion evidence was established for this specific layout. Search inclusion is not guaranteed. No verified App Store/TestFlight link was found, so the primary action explores the page and availability is described without implying a released download.

## Sources and assets

- [Apple TV Press — Severance](https://images.apple.com/tv-pr/originals/severance/): hero still; direct source https://images.apple.com/tv-pr/shows-and-films/s/severance/images/season-02/video-posters/poster-0203/Severance_Poster_0203.jpg
- [TMDB — The Bear](https://www.themoviedb.org/tv/136315-the-bear/images/posters): promotional poster; direct source https://image.tmdb.org/t/p/original/zHRGahGb5Ay6OUSwmAXHreZad72.jpg
- [IMDb — Shōgun](https://www.imdb.com/es/title/tt2788316/): promotional poster; direct source https://m.media-amazon.com/images/M/MV5BOTliMTk3ZDAtYTk3NS00NTMwLTk5M2ItYzBkODlmY2VhNTMzXkEyXkFqcGc%40._V1_.jpg

Promotional artwork belongs to its respective owners. Public availability of these sources does not establish a blanket commercial reuse license. Local files are retained for the review design; asset provenance is recorded here for launch review.

## Product truth constraints

Current native code verifies Today, Schedule, Library, Search, progress/status tracking, spoiler controls and a what-changed digest. The digest is not a plot recap. Streaming availability and recommendation explanations in `docs/backend-ux-handoff.md` are backend-only and are not promised in the page. Rewatch state is local; the page makes no sync claim. The legacy API domain is not used as a consumer destination.


## Redesign after visual review — 5 September 2026

The user rejected the first composition as too basic. Screenshots confirmed competing copy, repeated tilted art and undersized product controls. The replacement uses one cinematic hero, an interactive tracking window, warm paper sections, serif accents alongside the existing Outfit font, and a calmer legal reading layout. These are original art-direction decisions, not conversion claims. Linear’s current [design refresh](https://linear.app/now/behind-the-latest-design-refresh) remains useful for hierarchy and reducing noise; its [Output isn’t design](https://linear.app/now/output-isn-t-design) reinforces judging the rendered result in context.

The alternate Severance corridor still, previously downloaded during the original research, is now `public/images/severance-wide.jpg` (980×552, 74 KB), from Apple TV Press’s Severance media collection linked above. Rights caveats above still apply. No generated image asset was used.

Visual QA checked the homepage sections and privacy page at the actual desktop viewport and at 390px. Interaction QA verified progress advancement, undo, updates, spoiler reveal, library state, in-page demo links, and FAQ expansion. A changing preview-frame height was found and fixed. The redesign remains local while legal publication facts are unresolved.

## Copy reduction after user feedback

The user found the redesign far too prose-heavy. Removed the entire return/update marketing section, closing pitch, repeated taglines, explanatory library paragraphs and large footer; kept one hero sentence, the working preview, one visual library section, three feature labels and four short collapsed FAQs. At the same 983px desktop viewport, default visible text fell from 449 to 141 words (about 69%) and page height from 4091px to 2124px (about 48%). These are DOM measurements, not performance or conversion claims. Legal-policy disclosures remain on their dedicated pages.

## Previous revision — ivory product gallery

After the user accepted the shorter copy but rejected the visuals, replaced the dark editorial composition with an ivory canvas, one Outfit type family, restrained amber accents and a single upright interactive app preview. Removed the large background photograph, serif emphasis and repeated library illustration. The product artwork now lives within the app viewport, following the native Today screen's full-bleed hero and floating navigation. This is an illustrative web implementation, not a screenshot of a released app.

The existing bookmark SVG is reframed in `public/brand/mark-tight.svg` to remove oversized source padding; its paths and gradient are unchanged. Secondary landing copy uses #6b6c63 on #f5f4f0 (approximately 4.8:1 contrast). All three preview tabs keep their height, progress and undo share state with the library, and episode details remain hidden until deliberately revealed. Schedule dates are explicitly sample data.

Browser QA covered desktop and 390px mobile: Today, Library, Schedule, update details and spoiler reveal/hide; all mobile panel contents fit their fixed 605px content area and the page has no horizontal overflow. Privacy layout was visually checked at both widths after removing obsolete homepage CSS. Application lint, TypeScript and production build pass. No new generated artwork or additional product claims were introduced. This revision remains local; the public deployment is still version 2 and the existing legal publication blockers remain unresolved.

## Collection and continuity showcase

The user rejected the ivory phone composition as still sloppy and insufficiently premium. A source review identified five concrete weaknesses: a generic split hero, disproportionate phone height, simulated metal edges, a severe landscape-image crop, and inconsistent small details. Replaced that structure with a centered concise introduction and a broad product stage. The collection is the initial view; the primary preview link opens working episode tracking, while the third tab shows an explicitly illustrative schedule. This is a marketing illustration of verified workflows, not a screenshot of a released desktop app.

The renewed spike inspected the live [Sequel homepage](https://www.getsequel.app/) and [Flighty homepage](https://flighty.com/) in the browser. Both visibly lead with a concise product promise and product imagery. Their device renders, download availability, customer counts and awards are not reused or attributed to Previously. The [Things homepage](https://culturedcode.com/things/) was also fetched as category context. These observations inform hierarchy only; no conversion claim is established.

Implementation choices are original: #f7f7f5 page surface, #17191b showcase, #ebba7d accent, 1160px maximum page width, 16px stage corners, 11px minimum metadata, and 44px mobile tab and progress controls. Removed static carousel-like numbers, a misleading completed bookmark, and a non-link arrow. Desktop poster widths match caption widths; mobile uses two portraits plus a compact third item.

Replaced the fabricated Severance cover with genuine 2:3 promotional artwork from the [TMDB season 2 poster catalogue](https://www.themoviedb.org/tv/95396-severance/season/2/images/posters). Source: [original 2000×3000 poster](https://image.tmdb.org/t/p/original/Rb7sga832Cyqvafd7CqOzbwdK4.jpg). Local delivery asset `public/images/severance-poster.jpg` is the catalogue CDN's 500×750 version, 73,646 bytes. Artwork provenance does not establish a blanket commercial reuse license; the earlier launch-review note still applies.

Checked rendered layouts at 983px and 1440px desktop widths and 390px mobile, plus 320px overflow checks. Verified collection progress updates, watched/undo, update view, spoiler reveal/hide, schedule, and primary-link navigation. Mobile panels fit 636px without horizontal overflow. Browser error/warning logs were empty; lint, TypeScript and production build passed. The existing legal content is unchanged and the revision remains local. User acceptance of this visual direction is pending.


## Current revision — entertainment atmosphere and direct exploration

The user welcomed the collection direction, then clarified that the restrained presentation was still too plain for an entertainment-adjacent app. Kept the information structure and introduced a near-black cinema setting (#0d0f12), warm white type, an amber primary action (#eebf83), a compact two-line headline and larger artwork. The localized light behind the shelf follows the show artwork; posters remain vivid. No backdrop collage, autoplay or new marketing sections were added.

Each poster is now a real entrance into its matching continuation view. Severance, The Bear and Frieren retain independent sample progress. Marking Frieren's first episode changes its collection status from planned to watching; undo remains available. Keyboard entry moves focus to the next action, and poster descriptions include progress and status. Scene transitions last 240ms, with reduced-motion overrides and an instant scroll path for that preference. These values are design choices, not evidence of conversion lift.

Additional promotional assets, inspected locally after download:

- Frieren portrait: [TMDB English poster catalogue](https://www.themoviedb.org/tv/209867/images/posters?language=en-US), [original image](https://image.tmdb.org/t/p/original/dqZENchTd7lp5zht7BdlqM7RBhD.jpg). Delivered as `public/images/frieren-poster.jpg`, 500×750.
- Frieren landscape: [TMDB backdrop catalogue](https://www.themoviedb.org/tv/209867/images/backdrops), [original image](https://image.tmdb.org/t/p/original/96RT2A47UdzWlUfvIERFyBsLhL2.jpg). Delivered as `public/images/frieren-wide.jpg`, 780×439.
- The Bear landscape: [TMDB backdrop catalogue](https://www.themoviedb.org/tv/136315-the-bear/images/backdrops), [original image](https://image.tmdb.org/t/p/original/wHNwlE6ftEpgjVbdhLXOtv1hLs0.jpg). Delivered as `public/images/bear-wide.jpg`, 780×439.

The existing artwork-rights note remains applicable. Images are used to illustrate the shows, not to imply endorsement or streaming availability.

Verified exact-show navigation, independent progress (Severance 4/10, The Bear unchanged at 2/10, Frieren 1/28), undo, spoiler reveal, keyboard entry/focus, reduced-motion emulation (`animation-name: none`), and no horizontal overflow at 390px and 320px. Mobile content fits the 636px panels. Browser error/warning logs were empty. Lint, TypeScript and production build pass. Legal content and the public version 2 deployment remain unchanged; this visual revision is local and awaits user review.


## User-selected reference direction — Netflix and Apple TV

The oversized condensed-type / single-show editorial hero was rejected as weird. The user then supplied [Netflix India](https://www.netflix.com/in/) and [Apple TV](https://tv.apple.com/). The current implementation uses these as its visual references: a genuine poster wall, centered sans-serif proposition, neutral dark surfaces, landscape show cards and a horizontal mobile shelf. Detailed measurements, source scrutiny and current verification are in [the current research report](research/visual-spike-2026-09-05.md). This replaces the earlier recommended visual direction; product capabilities and legal draft boundaries are unchanged.
