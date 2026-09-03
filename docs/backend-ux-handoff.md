# Backend UX handoff — 2026-09-03

This release is backend-only and additive. Existing `cover`, `banner`, `images`, `source`,
`sequence`, `source` (announcement URL), and per-part progress calls remain valid. New iOS code can
adopt each capability independently.

## 1. Search is now the complete discovery surface

`GET /search` searches canonical names plus English, Romaji, native and synonym aliases. Optional
filters are `source`, `year`, `status`, `theme`, `providerId`, and `country`; `providerId` requires
an explicit or saved country. Exact-title Search still does its bounded catalogue/news enrichment,
and now also returns current regional availability when a country resolves. Opening Detail is not
required to begin announcement, trailer, artwork or metadata repair.

Search/trending/library rows can include:

```jsonc
"availability": {
  "country": "IN",
  "status": "available",
  "providers": [{ "id": 8, "name": "Netflix", "access": "subscription", "preferred": true }],
  "link": "https://www.themoviedb.org/…/watch?locale=IN",
  "attribution": "JustWatch",
  "checkedAt": "2026-09-03T…"
}
```

Use `GET/PUT /me/preferences` to save `{ country, language, providerIds }`. Saved services sort
first and carry `preferred: true`. Use `POST /franchises/watch-providers/batch` (max 100 ids) to
warm a visible shelf. Preserve the supplied JustWatch attribution and open the regional `link`;
provider rows are not deep links.

## 2. Portrait and landscape assets are first-class

Franchise, summary and part payloads now include `artwork`:

```jsonc
{
  "portraits": [{ "url": "…", "source": "tmdb", "width": 2000, "height": 3000,
                  "language": "en", "score": 5.3 }],
  "landscapes": [{ "url": "…", "source": "tmdb", "width": 3840, "height": 2160,
                   "language": null, "score": 5.0 }],
  "logos": []
}
```

Use `portraits` for vertical share/list compositions and `landscapes` for horizontal share, hero
and episode compositions. Arrays are ranked, de-duplicated and capped at six. `images` remains the
single best pair and is the simplest fallback.

For conservatively matched anime, TMDB can fill missing episode title, overview, runtime and
horizontal `still`. AniList's exact airing instant always wins. A match needs corroborating year
and episode count (or a strict year/sequence fallback); ambiguous seasons are skipped rather than
assigning the wrong stills.

## 3. “Fact or rumor?” is inspectable

`upcoming.status` remains the classification (`rumored` is never promoted to `announced`). It now
has `evidence[]`, with `tier: official | trade | reputable | catalogue | unknown` and `primary` to
distinguish the original announcement from reporting. Catalogue facts have a catalogue evidence
row immediately; research can add up to five direct sources.

`GET /franchises/:id/announcements?limit=20` returns immutable observations newest-first, each with
the status/release believed at that check and its evidence. This supports an “announcement history”
sheet without deriving history from notification text.

## 4. Explainable discovery

`GET /me/discover?limit=20` returns source-native recommendations with:

```jsonc
{
  "title": { "source": "anilist", "externalId": 123, "franchiseId": null,
             "title": "…", "year": 2026, "images": { "portrait": "…", "landscape": "…" },
             "score": 100 },
  "because": { "franchiseId": "uuid", "title": "Bleach" },
  "reason": "Because you completed Bleach",
  "score": 125
}
```

The backend excludes dropped sources and already-subscribed targets and caps one source franchise
at three results. If `title.franchiseId` is null, call `POST /franchises/resolve` with its `source`
and `externalId` only after selection; the response is a normal `FranchiseSummary`.

## 5. Franchise-first order and progress

Every part now has:

- `watchOrder`: one global chronology across seasons, movies, OVAs and specials;
- `relationship`: source-backed relation such as `SEQUEL` or `SIDE_STORY`, otherwise null;
- `optional`: true only for identified side/optional material.

Render by `watchOrder`; do not concatenate separately sorted kind arrays.

`PUT /me/franchises/:franchiseId/progress` is atomic. Supported bodies:

```jsonc
{ "mode": "caught_up" } // also completed | reset; optional status
{ "parts": [{ "mediaId": 123, "episodes": 7 }], "status": "watching" }
```

It returns canonical progress for every part. `caught_up` never counts an announced part as aired;
`completed` also upserts completed subscription status. Foreign or duplicate media ids are rejected
before any write. Keep `PUT /me/progress` for an individual +/- control.

## 6. Metadata transparency

Full Detail/Library franchises include `metadata.completeness` booleans for artwork, episodes,
people, ratings, related titles and videos, plus `metadata.sources[]` with provider id, match method,
confidence and checked time. This lets iOS omit an empty module because data is unavailable rather
than rendering an unexplained blank state.

The daily backend repair now prioritizes followed anime and then covers the rest of the materialized
catalogue. It fills artwork, episode overlays, ratings, people, themes, recommendations and videos
from a durable, conservative AniList→TMDB identity link. Regional availability snapshots are also
warmed daily for countries users explicitly save. No trailer-drop or provider-change notification
was added.

The exhaustive wire contract and attribution rules remain in [api-contract.md](api-contract.md).
