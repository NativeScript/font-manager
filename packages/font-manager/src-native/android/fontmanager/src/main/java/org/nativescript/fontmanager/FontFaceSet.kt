package org.nativescript.fontmanager

import android.content.Context
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.abs

class FontFaceSet internal constructor(private val dispatch: Executor?) {
  constructor() : this(null)

  init {
    synchronized(allSets) { allSets.add(this) }
  }

  private val lock = Any()
  private val fonts = LinkedHashSet<FontFace>()
  private val fontsByFamily = mutableMapOf<String, MutableList<FontFace>>()

  private val loadingFaces = mutableListOf<FontFace>()
  private val loadedFaces = mutableListOf<FontFace>()
  private val failedFaces = mutableListOf<FontFace>()
  private var lastError: String? = null

  enum class Status { Loading, Loaded }

  val status: Status
    get() = synchronized(lock) { if (loadingFaces.isEmpty()) Status.Loaded else Status.Loading }

  private val statusListeners = CopyOnWriteArrayList<(Status) -> Unit>()
  private val loadingListeners = CopyOnWriteArrayList<(FontFace) -> Unit>()
  private val loadingDoneListeners = CopyOnWriteArrayList<(FontFace) -> Unit>()
  private val loadingErrorListeners = CopyOnWriteArrayList<(FontFace, String) -> Unit>()
  private val loadingDoneFacesListeners = CopyOnWriteArrayList<(List<FontFace>) -> Unit>()
  private val loadingErrorFacesListeners = CopyOnWriteArrayList<(List<FontFace>, String?) -> Unit>()
  private val changedListeners = CopyOnWriteArrayList<() -> Unit>()

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

  fun addOnLoadingDoneFacesListener(listener: (List<FontFace>) -> Unit) {
    loadingDoneFacesListeners.add(listener)
  }

  fun removeOnLoadingDoneFacesListener(listener: (List<FontFace>) -> Unit) {
    loadingDoneFacesListeners.remove(listener)
  }

  fun addOnLoadingErrorFacesListener(listener: (List<FontFace>, String?) -> Unit) {
    loadingErrorFacesListeners.add(listener)
  }

  fun removeOnLoadingErrorFacesListener(listener: (List<FontFace>, String?) -> Unit) {
    loadingErrorFacesListeners.remove(listener)
  }

  fun addOnChangedListener(listener: () -> Unit) {
    changedListeners.add(listener)
  }

  fun removeOnChangedListener(listener: () -> Unit) {
    changedListeners.remove(listener)
  }

  private val readyCallbacks = mutableListOf<(FontFaceSet) -> Unit>()

  val iter: Iterator<FontFace>
    get() = array.iterator()

  val array: Array<FontFace>
    get() = synchronized(lock) { fonts.toTypedArray() }

  val size: Int
    get() = synchronized(lock) { fonts.size }

  fun add(font: FontFace) {
    synchronized(lock) {
      if (!fonts.add(font)) return
      fontsByFamily.getOrPut(font.fontFamily.lowercase()) { mutableListOf() }.add(font)
    }
    notifyChanged()
    if (font.status == FontFaceStatus.Loading) onFaceLoading(font)
  }

  fun delete(font: FontFace) {
    val end = synchronized(lock) {
      if (!fonts.remove(font)) return
      val key = font.fontFamily.lowercase()
      fontsByFamily[key]?.let { list ->
        list.remove(font)
        if (list.isEmpty()) fontsByFamily.remove(key)
      }
      if (loadingFaces.remove(font) && loadingFaces.isEmpty()) endPeriodLocked() else null
    }
    notifyChanged()
    end?.let { raise(it) }
  }

  fun clear() {
    val end = synchronized(lock) {
      if (fonts.isEmpty()) return
      fonts.clear()
      fontsByFamily.clear()
      if (loadingFaces.isNotEmpty()) {
        loadingFaces.clear()
        endPeriodLocked()
      } else {
        null
      }
    }
    notifyChanged()
    end?.let { raise(it) }
  }

  fun has(font: FontFace): Boolean = synchronized(lock) { fonts.contains(font) }

