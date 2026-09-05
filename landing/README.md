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

Stack: the official Sites scaffold with Vinext, React 19, TypeScript and existing Base UI/Shadcn primitives. All visible product copy is server-rendered. The interactive example and FAQ are the only client components. Font and artwork assets are local. The sample UI makes no app API requests or account changes. No app-owned analytics integration is present; normal hosting requests still occur.

## Content and launch settings

- `app/page.tsx`: landing page and truthful SoftwareApplication JSON-LD.
- `app/experience.tsx`: illustrative progress example and FAQ. Its sample progress is ephemeral and does not affect an account.
- `app/gallery.css`: the Netflix/Apple TV-inspired poster-wall hero and responsive collection, progress and schedule preview.
- `app/globals.css`: shared Previously. theme, legal layouts, FAQ and footer styles.
- `app/layout.tsx`, `app/robots.ts`, `app/sitemap.ts`: page metadata and search discovery. Replace the Sites origin in these and JSON-LD if a custom domain becomes canonical.
- `public/brand`: the existing Previously. bookmark, copied from the parent project's current brand source.
- `docs/research/visual-spike-2026-09-05.md`: current measured benchmarks, user-selected Netflix/Apple TV references and rejected directions.
- `docs/spike.md`: earlier research, verified feature boundaries and original asset sources.
- `docs/research/artwork-2026-09-05.json`: newly integrated artwork provenance.

There is no verified App Store/TestFlight URL in the repository. The page honestly states that its public download link is not yet available. Update the primary call to action, availability label and FAQ when a verified link is provided. Do not use `anime.cognipin.com` as an app destination: it is the backend API.

Search eligibility requires a publicly accessible deployment. The code allows search crawlers and includes textual product answers, canonical metadata, a sitemap and JSON-LD; it does not guarantee indexing or rankings. No generated reviews, download counts, prices, endorsements or unsupported app features are included.

## Verification

Application lint, TypeScript, production build, and server-response checks cover metadata, FAQ text without client execution, heading count, local assets, internal anchors, robots and sitemap. The untouched generated component catalog has lint findings; the lint script checks application-owned source. The latest revision uses a centered sans-serif hero with a local poster wall, an unobstructed landscape collection shelf, and the existing interactive progress/schedule preview. Mobile collection cards scroll horizontally. Poster selection retains separate sample progress for TV and anime; a focus-request counter handles repeated selection of the same show. The previous condensed-type, full-screen single-show design was rejected and is no longer used. Validation for this revision is recorded in the current research report.

Only the landing directory is publishable. Never include parent environment files, SQL dumps, iPhone/backend source or local caches in a deployment. Build artifacts and dependency folders are ignored.

The user accepted the Netflix/Apple TV direction. The finish pass preserves its composition and copy, adds restrained opening and selection motion, uses 16:9 collection images, and standardizes neutral surfaces and rounded controls. Tabs provide 44px touch targets. Opening and closing release updates transfers keyboard focus to the replacement control. New motion respects reduced-motion preferences.

**Outfit is the brand typeface throughout the website.** The gallery inherits the global Outfit family. Local static files are accurately declared at 400, 500, 600 and 700; the Bold file comes from the iPhone app's existing font assets. Use 700 for the hero and 600 for section headings and primary controls. Do not replace Outfit with a system font when interpreting visual references. Artwork focus uses an inset border so it stays visible inside the mobile shelf. Show navigation cycles through all three examples.

## Legal-page drafts (5 September 2026)

The local `/privacy`, `/terms`, `/support` and `/delete-account` routes are **unpublished drafts**. They are marked noindex and are not in the sitemap. Shantanu Sinha and shantanusinha95@gmail.com are confirmed public contacts; GitHub and LinkedIn profiles are linked. Support now has a usable mailto route; privacy, terms and deletion remain visibly draft. Do not deploy this modified source as the final legal policy: retention practices remain unconfirmed, and the app’s account deletion still leaves its Clerk identity and local records behind. See `docs/store-readiness.md` for the verified blockers. The public Sites deployment remains version 2 and does not include these draft routes.
