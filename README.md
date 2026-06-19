# AniTrack

A calm, **airing-first** anime tracker. Built from the `AniTrack.dc.html` Claude Design, powered by live [AniList](https://anilist.co) data, with a fully local (private) library.

> The whole app exists to answer one question well: **what's airing, and what do I need to watch right now?**

## Features

- **Today** — a quiet briefing of what aired since you were last here ("Out now"), plus the next episodes dropping in the next 48h. Three home layouts: Briefing, Spotlight, Grid.
- **Mark caught up** — the signature one-tap action. Bumps a show to the latest aired episode instantly, with a satisfying confirmation animation and an Undo toast.
- **Schedule** — your week of airings, today highlighted, with live countdowns and "behind" badges.
- **Library** — organized airing-first: **Behind · Caught up · Finished airing · Plan to watch**, with fast search and filter chips.
- **Add** — search AniList (or browse what's trending) and add to your library in one tap.
- **Detail sheet** — synopsis, genres, next-episode countdown, precise episode +/− control, status, and Mark caught up.

No accounts, no social, no ads. Your library lives in `localStorage`.

## Stack

- React 18 + TypeScript + Vite
- AniList GraphQL API (`https://graphql.anilist.co`) — no API key required
- Dark, minimal design system (Geist / Geist Mono), accent `#F0A24E`

## Run

```bash
npm install
npm run dev      # http://localhost:5173
npm run build    # type-check + production build to dist/
npm run preview  # preview the production build
```

## How it works

**No show data is hardcoded, and there is no seed data.** The library starts empty — add shows from the Add tab. Only your own data is persisted (`src/store.ts`): each library entry is `{ anilistId, status, progress }`. Everything shown — titles, covers, episode counts, genres, synopses, and airing times — is fetched live from AniList on load (`src/anilist.ts`) and merged into a view model (`src/format.ts`). The UI (`src/App.tsx`) is a faithful port of the design's screens and logic.

### Resilience

- **Safe storage:** every `localStorage` touch is guarded (private mode / disabled storage / quota never crashes the app), persisted entries are sanitized on load, and a top-level error boundary catches any render failure.
- **Network:** requests retry with backoff and honor AniList's `429 Retry-After`; chunked queries use `Promise.allSettled` so a partial failure still yields data; total failure shows an inline **Retry** banner while keeping saved data visible.
- **Freshness:** live airing data refetches when the tab regains focus and on a slow background interval, so countdowns don't rot while the tab stays open.

### Exact airing times, in IST

- **Next episode** times come from AniList's `nextAiringEpisode`.
- **Last aired / "Out now"** times come from AniList's `airingSchedules` (queried `TIME_DESC`, batched via aliased `Page` queries) — exact past air times, no heuristic. (A weekly fallback is used only for the brief moment before that data loads.)
- **All dates and times are rendered in IST (Asia/Kolkata)** via `Intl.DateTimeFormat`, independent of the viewer's local timezone — the weekly schedule columns, "Today/Tomorrow", countdowns, and clock labels (e.g. `6:30 PM IST`). Change `TZ` in `src/format.ts` to use a different zone.

## Layout

| File | Responsibility |
| --- | --- |
| `src/App.tsx` | All screens, components, and view-model derivation |
| `src/anilist.ts` | AniList GraphQL client (search + batch fetch by id) |
| `src/store.ts` | Local library persistence + first-run seed |
| `src/format.ts` | Date/countdown formatters + AniList→Show mapper |
| `src/types.ts` | Shared types |
| `src/styles.css` | Tokens, animations, responsive shell |
