package com.anitrack.model

/**
 * Time substrate. Every timestamp on the wire is milliseconds since the Unix epoch as a [Long],
 * mirroring the iOS models exactly (`docs/android-port/spec/models.md`).
 *
 * `java.time` is available natively at minSdk 26, so none of this needs desugaring.
 */
object Time {
    const val DAY_MS: Long = 86_400_000
    const val HOUR_MS: Long = 3_600_000
    const val MINUTE_MS: Long = 60_000
}
