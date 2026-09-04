package com.anitrack.app.data

import android.content.Context
import android.content.SharedPreferences
import com.anitrack.model.AniTrackJson
import com.anitrack.model.FranchiseSummary
import com.anitrack.model.LibraryResponse
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import java.io.File
import java.util.UUID

/*
 * # The two on-device stores the model hydrates from at launch
 *
 * [LibraryCache] — the last library this device saw. **A launch with no network opens on the shows,
 * not on an error.** The app had no copy at all once: a bad connection at launch was "Couldn't
 * reach the server" over nothing, seconds after the library had been on screen.
 *
 * [RecentsStore] — the search surface's memory: the terms typed and, more usefully, the shows
 * found. Apple Music's model — the things you found, not the strings you typed.
 *
 * Both are read **synchronously**, once, during construction of the model. That is why neither uses
 * DataStore: the offline copy has to be in `library` before the first frame or the first frame is
 * the empty state, and the recents have to be in hand before the search tab can compose. A
 * `runBlocking` on a `Flow` in a constructor would be a worse answer to the same requirement than
 * the synchronous read `SharedPreferences` and `File` already offer.
 */

// ---------------------------------------------------------------------------------------------
// MARK: - The offline library copy
// ---------------------------------------------------------------------------------------------

/**
 * The snapshot on disk, and the moment it was taken.
 *
 * [savedAt] is the cache's **own** timestamp, adopted as `lastLoadedAt` when the cache is used — so
 * a launch from cache immediately shows the honest stale strip and inline notice rather than
 * claiming the data is fresh.
 */
@Serializable
data class CachedLibrary(
    val response: LibraryResponse,
    val savedAt: Long,
)

/**
 * `library-cache.json`, written after every successful reload and deleted on sign-out.
 *
 * Every read and write swallows its failure: a corrupt or missing file is simply "no cache", and a
 * failed write leaves the previous file intact. Nothing here may ever surface as an error — the
 * cache is a courtesy, and a courtesy that can fail loudly is worse than none.
 *
 * @param dir the app's own files directory. Not `cacheDir`: an offline copy the system may evict
 *   between a flight taking off and landing is not an offline copy. This mirrors iOS, which keeps
 *   it in Application Support.
 */
