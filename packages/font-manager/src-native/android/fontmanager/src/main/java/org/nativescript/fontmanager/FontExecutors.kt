package org.nativescript.fontmanager

import java.util.ArrayDeque
import java.util.concurrent.Executor
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

internal object FontExecutors {
  /**
   * One pool for all font work. Core threads are allowed to time out, so an app
   * holding many [FontFace]s costs no threads at rest — previously each face owned
   * a single-thread executor that lived for the process lifetime.
   */
  val shared: Executor = ThreadPoolExecutor(
    2, 2, 30L, TimeUnit.SECONDS, LinkedBlockingQueue()
  ) { r -> Thread(r, "ns-font-manager").apply { isDaemon = true } }
    .apply { allowCoreThreadTimeOut(true) }

  fun serial(): Executor = SerialExecutor(shared)
}

/**
 * Runs its tasks one at a time, in submission order, on [delegate].
 *
 * This preserves the ordering guarantee each face used to get from owning a
 * dedicated single-thread executor, without owning a thread.
 */
internal class SerialExecutor(private val delegate: Executor) : Executor {
  private val tasks = ArrayDeque<Runnable>()
  private var active: Runnable? = null

  override fun execute(command: Runnable) {
    synchronized(tasks) {
      tasks.add(Runnable {
        try {
          command.run()
        } finally {
          scheduleNext()
        }
      })
      if (active == null) scheduleNext()
    }
  }

  private fun scheduleNext() {
    synchronized(tasks) {
      active = tasks.poll()
      active?.let { delegate.execute(it) }
    }
  }
}
