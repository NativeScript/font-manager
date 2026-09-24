package org.nativescript.fontmanager

import android.content.Context
import android.graphics.Typeface
import android.util.Log
import androidx.core.content.res.ResourcesCompat
import java.io.File
import java.net.URL
import java.nio.ByteBuffer
import java.util.UUID
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.regex.Matcher


class FontFace {
  val id: String = UUID.randomUUID().toString()

  val version: Long get() = _version.get()
  private val _version = AtomicLong(0L)

  val sourceHash: Long
    get() {
      var h = _sourceHash
      if (h == 0L) {
        h = fontPath?.hashCode()?.toLong() ?: _dataHash
        if (h == 0L) h = -1L
        _sourceHash = h
      }
      return h
    }
  @Volatile private var _sourceHash: Long = 0L

  val matchingHash: Long
    get() {
      var h = _matchingHash
      if (h == 0L) {
        h = fontDescriptors.renderHash()
        if (h == 0L) h = -1L
        _matchingHash = h
      }
      return h
    }
  @Volatile private var _matchingHash: Long = 0L

  /**
   * Computed on first read rather than at construction. ByteBuffer.hashCode reads
   * the remaining bytes in place, without copying the font.
   */
  private val _dataHash: Long
    get() {
      var h = _dataHashValue
      if (h == 0L) {
        h = fontData?.duplicate()?.hashCode()?.toLong() ?: 0L
        if (h == 0L) h = -1L
        _dataHashValue = h
      }
      return h
    }
  @Volatile private var _dataHashValue: Long = 0L

  @Volatile
  var font: Typeface? = null
    private set
  var fontFamily: String
    private set

  /** Lowercased [fontFamily], precomputed for the per-lookup map keys in [FontFaceSet]. */
  internal val familyKey: String by lazy { fontFamily.lowercase() }
  private var fontData: ByteBuffer? = null
  var fontPath: String? = null
    private set
  private var localOrRemoteSource: String? = null
  private var fontDescriptors: FontDescriptors

  companion object {
    /**
     * CSS generic families mapped to the aliases Android's font config defines.
     * Typeface.create takes one family name and silently returns the default for
     * anything it does not know, which is what product names like "Noto Serif"
     * and comma lists like "Dancing Script, Noto Sans Cursive" resolved to.
     */
    private val genericFontFamilies = mapOf(
      "serif" to "serif",
      "sans-serif" to "sans-serif",
      "monospace" to "monospace",
      "cursive" to "cursive",
      "fantasy" to "casual",
      "system-ui" to "sans-serif",
      "ui-serif" to "serif",
      "ui-sans-serif" to "sans-serif",
      "ui-monospace" to "monospace",
      "ui-rounded" to "sans-serif",
      "emoji" to "sans-serif",
    )

    /** Downloads CSS and remote fonts, so it blocks — see [FontExecutors.io]. */
    @JvmStatic
    private val executors = FontExecutors.serial(FontExecutors.io)

    internal const val FONT_CACHE_DIR = "ns_fonts_cache"

    @JvmStatic
    fun clearFontCache(context: Context) {
      TypefaceCache.clear()
      executors.execute {
        val fonts = File(context.filesDir, FONT_CACHE_DIR)
        if (fonts.exists()) {
          fonts.deleteRecursively()
        }
      }
    }

    @JvmStatic
    fun importFromRemote(
      context: Context,
      url: String,
      load: Boolean = true,
      callback: (fonts: List<FontFace>, error: String?) -> Unit
    ) {
      val result = arrayListOf<FontFace>()
      try {
        val remote = URL(url)
        executors.execute {
          try {
            val css = FontDownloads.readText(remote.toString())
            val matcher: Matcher = Constants.FONT_FACE_PATTERN.matcher(css)
            while (matcher.find()) {
              val match = matcher.group(1)
              match?.let { it ->

                val fontFamily = Constants.FONT_FAMILY_PATTERN.find(it)?.let {
                  it.groupValues[1]
                }

                val fontDisplay = Constants.FONT_DISPLAY_PATTERN.find(it)?.let {
                  it.groupValues[1]
                } ?: "auto"

                val fontStyle = Constants.FONT_STYLE_PATTERN.find(it)?.let {
                  it.groupValues[1]
                } ?: "normal"

                val fontWeight = Constants.FONT_WEIGHT_PATTERN.find(it)?.let {
                  it.groupValues[1]
                } ?: "normal"


                val src = Constants.FONT_SRC_PATTERN.find(it)?.let {
                  it.groupValues[1]
                }

                val font = FontFace(fontFamily ?: "", src)
                font.setFontWeight(fontWeight)
                font.setFontDisplay(fontDisplay)
                font.setFontStyle(fontStyle)
                FontFaceSet.instance.add(font)
                result.add(font)
              }
            }
            if (!load || result.isEmpty()) {
              FontExecutors.main.execute { callback(result, null) }
              return@execute
            }
            // Each face downloads on its own queue, so a stylesheet's fonts arrive
            // in parallel instead of one after another on this one.
            val remaining = AtomicInteger(result.size)
            for (font in result) {
              font.load(context) { if (remaining.decrementAndGet() == 0) callback(result, null) }
            }
          } catch (e: Exception) {
            FontExecutors.main.execute { callback(result, e.localizedMessage) }
          }
        }
      } catch (e: Exception) {
        FontExecutors.main.execute { callback(result, e.localizedMessage) }
      }
    }
  }

