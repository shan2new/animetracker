// Raw TMDB v3 wire shapes (only the fields we consume).

export type TmdbShowStatus =
  | 'Returning Series'
  | 'Ended'
  | 'Canceled'
  | 'In Production'
  | 'Planned'
  | 'Pilot'
  | (string & {})

export interface TmdbSearchResult {
  id: number
  name: string
  genre_ids: number[]
  origin_country: string[]
  poster_path: string | null
  first_air_date: string | null
  popularity: number
  overview: string | null
}

export interface TmdbEpisodeStub {
  air_date: string | null
  episode_number: number
  season_number: number
}

// Full episode from the season-detail endpoint (/tv/{id}/season/{n}).
export interface TmdbEpisode {
  episode_number: number
  name: string | null
  overview: string | null
  air_date: string | null
  still_path: string | null
  runtime: number | null
}

export interface TmdbSeasonDetail {
  id: number
  season_number: number
  episodes: TmdbEpisode[]
}

export interface TmdbSeason {
  id: number
  season_number: number
  episode_count: number
  air_date: string | null
  poster_path: string | null
  name: string
  overview: string | null
}

export interface TmdbShow {
  id: number
  name: string
  status: TmdbShowStatus
  number_of_seasons: number
  seasons: TmdbSeason[]
  next_episode_to_air: TmdbEpisodeStub | null
  last_episode_to_air: TmdbEpisodeStub | null
  genres: { id: number; name: string }[]
  networks?: { id: number; name: string }[]
  overview: string | null
  backdrop_path: string | null
  poster_path: string | null
  popularity: number
  origin_country: string[]
}
