package org.nativescript.fontmanager

import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import java.io.File
import java.io.IOException
import java.net.ServerSocket
import java.net.Socket
import java.nio.file.Files
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import kotlin.concurrent.thread

/** Answers each request with whatever [handler] writes for its path. */
class TestServer(private val handler: (path: String, socket: Socket) -> Unit) : AutoCloseable {
  private val server = ServerSocket(0)
  val base = "http://127.0.0.1:${server.localPort}"

  init {
    thread(isDaemon = true) {
      while (!server.isClosed) {
        val socket = try { server.accept() } catch (_: IOException) { break }
        thread(isDaemon = true) {
          socket.use {
            val requestLine = it.getInputStream().bufferedReader().readLine() ?: return@use
            handler(requestLine.split(" ")[1], it)
          }
        }
      }
    }
  }

  override fun close() = server.close()

  companion object {
    fun respond(socket: Socket, body: ByteArray, declaredLength: Int = body.size) {
      val out = socket.getOutputStream()
      out.write("HTTP/1.1 200 OK\r\nContent-Length: $declaredLength\r\nConnection: close\r\n\r\n".toByteArray())
      out.write(body)
      out.flush()
    }
  }
}

class FontDownloadsTest {
  private lateinit var dir: File

  @Before
  fun setUp() {
    dir = Files.createTempDirectory("fonts").toFile()
  }

  @After
  fun tearDown() {
    dir.deleteRecursively()
  }

  @Test
  fun `a download cut off mid-body is not served from the cache later`() {
    val full = ByteArray(4096) { it.toByte() }
    var cutOff = true
    TestServer { _, socket ->
      if (cutOff) TestServer.respond(socket, full.copyOf(100), declaredLength = full.size)
      else TestServer.respond(socket, full)
    }.use { server ->
      try {
        FontDownloads.fetch("${server.base}/f/Font.ttf", dir)
        fail("a truncated body should fail the download")
      } catch (_: IOException) {
      }
      cutOff = false
      val file = FontDownloads.fetch("${server.base}/f/Font.ttf", dir)
      assertArrayEquals(full, file.readBytes())
    }
  }

  @Test
  fun `same file name on different paths caches separately`() {
    TestServer { path, socket -> TestServer.respond(socket, path.toByteArray()) }.use { server ->
      val a = FontDownloads.fetch("${server.base}/a/font.ttf", dir)
      val b = FontDownloads.fetch("${server.base}/b/font.ttf", dir)
      assertNotEquals(a, b)
      assertEquals("/a/font.ttf", a.readText())
      assertEquals("/b/font.ttf", b.readText())
    }
  }

  @Test
  fun `concurrent downloads of one url all see the complete file`() {
    val body = ByteArray(256 * 1024) { (it * 31).toByte() }
    TestServer { _, socket ->
      val out = socket.getOutputStream()
      out.write("HTTP/1.1 200 OK\r\nContent-Length: ${body.size}\r\nConnection: close\r\n\r\n".toByteArray())
      body.asList().chunked(8192).forEach { out.write(it.toByteArray()); out.flush(); Thread.sleep(2) }
    }.use { server ->
      val pool = Executors.newFixedThreadPool(6)
      val results = (0 until 6).map {
        pool.submit(Callable { FontDownloads.fetch("${server.base}/c/Shared.ttf", dir).readBytes() })
      }.map { it.get() }
      pool.shutdown()
      results.forEach { assertArrayEquals(body, it) }
    }
  }

  @Test
  fun `a server that never answers times out`() {
    TestServer { _, _ -> Thread.sleep(10_000) }.use { server ->
      val started = System.nanoTime()
      try {
        FontDownloads.fetch("${server.base}/slow/Font.ttf", dir, timeoutMs = 300)
        fail("a stalled download should time out")
      } catch (_: IOException) {
      }
      val elapsedMs = (System.nanoTime() - started) / 1_000_000
      assertTrue("took ${elapsedMs}ms", elapsedMs < 3_000)
    }
  }
}
