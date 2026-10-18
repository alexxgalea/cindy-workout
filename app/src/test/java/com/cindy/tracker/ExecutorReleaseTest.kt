package com.cindy.tracker

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ExecutorReleaseTest {

    @Test
    fun `release waits for the task already running`() {
        val executor = Executors.newSingleThreadExecutor()
        val running = CountDownLatch(1)
        val finish = CountDownLatch(1)
        val released = AtomicBoolean(false)
        val releasedWhileRunning = AtomicBoolean(true)

        executor.execute {
            running.countDown()
            finish.await(5, TimeUnit.SECONDS)
            releasedWhileRunning.set(released.get())
        }
        assertTrue(running.await(5, TimeUnit.SECONDS))

        executor.releaseAfterPending { released.set(true) }
        // The frame is still in flight: nothing may have been released under it.
        assertFalse(released.get())

        finish.countDown()
        assertTrue(executor.awaitTermination(5, TimeUnit.SECONDS))
        assertFalse("released while the task was still running", releasedWhileRunning.get())
        assertTrue(released.get())
    }

    @Test
    fun `executor stops accepting work after the release is queued`() {
        val executor = Executors.newSingleThreadExecutor()
        executor.releaseAfterPending { }
        assertTrue(executor.awaitTermination(5, TimeUnit.SECONDS))
        assertTrue(executor.isShutdown)
    }
}
