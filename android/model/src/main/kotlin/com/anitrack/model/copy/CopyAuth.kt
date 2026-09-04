package com.anitrack.model.copy

/*
 * THE SIGN-IN GATE — the auth surface's own strings.
 *
 * They kept themselves at their call sites for a while, mirroring iOS (`SignInView.swift`,
 * `AuthManager.swift`, which do the same); the reason given was that a Kotlin object cannot be
 * reopened from `:app` to add to `Copy`. That was true and beside the point — nothing stopped them
 * living in the catalogue package as a sibling object, which is what they do now. `Copy.Auth.*`.
 *
 * Everything that has a home in the shared table is read from there rather than restated:
 * `Copy.State.signedOut` is the string `APIError.unauthorized` carries, `Copy.Account.signedInWithClerk`
 * is the provenance line, and the brand's own words are `Copy.Brand`'s — this file used to declare
 * a third spelling of the wordmark and a second, different tagline.
 */
object CopyAuth {


    /** `AuthManager.signInDev` rejects an empty id without touching any state. */
    const val ENTER_DEV_USER_ID = "Enter a dev user id."

    /** The gate's one action. */
    const val SIGN_IN = "Sign in"

    /**
     * The fail-closed branch. "no key, no field, no bypass, and nothing a reviewer could mistake
     * for a way in. The condition is a build misconfiguration, so it is stated as one rather than
     * dressed up as a temporary outage the user could wait out."
     */
    const val UNAVAILABLE_IN_THIS_BUILD = "Sign-in isn’t available in this build."

    const val DEVELOPER_SIGN_IN = "Developer sign-in"

    const val DEVELOPER_EXPLAINER =
        "No Clerk key configured. Sign in with a dev user id (the backend must allow " +
            "DEV_AUTH_BYPASS outside production)."

    const val DEV_USER_ID_PLACEHOLDER = "dev user id"
}