  @Volatile
  var status = FontFaceStatus.Unloaded
    private set

  private val reloadListeners = java.util.concurrent.CopyOnWriteArrayList<(FontFace, String?) -> Unit>()

  fun addOnReloadListener(listener: (FontFace, String?) -> Unit) { reloadListeners.add(listener) }
  fun removeOnReloadListener(listener: (FontFace, String?) -> Unit) { reloadListeners.remove(listener) }

  @Volatile
  private var reloadPending = false

  private val lock = Any()

  /**
   * A remote face blocks its thread for the whole download, so it runs on the I/O
   * pool instead of the shared one. Lazy because the source is assigned by the
   * constructor body, which runs after property initializers.
   */
  private val executor: Executor by lazy {
    FontExecutors.serial(if (isRemoteSource) FontExecutors.io else FontExecutors.shared)
  }

  private val isRemoteSource: Boolean
    get() = localOrRemoteSource?.startsWith("http") == true

  @JvmOverloads
  constructor(
    family: String,
    source: String? = null,
    descriptors: FontDescriptors? = null
  ) {
    fontFamily = family
    localOrRemoteSource = source
    fontDescriptors = descriptors ?: FontDescriptors(family)
  }

  @JvmOverloads
  constructor(
    family: String,
    source: ByteArray,
    descriptors: FontDescriptors? = null
  ) {
    fontFamily = family
    fontData = ByteBuffer.wrap(source)
    fontDescriptors = descriptors ?: FontDescriptors(family)
  }

  @JvmOverloads
  constructor(
    family: String,
    source: ByteBuffer,
    descriptors: FontDescriptors? = null
  ) {
    fontFamily = family
    fontData = source
    fontDescriptors = descriptors ?: FontDescriptors(family)
  }


  interface Callback {
    fun onSuccess()
    fun onError(error: String)
  }

  fun rawData(): ByteArray? {
    fontData?.let {
      val bytes = ByteArray(it.remaining())
      it.duplicate().get(bytes)
      return bytes
    }
    fontPath?.let { path ->
      val file = File(path)
      if (file.exists()) return file.readBytes()
    }
    return null
  }

  fun updateDescriptor(value: String) {
    fontDescriptors.update(value)
    scheduleReloadIfNeeded()
  }

  var display: FontDisplay
    get() = fontDescriptors.display
    set(value) {
      fontDescriptors.display = value
      scheduleReloadIfNeeded()
    }

