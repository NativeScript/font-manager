package org.nativescript.fontmanagerdemo

import android.os.Bundle
import android.util.Log
import android.widget.Button
import android.widget.ScrollView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import org.nativescript.fontmanager.FontDisplay
import org.nativescript.fontmanager.FontFace
import org.nativescript.fontmanager.FontFaceSet
import org.nativescript.fontmanager.FontFaceStatus
import org.nativescript.fontmanager.FontWeight
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class MainActivity : AppCompatActivity() {

  private lateinit var tvLog: TextView
  private lateinit var scrollView: ScrollView

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContentView(R.layout.activity_main)
    ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.main)) { v, insets ->
      val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
      v.setPadding(systemBars.left, systemBars.top, systemBars.right, systemBars.bottom)
      insets
    }

    tvLog = findViewById(R.id.tvLog)
    scrollView = findViewById(R.id.scrollView)

    findViewById<Button>(R.id.btnRunTests).setOnClickListener {
      tvLog.text = "=== FontManager Tests ==="
      Thread { runAllTests() }.start()
    }
  }

  private fun log(message: String) {
    Log.i("FontManagerTest", message)
    runOnUiThread {
      tvLog.append("\n$message")
      scrollView.post { scrollView.fullScroll(ScrollView.FOCUS_DOWN) }
    }
  }

  private fun runAllTests() {
    test01_systemFont()
    test02_descriptorSetters()
    test03_fontFaceSet()
    test04_fontFaceSetLoad()
    test05_forEach()
    test06_updateDescriptor()
    test07_autoReload()
    test08_onReloadCallback()
    test09_fontFaceSetEvents()
    test10_ready()
    test11_has()
    test12_variant()
    test13_clearCache()
    test14_remoteFont()
    test15_remoteFontFaceSet()
    test16_importFromRemote()
    log("\n=== All tests complete ===")
  }

  // ── Test 1 ───────────────────────────────────────────────────────────────
  private fun test01_systemFont() {
    log("\n[1] System font load")
    val face = FontFace("sans-serif")
    log("  family: ${face.fontFamily}")
    log("  status before load: ${face.status}")

    val latch = CountDownLatch(1)
    face.load(this) { error ->
      if (error != null) log("  ERROR: $error")
      latch.countDown()
    }
    latch.await(5, TimeUnit.SECONDS)

    log("  status after load: ${face.status} (expected ${FontFaceStatus.Loaded})")
    log("  font != null: ${face.font != null}")
  }

  // ── Test 2 ───────────────────────────────────────────────────────────────
  private fun test02_descriptorSetters() {
    log("\n[2] Descriptor setters")
    val face = FontFace("serif")
    face.setFontWeight("700")
    face.setFontStyle("italic")
    face.setFontDisplay("swap")
    face.stretch = "condensed"
    face.unicodeRange = "U+0025-00FF"
    face.featureSettings = "\"smcp\""
    face.ascentOverride = "90%"
    face.descentOverride = "10%"
    face.lineGapOverride = "5%"

    log("  weight: ${face.weight.weight} (expected 700)")
    log("  style: ${face.style} (expected italic)")
    log("  display: ${face.display} (expected ${FontDisplay.Swap})")
    log("  stretch: ${face.stretch}")
    log("  unicodeRange: ${face.unicodeRange}")
    log("  featureSettings: ${face.featureSettings}")
    log("  ascentOverride: ${face.ascentOverride}")
    log("  descentOverride: ${face.descentOverride}")
    log("  lineGapOverride: ${face.lineGapOverride}")
  }

  // ── Test 3 ───────────────────────────────────────────────────────────────
  private fun test03_fontFaceSet() {
    log("\n[3] FontFaceSet add/delete/check/has")
    val set = FontFaceSet()
    val serif = FontFace("serif")
    set.add(serif)

    log("  size after add: ${set.size} (expected 1)")
    log("  has(serif): ${set.has(serif)} (expected true)")
    log("  check '16px serif': ${set.check("16px serif", null)} (expected true)")
    log("  check '16px NonExistent': ${set.check("16px 'NonExistentFont'", null)} (expected false)")

    set.delete(serif)
    log("  size after delete: ${set.size} (expected 0)")
    log("  has after delete: ${set.has(serif)} (expected false)")
  }

  // ── Test 4 ───────────────────────────────────────────────────────────────
  private fun test04_fontFaceSetLoad() {
    log("\n[4] FontFaceSet load")
    val set = FontFaceSet()
    set.add(FontFace("monospace"))

    val latch = CountDownLatch(1)
    var loadedFaces: List<FontFace> = emptyList()
    set.load(this, "16px monospace", null) { faces, error ->
      if (error != null) log("  ERROR: $error")
      loadedFaces = faces
      latch.countDown()
    }
    latch.await(5, TimeUnit.SECONDS)

    log("  loaded faces: ${loadedFaces.size} (expected 1)")
    loadedFaces.firstOrNull()?.let {
      log("  face family: ${it.fontFamily}, status: ${it.status}")
    }
  }

  // ── Test 5 ───────────────────────────────────────────────────────────────
  private fun test05_forEach() {
    log("\n[5] forEach")
    val set = FontFaceSet()
    set.add(FontFace("serif"))
    set.add(FontFace("monospace"))

    var count = 0
    set.forEach { face ->
      log("  face: ${face.fontFamily}")
      count++
    }
    log("  iterated $count faces")
  }

  // ── Test 6 ───────────────────────────────────────────────────────────────
  private fun test06_updateDescriptor() {
    log("\n[6] updateDescriptor")
    val face = FontFace("Roboto")
    face.updateDescriptor("@font-face { font-weight: 300; font-style: italic; font-display: swap; }")

    log("  weight: ${face.weight.weight} (expected 300)")
    log("  style: ${face.style} (expected italic)")
    log("  display: ${face.display} (expected ${FontDisplay.Swap})")
  }

  // ── Test 7 ───────────────────────────────────────────────────────────────
  private fun test07_autoReload() {
    log("\n[7] Auto-reload on descriptor change")
    val face = FontFace("serif")

    val latch = CountDownLatch(1)
    face.load(this) { latch.countDown() }
    latch.await(5, TimeUnit.SECONDS)

    log("  status after initial load: ${face.status} (expected ${FontFaceStatus.Loaded})")

    // Changing weight on a loaded face marks it Unloaded and schedules reload
    face.weight = FontWeight.Bold
    log("  status after weight change: ${face.status} (expected ${FontFaceStatus.Unloaded})")

    // Give the async reload signal a moment
    Thread.sleep(300)
    // On Android, onReload fires to notify the view; the view then calls load().
    // So status remains Unloaded until the caller reloads.
    log("  status after 300ms: ${face.status}")
    log("  (Android: onReload fires to notify views; views call load() to resolve)")
  }

  // ── Test 8 ───────────────────────────────────────────────────────────────
  private fun test08_onReloadCallback() {
    log("\n[8] onReload callback")
    val face = FontFace("sans-serif")

    val loadLatch = CountDownLatch(1)
    face.load(this) { loadLatch.countDown() }
    loadLatch.await(5, TimeUnit.SECONDS)

    val reloadLatch = CountDownLatch(1)
    var reloadFired = false
    var reloadError: String? = "not-fired"

    face.onReload = { f, error ->
      reloadFired = true
      reloadError = error
      log("  onReload fired for: ${f.fontFamily}, error: $error")
      // Simulate what a view would do — reload with context
      f.load(this) { reloadLatch.countDown() }
    }

    face.setFontStyle("italic")

    reloadLatch.await(5, TimeUnit.SECONDS)

    log("  onReload fired: $reloadFired (expected true)")
    log("  reload error: $reloadError (expected null)")
    log("  face status after view reload: ${face.status} (expected ${FontFaceStatus.Loaded})")
  }

  // ── Test 9 ───────────────────────────────────────────────────────────────
  private fun test09_fontFaceSetEvents() {
    log("\n[9] FontFaceSet events (onLoading / onLoadingDone / onLoadingError)")
    val set = FontFaceSet()
    var loadingCount = 0
    var doneCount = 0

    set.onLoading = { face -> loadingCount++; log("  onLoading: ${face.fontFamily}") }
    set.onLoadingDone = { face -> doneCount++; log("  onLoadingDone: ${face.fontFamily}") }
    set.onLoadingError = { face, err -> log("  onLoadingError: ${face.fontFamily} — $err") }

    set.add(FontFace("monospace"))

    val latch = CountDownLatch(1)
    set.load(this, "16px monospace", null) { _, _ -> latch.countDown() }
    latch.await(5, TimeUnit.SECONDS)

    log("  onLoading calls: $loadingCount (expected 1)")
    log("  onLoadingDone calls: $doneCount (expected 1)")
  }

  // ── Test 10 ──────────────────────────────────────────────────────────────
  private fun test10_ready() {
    log("\n[10] FontFaceSet.ready")
    val set = FontFaceSet()

    // Should fire immediately — no pending loads
    val immediateLatch = CountDownLatch(1)
    var immediateFired = false
    set.ready { immediateFired = true; immediateLatch.countDown() }
    immediateLatch.await(1, TimeUnit.SECONDS)
    log("  ready fired immediately: $immediateFired (expected true)")

    // Load a font; ready should fire once it completes
    set.add(FontFace("serif"))
    val readyLatch = CountDownLatch(1)
    var readyAfterLoad = false

    set.load(this, "16px serif", null) { _, _ -> }
    set.ready { readyAfterLoad = true; readyLatch.countDown() }

    readyLatch.await(5, TimeUnit.SECONDS)
    log("  ready fired after load: $readyAfterLoad (expected true)")
  }

  // ── Test 11 ──────────────────────────────────────────────────────────────
  private fun test11_has() {
    log("\n[11] FontFaceSet.has")
    val set = FontFaceSet()
    val face = FontFace("cursive")

    log("  has before add: ${set.has(face)} (expected false)")
    set.add(face)
    log("  has after add: ${set.has(face)} (expected true)")
    set.delete(face)
    log("  has after delete: ${set.has(face)} (expected false)")
  }

  // ── Test 12 ──────────────────────────────────────────────────────────────
  private fun test12_variant() {
    log("\n[12] FontFace.variant")
    val face = FontFace("serif")
    log("  default variant: ${face.variant} (expected normal)")
    face.setFontVariant("small-caps")
    log("  after set: ${face.variant} (expected small-caps)")
  }

  // ── Test 13 ──────────────────────────────────────────────────────────────
  private fun test13_clearCache() {
    log("\n[13] clearFontCache")
    FontFace.clearFontCache(this)
    log("  clearFontCache called (no error)")
  }

  // ── Test 14 ──────────────────────────────────────────────────────────────
  // Load a single font directly from a remote .ttf URL
  private fun test14_remoteFont() {
    log("\n[14] Remote font file (direct URL)")

    // Roboto Regular from Google Fonts static CDN
    val url = "https://fonts.gstatic.com/s/roboto/v32/KFOmCnqEu92Fr1Mu4mxKKTU1Kg.woff2"
    val face = FontFace("RobotoRemote", url)

    val latch = CountDownLatch(1)
    face.load(this) { error ->
      if (error != null) {
        log("  ERROR: $error")
      } else {
        log("  family: ${face.fontFamily}")
        log("  status: ${face.status} (expected ${FontFaceStatus.Loaded})")
        log("  font != null: ${face.font != null}")
        log("  fontPath: ${face.fontPath ?: "(null — cached in memory)"}")
      }
      latch.countDown()
    }
    val completed = latch.await(15, TimeUnit.SECONDS)
    if (!completed) log("  TIMEOUT waiting for remote font")
  }

  // ── Test 15 ──────────────────────────────────────────────────────────────
  // Add a remote-URL FontFace to a FontFaceSet and use set.load()
  private fun test15_remoteFontFaceSet() {
    log("\n[15] FontFaceSet.load with remote font")

    val url = "https://fonts.gstatic.com/s/montserrat/v26/JTUSjIg1_i6t8kCHKm459WlhyyTh89Y.woff2"
    val face = FontFace("MontserratRemote", url)

    val set = FontFaceSet()
    set.add(face)

    val latch = CountDownLatch(1)
    set.load(this, "16px MontserratRemote", null) { faces, error ->
      if (error != null) {
        log("  ERROR: $error")
      } else {
        log("  resolved faces: ${faces.size}")
        faces.firstOrNull()?.let { f ->
          log("  face: ${f.fontFamily}, status: ${f.status}")
        }
      }
      latch.countDown()
    }
    val completed = latch.await(15, TimeUnit.SECONDS)
    if (!completed) log("  TIMEOUT waiting for set.load remote font")
  }

  // ── Test 16 ──────────────────────────────────────────────────────────────
  // importFromRemote parses a Google Fonts CSS stylesheet and loads all faces
  private fun test16_importFromRemote() {
    log("\n[16] FontFace.importFromRemote (CSS stylesheet)")

    val cssUrl = "https://fonts.googleapis.com/css2?family=Roboto:wght@400;700&display=swap"

    val latch = CountDownLatch(1)
    FontFace.importFromRemote(this, cssUrl, true) { faces, error ->
      if (error != null) {
        log("  ERROR: $error")
      } else {
        log("  imported ${faces.size} face(s)")
        for (face in faces) {
          log("  - ${face.fontFamily} weight=${face.weight.weight} status=${face.status}")
        }
      }
      latch.countDown()
    }
    val completed = latch.await(20, TimeUnit.SECONDS)
    if (!completed) log("  TIMEOUT waiting for importFromRemote")

    // Verify they landed in the global FontFaceSet
    val inSet = FontFaceSet.instance.check("16px Roboto", null)
    log("  'Roboto' in global FontFaceSet after import: $inSet")
  }
}
