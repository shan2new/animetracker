import type { PartKind } from '../grouping/partKind.js'

export type WatchStatus = 'watching' | 'completed' | 'planned'

export interface FranchisePart {
  mediaId: number
  kind: PartKind
  sequence: number
  label: string
  title: string
  cover: string
  banner: string
  format: string | null
  status: string | null
  isReleasing: boolean
  totalEpisodes: number
  airedEpisodes: number
  nextEpisodeNumber: number | null
  nextAiringAt: number | null
  lastAiredAt: number | null
  synopsis: string
  genres: string[]
  progress: number
}

export interface Franchise {
  id: string
  title: string
  cover: string
  banner: string
  synopsis: string
  genres: string[]
  isReleasing: boolean
  partCounts: Partial<Record<PartKind, number>>
  parts: FranchisePart[]
  subscription: { status: WatchStatus } | null
}

export interface FranchiseSummary {
  id: string
  title: string
  cover: string
  banner: string
  isReleasing: boolean
  partCount: number
  nextAiringAt: number | null
  status?: WatchStatus
  behind?: number
  newParts?: number
}

export type LibraryFranchise = Franchise & { status: WatchStatus; behind: number; newParts: number }