  fun setFontDisplay(value: String): FontFace {
    fontDescriptors.setFontDisplay(value)
    scheduleReloadIfNeeded()
    return this
  }

  var weight: FontWeight
    get() = fontDescriptors.weight
    set(value) {
      fontDescriptors.weight = value
      scheduleReloadIfNeeded()
    }

  fun setFontWeight(value: String): FontFace {
    fontDescriptors.setFontWeight(value)
    scheduleReloadIfNeeded()
    return this
  }

  var style: FontStyle
    get() = fontDescriptors.style
    set(value) {
      fontDescriptors.style = value
      scheduleReloadIfNeeded()
    }

  fun setFontStyle(value: String): FontFace {
    fontDescriptors.setFontStyle(value)
    scheduleReloadIfNeeded()
    return this
  }

  var variant: String
    get() = fontDescriptors.variant
    set(value) {
      fontDescriptors.variant = value
    }

  fun setFontVariant(value: String): FontFace {
    fontDescriptors.variant = value
    return this
  }

  var stretch: String
    get() = fontDescriptors.stretch
    set(value) {
      fontDescriptors.stretch = value
      scheduleReloadIfNeeded()
    }

  fun setFontStretch(value: String): FontFace {
    fontDescriptors.stretch = value
    scheduleReloadIfNeeded()
    return this
  }

  var unicodeRange: String
    get() = fontDescriptors.unicodeRange
    set(value) {
      fontDescriptors.unicodeRange = value
    }

  fun setFontUnicodeRange(value: String): FontFace {
    fontDescriptors.unicodeRange = value
    return this
  }

  var featureSettings: String
    get() = fontDescriptors.featureSettings
    set(value) {
      fontDescriptors.featureSettings = value
    }

  fun setFontFeatureSettings(value: String): FontFace {
    fontDescriptors.featureSettings = value
    return this
  }

  var variationSettings: String
    get() = fontDescriptors.variationSettings
    set(value) {
      fontDescriptors.variationSettings = value
    }

  fun setFontVariationSettings(value: String): FontFace {
    fontDescriptors.variationSettings = value
    return this
  }

  var ascentOverride: String
    get() = fontDescriptors.ascentOverride
    set(value) {
      fontDescriptors.ascentOverride = value
    }

  fun setFontAscentOverride(value: String): FontFace {
    fontDescriptors.ascentOverride = value
    return this
  }

  var descentOverride: String
    get() = fontDescriptors.descentOverride
    set(value) {
      fontDescriptors.descentOverride = value
    }

  fun setFontDescentOverride(value: String): FontFace {
    fontDescriptors.descentOverride = value
    return this
  }

  var lineGapOverride: String
    get() = fontDescriptors.lineGapOverride
    set(value) {
      fontDescriptors.lineGapOverride = value
    }

  fun setFontLineGapOverride(value: String): FontFace {
    fontDescriptors.lineGapOverride = value
    return this
  }

  var kerning: String
    get() = fontDescriptors.kerning
    set(value) {
      fontDescriptors.kerning = value
    }

  fun setFontKerning(value: String): FontFace {
    fontDescriptors.kerning = value
    return this
  }

  var variantLigatures: String
    get() = fontDescriptors.variantLigatures
    set(value) {
      fontDescriptors.variantLigatures = value
    }

  fun setFontVariantLigatures(value: String): FontFace {
    fontDescriptors.variantLigatures = value
    return this
  }

  private fun getMathFontPath(weight: Int, italic: Boolean = false): Int {
    val value = weight.coerceIn(100, 1000)
    when (value) {
      in 100..499 -> {
        if (italic) {
          return R.font.stix_two_text_italic
        }
        return R.font.stix_two_math_regular
      }

      in 500..599 -> {
        if (italic) {
          return R.font.stix_two_text_medium_italic
        }

        return R.font.stix_two_text_medium
      }

      in 600..699 -> {
        if (italic) {
          return R.font.stix_two_text_semi_bold_italic
        }

        return R.font.stix_two_text_semi_bold
      }

      else -> {
        if (italic) {
          return R.font.stix_two_text_bold_italic
        }

        return R.font.stix_two_text_bold
      }
    }
  }

