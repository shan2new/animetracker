package com.anitrack.model

import kotlinx.serialization.Serializable
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Regression guard for the defect that made the whole library undecodable on first run:
 * **`coerceInputValues = true` peeks — and CONSUMES — the token of any element whose descriptor
 * reports [kotlinx.serialization.descriptors.SerialKind.ENUM].**
 *
 * kotlinx's `tryCoerceValue` runs before the property's own deserializer, and for an ENUM-kind
 * element it calls `lexer.peekString()`, which is a peek only in the sense that it stashes the
 * result in `peekedString` — the lexer cursor moves past the value. `decodeString()` consults that
 * stash, so a plain enum property is unaffected; `decodeJsonElement()` does not, so it resumes at
 * the delimiter after the value and dies on `Unexpected JSON token ... unexpected comma`.
 *
 * Every safe wrapper in this module is built on `decodeJsonElement()` — that is the whole point of
 * [SafeSerializer], which must consume the failed value exactly once so one bad field cannot
 * desynchronise the rest of the object. So an enum behind a safe wrapper was a guaranteed failure
 * of the ENTIRE payload, and `$.franchises[0].source` is the first enum on the wire: not one show
 * missing a badge, but "Couldn't load your library" on every screen.
 *
 * The fix is in the wrappers' `descriptor`, not at these call sites, so the tests below are written
 * against the real payload shape — an enum field followed by another field.
 */
class EnumCoercionTest {

    @Serializable
    private data class Row(
        val id: String,
        @Serializable(with = MediaSourceSerializer::class) val source: MediaSource = MediaSource.ANILIST,
        @Serializable(with = SafeWatchStatus::class) val status: WatchStatus? = null,
        @Serializable(with = PartKindSerializer::class) val kind: PartKind = PartKind.SEASON,
        val title: String,
    )

    /** The exact shape that failed: a known enum value with a field after it. */
    @Test
    fun `a known enum value decodes and the fields after it survive`() {
        val row = AniTrackJson.decodeFromString(
            Row.serializer(),
            """{"id":"a","source":"tmdb","status":"watching","kind":"movie","title":"Andor"}""",
        )
        assertEquals(MediaSource.TMDB, row.source)
        assertEquals(WatchStatus.WATCHING, row.status)
        assertEquals(PartKind.MOVIE, row.kind)
        assertEquals("Andor", row.title)
    }

    /** An unrecognised constant falls back without taking the object with it. */
    @Test
    fun `an unknown enum constant falls back to the default`() {
        val row = AniTrackJson.decodeFromString(
            Row.serializer(),
            """{"id":"a","source":"crunchyroll","status":"rewatching","kind":"webtoon","title":"X"}""",
        )
        assertEquals(MediaSource.ANILIST, row.source)
        assertEquals(null, row.status)
        assertEquals(PartKind.SEASON, row.kind)
        assertEquals("X", row.title)
    }

    /** A type mismatch is the case plain `coerceInputValues` never covered. */
    @Test
    fun `a wrong-typed enum field falls back and the object still decodes`() {
        val row = AniTrackJson.decodeFromString(
            Row.serializer(),
            """{"id":"a","source":7,"status":{"v":1},"kind":["season"],"title":"X"}""",
        )
        assertEquals(MediaSource.ANILIST, row.source)
        assertEquals(null, row.status)
        assertEquals(PartKind.SEASON, row.kind)
        assertEquals("X", row.title)
    }

    /** An explicit null on a non-nullable enum property reads as the default. */
    @Test
    fun `a null enum field reads as the default`() {
        val row = AniTrackJson.decodeFromString(
            Row.serializer(),
            """{"id":"a","source":null,"status":null,"kind":null,"title":"X"}""",
        )
        assertEquals(MediaSource.ANILIST, row.source)
        assertEquals(null, row.status)
        assertEquals(PartKind.SEASON, row.kind)
        assertEquals("X", row.title)
    }

    /** The payload the app actually failed on, trimmed to the two fields that mattered. */
    @Test
    fun `a library payload decodes end to end`() {
        val json = """
            {"franchises":[{"id":"13711bf524","source":"anilist","title":"The Exiled Heavy Knight",
             "parts":[],"status":"watching"}],"prevOpenedAt":1757000000000}
        """.trimIndent()
        val page = AniTrackJson.decodeFromString(LibraryResponse.serializer(), json)
        assertEquals(1, page.franchises.size)
        assertEquals(MediaSource.ANILIST, page.franchises[0].source)
        assertEquals("The Exiled Heavy Knight", page.franchises[0].title)
    }
}
