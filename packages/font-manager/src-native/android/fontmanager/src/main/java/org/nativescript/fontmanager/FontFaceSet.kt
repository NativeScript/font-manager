package org.nativescript.fontmanager

import android.content.Context
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.abs

class FontFaceSet {
  private val fonts = mutableSetOf<FontFace>()
  private val fontsByFamily = mutableMapOf<String, MutableList<FontFace>>()
  /**
   * [load] resolves faces and loads them inline, which for a remote face means
   * waiting on a download, so this runs on the I/O pool — on the shared one it
   * would hold a thread that all other font work is queued behind.
   */
  private val executor = FontExecutors.serial(FontExecutors.io)

  enum class Status { Loading, Loaded }

  var status = Status.Loaded
    private set

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
  private val readyCallbacks = CopyOnWriteArrayList<(FontFaceSet) -> Unit>()

  val iter: Iterator<FontFace>
    get() = fonts.iterator()

  val array: Array<FontFace>
    get() = fonts.toTypedArray()

  val size: Int
    get() = fonts.size

  private val reloadListeners: MutableMap<FontFace, (FontFace, String?) -> Unit> = mutableMapOf()

  fun add(font: FontFace) {
    val added = fonts.add(font)
    fontsByFamily.getOrPut(font.familyKey) { mutableListOf() }.add(font)

    if (added) {
      val listener: (FontFace, String?) -> Unit = { reloadedFace, error ->
        if (error != null) {
          loadingErrorListeners.forEach { it(reloadedFace, error) }
          decrementPending()
        } else {
          loadingDoneListeners.forEach { it(reloadedFace) }
          decrementPending()
        }
      }
      font.addOnReloadListener(listener)
      reloadListeners[font] = listener
    }
  }

  fun delete(font: FontFace) {
    if (!fonts.remove(font)) return
    reloadListeners.remove(font)
    val key = font.familyKey
    fontsByFamily[key]?.let { list ->
      list.remove(font)
      if (list.isEmpty()) fontsByFamily.remove(key)
    }
  }

  fun clear() {
    for (face in fonts) reloadListeners.remove(face)
    fonts.clear()
    fontsByFamily.clear()
  }

  fun has(font: FontFace): Boolean = fonts.contains(font)

  /**
   * Calls [callback] immediately when there are no pending font loads,
   * otherwise waits until all current loads complete.
   */
  fun ready(callback: (FontFaceSet) -> Unit) {
    if (pendingLoads.get() <= 0 && status == Status.Loaded) {
      callback(this)
    } else {
      readyCallbacks.add(callback)
    }
  }

  /**
   * Only membership matters here — the caller discards the typeface — so this no
   * longer materializes one just to null-check it.
   */
  private fun isGenericFamily(familyKey: String): Boolean = familyKey in GENERIC_FAMILIES

  private fun resolveFonts(parsed: FontParser.Result): List<FontFace> {
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

  fun check(font: String, text: String?): Boolean {
    return try {
      val parsed = FontParser.parse(font) ?: return false
      resolveFonts(parsed).isNotEmpty()
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
    executor.execute {
      beginSetLoad()
      try {
        val parsed = FontParser.parse(font) ?: run {
          endSetLoadError(null, "Failed to load font $font")
          if (callback != null) {
            callback(emptyList(), "Failed to load font $font")
          }
          return@execute
        }
        val resolved = resolveFonts(parsed)
        for (face in resolved) {
          loadingListeners.forEach { it(face) }
          face.loadSync(context) { error ->
            if (error != null) {
              loadingErrorListeners.forEach { it(face, error) }
            } else {
              loadingDoneListeners.forEach { it(face) }
            }
          }
        }
        endSetLoadSuccess()
        if (callback != null) {
          callback(resolved, null)
        }
      } catch (e: Exception) {
        endSetLoadError(null, e.localizedMessage)
        if (callback != null) {
          callback(emptyList(), e.localizedMessage)
        }
      }
    }
  }

  private fun beginSetLoad() {
    pendingLoads.incrementAndGet()
    status = Status.Loading
    statusListeners.forEach { it(status) }
  }

  private fun endSetLoadSuccess() {
    decrementPending()
  }

  private fun endSetLoadError(face: FontFace?, error: String?) {
    decrementPending()
  }

  private fun decrementPending() {
    if (pendingLoads.decrementAndGet() <= 0) {
      status = Status.Loaded
      statusListeners.forEach { it(status) }
      val callbacks = readyCallbacks.toList()
      readyCallbacks.clear()
      for (cb in callbacks) cb(this)
    }
  }

  fun forEach(block: (FontFace) -> Unit) {
    for (face in fonts.toList()) block(face)
  }

  companion object {
    @JvmStatic
    val instance = FontFaceSet()

    private val GENERIC_FAMILIES =
      setOf("serif", "sans-serif", "monospace", "cursive", "fantasy")
  }
}