  /**
   * Calls [callback] immediately when there are no pending font loads,
   * otherwise waits until all current loads complete.
   */
  fun ready(callback: (FontFaceSet) -> Unit) {
    val idle = synchronized(lock) {
      if (loadingFaces.isEmpty()) true else { readyCallbacks.add(callback); false }
    }
    if (idle) notify { callback(this) }
  }

  private fun isGenericFamily(familyKey: String): Boolean = familyKey in GENERIC_FAMILIES

  private fun resolveFonts(parsed: FontParser.Result): List<FontFace> = synchronized(lock) {
    for (family in parsed.families) {
      val familyKey = family.lowercase()
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
    val resolved = try {
      FontParser.parse(font)?.let { resolveFonts(it) }
    } catch (e: Exception) {
      null
    }

    if (resolved.isNullOrEmpty()) {
      val error = if (resolved == null) "Failed to load font $font" else null
      if (callback != null) notify { callback(emptyList(), error) }
      return
    }

    val remaining = AtomicInteger(resolved.size)
    val firstError = AtomicReference<String?>(null)
    for (face in resolved) {
      face.load(context) { faceError ->
        if (faceError != null) firstError.compareAndSet(null, faceError)
        if (remaining.decrementAndGet() == 0) callback?.invoke(resolved, firstError.get())
      }
    }
  }

  private class PeriodEnd(
    val loaded: List<FontFace>,
    val failed: List<FontFace>,
    val error: String?,
    val ready: List<(FontFaceSet) -> Unit>
  )

  internal fun onFaceLoading(face: FontFace) {
    val started = synchronized(lock) {
      if (face !in fonts || face.status != FontFaceStatus.Loading || face in loadingFaces) return
      val first = loadingFaces.isEmpty()
      loadingFaces.add(face)
      first
    }
    if (!started) return
    notify {
      statusListeners.forEach { it(Status.Loading) }
      loadingListeners.forEach { it(face) }
    }
  }

  internal fun onFaceSettled(face: FontFace, error: String?) {
    var member = false
    val end = synchronized(lock) {
      member = face in fonts
      if (!loadingFaces.remove(face)) return@synchronized null
      if (error == null) loadedFaces.add(face) else {
        failedFaces.add(face)
        lastError = error
      }
      if (loadingFaces.isEmpty()) endPeriodLocked() else null
    }
    if (member) notifyChanged()
    end?.let { raise(it) }
  }

  private fun endPeriodLocked(): PeriodEnd {
    val end = PeriodEnd(loadedFaces.toList(), failedFaces.toList(), lastError, readyCallbacks.toList())
    loadedFaces.clear()
    failedFaces.clear()
    lastError = null
    readyCallbacks.clear()
    return end
  }

  private fun raise(end: PeriodEnd) {
    notify {
      statusListeners.forEach { it(Status.Loaded) }
      end.loaded.forEach { face -> loadingDoneListeners.forEach { it(face) } }
      loadingDoneFacesListeners.forEach { it(end.loaded) }
      if (end.failed.isNotEmpty()) {
        end.failed.forEach { face -> loadingErrorListeners.forEach { it(face, end.error ?: "") } }
        loadingErrorFacesListeners.forEach { it(end.failed, end.error) }
      }
      for (cb in end.ready) cb(this)
    }
  }

  private fun notifyChanged() {
    if (changedListeners.isNotEmpty()) notify { changedListeners.forEach { it() } }
  }

  private fun notify(block: () -> Unit) = (dispatch ?: FontExecutors.main).execute(block)

  fun forEach(block: (FontFace) -> Unit) {
    for (face in array) block(face)
  }

  companion object {
    private val allSets = java.util.Collections.newSetFromMap(java.util.WeakHashMap<FontFaceSet, Boolean>())

    private fun sets(): List<FontFaceSet> = synchronized(allSets) { allSets.toList() }

    internal fun faceLoading(face: FontFace) = sets().forEach { it.onFaceLoading(face) }

    internal fun faceSettled(face: FontFace, error: String?) = sets().forEach { it.onFaceSettled(face, error) }

    @JvmStatic
    val instance = FontFaceSet()

    private val GENERIC_FAMILIES =
      setOf("serif", "sans-serif", "monospace", "cursive", "fantasy")
  }
}
