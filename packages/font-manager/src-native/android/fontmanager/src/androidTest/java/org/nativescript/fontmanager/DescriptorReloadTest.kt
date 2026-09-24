package org.nativescript.fontmanager

import androidx.core.content.res.ResourcesCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class DescriptorReloadTest {
  @Test
  fun aFileFaceStaysLoadedWhenItsDescriptorsChange() {
    val face = FontFace("Stix", fontFile("reload-stix.ttf").absolutePath)
    assertNull(face.loadAndWait())
    val loaded = face.font

    face.display = FontDisplay.Swap
    face.weight = FontWeight.Bold
    face.setFontStyle("italic")

    assertEquals(FontFaceStatus.Loaded, face.status)
    assertEquals(loaded, face.font)
  }

  @Test
  fun aSystemFaceReloadsOnlyForChangesThatPickADifferentTypeface() {
    val face = FontFace("serif")
    assertNull(face.loadAndWait())

    face.display = FontDisplay.Swap
    assertEquals(FontFaceStatus.Loaded, face.status)

    face.weight = FontWeight.Bold
    assertEquals(FontFaceStatus.Unloaded, face.status)
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
