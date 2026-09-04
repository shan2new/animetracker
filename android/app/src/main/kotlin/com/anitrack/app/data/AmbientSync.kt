package com.anitrack.app.data

import android.util.Log
import com.anitrack.model.Franchise
import kotlinx.coroutines.CancellationException

/*
 * The [AmbientSync] fan-out.
 *
 * A file of its own rather than a third declaration under the interface in `WritePolicy.kt`,
 * because that file also hosts `ProgressLane` — the one class here deliberately free of Android
 * imports so a virtual-time scheduler can drive it from a plain JVM test. This needs
 * `android.util.Log`, and a swallowed failure with nowhere to report itself is the one thing a
 * fan-out must not be.
 */

/**
 * Every ambient surface as one, because the model is allowed to know about exactly one.
 *
 * There are two — the episode-alert scheduler and the home-screen widget — and they landed
 * separately behind the same seam on purpose. Composing them here rather than letting `AppModel`
 * hold a list keeps the model's contract at "push the library into the ambient layer" instead of
 * "push it into each of the ambient layers", which is the difference between adding a third surface
 * later and re-opening the model to do it.
 *
 * **Each member is isolated from the others.** [sync]'s whole contract is that it must not throw —
 * it is awaited inside the *successful* branch of `reload()`, where an escaping exception is read as
 * a library failure and paints "couldn't refresh" over a library that had just arrived intact. Both
 * implementations already swallow their own failures, so this `try` is not a third belt over the
 * same waist: it is what stops one surface's failure from cancelling the surfaces *after* it in the
 * list. Without it a `SecurityException` out of `AlarmManager` — the ordinary consequence of
 * revoking "Alarms & reminders" mid-session — would skip the widget refresh that follows it, and the
 * card on the home screen would sit on yesterday's episode with nothing anywhere to say why.
 *
 * Cancellation is the one thing that does propagate: it is the caller's own scope going away, not a
 * surface failing, and swallowing it would leave the remaining members running work nobody wants.
 */
class CompositeAmbientSync(private val members: List<AmbientSync>) : AmbientSync {

    constructor(vararg members: AmbientSync) : this(members.toList())

    override suspend fun sync(library: List<Franchise>, now: Long) {
        for (member in members) {
            try {
                member.sync(library, now)
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (t: Throwable) {
                Log.w(AMBIENT_LOG_TAG, "ambient surface ${member.javaClass.simpleName} failed", t)
            }
        }
    }

    /**
     * Sign-out. Every member is torn down even if an earlier one throws — a surface that kept the
     * previous account's episodes armed because a *different* surface failed is the exact leak this
     * method exists to prevent.
     */
    override fun cancelAll() {
        for (member in members) {
            runCatching { member.cancelAll() }
                .onFailure { Log.w(AMBIENT_LOG_TAG, "couldn’t cancel ${member.javaClass.simpleName}", it) }
        }
    }
}

private const val AMBIENT_LOG_TAG = "Ambient"
