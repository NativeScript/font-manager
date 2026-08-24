package org.nativescript.fontmanager

import android.graphics.Typeface
import java.io.File

/**
 * Small synchronized LRU. Deliberately not [android.util.LruCache] so this stays
 * usable from local unit tests (no android.jar stubs required).
 */
internal class LruMap<K : Any, V : Any>(private val maxEntries: Int) {
  private val map = object : LinkedHashMap<K, V>(16, 0.75f, true) {
    override fun removeEldestEntry(eldest: MutableMap.MutableEntry<K, V>): Boolean =
      size > maxEntries
  }

  operator fun get(key: K): V? = synchronized(map) { map[key] }

  operator fun set(key: K, value: V) {
    synchronized(map) { map[key] = value }
  }

  fun clear() {
    synchronized(map) { map.clear() }
  }
}

/**
 * Process wide [Typeface] cache.
 *
 * Every `Typeface.createFromFile` re-parses and re-uploads the font file, and
 * `Typeface.create` walks the system font config, so repeated loads of the same
 * face were paying full price each time. Typefaces are immutable and safe to share.
 */
internal object TypefaceCache {
  private const val MAX_ENTRIES = 64

  private val cache = LruMap<String, Typeface>(MAX_ENTRIES)

  private inline fun get(key: String, create: () -> Typeface): Typeface {
    cache[key]?.let { return it }
    // A race here can create the same Typeface twice; both are equivalent and
    // the loser is simply dropped, which is cheaper than holding a lock across
    // font parsing.
    val created = create()
    cache[key] = created
    return created
  }

  /** Keyed on identity + mtime + size so a re-downloaded file invalidates itself. */
  fun fromFile(file: File): Typeface =
    get("file:${file.absolutePath}:${file.lastModified()}:${file.length()}") {
      Typeface.createFromFile(file)
    }

  fun fromFamily(family: String, style: Int): Typeface =
    get("family:$family:$style") { Typeface.create(family, style) }

  fun fromResource(resId: Int, create: () -> Typeface): Typeface =
    get("res:$resId", create)

  /** [baseKey] must identify [base]; it is what makes the derived entry unique. */
  fun weighted(base: Typeface, baseKey: String, weight: Int, italic: Boolean): Typeface =
    get("weighted:$baseKey:$weight:$italic") { Typeface.create(base, weight, italic) }

  fun clear() = cache.clear()
}
