package org.nativescript.fontmanager

import android.content.Context
import android.graphics.Typeface
import android.util.Log
import androidx.core.content.res.ResourcesCompat
import androidx.core.net.toUri
import java.io.BufferedInputStream
import java.io.File
import java.io.FileOutputStream
import java.net.URL
import java.nio.ByteBuffer
import java.util.UUID
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicLong
import java.util.regex.Matcher


data class FontSnapshot(
  val id: String,
  val version: Long,
  val sourceHash: Long,
  val matchingHash: Long,
  val fontFamily: String,
  val weight: FontWeight,
  val style: FontStyle,
  private val rawDataProvider: () -> ByteArray?
) {
  /**
   * Read on demand, and at most once per snapshot.
   *
   * Snapshots are taken to compare [version] / [sourceHash]; eagerly copying the
   * whole font file into every snapshot made that comparison cost a full file read.
   */
  val rawData: ByteArray? by lazy(LazyThreadSafetyMode.PUBLICATION) { rawDataProvider() }

  override fun equals(other: Any?): Boolean {
    if (this === other) return true
    if (other !is FontSnapshot) return false
    return id == other.id && version == other.version
  }
  override fun hashCode(): Int = 31 * id.hashCode() + version.hashCode()
}

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
   * Computed on first read rather than at construction — hashing meant copying the
   * whole buffer, which every `new FontFace(family, bytes)` paid even if the hash
   * was never asked for.
   */
  private val _dataHash: Long
    get() {
      var h = _dataHashValue
      if (h == 0L) {
        h = fontData?.let { buffer ->
          val bytes = ByteArray(buffer.remaining())
          buffer.duplicate().get(bytes)
          bytes.contentHashCode().toLong()
        } ?: 0L
        if (h == 0L) h = -1L
        _dataHashValue = h
      }
      return h
    }
  @Volatile private var _dataHashValue: Long = 0L

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
    @JvmStatic
    private val genericFontFamilies = mutableMapOf(
      Pair("serif", "Noto Serif"),
      Pair("sans-serif", "Roboto"),
      Pair("monospace", "Roboto Mono, Droid Sans Mono"),
      Pair("cursive", "Dancing Script, Noto Sans Cursive"),
      Pair("fantasy", "Papyrus"),
      Pair("system-ui", "Roboto"),
      Pair("ui-serif", "Noto Serif"),
      Pair("ui-sans-serif", "Roboto"),
      Pair("ui-monospace", "Roboto Mono"),
      Pair("ui-rounded", "Google Sans Rounded, Roboto"),
      Pair("emoji", "Noto Emoji"),
    )

    @JvmStatic
    private val executors = FontExecutors.serial()

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
            val connection = remote.openConnection()
            val stream = BufferedInputStream(connection.getInputStream())
            val css = String(stream.readBytes())
            val matcher: Matcher = Constants.FONT_FACE_PATTERN.matcher(css)
            stream.close()
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
                if (load) {
                  font.loadSync(context) {}
                }
                result.add(font)
              }
            }
            callback(result, null)

          } catch (e: Exception) {
            callback(result, e.localizedMessage)
          }
        }
      } catch (e: Exception) {
        callback(result, e.localizedMessage)
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

  private val executor: Executor = FontExecutors.serial()

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
    val nsFonts = File(context.filesDir, FONT_CACHE_DIR)
    nsFonts.mkdir()
    val uri = source.toUri()
    if (uri.lastPathSegment == null) {
      throw Error("Invalid source $source")
    }
    val path = File(nsFonts, uri.lastPathSegment!!)
    if (path.exists() && path.length() > 0) {
      val ret = handleFontPath(path)
      fontPath = path.absolutePath
      bumpVersionSource()
      return ret
    }
    val url = URL(source)
    val fs = FileOutputStream(path)
    url.openStream().use { input ->
      fs.use { output ->
        input.copyTo(output)
      }
    }
    val ret = handleFontPath(path)
    fontPath = path.absolutePath
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

  fun snapshot(): FontSnapshot = FontSnapshot(
    id = id,
    version = version,
    sourceHash = sourceHash,
    matchingHash = matchingHash,
    fontFamily = fontFamily,
    weight = fontDescriptors.weight,
    style = fontDescriptors.style,
    rawDataProvider = ::rawData
  )

  private fun scheduleReloadIfNeeded() {
    bumpVersion()
    if (status != FontFaceStatus.Loaded) return
    synchronized(lock) {
      if (reloadPending) return
      reloadPending = true
    }
    synchronized(lock) { status = FontFaceStatus.Unloaded }
    executor.execute {
      synchronized(lock) { reloadPending = false }
      reloadListeners.forEach { it(this, null) }
    }
  }

  private val pendingLoadCallbacks = ArrayList<(error: String?) -> Unit>()

  fun load(context: Context, callback: (error: String?) -> Unit) {
    synchronized(lock) {
      if (status == FontFaceStatus.Loaded) {
        callback(null)
        return
      }
      // A load is already in flight — queue the callback instead of posting
      // another runnable that would no-op against the same in-flight status.
      // Callers on hot paths (per-view paint access, per-node append) can
      // otherwise pile duplicate runnables onto the executor while a slow
      // source (e.g. a remote font) is still downloading.
      if (status == FontFaceStatus.Loading) {
        pendingLoadCallbacks.add(callback)
        return
      }
      status = FontFaceStatus.Loading
      pendingLoadCallbacks.add(callback)
    }
    executor.execute {
      loadSync(context) { error ->
        val queued = synchronized(lock) {
          val cbs = pendingLoadCallbacks.toList()
          pendingLoadCallbacks.clear()
          cbs
        }
        queued.forEach { it(error) }
      }
    }
  }

  internal fun loadSync(context: Context, callback: (error: String?) -> Unit) {
    if (status == FontFaceStatus.Loaded) {
      callback(null)
      return
    }
    synchronized(lock) {
      status = FontFaceStatus.Loading
    }
    val isMath = fontFamily == "math"
    // todo handle "fangsong"
    when (fontFamily) {
      "math" -> {
        val font = try {
          val resId = getMathFontPath(fontDescriptors.weight.weight)
          TypefaceCache.fromResource(resId) {
            ResourcesCompat.getFont(context, resId) ?: Typeface.DEFAULT
          }
        } catch (e: Exception) {
          Log.w("JS", "Failed to get $fontFamily font falling back to the system default")
          Typeface.DEFAULT
        }
        synchronized(lock) {
          status = FontFaceStatus.Loaded
        }
        this.font = font
        callback(null)
        return
      }

      else -> {
        if (fontData == null && localOrRemoteSource == null) {
          // Source-less faces resolve through the system. Generic families map
          // to their platform default; any other family is looked up by name
          // and falls back to the system default when it is not installed
          // (CSS font fallback semantics). Previously non-generic source-less
          // faces fell through here without invoking the callback and with
          // status stuck at Loading, so callers polling `font != null`
          // re-posted a no-op load runnable on every check, forever.
          val family = genericFontFamilies[fontFamily] ?: fontFamily
          val style = if (fontDescriptors.weight.weight >= 600) {
            if (fontDescriptors.style is FontStyle.Italic) {
              Typeface.BOLD_ITALIC
            } else {
              Typeface.BOLD
            }
          } else {
            fontDescriptors.style.fontStyle
          }

          // Key tracks which branch produced the base typeface so the derived
          // weighted entry below cannot collide across families.
          val baseKey = "$fontFamily:$style"
          var font = when (fontFamily) {
            "serif" -> {
              Typeface.SERIF
            }

            "sans-serif" -> {
              Typeface.SANS_SERIF
            }

            "monospace" -> {
              Typeface.MONOSPACE
            }

            else -> {
              TypefaceCache.fromFamily(family, style)
            }
          }

          if (fontDescriptors.weight != FontWeight.Normal) {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
              val italic = fontDescriptors.style is FontStyle.Italic
              font = TypefaceCache.weighted(
                font,
                baseKey,
                fontDescriptors.weight.weight,
                italic
              )
            }
          }
          synchronized(lock) {
            status = FontFaceStatus.Loaded
          }
          this.font = font
          callback(null)
          return
        }
      }
    }


    localOrRemoteSource?.let {
      if (it.startsWith("http")) {
        try {
          val font = cacheData(context, localOrRemoteSource!!)
          this.font = font
          synchronized(lock) {
            status = FontFaceStatus.Loaded
          }
          callback(null)
        } catch (e: Exception) {
          synchronized(lock) {
            status = FontFaceStatus.Error
          }
          callback(e.localizedMessage)
        }
      } else {
        try {
          val fontPath = File(it)
          this.font = handleFontPath(fontPath)
          synchronized(lock) {
            status = FontFaceStatus.Loaded
          }
          callback(null)
        } catch (e: Exception) {
          synchronized(lock) {
            status = FontFaceStatus.Error
          }
          callback(e.localizedMessage)
        }
      }
    }
  }
}
