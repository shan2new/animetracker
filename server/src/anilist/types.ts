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
  title: { romaji: string | null; english: string | null; native?: string | null }
  synonyms?: string[] | null
  coverImage: { extraLarge: string | null; large: string | null }
  bannerImage: string | null
  trailer?: { id: string | null; site: string | null; thumbnail: string | null } | null
  isAdult?: boolean | null
  description: string | null
  genres: string[]
  episodes: number | null
  format: MediaFormat | null
  status: MediaStatus | null
  season: string | null
  seasonYear: number | null
  popularity: number | null
  trending: number | null
  duration?: number | null // per-episode runtime (minutes)
  studios?: { nodes: { name: string; isAnimationStudio: boolean }[] } | null
  streamingEpisodes?: { title: string | null; thumbnail: string | null }[] | null
  nextAiringEpisode: { episode: number; airingAt: number } | null
  /** Per-episode air instants (seconds), when AniList has a schedule for the run. */
  airingSchedule?: { nodes: { episode: number; airingAt: number }[] } | null
  relations?: { edges: AniListRelationEdge[] } | null
}

export interface AniListTag {
  name: string
  rank: number
  isGeneralSpoiler: boolean
  isMediaSpoiler: boolean
  isAdult: boolean
}

export interface AniListPerson {
  id: number
  name: { full: string | null }
  image: { large: string | null }
}

export interface AniListStaffEdge {
  role: string | null
  node: AniListPerson
}

export interface AniListCharacterEdge {
  role: string | null
  node: AniListPerson
  voiceActors: AniListPerson[]
}

/** A related node as the recommendation ranker needs it: identity, kind and state, no payload. */
export interface AniListRelatedNode {
  id: number
  type: 'ANIME' | 'MANGA'
  format: MediaFormat | null
  status?: MediaStatus | null
  season?: string | null
  seasonYear?: number | null
}

export interface AniListRecommendedMedia {
  id: number
  type: 'ANIME' | 'MANGA'
  title: { romaji: string | null; english: string | null }
  coverImage: { extraLarge: string | null; large: string | null }
  bannerImage: string | null
  seasonYear: number | null
  // The ranker's facts (recommendation_targets). Optional: older payloads/tests omit them.
  format?: MediaFormat | null
  status?: MediaStatus | null
  episodes?: number | null
  averageScore?: number | null
  meanScore?: number | null
  popularity?: number | null
  genres?: string[] | null
  isAdult?: boolean | null
  countryOfOrigin?: string | null
  season?: string | null
  startDate?: { year: number | null; month: number | null; day: number | null } | null
  /** One level: enough to see a season's prequel/parent, its spin-offs and an announced sequel. */
  relations?: { edges: { relationType: RelationType; node: AniListRelatedNode }[] } | null
}

export interface AniListRecommendation {
  rating: number | null
  mediaRecommendation: AniListRecommendedMedia | null
}

/** The slim node the series-root walk fetches (recommendationRoots.ts). */
export interface AniListRootNode {
  id: number
  format: MediaFormat | null
  status: MediaStatus | null
  episodes: number | null
  season: string | null
  seasonYear: number | null
  title: { romaji: string | null; english: string | null }
  coverImage: { extraLarge: string | null; large: string | null }
  bannerImage: string | null
  relations: { edges: { relationType: RelationType; node: AniListRelatedNode }[] } | null
}

/** Expensive fields fetched only by background/detail enrichment, never provider typeahead. */
export interface AniListMediaEnrichment {
  id: number
  isAdult: boolean | null
  tags: AniListTag[]
  staff: { edges: AniListStaffEdge[] } | null
  characters: { edges: AniListCharacterEdge[] } | null
  recommendations: { nodes: AniListRecommendation[] } | null
}
