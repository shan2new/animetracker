import type { ArtworkImage } from '../types/api.js'

function pixelArea(image: ArtworkImage): number {
  return image.width != null && image.width > 0 && image.height != null && image.height > 0
    ? image.width * image.height
    : 0
}

/** A URL-only fallback has no language either, but is not evidence of textless artwork. */
export function isTextlessArtwork(image: ArtworkImage): boolean {
  return image.source === 'tmdb' && pixelArea(image) > 0 && !image.language?.trim()
}

/** Cap a ranked/merged gallery without throwing away its only usable clean-art alternative. */
export function limitArtwork(images: ArtworkImage[], limit = 6, preserveTextless = false): ArtworkImage[] {
  if (limit <= 0) return []
  const byURL = new Map<string, ArtworkImage>()
  for (const image of images) {
    if (!image.url) continue
    const existing = byURL.get(image.url)
    // A stored URL-only entry must not hide metadata for that exact asset from a part.
    // Map replacement preserves its position; this is not a new quality ranking.
    if (!existing || (pixelArea(existing) === 0 && pixelArea(image) > 0)) byURL.set(image.url, image)
  }
  const unique = [...byURL.values()]
  const result = unique.slice(0, limit)
  if (preserveTextless && limit > 1 && !result.some(isTextlessArtwork)) {
    const clean = unique.find(isTextlessArtwork)
    if (clean) result.splice(result.length - 1, 1, clean)
  }
  return result
}

/**
 * Put the highest-quality source asset first. Resolution is the primary quality signal; catalogue
 * score breaks equal-resolution ties, and TMDB wins only when the available metadata is otherwise
 * equal (AniList does not publish image dimensions or scores).
 */
export function rankArtwork(images: ArtworkImage[], limit = 6, preserveTextless = false): ArtworkImage[] {
  const ranked = images
    .map((image, index) => ({ image, index }))
    .sort((a, b) =>
      pixelArea(b.image) - pixelArea(a.image)
      || (b.image.score ?? -1) - (a.image.score ?? -1)
      || Number(b.image.source === 'tmdb') - Number(a.image.source === 'tmdb')
      || a.index - b.index,
    )

  return limitArtwork(ranked.map(({ image }) => image), limit, preserveTextless)
}

/**
 * Logos rank by the catalogue's own preference before size. Resolution is no quality signal for
 * a logo: the largest is often a season-stamped variant nobody voted for — Re:ZERO's 1200×478
 * "SEASON 3" mark (score 0) outranked three plain marks scored 3.3 and put "Season 3" on Season
 * 4's cards (review, 24 Sep). English first (the app's language), then TMDB's vote average, then
 * area, then TMDB, then the order given.
 */
export function rankLogos(images: ArtworkImage[], limit = 6): ArtworkImage[] {
  const english = (image: ArtworkImage) => Number(image.language?.trim().toLowerCase() === 'en')
  const ranked = images
    .map((image, index) => ({ image, index }))
    .sort((a, b) =>
      english(b.image) - english(a.image)
      || (b.image.score ?? -1) - (a.image.score ?? -1)
      || pixelArea(b.image) - pixelArea(a.image)
      || Number(b.image.source === 'tmdb') - Number(a.image.source === 'tmdb')
      || a.index - b.index,
    )
  return limitArtwork(ranked.map(({ image }) => image), limit, false)
}
