// Moderation decisions for the social layer (docs/api-contract.md, "Social"). Pure.
//
// A comment is auto-hidden once `threshold` DISTINCT people have reported it (env
// SOCIAL_AUTO_HIDE_REPORTS; `comments.report_count` counts one per reporter, because
// `reports` is unique on (reporter, comment)). A comment that is already hidden — by earlier
// reports or by the operator — is never re-stamped, so its `hidden_reason` and time stay the
// first decision's. The operator's `restore` resets the count to 0, so N NEW reporters are needed
// to hide it again.
//
// `report_count` is RECOMPUTED on every report (services/comments.ts `fileReport`), never
// incremented: it counts the comment's OPEN reports whose reporter's account is at least
// SOCIAL_REPORTER_MIN_AGE_HOURS old (`countsTowardAutoHide`). So an erased reporter's report (it
// goes with their account) stops counting, and "report, delete account, sign back in, report
// again" cannot hide a comment single-handed: each new account is too young to count for a day.
// Every report is still stored, logged and alerted — a young account's report reaches the
// operator, it just cannot hide anything by itself.

export interface AutoHideInput {
  /** Distinct reporters after this report was counted. */
  reportCount: number
  /** SOCIAL_AUTO_HIDE_REPORTS (≥ 1). */
  threshold: number
  /** The comment's current `hidden_at`; anything non-null means already hidden. */
  hiddenAt: Date | number | string | null | undefined
}

export function shouldAutoHide({ reportCount, threshold, hiddenAt }: AutoHideInput): boolean {
  return hiddenAt == null && reportCount >= threshold
}

const HOUR_MS = 3_600_000

/** The newest account creation time whose reports still count at `nowMs`. */
export function reporterCutoff(nowMs: number, minAgeHours: number): Date {
  return new Date(nowMs - Math.max(0, minAgeHours) * HOUR_MS)
}

export interface CountableReport {
  /** The report's `resolved_at`: a resolved report no longer counts. */
  resolvedAt: Date | number | string | null | undefined
  /** The reporter's `users.created_at`. */
  reporterCreatedAt: Date | number
}

/** Whether a report counts toward `report_count`: open, and filed by an account old enough. */
export function countsTowardAutoHide(
  report: CountableReport,
  opts: { nowMs: number; minAgeHours: number },
): boolean {
  if (report.resolvedAt != null) return false
  const created = report.reporterCreatedAt instanceof Date ? report.reporterCreatedAt.getTime() : report.reporterCreatedAt
  return created <= reporterCutoff(opts.nowMs, opts.minAgeHours).getTime()
}

/** `report_count` over a comment's reports (the SQL in `fileReport` computes exactly this). */
export function autoHideCount(
  reports: readonly CountableReport[],
  opts: { nowMs: number; minAgeHours: number },
): number {
  return reports.filter((r) => countsTowardAutoHide(r, opts)).length
}
