package org.nativescript.fontmanager

import android.content.Context
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.abs

class FontFaceSet {
  /**
   * [add] and [delete] are called from JS while [load] reads the same maps on a pool
   * thread, so every touch of this group is under [lock]. Reads that escape the set
   * ([array], [iter], [forEach]) hand out a copy rather than a live view.
   */
  private val lock = Any()
  private val fonts = LinkedHashSet<FontFace>()
  private val fontsByFamily = mutableMapOf<String, MutableList<FontFace>>()
  private val reloadListeners = mutableMapOf<FontFace, (FontFace, String?) -> Unit>()

  enum class Status { Loading, Loaded }

  /** Read from the load count, so no interleaving of loads can leave it stale. */
  val status: Status
    get() = if (pendingLoads.get() == 0) Status.Loaded else Status.Loading

  private val statusListeners = CopyOnWriteArrayList<(Status) -> Unit>()
  private val loadingListeners = CopyOnWriteArrayList<(FontFace) -> Unit>()
  private val loadingDoneListeners = CopyOnWriteArrayList<(FontFace) -> Unit>()
  private val loadingErrorListeners = CopyOnWriteArrayList<(FontFace, String) -> Unit>()

  fun addOnStatusListener(listener: (Status) -> Unit) {
    statusListeners.add(listener)
  }

  fun removeOnStatusListener(listener: (Status) -> Unit) {
    statusListeners.remove(listener)
  }

  fun addOnLoadingListener(listener: (FontFace) -> Unit) {
    loadingListeners.add(listener)
  }

  fun removeOnLoadingListener(listener: (FontFace) -> Unit) {
    loadingListeners.remove(listener)
  }

  fun addOnLoadingDoneListener(listener: (FontFace) -> Unit) {
    loadingDoneListeners.add(listener)
  }

  fun removeOnLoadingDoneListener(listener: (FontFace) -> Unit) {
    loadingDoneListeners.remove(listener)
  }

  fun addOnLoadingErrorListener(listener: (FontFace, String) -> Unit) {
    loadingErrorListeners.add(listener)
  }

  fun removeOnLoadingErrorListener(listener: (FontFace, String) -> Unit) {
    loadingErrorListeners.remove(listener)
  }

  private val pendingLoads = AtomicInteger(0)
  private val readyCallbacks = mutableListOf<(FontFaceSet) -> Unit>()

  val iter: Iterator<FontFace>
    get() = array.iterator()

  val array: Array<FontFace>
    get() = synchronized(lock) { fonts.toTypedArray() }

  val size: Int
    get() = synchronized(lock) { fonts.size }

  fun add(font: FontFace) {
    val listener: (FontFace, String?) -> Unit = { reloadedFace, error ->
      if (error != null) {
        loadingErrorListeners.forEach { it(reloadedFace, error) }
      } else {
        loadingDoneListeners.forEach { it(reloadedFace) }
      }
    }
    synchronized(lock) {
      // The family index used to be appended to unconditionally, so re-adding a
      // face left a duplicate that delete() could not fully remove.
      if (!fonts.add(font)) return
      fontsByFamily.getOrPut(font.familyKey) { mutableListOf() }.add(font)
      reloadListeners[font] = listener
    }
    font.addOnReloadListener(listener)
  }

  fun delete(font: FontFace) {
    val listener = synchronized(lock) {
      if (!fonts.remove(font)) return
      val key = font.familyKey
      fontsByFamily[key]?.let { list ->
        list.remove(font)
        if (list.isEmpty()) fontsByFamily.remove(key)
      }
      reloadListeners.remove(font)
    }
    // Dropping the map entry alone left the face holding the listener, and through
    // it this set, for the rest of the process.
    listener?.let { font.removeOnReloadListener(it) }
  }

  fun clear() {
    val detached = synchronized(lock) {
      val entries = reloadListeners.toList()
      reloadListeners.clear()
      fonts.clear()
      fontsByFamily.clear()
      entries
    }
    for ((face, listener) in detached) face.removeOnReloadListener(listener)
  }

  fun has(font: FontFace): Boolean = synchronized(lock) { fonts.contains(font) }

