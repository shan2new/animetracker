package com.anitrack.app

import com.anitrack.model.copy.Copy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * `res/values/strings.xml` is the one place user-facing copy lives outside the catalogue, and it
 * cannot be anywhere else: the launcher and the widget picker read `app_name` and
 * `widget_up_next_label` out of the MANIFEST, before any of this app's code runs, and a manifest
 * attribute can only reference a resource.
 *
 * So the duplication is unavoidable — but "kept in sync by hand", which is what the file's own
 * comment claimed, is not a mechanism. This is: two strings, checked against the entries they
 * duplicate, so the copy gate reaches the last two strings in the app that it otherwise could not.
 *
 * The third resource, `widget_up_next_description`, has no counterpart in the table (nothing else in
 * the app describes the widget), so it is audited for VOICE here instead — which is what
 * `CopyAuditTest` would do to it if it could see it.
 */
class StringResourceCopyTest {

    private val strings: Map<String, String> by lazy {
        val file = resolve("src/main/res/values/strings.xml")
        val xml = file.readText()
        Regex("""<string name="([^"]+)">(.*?)</string>""", RegexOption.DOT_MATCHES_ALL)
            .findAll(xml)
            .associate { it.groupValues[1] to it.groupValues[2] }
    }

    /**
     * A unit test's working directory is the module's own, but a runner that chooses the repo root
     * would otherwise fail on a path rather than on a claim.
     */
    private fun resolve(relative: String): File {
        var dir: File? = File(".").absoluteFile
        while (dir != null) {
            val candidate = File(dir, relative)
            if (candidate.exists()) return candidate
            val nested = File(dir, "app/$relative")
            if (nested.exists()) return nested
            dir = dir.parentFile
        }
        error("couldn’t find $relative from ${File(".").absolutePath}")
    }

    @Test
    fun `the launcher label is the wordmark`() {
        assertEquals(Copy.Brand.wordmark, strings.getValue("app_name"))
    }

    @Test
    fun `the widget picker's label is the table's own`() {
        assertEquals(Copy.Label.nextUp, strings.getValue("widget_up_next_label"))
    }

    @Test
    fun `the resource strings obey the voice laws`() {
        val problems = Copy.audit(strings.values.toList())
        assertEquals(problems.joinToString("\n"), 0, problems.size)
        assertTrue(strings.size >= 3)
    }
}
