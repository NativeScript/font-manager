package org.nativescript.fontmanager

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class FontFaceSetLoadingTest {
  private val set = FontFaceSet()
  private val events = Collections.synchronizedList(mutableListOf<String>())

  private fun record() {
    set.addOnStatusListener { events.add("status:$it") }
    set.addOnLoadingListener { events.add("loading:${it.fontFamily}") }
    set.addOnLoadingDoneListener { events.add("done:${it.fontFamily}") }
    set.addOnLoadingDoneFacesListener { faces -> events.add("doneFaces:" + faces.joinToString(",") { it.fontFamily }) }
    set.addOnLoadingErrorFacesListener { faces, _ -> events.add("errorFaces:" + faces.joinToString(",") { it.fontFamily }) }
    set.addOnChangedListener { events.add("changed") }
  }

  private fun idle() = InstrumentationRegistry.getInstrumentation().waitForIdleSync()

  @Test
  fun aMemberFacesOwnLoadRunsOneLoadingPeriod() {
    record()
    val face = FontFace("PeriodA", fontFile("period-a.ttf").absolutePath)
    set.add(face)
    set.add(face)
    assertEquals(1, set.size)
    assertNull(face.loadAndWait())
    idle()
    assertEquals(
      listOf("changed", "status:Loading", "loading:PeriodA", "changed", "status:Loaded", "done:PeriodA", "doneFaces:PeriodA"),
      events.toList()
    )
    assertEquals(FontFaceSet.Status.Loaded, set.status)
  }

  @Test
  fun concurrentLoadsShareAPeriodAndReportFailuresTogether() {
    val good = FontFace("PeriodB", fontFile("period-b.ttf").absolutePath)
    val bad = FontFace("PeriodC", "/no/such/file.ttf")
    set.add(good)
    set.add(bad)
    record()
    val done = CountDownLatch(2)
    var badError: String? = null
    good.load(context) { done.countDown() }
    bad.load(context) { badError = it; done.countDown() }
    assertTrue(done.await(10, TimeUnit.SECONDS))
    idle()
    assertNotNull(badError)
    assertEquals(1, events.count { it == "status:Loading" })
    assertEquals(1, events.count { it == "status:Loaded" })
    assertTrue(events.contains("doneFaces:PeriodB"))
    assertTrue(events.contains("errorFaces:PeriodC"))
    assertEquals(1, events.count { it.startsWith("doneFaces:") })
  }

  @Test
  fun addingAFaceThatHasAlreadyLoadedOnlyRaisesChanged() {
    val face = FontFace("PeriodD", fontFile("period-d.ttf").absolutePath)
    assertNull(face.loadAndWait())
    record()
    set.add(face)
    idle()
    assertEquals(listOf("changed"), events.toList())
  }

  @Test
  fun loadingAFaceThatHasAlreadyLoadedThroughTheSetRaisesNothing() {
    val face = FontFace("PeriodE", fontFile("period-e.ttf").absolutePath)
    set.add(face)
    assertNull(face.loadAndWait())
    idle()
    record()
    val done = CountDownLatch(1)
    set.load(context, "16px PeriodE") { _, _ -> done.countDown() }
    assertTrue(done.await(10, TimeUnit.SECONDS))
    idle()
    assertEquals(emptyList<String>(), events.toList())
  }

  @Test
  fun removingAFaceRaisesChanged() {
    val face = FontFace("PeriodF", fontFile("period-f.ttf").absolutePath)
    set.add(face)
    record()
    set.delete(face)
    set.delete(face)
    idle()
    assertEquals(listOf("changed"), events.toList())
  }
}
