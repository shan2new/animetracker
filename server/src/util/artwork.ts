import type { ArtworkImage } from '../types/api.js'

function pixelArea(image: ArtworkImage): number {
  return image.width != null && image.width > 0 && image.height != null && image.height > 0
    ? image.width * image.height
    : 0
}

/**
 * Put the highest-quality source asset first. Resolution is the primary quality signal; catalogue
 * score breaks equal-resolution ties, and TMDB wins only when the available metadata is otherwise
 * equal (AniList does not publish image dimensions or scores).
 */
export function rankArtwork(images: ArtworkImage[], limit = 6): ArtworkImage[] {
  const ranked = images
    .map((image, index) => ({ image, index }))
    .sort((a, b) =>
      pixelArea(b.image) - pixelArea(a.image)
      || (b.image.score ?? -1) - (a.image.score ?? -1)
      || Number(b.image.source === 'tmdb') - Number(a.image.source === 'tmdb')
      || a.index - b.index,
    )

  const seen = new Set<string>()
  const out: ArtworkImage[] = []
  for (const { image } of ranked) {
    if (seen.has(image.url)) continue
    seen.add(image.url)
    out.push(image)
    if (out.length >= limit) break
  }
  return out
}
