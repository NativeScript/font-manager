package org.nativescript.fontmanager

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

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
}
