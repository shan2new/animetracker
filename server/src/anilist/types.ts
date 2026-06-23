export type MediaFormat = 'TV' | 'TV_SHORT' | 'MOVIE' | 'OVA' | 'ONA' | 'SPECIAL' | 'MUSIC'
export type MediaStatus = 'FINISHED' | 'RELEASING' | 'NOT_YET_RELEASED' | 'CANCELLED' | 'HIATUS'

export type RelationType =
  | 'PREQUEL'
  | 'SEQUEL'
  | 'PARENT'
  | 'SIDE_STORY'
  | 'ALTERNATIVE'
  | 'SPIN_OFF'
  | 'ADAPTATION'
  | 'CHARACTER'
  | 'SUMMARY'
  | 'OTHER'
  | (string & {})

export interface AniListRelationEdge {
  relationType: RelationType
  node: { id: number; type: 'ANIME' | 'MANGA'; format: MediaFormat | null }
}

// Raw shape returned by the AniList GraphQL API for a Media node.
export interface AniListMedia {
  id: number
  title: { romaji: string | null; english: string | null }
  coverImage: { extraLarge: string | null; large: string | null }
  bannerImage: string | null
  description: string | null
  genres: string[]
  episodes: number | null
  format: MediaFormat | null
  status: MediaStatus | null
  season: string | null
  seasonYear: number | null
  popularity: number | null
  trending: number | null
  nextAiringEpisode: { episode: number; airingAt: number } | null
  relations?: { edges: AniListRelationEdge[] } | null
}