class LibraryCache(
    private val dir: File,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO),
) {

    private val file: File get() = File(dir, FILE_NAME)

    /**
     * One save at a time. Two reloads can land together — a pull-to-refresh over the reload a
     * foreground already started — and both used to write the SAME `library-cache.json.tmp`: two
     * interleaved payloads in one file, renamed into place as the offline copy. The next launch
     * with no network then opened on a decode failure, which is the exact morning this cache
     * exists to prevent.
     */
    private val writeLock = Mutex()

    /**
     * The stamp of the newest snapshot actually on disk. Guarded by [writeLock].
     *
     * Two saves are serialised by the lock but not *ordered* by it — the dispatcher decides which
     * waiter goes first — so without this an older library could be the one left on disk, and the
     * next offline launch would open on a copy the device had already replaced.
     */
    private var lastSavedAt = 0L

    /**
     * Bumped by [clear]. A save queued before a sign-out must not land after it: the delete would
     * be undone by a coroutine still holding the previous account's library, and the next person to
     * open the app on this device would hydrate from their shows.
     */
    @Volatile
    private var generation = 0

    /** The cached snapshot, or `null` for "no cache" — including every failure mode. */
    fun load(): CachedLibrary? = runCatching {
        val f = file
        if (!f.exists()) return null
        AniTrackJson.decodeFromString(CachedLibrary.serializer(), f.readText())
    }.getOrNull()

    /**
     * Persist a snapshot, off the main thread.
     *
     * Written to a sibling temp file and renamed into place, which is the Android spelling of iOS's
     * `Data.write(options: .atomic)`: **a launch can never read a half-written file.**
     */
    fun save(response: LibraryResponse, at: Long) {
        val snapshot = CachedLibrary(response = response, savedAt = at)
        val gen = generation
        scope.launch {
            // Suspends OUTSIDE the `runCatching`: a `runCatching` around a suspension point also
            // swallows the `CancellationException` thrown while it is parked.
            writeLock.withLock {
                // The account this snapshot belongs to has signed out. See [generation].
                if (gen != generation) return@withLock
                // An older payload that lost the race to the lock has nothing to add.
                if (at < lastSavedAt) return@withLock
                // A name no concurrent writer can be holding, so even two `LibraryCache` instances
                // (a sign-out and the account after it) cannot share a half-written scratch file.
                val tmp = File(dir, "$FILE_NAME.${UUID.randomUUID()}.tmp")
                val written = runCatching {
                    dir.mkdirs()
                    // Any OTHER scratch file here belongs to a process that died mid-write: this
                    // cache is a singleton and its lock is held, so nothing alive owns one. Unique
                    // names would otherwise accumulate a copy of the library per unlucky kill, in
                    // `filesDir`, where the system never reclaims them.
                    dir.listFiles()?.forEach { f ->
                        if (f != tmp && f.name.startsWith("$FILE_NAME.") && f.name.endsWith(".tmp")) {
                            f.delete()
                        }
                    }
                    tmp.writeText(AniTrackJson.encodeToString(CachedLibrary.serializer(), snapshot))
                    // `rename(2)` REPLACES the destination atomically, so the previous copy stands
                    // until the instant the new one takes its place — which is the promise this
                    // file makes ("a failed write leaves the previous file intact"). Deleting the
                    // target first, as this did, opened a window where a launch found no cache at
                    // all, and lost the good copy outright whenever the rename then failed.
                    var renamed = tmp.renameTo(file)
                    if (!renamed) {
                        file.delete()
                        renamed = tmp.renameTo(file)
                    }
                    renamed
                }.getOrDefault(false)
                if (written) lastSavedAt = at
                // The scratch file never outlives the attempt, whichever way it ended. (Also what
                // keeps this block Unit-typed, next to the early `return@withLock`s above.)
                if (tmp.exists()) runCatching { tmp.delete() }
            }
        }
    }

    /** Sign-out. The copy belongs to the account that fetched it. */
    fun clear() {
        // Before the delete, so a save already queued on IO can see it and stand down. Nothing
        // resets [lastSavedAt]: it is only ever compared against a wall clock, and every stamp the
        // next account writes is larger than every stamp this one did.
        generation += 1
        runCatching { file.delete() }
    }

    private companion object {
        const val FILE_NAME = "library-cache.json"
    }
}

// ---------------------------------------------------------------------------------------------
// MARK: - Recents
// ---------------------------------------------------------------------------------------------

/**
 * The two recents lists, persisted under the **same keys iOS uses** so the two ports name the same
 * user state — `recentSearches` (terms) and `recentSearchItems` (shows).
 *
 * A decode failure leaves the list empty; it is never an error.
 */
class RecentsStore(private val prefs: SharedPreferences) {

    fun loadTerms(): List<String> = runCatching {
        val json = prefs.getString(TERMS_KEY, null) ?: return emptyList()
        AniTrackJson.decodeFromString(TERM_LIST, json)
    }.getOrElse { emptyList() }

    fun saveTerms(terms: List<String>) {
        val json = runCatching { AniTrackJson.encodeToString(TERM_LIST, terms) }.getOrNull() ?: return
        prefs.edit().putString(TERMS_KEY, json).apply()
    }

    fun loadItems(): List<FranchiseSummary> = runCatching {
        val json = prefs.getString(ITEMS_KEY, null) ?: return emptyList()
        AniTrackJson.decodeFromString(ListSerializer(FranchiseSummary.serializer()), json)
    }.getOrElse { emptyList() }

    fun saveItems(items: List<FranchiseSummary>) {
        val json = runCatching {
            AniTrackJson.encodeToString(ListSerializer(FranchiseSummary.serializer()), items)
        }.getOrNull() ?: return
        prefs.edit().putString(ITEMS_KEY, json).apply()
    }

    companion object {
        private val TERM_LIST = ListSerializer(String.serializer())

        /** iOS `UserDefaults` key, kept identical. */
        const val TERMS_KEY = "recentSearches"

        /** iOS `UserDefaults` key, kept identical. */
        const val ITEMS_KEY = "recentSearchItems"

        const val PREFS_NAME = "previously.recents"

        fun from(context: Context): RecentsStore = RecentsStore(
            context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE),
        )
    }
}
