package org.nativescript.fontmanager

import android.os.Handler
import android.os.Looper
import java.util.ArrayDeque
import java.util.concurrent.Executor
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

internal object FontExecutors {
  private fun pool(threads: Int, name: String): Executor = ThreadPoolExecutor(
    threads, threads, 30L, TimeUnit.SECONDS, LinkedBlockingQueue()
  ) { r -> Thread(r, name).apply { isDaemon = true } }
    .apply { allowCoreThreadTimeOut(true) }

  val shared: Executor = pool(Runtime.getRuntime().availableProcessors().coerceIn(2, 4), "ns-font-manager")

  val io: Executor = pool(4, "ns-font-manager-io")

  /**
   * Every callback this library hands back originates in JS, and the NativeScript
   * runtime is bound to the main thread, so results are delivered here rather than
   * on whichever pool thread happened to finish the work.
   */
  val main: Executor = Handler(Looper.getMainLooper()).let { handler ->
    Executor { command ->
      if (Looper.myLooper() === handler.looper) command.run() else handler.post(command)
    }
  }

  fun serial(delegate: Executor = shared): Executor = SerialExecutor(delegate)
}

internal class SerialExecutor(private val delegate: Executor) : Executor {
  private val tasks = ArrayDeque<Runnable>()
  private var running = false

  override fun execute(command: Runnable) {
    synchronized(tasks) {
      tasks.add(Runnable {
        try {
          command.run()
        } finally {
          drainNext()
        }
      })
      if (running) return
      running = true
    }
    drainNext()
  }

  private fun drainNext() {
    val next = synchronized(tasks) {
      tasks.poll().also { if (it == null) running = false }
    } ?: return
    try {
      delegate.execute(next)
    } catch (e: Throwable) {
      synchronized(tasks) {
        tasks.clear()
        running = false
      }
      throw e
    }
  }
}
