package org.nativescript.fontmanager

import androidx.core.content.res.ResourcesCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

@RunWith(AndroidJUnit4::class)
class DescriptorReloadTest {
  @Test
  fun aFileFaceKeepsItsTypefaceWhenItsDescriptorsChange() {
    val face = FontFace("Stix", fontFile("reload-stix.ttf").absolutePath)
    assertNull(face.loadAndWait())
    val loaded = face.font
    val reloads = AtomicInteger()
    face.addOnReloadListener { _, _ -> reloads.incrementAndGet() }

    face.display = FontDisplay.Swap
    face.weight = FontWeight.Bold
    face.setFontStyle("italic")
    InstrumentationRegistry.getInstrumentation().waitForIdleSync()

    assertEquals(FontFaceStatus.Loaded, face.status)
    assertSame(loaded, face.font)
    assertEquals(0, reloads.get())
  }

  @Test
  fun aSystemFaceSwapsItsTypefaceOnlyForChangesThatPickADifferentOne() {
    val face = FontFace("serif")
    assertNull(face.loadAndWait())
    val regular = face.font
    val reloads = AtomicInteger()
    face.addOnReloadListener { _, error ->
      assertNull(error)
      reloads.incrementAndGet()
    }

    face.display = FontDisplay.Swap
    assertEquals(FontFaceStatus.Loaded, face.status)
    assertSame(regular, face.font)

    face.weight = FontWeight.Bold
    InstrumentationRegistry.getInstrumentation().waitForIdleSync()
    assertEquals(FontFaceStatus.Loaded, face.status)
    assertNotSame(regular, face.font)
    assertTrue(face.font!!.isBold)
    assertEquals(1, reloads.get())
  }

  @Test
  fun aWeightChangeDuringALoadIsNotLost() {
    val bold = TypefaceCache.fromResource(R.font.stix_two_text_bold) {
      ResourcesCompat.getFont(context, R.font.stix_two_text_bold)!!
    }
    var stale = 0
    repeat(300) { i ->
      TypefaceCache.clear()
      TypefaceCache.fromResource(R.font.stix_two_text_bold) { bold }
      val face = FontFace("math")
      val firstLoad = CountDownLatch(1)
      face.load(context) { firstLoad.countDown() }
      val spinUntil = System.nanoTime() + (i % 20) * 100_000L
      while (System.nanoTime() < spinUntil) Thread.onSpinWait()
      face.weight = FontWeight.Bold
      assertTrue(firstLoad.await(10, TimeUnit.SECONDS))
      assertNull(face.loadAndWait())
      if (face.font !== bold) stale++
    }
    assertEquals("loads that kept the pre-change weight", 0, stale)
  }
}