  /**
   * Calls [callback] immediately when there are no pending font loads,
   * otherwise waits until all current loads complete.
   */
  fun ready(callback: (FontFaceSet) -> Unit) {
    // Registering and draining share [lock]: unsynchronized, a callback could be
    // added just after the last load drained the list and never be called at all.
    val idle = synchronized(lock) {
      if (pendingLoads.get() == 0) true else { readyCallbacks.add(callback); false }
    }
    if (idle) FontExecutors.main.execute { callback(this) }
  }

  /**
   * Only membership matters here — the caller discards the typeface — so this no
   * longer materializes one just to null-check it.
   */
  private fun isGenericFamily(familyKey: String): Boolean = familyKey in GENERIC_FAMILIES

  private fun resolveFonts(parsed: FontParser.Result): List<FontFace> = synchronized(lock) {
    for (familyKey in parsed.familyKeys) {
      val candidates = fontsByFamily[familyKey]
      if (!candidates.isNullOrEmpty()) {
        val best = candidates.minByOrNull { face ->
          abs(face.weight.weight - parsed.weight.weight) +
            if (face.style != parsed.style) 1000 else 0
        }
        if (best != null) return listOf(best)
      }
      if (isGenericFamily(familyKey)) return emptyList()
    }
    return emptyList()
  }

  /**
   * True when rendering with [font] would not start a load, as the CSS Font Loading
   * spec defines it: every matching face is loaded, or nothing in the set matches.
   */
  fun check(font: String, text: String?): Boolean {
    return try {
      val parsed = FontParser.parse(font) ?: return false
      resolveFonts(parsed).all { it.status == FontFaceStatus.Loaded }
    } catch (_: Exception) {
      false
    }
  }

  @JvmOverloads
  fun load(
    context: Context,
    font: String,
    text: String? = null,
    callback: ((List<FontFace>, String?) -> Unit)? = null
  ) {
    beginLoad()

    val resolved = try {
      FontParser.parse(font)?.let { resolveFonts(it) }
    } catch (e: Exception) {
      null
    }

    // Parsing is memoized and resolution is a map lookup, so this no longer needs a
    // thread of its own. The faces then load on their own executors in parallel,
    // instead of one download at a time on a thread this set held for the duration.
    if (resolved.isNullOrEmpty()) {
      val error = if (resolved == null) "Failed to load font $font" else null
      endLoad()
      if (callback != null) notify { callback(emptyList(), error) }
      return
    }

    val remaining = AtomicInteger(resolved.size)
    val firstError = AtomicReference<String?>(null)
    for (face in resolved) {
      notify { loadingListeners.forEach { it(face) } }
      face.load(context) { faceError ->
        if (faceError != null) {
          firstError.compareAndSet(null, faceError)
          loadingErrorListeners.forEach { it(face, faceError) }
        } else {
          loadingDoneListeners.forEach { it(face) }
        }
        // The set is done only once every face is, so `ready` and the status
        // listeners no longer report idle while a download is still running.
        if (remaining.decrementAndGet() == 0) {
          endLoad()
          callback?.invoke(resolved, firstError.get())
        }
      }
    }
  }

  /** Face callbacks already arrive here, so this is inline on the main thread. */
  private fun notify(block: () -> Unit) = FontExecutors.main.execute(block)

  private fun beginLoad() {
    pendingLoads.incrementAndGet()
    notify { statusListeners.forEach { it(Status.Loading) } }
  }

  private fun endLoad() {
    if (pendingLoads.decrementAndGet() != 0) return
    val callbacks = synchronized(lock) {
      val pending = readyCallbacks.toList()
      readyCallbacks.clear()
      pending
    }
    notify {
      statusListeners.forEach { it(Status.Loaded) }
      for (cb in callbacks) cb(this)
    }
  }

  fun forEach(block: (FontFace) -> Unit) {
    for (face in array) block(face)
  }

  companion object {
    @JvmStatic
    val instance = FontFaceSet()

    private val GENERIC_FAMILIES =
      setOf("serif", "sans-serif", "monospace", "cursive", "fantasy")
  }
}
