package com.anitrack.model.copy

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `Copy.auditProblems` re-homed as the CI gate PLAN M1 asks for.
 *
 * On iOS these invariants render in a SwiftUI preview that must come up empty; a preview nobody
 * opens is not a gate, so here they fail the build. The voice laws under test: no straight
 * apostrophe, no exclamation mark, no `E19`-style episode notation, no unpaired ellipsis (an
 * action that ends in one MUST open a confirmation), and no confirmation button that ends in one.
 *
 * **The corpus is the whole catalogue, not `Copy`'s own members.** It used to be exactly those —
 * Action / Confirm / Toast / Notice / Progress / State / statuses plus `EmptyStateCopy` — which
 * clears the `size > 50` floor below on its own, so the gate read as healthy while `CopyLibrary`,
 * `CopySearch`, `CopyAlerts` and everything in `CopyScreens.kt` shipped unchecked, and the five
 * satellite copy objects staged in `:app` were not reachable from here at all. Both halves of that
 * are fixed: the satellites are sibling namespaces now, and [everyDeclaredString] sweeps every
 * namespace's constants reflectively so a new one is audited the moment it is declared, without
 * anybody having to remember to register it.
 */
class CopyAuditTest {

    /**
     * Every namespace in the catalogue. A new sibling object is added here — and
     * the last test below fails until it is, because `Copy`'s own getters are the cross-check.
     */
    private val namespaces: List<Any> = listOf(
        Copy,
        Copy.Action, Copy.Alert, Copy.Confirm, Copy.Heading, Copy.Label, Copy.Notice,
        Copy.Progress, Copy.State, Copy.Toast, Copy.Accessibility,
        CopyAlerts, CopyAuth, CopyBrand, CopyDetail, CopyFilter, CopyLibrary, CopyPeople,
        CopyProfile, CopyRecap, CopyRewatch, CopySchedule, CopySearch,
        CopyVideo, CopyWatch, CopyAccount,
    )

    /**
     * Every `const val` / `val` String declared on those objects.
     *
     * Java reflection rather than `kotlin-reflect` (which is not on this module's classpath): a
     * `const val` compiles to a static final field on the object's class and a plain `val` to a
     * private instance field with a getter, and reading the FIELDS catches both without having to
     * guess at getter names. Parameterised strings cannot be read off a class at all — those are
     * listed by hand in `Copy.allSampleStrings`.
     */
    private fun everyDeclaredString(): List<String> = namespaces.flatMap { namespace ->
        namespace.javaClass.declaredFields
            .filter { it.type == String::class.java }
            .mapNotNull { field ->
                field.isAccessible = true
                field.get(namespace) as? String
            }
    }

    @Test
    fun `the copy table is sound`() {
        val problems = Copy.auditProblems
        assertEquals(
            "copy audit found ${problems.size} problem(s):\n" + problems.joinToString("\n"),
            0,
            problems.size,
        )
    }

    @Test
    fun `every declared string obeys the voice laws`() {
        val declared = everyDeclaredString()
        val problems = Copy.audit(declared)
        assertEquals(
            "copy audit found ${problems.size} problem(s) among ${declared.size} declared " +
                "strings:\n" + problems.joinToString("\n"),
            0,
            problems.size,
        )
    }

    @Test
    fun `the audit actually walks a corpus`() {
        // A table that stopped enumerating itself would pass the audit vacuously. The floor is set
        // above what `Copy`'s own members alone can supply, so a regression to the narrow corpus
        // fails here rather than passing quietly.
        assertTrue(Copy.allSampleStrings.size > 150)
        assertTrue(everyDeclaredString().size > 250)
    }

    @Test
    fun `the sweep reaches every namespace the table publishes`() {
        // `Copy` wires each sibling object in with a getter. If one is added and not swept, the
        // gate is narrower than it looks — which is exactly how the last gap happened.
        val published = listOf(
            Copy.Alert, Copy.Brand, Copy.Profile, Copy.Detail, Copy.Auth, Copy.Library,
            Copy.Search, Copy.Recap, Copy.Rewatch, Copy.Account, Copy.Filter, Copy.Schedule,
            Copy.Video, Copy.People, Copy.Watch,
        )
        val missing = published.filter { one -> namespaces.none { it === one } }
        assertEquals("namespaces published by Copy but not swept: $missing", 0, missing.size)
    }

    @Test
    fun `banned notation is detected`() {
        assertTrue(Copy.hasBannedNotation("E19"))
        assertTrue(Copy.hasBannedNotation("Ep 19"))
        assertTrue(Copy.hasBannedNotation("Ep.19"))
        assertTrue(Copy.hasBannedNotation("S5 E19"))
        assertTrue(!Copy.hasBannedNotation(Copy.episode(19)))
    }

    @Test
    fun `the brand is spelled once`() {
        // The wordmark had already drifted across four files before `CopyBrand` existed: two of
        // them disagreed about whether the period is part of the name.
        assertEquals(CopyBrand.wordmark, CopyBrand.word + CopyBrand.period)
        assertEquals(CopyBrand.word, CopyBrand.spoken)
    }
}
