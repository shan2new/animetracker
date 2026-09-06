package com.anitrack.app.data.api

import com.anitrack.app.BuildConfig
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.util.Calendar

/**
 * `--ez demoBusy true` — a synthetic library state for CAPTURES, in the same family as
 * `--ez calmDemo true` and `--ez scheduleDemoStates true`. The Android port of iOS's
 * `DemoLibrary.swift`.
 *
 * The QA account is permanently caught up (every watching show sits at `behind: 0`), so the state
 * Today actually exists to serve — a couple of drops waiting, a few shows mid-way through whose
 * run has finished — cannot be photographed from real data without writing fake progress into the
 * user's account. This rewrites the `/me/library` PAYLOAD on the way in instead: no model changes,
 * no writes, and the screen renders it exactly as it would render the real thing.
 *
 * The shape it builds:
 *  - two RELEASING shows whose latest episode struck YESTERDAY and is unwatched (`behind: 1`)
 *  - three shows still in progress whose broadcast is OVER (backlog, no airings)
 *
 * Everything else is filed `completed` so it cannot crowd the stack.
 *
 * DEBUG only, by construction: [isOn] is hard `false` in a release build, so the rewrite is dead
 * code the optimiser removes.
 */
object DemoLibrary {

    @Volatile
    var enabled: Boolean = false

    val isOn: Boolean get() = BuildConfig.DEBUG && enabled

    /** Titles are matched by substring so the fixture survives a catalogue rename. */
    private val freshTitles = listOf("Daemons", "Bleach", "Re:ZERO")
    private val backlogTitles = listOf("Game of Thrones", "House of the Dragon", "The Witcher")

    private const val DAY_MS = 86_400_000L

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    fun rewriteIfNeeded(path: String, body: String): String {
        if (!isOn || path != "/me/library") return body
        return runCatching { rewrite(body) }.getOrDefault(body)
    }

    private fun rewrite(body: String): String {
        val root = json.parseToJsonElement(body).jsonObject
        val franchises = root["franchises"]?.jsonArray ?: return body

        // Yesterday at 20:00 local, so the drop reads "Aired yesterday" rather than "23h ago".
        val cal = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, -1)
            set(Calendar.HOUR_OF_DAY, 20)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val dropAt = cal.timeInMillis

