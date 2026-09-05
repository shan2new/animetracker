# Previously. landing website

Public-facing product introduction for **Previously.**, the TV and anime companion. This website is separate from the iPhone app, backend API and retired `legacy-web` app.

## Local development

```sh
npm ci
npm run dev -- --host 127.0.0.1 --port 4321
npm run lint
npx tsc --noEmit
npm run build
```

Stack: the official Sites scaffold with Vinext, React 19, TypeScript and existing Base UI/Shadcn primitives. Product copy is server-rendered. The app tour and FAQ use client components for tabs, image dialogs and accordions. Font and artwork assets are local. The tour makes no app API requests or account changes. No app-owned analytics integration is present; normal hosting requests still occur.

## Content and launch settings

- `app/page.tsx`: landing page and truthful SoftwareApplication JSON-LD.
- `app/experience.tsx`: the app-led hero and source-checked FAQ.
- `app/product-tour.tsx` and `app/product-tour.css`: responsive Today, Schedule, Library and Search tabs with actual iPhone captures, enlarged images and a native season-picker example.
- `app/gallery.css`: the Netflix/Apple TV-inspired poster-wall hero, header and FAQ layout.
- `app/globals.css`: shared Previously. theme, legal layouts, FAQ and footer styles.
- `app/layout.tsx`, `app/robots.ts`, `app/sitemap.ts`: page metadata and search discovery. Replace the Sites origin in these and JSON-LD if a custom domain becomes canonical.
- `public/brand`: the existing Previously. bookmark, copied from the parent project's current brand source.
- `public/app`: iPhone screenshots captured on 6 September 2026. Full images are lossless WebP; smaller previews load as their tabs become visible.
- `docs/research/app-grounding-2026-09-06.md`: current product evidence, asset provenance and verification.
- `docs/research/visual-spike-2026-09-05.md`: earlier measured benchmarks, user-selected Netflix/Apple TV references and rejected directions.
- `docs/spike.md`: earlier research, verified feature boundaries and original asset sources.
- `docs/research/artwork-2026-09-05.json`: newly integrated artwork provenance.

There is no verified App Store/TestFlight URL in the repository. The page honestly states that its public download link is not yet available. Update the primary call to action, availability label and FAQ when a verified link is provided. Do not use `anime.cognipin.com` as an app destination: it is the backend API.

Search eligibility requires a publicly accessible deployment. The code allows search crawlers and includes textual product answers, canonical metadata, a sitemap and JSON-LD; it does not guarantee indexing or rankings. No generated reviews, download counts, prices, endorsements or unsupported app features are included.

## Verification

Application lint, TypeScript and production build are checked alongside browser verification of the tour, dialogs, FAQ and mobile layout. The lint script checks application-owned source. The current revision introduces the product with a real Library screen, then replaces the illustrative collection, progress, schedule and updates interfaces with actual app screens. The screenshot dates are snapshots, not a live release feed. See the current research report for the evidence and verification limits.

Only the landing directory is publishable. Never include parent environment files, SQL dumps, iPhone/backend source or local caches in a deployment. Build artifacts and dependency folders are ignored.

After the lower tour was grounded in the app, the user requested an improvement to the upper section too. The hero now pairs a larger, left-aligned Outfit headline with the actual Library screen. Existing poster artwork provides a quieter backdrop. The page retains Previously's amber identity and coming-soon status. The tour follows the app's four root tabs and explains actual workflows. Tab and dialog controls support keyboard input; closing a dialog restores focus. Touch targets are at least 44px tall and new motion respects reduced-motion preferences.

The refinement pass keeps the approved composition and connects it more closely to the tour: the hero screen links to Library, desktop tabs explain each section, and the tab bar stays within reach while scrolling. Selecting a tab keeps the URL in sync and brings its introduction into view when needed. Full-screen image controls sit below the captures, leaving the app screens unobstructed. The tour, FAQ and footer share the same warm neutrals.

**Outfit is the brand typeface throughout the website.** The gallery inherits the global Outfit family. Local static files are accurately declared at 400, 500, 600 and 700; the Bold file comes from the iPhone app's existing font assets. Use 700 for the hero and 600 for section headings and primary controls. Do not replace Outfit with a system font when interpreting visual references.

## Legal-page drafts (5 September 2026)

The local `/privacy`, `/terms`, `/support` and `/delete-account` routes are **unpublished drafts**. They are marked noindex and are not in the sitemap. Shantanu Sinha and shantanusinha95@gmail.com are confirmed public contacts; GitHub and LinkedIn profiles are linked. Support now has a usable mailto route; privacy, terms and deletion remain visibly draft. Do not deploy this modified source as the final legal policy: retention practices remain unconfirmed, and the app’s account deletion still leaves its Clerk identity and local records behind. See `docs/store-readiness.md` for the verified blockers. The public Sites deployment remains version 2 and does not include these draft routes.
