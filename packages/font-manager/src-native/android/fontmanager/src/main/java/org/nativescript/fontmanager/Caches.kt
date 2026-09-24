package org.nativescript.fontmanager

import android.graphics.Typeface
import java.io.File

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

internal object TypefaceCache {
  private const val MAX_ENTRIES = 64

  private val cache = LruMap<String, Typeface>(MAX_ENTRIES)

  private inline fun get(key: String, create: () -> Typeface): Typeface {
    cache[key]?.let { return it }
    val created = create()
    cache[key] = created
    return created
  }

  fun fromFile(file: File): Typeface =
    get("file:${file.absolutePath}:${file.lastModified()}:${file.length()}") {
      Typeface.createFromFile(file)
    }

  fun fromFamily(family: String, style: Int): Typeface =
    get("family:$family:$style") { Typeface.create(family, style) }

  fun fromResource(resId: Int, create: () -> Typeface): Typeface =
    get("res:$resId", create)

  fun weighted(family: String, style: Int, weight: Int, italic: Boolean): Typeface =
    get("weighted:$family:$style:$weight:$italic") { Typeface.create(fromFamily(family, style), weight, italic) }

  fun clear() = cache.clear()
}
