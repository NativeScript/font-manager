package org.nativescript.fontmanager

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class SerialExecutorTest {
  private val pool = Executors.newFixedThreadPool(8)
  private val serial: Executor = SerialExecutor(pool)

  @Test
  fun `runs every task exactly once, in submission order`() {
    val seen = Collections.synchronizedList(mutableListOf<Int>())
    val done = CountDownLatch(500)
    for (i in 0 until 500) {
      serial.execute {
        seen.add(i)
        done.countDown()
      }
    }
    assertTrue("tasks did not finish", done.await(10, TimeUnit.SECONDS))
    assertEquals((0 until 500).toList(), seen)
  }

  @Test
  fun `never runs two tasks at once, even when submitted from many threads`() {
    val concurrent = AtomicInteger(0)
    val overlaps = AtomicInteger(0)
    val done = CountDownLatch(400)
    val submitters = Executors.newFixedThreadPool(8)
    for (i in 0 until 400) {
      submitters.execute {
        serial.execute {
          if (concurrent.incrementAndGet() != 1) overlaps.incrementAndGet()
          Thread.yield()
          concurrent.decrementAndGet()
          done.countDown()
        }
      }
    }
    assertTrue("tasks did not finish", done.await(10, TimeUnit.SECONDS))
    assertEquals(0, overlaps.get())
    submitters.shutdown()
  }

  @Test
  fun `a throwing task does not stall the queue`() {
    val done = CountDownLatch(1)
    serial.execute { throw IllegalStateException("boom") }
    serial.execute { done.countDown() }
    assertTrue("queue stalled after a task threw", done.await(10, TimeUnit.SECONDS))
  }

  @Test
  fun `an inline delegate does not deadlock`() {
    val inline = Executor { it.run() }
    val ran = AtomicInteger(0)
    val nested: Executor = SerialExecutor(inline)
    nested.execute {
      ran.incrementAndGet()
      nested.execute { ran.incrementAndGet() }
    }
    assertEquals(2, ran.get())
  }
}

class LruMapTest {
  @Test
  fun `evicts the least recently used entry past the cap`() {
    val map = LruMap<String, String>(2)
    map["a"] = "1"
    map["b"] = "2"
    assertEquals("1", map["a"])
    map["c"] = "3"
    assertNull("b was the least recently used", map["b"])
    assertEquals("1", map["a"])
    assertEquals("3", map["c"])
  }

  @Test
  fun `clear drops everything`() {
    val map = LruMap<String, String>(4)
    map["a"] = "1"
    map.clear()
    assertNull(map["a"])
  }
}

class FontParserTest {
  @Test
  fun `memoizes a parsed shorthand`() {
    val first = FontParser.parse("italic bold 16px/1.5 Roboto, serif")
    val second = FontParser.parse("italic bold 16px/1.5 Roboto, serif")
    assertNotNull(first)
    assertSame("repeat parses should hit the cache", first, second)
    assertEquals(listOf("Roboto", "serif"), first!!.families)
    assertEquals(16, first.sizePx)
  }

  @Test
  fun `parses the size slash line-height shorthand`() {
    val withLineHeight = FontParser.parse("20px/1.5 Roboto")
    assertNotNull("`<size>/<line-height>` is valid CSS font shorthand", withLineHeight)
    assertEquals(20, withLineHeight!!.sizePx)
    assertEquals(1.5f, withLineHeight.lineHeight!!, 0.0001f)
    assertEquals(listOf("Roboto"), withLineHeight.families)

    val plain = FontParser.parse("20px Roboto")!!
    assertEquals(20, plain.sizePx)
    assertNull(plain.lineHeight)
  }

  @Test
  fun `caches a failed parse without re-tokenizing`() {
    assertNull(FontParser.parse("not-a-font"))
    assertNull(FontParser.parse("not-a-font"))
  }

  @Test
  fun `lowercases family keys once`() {
    val parsed = FontParser.parse("16px RoBoTo")!!
    assertEquals(listOf("roboto"), parsed.familyKeys)
    assertSame(parsed.familyKeys, parsed.familyKeys)
  }
}