        val rewritten = buildJsonArray {
            for (element in franchises) {
                add(rewriteFranchise(element.jsonObject, dropAt))
            }
        }
        return json.encodeToString(
            JsonObject.serializer(),
            JsonObject(root.toMutableMap().apply { put("franchises", rewritten) }),
        )
    }

    private fun rewriteFranchise(f: JsonObject, dropAt: Long): JsonObject {
        val title = f["title"]?.jsonPrimitive?.contentOrNullSafe().orEmpty()
        val parts = f["parts"]?.jsonArray?.map { it.jsonObject } ?: return f
        if (parts.isEmpty()) return f

        return when {
            title.matchesAny(freshTitles) -> fresh(f, parts, dropAt)
            title.matchesAny(backlogTitles) -> backlog(f, parts, dropAt, stillAiring = title.contains("Witcher", true))
            // Everything else is done, so the stack is exactly the fixture.
            else -> completed(f, parts)
        }
    }

    /** A releasing show whose latest episode struck yesterday and is unwatched. */
    private fun fresh(f: JsonObject, parts: List<JsonObject>, dropAt: Long): JsonObject {
        // The highest-sequence episodic part is the one still on air.
        val idx = parts.indices.maxByOrNull { parts[it].intOr("sequence", 0) } ?: return f
        val watched = maxOf(1, parts[idx].intOr("progress", 1))
        val dropped = watched + 1
        val newParts = parts.mapIndexed { i, p ->
            if (i != idx) p else p.edit {
                put("isReleasing", JsonPrimitive(true))
                put("progress", JsonPrimitive(watched))
                put("airedEpisodes", JsonPrimitive(dropped))
                put("lastAiredAt", JsonPrimitive(dropAt))
                put("totalEpisodes", JsonPrimitive(maxOf(dropped + 4, p.intOr("totalEpisodes", 0))))
                put("nextEpisodeNumber", JsonPrimitive(dropped + 1))
                put("nextAiringAt", JsonPrimitive(dropAt + 7 * DAY_MS))
                put("nextAiringCount", JsonPrimitive(1))
                put(
                    "airings",
                    buildJsonArray {
                        add(airing(dropped, dropAt))
                        add(airing(dropped + 1, dropAt + 7 * DAY_MS))
                    },
                )
            }
        }
        return f.edit {
            put("status", JsonPrimitive("watching"))
            put("isReleasing", JsonPrimitive(true))
            put("behind", JsonPrimitive(1))
            put("parts", JsonArray(newParts))
        }
    }

    /**
     * Mid-way through a run that has finished airing: no airings, nothing upcoming.
     *
     * One of them keeps a RUNNING season whose last drop is older than the out-now window —
     * backlog, but still on air. That is the state the airing dot exists for, and it cannot occur
     * in the two clean buckets.
     */
    private fun backlog(f: JsonObject, parts: List<JsonObject>, dropAt: Long, stillAiring: Boolean): JsonObject {
        var newParts = parts.map { p ->
            p.edit {
                put("isReleasing", JsonPrimitive(false))
                put("airings", JsonArray(emptyList()))
                put("nextAiringAt", JsonNull)
                put("nextEpisodeNumber", JsonNull)
            }
        }
        if (stillAiring) {
            val s = newParts.indices
                .filter { newParts[it]["kind"]?.jsonPrimitive?.contentOrNullSafe() == "season" }
                .maxByOrNull { newParts[it].intOr("sequence", 0) }
            if (s != null) {
                newParts = newParts.mapIndexed { i, p ->
                    if (i != s) p else p.edit {
                        put("isReleasing", JsonPrimitive(true))
                        put("lastAiredAt", JsonPrimitive(dropAt - 9 * DAY_MS))
                        put("nextAiringAt", JsonPrimitive(dropAt + 5 * DAY_MS))
                        put("airings", buildJsonArray { add(airing(4, dropAt + 5 * DAY_MS)) })
                    }
                }
            }
        }
        // The first SEASON, never the sequence-0 special: `episodicParts` excludes specials, so a
        // backlog written onto one is invisible to the resume logic.
        val seasons = newParts.indices
            .filter { newParts[it]["kind"]?.jsonPrimitive?.contentOrNullSafe() == "season" }
        val idx = seasons.minByOrNull { newParts[it].intOr("sequence", 0) } ?: return f.edit {
            put("status", JsonPrimitive("watching"))
            put("parts", JsonArray(newParts))
        }
        val total = maxOf(8, newParts[idx].intOr("totalEpisodes", 8))
        newParts = newParts.mapIndexed { i, p ->
            if (i != idx) p else p.edit {
                put("totalEpisodes", JsonPrimitive(total))
                put("airedEpisodes", JsonPrimitive(total))
                put("progress", JsonPrimitive(maxOf(1, total / 3)))
            }
        }
        return f.edit {
            put("status", JsonPrimitive("watching"))
            put("isReleasing", JsonPrimitive(stillAiring))
            put("behind", JsonPrimitive(0))
            put("parts", JsonArray(newParts))
        }
    }

    private fun completed(f: JsonObject, parts: List<JsonObject>): JsonObject {
        val newParts = parts.map { p ->
            val avail = maxOf(p.intOr("airedEpisodes", 0), p.intOr("totalEpisodes", 0))
            p.edit {
                put("isReleasing", JsonPrimitive(false))
                put("airings", JsonArray(emptyList()))
                put("nextAiringAt", JsonNull)
                put("progress", JsonPrimitive(avail))
            }
        }
        return f.edit {
            put("status", JsonPrimitive("completed"))
            put("isReleasing", JsonPrimitive(false))
            put("behind", JsonPrimitive(0))
            put("parts", JsonArray(newParts))
        }
    }

    private fun airing(episode: Int, at: Long): JsonObject = buildJsonObject {
        put("episode", JsonPrimitive(episode))
        put("at", JsonPrimitive(at))
    }

    private fun String.matchesAny(prefixes: List<String>): Boolean =
        prefixes.any { this.contains(it, ignoreCase = true) }

    private fun JsonObject.intOr(key: String, fallback: Int): Int =
        runCatching { this[key]?.jsonPrimitive?.int }.getOrNull() ?: fallback

    private fun JsonPrimitive.contentOrNullSafe(): String? = if (this is JsonNull) null else content

    private inline fun JsonObject.edit(block: MutableMap<String, JsonElement>.() -> Unit): JsonObject =
        JsonObject(toMutableMap().apply(block))
}
