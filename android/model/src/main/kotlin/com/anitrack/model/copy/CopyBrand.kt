package com.anitrack.model.copy

/*
 * THE NAME — one home for it, because it had already drifted.
 *
 * The wordmark was spelled at four independent sites before this file existed: Today's header
 * declared `"Previously."` with the full stop baked into the constant, the splash declared
 * `"Previously"` and drew the period separately in accent, the auth gate declared a third
 * `"Previously"`, and `res/values/strings.xml` carried `app_name` as `"Previously."`. Two of them
 * already disagreed about whether the period is part of the string — which is the exact failure the
 * copy law exists to prevent, arrived at through the one string in the app that is never allowed to
 * vary.
 *
 * **The period belongs to the name.** "Previously." is the brand; "Previously" is an adverb. So
 * [wordmark] is the whole name, and [word] / [period] exist only for the ONE lockup that draws them
 * in two inks (the splash's, where the period is the ember). A surface that wants the name and has
 * nothing to say about its colour uses [wordmark] and nothing else.
 *
 * `app_name` in `strings.xml` is the single unavoidable second copy — the launcher reads it out of
 * the manifest before any of this app's code runs, and a manifest attribute can only reference a
 * resource. `StringResourceCopyTest` asserts the two agree, so the duplication is checked rather
 * than trusted.
 */
object CopyBrand {

    /**
     * The name, whole. **Never a clause subject** — stripped of its full stop the name reverts to
     * its ordinary meaning, so "Previously couldn’t reach the server" parses as the adverb and says
     * the opposite of what it means.
     */
    const val wordmark = "Previously."

    /** The name's word, for the two-ink lockup only. Its period is [period], drawn in accent. */
    const val word = "Previously"

    /** The lockup's second half. It is part of the name, not punctuation after it. */
    const val period = "."

    /**
     * What a screen reader hears in place of a lockup drawn in two colours (and in place of the
     * mark beside it). A trailing full stop is heard as the end of a sentence, so the spoken form
     * drops it — the one place the name is legitimately said without it.
     */
    const val spoken = "Previously"

    /**
     * The ident's line, under the mark, on the first screen every user sees. Set in small caps at
     * render; the string carries the caps because the lockup is a piece of artwork, not a sentence.
     */
    const val tagline = "ON EVERYTHING YOU WATCH"

    /**
     * The sign-in gate's line — the app's *other* brand line, and deliberately a different one:
     * the ident says what the app is about, the gate says what it does for you.
     *
     * They live together here so the two can be read together, which is the whole point: they were
     * declared in two files that never mention each other.
     */
    const val promise = "Know what changed. Record what you watched."
}