  private fun getFangsongFontPath(weight: Int, italic: Boolean = false): Int {
    val value = weight.coerceIn(100, 1000)
    return 0
  }

  private fun cacheData(context: Context, source: String): Typeface {
    val file = FontDownloads.fetch(source, File(context.filesDir, FONT_CACHE_DIR))
    val ret = handleFontPath(file)
    fontPath = file.absolutePath
    bumpVersionSource()
    return ret
  }

  private fun handleFontPath(file: File): Typeface {
    return TypefaceCache.fromFile(file)
  }

  private fun bumpVersion() {
    _version.incrementAndGet()
    _matchingHash = 0L
  }

  private fun bumpVersionSource() {
    _version.incrementAndGet()
    _sourceHash = 0L
    _matchingHash = 0L
  }

  /**
   * What the loaded typeface was picked by. Only a source-less face chooses its
   * typeface from weight and style; a file or download is the same font whatever
   * its descriptors say, so for those this is null and a descriptor change never
   * throws away a loaded font.
   */
  @Volatile
  private var loadedFrom: Pair<FontWeight, FontStyle>? = null

  private fun resolutionKey(): Pair<FontWeight, FontStyle>? =
    if (fontData == null && localOrRemoteSource == null) fontDescriptors.weight to fontDescriptors.style else null

  private fun scheduleReloadIfNeeded() {
    bumpVersion()
    val reload = synchronized(lock) { status == FontFaceStatus.Loaded && beginReloadLocked() }
    if (reload) postReload()
  }

  private fun beginReloadLocked(): Boolean {
    if (reloadPending || resolutionKey() == loadedFrom) return false
    reloadPending = true
    status = FontFaceStatus.Unloaded
    return true
  }

  private fun postReload() {
    executor.execute {
      synchronized(lock) { reloadPending = false }
      FontExecutors.main.execute { reloadListeners.forEach { it(this, null) } }
    }
  }

  private val pendingLoadCallbacks = ArrayList<(error: String?) -> Unit>()
  private var loadInFlight = false

  private enum class Admission { AlreadyLoaded, Queued, Claimed }

  /**
   * Every load request goes through here, so at most one load per face is ever in
   * flight and every caller is answered exactly once.
   *
   * Callers on hot paths (per-view paint access, per-node append) used to pile a
   * duplicate runnable onto the executor on every check while a slow source was
   * still downloading, and [FontFaceSet.load] reaching a face directly could
   * start a second load alongside one already running.
   */
  private fun admit(callback: (error: String?) -> Unit): Admission = synchronized(lock) {
    if (status == FontFaceStatus.Loaded) return Admission.AlreadyLoaded
    pendingLoadCallbacks.add(callback)
    if (loadInFlight) return Admission.Queued
    loadInFlight = true
    status = FontFaceStatus.Loading
    Admission.Claimed
  }

  /**
   * Publishes the result and answers every caller admitted since the load started.
   * Only the first call per load wins, so a late failure cannot downgrade a result
   * already reported as loaded.
   */
  private fun finish(error: String?) {
    var reload = false
    val queued = synchronized(lock) {
      if (!loadInFlight) return
      status = if (error == null) FontFaceStatus.Loaded else FontFaceStatus.Error
      loadInFlight = false
      // A descriptor change made while this load ran was ignored by
      // scheduleReloadIfNeeded, since the face was not yet Loaded.
      reload = error == null && beginReloadLocked()
      val cbs = pendingLoadCallbacks.toList()
      pendingLoadCallbacks.clear()
      cbs
    }
    if (queued.isNotEmpty()) FontExecutors.main.execute { queued.forEach { it(error) } }
    if (reload) postReload()
  }

  fun load(context: Context, callback: (error: String?) -> Unit) {
    when (admit(callback)) {
      Admission.AlreadyLoaded -> FontExecutors.main.execute { callback(null) }
      Admission.Queued -> Unit
      Admission.Claimed -> if (resolvesWithoutIo) runLoad(context) else executor.execute { runLoad(context) }
    }
  }

  /**
   * A source-less face resolves to a platform typeface through a constant or a
   * cached Typeface.create, so it loads on the calling thread. Sending it through
   * the pool made every system face arrive a main-thread turn late: a caller
   * laying out on the main thread measured with the fallback typeface, then had
   * to lay out again when the callback landed. "math" reads a font resource and
   * keeps the pool.
   */
  private val resolvesWithoutIo: Boolean
    get() = fontData == null && localOrRemoteSource == null && fontFamily != "math"

  /**
   * Nothing may escape without calling [finish]. An exception that got past the
   * inner handlers would otherwise leave the face claimed forever, stranding every
   * queued callback and rejecting all later loads by silence.
   */
  private fun runLoad(context: Context) {
    try {
      resolveAndFinish(context)
    } catch (e: Throwable) {
      finish(e.localizedMessage ?: "Failed to load $fontFamily")
      throw e
    }
  }

  private fun resolveAndFinish(context: Context) {
    val key = resolutionKey()
    // todo handle "fangsong"
    when (fontFamily) {
      "math" -> {
        val font = try {
          val resId = getMathFontPath(key!!.first.weight)
          TypefaceCache.fromResource(resId) {
            ResourcesCompat.getFont(context, resId) ?: Typeface.DEFAULT
          }
        } catch (e: Exception) {
          Log.w("JS", "Failed to get $fontFamily font falling back to the system default")
          Typeface.DEFAULT
        }
        this.font = font
        loadedFrom = key
        finish(null)
        return
      }

      else -> {
        if (key != null) {
          val (weight, fontStyle) = key
          // Source-less faces resolve through the system. Generic families map
          // to their platform default; any other family is looked up by name
          // and falls back to the system default when it is not installed
          // (CSS font fallback semantics). Previously non-generic source-less
          // faces fell through here without invoking the callback and with
          // status stuck at Loading, so callers polling `font != null`
          // re-posted a no-op load runnable on every check, forever.
          val family = genericFontFamilies[fontFamily] ?: fontFamily
          val style = if (weight.weight >= 600) {
            if (fontStyle is FontStyle.Italic) {
              Typeface.BOLD_ITALIC
            } else {
              Typeface.BOLD
            }
          } else {
            fontStyle.fontStyle
          }

          // Key tracks which branch produced the base typeface so the derived
          // weighted entry below cannot collide across families.
          val baseKey = "$fontFamily:$style"
          var font = TypefaceCache.fromFamily(family, style)

          if (weight != FontWeight.Normal) {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
              val italic = fontStyle is FontStyle.Italic
              font = TypefaceCache.weighted(
                font,
                baseKey,
                weight.weight,
                italic
              )
            }
          }
          this.font = font
          loadedFrom = key
          finish(null)
          return
        }
      }
    }

    val source = localOrRemoteSource
    if (source == null) {
      // In-memory sources are accepted by the constructors and surfaced by
      // rawData(), but nothing here turns them into a Typeface. Report it instead
      // of returning without finishing, which left status at Loading forever and
      // grew pendingLoadCallbacks without bound on every retry.
      finish("Loading $fontFamily from in-memory data is not supported on Android")
      return
    }

    try {
      this.font = if (source.startsWith("http")) {
        cacheData(context, source)
      } else {
        handleFontPath(File(source))
      }
      finish(null)
    } catch (e: Exception) {
      finish(e.localizedMessage ?: "Failed to load $fontFamily from $source")
    }
  }
}
