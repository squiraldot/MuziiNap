package com.merrmist.muziinapmusic

import com.sun.net.httpserver.HttpServer
import java.io.File
import java.net.InetSocketAddress
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class BgUtilsRuntimeManagerTest {
    @Test
    fun healthCheckUsesCleartextPermittedLocalhostHost() {
        val url = java.net.URL(BgUtilsRuntimeManager.HEALTH_CHECK_URL)
        assertEquals("http", url.protocol)
        assertEquals("localhost", url.host)
        assertEquals("/ping", url.path)
    }

    @Test
    fun healthCheckRequiresExpectedProviderVersionAndUptime() {
        assertTrue(BgUtilsRuntimeManager.isHealthyPingResponse("""{"server_uptime":12.34,"version":"2.0.2"}"""))
        assertFalse(BgUtilsRuntimeManager.isHealthyPingResponse("""{"server_uptime":12.34,"version":"2.0.1"}"""))
        assertFalse(BgUtilsRuntimeManager.isHealthyPingResponse("""{"version":"2.0.2"}"""))
        assertFalse(BgUtilsRuntimeManager.isHealthyPingResponse("not json"))
    }

    @Test
    fun selectsCorrectPublishedRuntimeAssetForSupportedAbis() {
        assertEquals("app-nodejs-arm64-v8a-release.apk", BgUtilsRuntimeManager.runtimeAssetForAbi("arm64-v8a")?.first)
        assertEquals("app-nodejs-armeabi-v7a-release.apk", BgUtilsRuntimeManager.runtimeAssetForAbi("armeabi-v7a")?.first)
        assertEquals("app-nodejs-x86-release.apk", BgUtilsRuntimeManager.runtimeAssetForAbi("x86")?.first)
        assertEquals("app-nodejs-x86_64-release.apk", BgUtilsRuntimeManager.runtimeAssetForAbi("x86_64")?.first)
        assertNull(BgUtilsRuntimeManager.runtimeAssetForAbi("riscv64"))
    }

    @Test
    fun constructsVersionedRuntimeReleaseUrl() {
        assertEquals(
            "https://github.com/deniscerri/ytdlnis-packages/releases/download/nodejs-26.12.1/app-nodejs-arm64-v8a-release.apk",
            BgUtilsRuntimeManager.runtimeUrlForAbi("arm64-v8a")
        )
        assertNull(BgUtilsRuntimeManager.runtimeUrlForAbi("unknown"))
    }

    @Test
    fun elfLibraryValidationRejectsFourteenByteSymlinkPlaceholder() {
        val file = File.createTempFile("bgutils-libz", ".so")
        try {
            file.writeBytes("libz.so.1.3.1".toByteArray())
            assertFalse(BgUtilsRuntimeManager.isElfLibrary(file))
            file.writeBytes(byteArrayOf(0x7f, 0x45, 0x4c, 0x46, 0x02, 0x01, 0x01, 0x00))
            assertTrue(BgUtilsRuntimeManager.isElfLibrary(file))
        } finally {
            file.delete()
        }
    }

    @Test
    fun verifiesSha256AndRejectsMismatch() {
        val file = File.createTempFile("bgutils-digest", ".bin")
        try {
            file.writeBytes("verified-runtime".toByteArray())
            assertTrue(BgUtilsRuntimeManager.verifySha256(file, sha256("verified-runtime".toByteArray())))
            assertFalse(BgUtilsRuntimeManager.verifySha256(file, "0".repeat(64)))
        } finally {
            file.delete()
        }
    }

    @Test
    fun successfulDownloadAtomicallyReplacesTargetAfterVerification() {
        val payload = "new verified apk bytes".toByteArray()
        withServer(payload) { url ->
            val directory = createTempDir(prefix = "bgutils-atomic")
            val target = File(directory, "runtime.apk")
            target.writeText("old invalid file")
            try {
                BgUtilsRuntimeManager.downloadVerified(url, target, sha256(payload), 1024, 5_000) { _, _ -> }
                assertArrayEquals(payload, target.readBytes())
                assertFalse(File(directory, "runtime.apk.part").exists())
            } finally {
                directory.deleteRecursively()
            }
        }
    }

    @Test
    fun httpErrorDoesNotPublishOrLeavePartialFile() {
        withServer("denied".toByteArray(), status = 403) { url ->
            val directory = createTempDir(prefix = "bgutils-http")
            val target = File(directory, "runtime.apk")
            try {
                val error = assertFails { BgUtilsRuntimeManager.downloadVerified(url, target, "0".repeat(64), 1024, 2_000) { _, _ -> } }
                assertTrue(error.message?.contains("403") == true)
                assertFalse(target.exists())
                assertFalse(File(directory, "runtime.apk.part").exists())
            } finally {
                directory.deleteRecursively()
            }
        }
    }

    @Test
    fun shaMismatchDeletesPartAndPreservesPreviousTarget() {
        withServer("tampered".toByteArray()) { url ->
            val directory = createTempDir(prefix = "bgutils-sha")
            val target = File(directory, "runtime.apk")
            target.writeText("previous")
            try {
                assertFails { BgUtilsRuntimeManager.downloadVerified(url, target, "0".repeat(64), 1024, 2_000) { _, _ -> } }
                assertEquals("previous", target.readText())
                assertFalse(File(directory, "runtime.apk.part").exists())
                val recovered = "valid retry payload".toByteArray()
                withServer(recovered) { retryUrl ->
                    BgUtilsRuntimeManager.downloadVerified(retryUrl, target, sha256(recovered), 1024, 2_000) { _, _ -> }
                }
                assertArrayEquals(recovered, target.readBytes())
            } finally {
                directory.deleteRecursively()
            }
        }
    }

    @Test
    fun readTimeoutRejectsAResponseThatStopsSendingData() {
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/stall") { exchange ->
            try {
                Thread.sleep(500)
                exchange.sendResponseHeaders(200, 1)
                exchange.responseBody.write(byteArrayOf(1))
            } catch (_: Exception) {
            } finally {
                exchange.close()
            }
        }
        server.start()
        val directory = createTempDir(prefix = "bgutils-read-timeout")
        val target = File(directory, "runtime.apk")
        try {
            val url = "http://127.0.0.1:${server.address.port}/stall"
            val error = assertFails {
                BgUtilsRuntimeManager.downloadVerified(
                    url,
                    target,
                    "0".repeat(64),
                    1024,
                    overallTimeoutMillis = 3_000,
                    readTimeoutMillis = 100
                ) { _, _ -> }
            }
            assertTrue(error is java.net.SocketTimeoutException)
            assertFalse(target.exists())
            assertFalse(File(directory, "runtime.apk.part").exists())
        } finally {
            server.stop(0)
            directory.deleteRecursively()
        }
    }

    @Test
    fun overallDeadlineClosesSlowTricklingResponseAndCleansPartialFile() {
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/runtime") { exchange ->
            exchange.sendResponseHeaders(200, 0)
            try {
                exchange.responseBody.write(byteArrayOf(1))
                exchange.responseBody.flush()
                Thread.sleep(600)
                exchange.responseBody.write(byteArrayOf(2))
                exchange.responseBody.flush()
            } catch (_: Exception) {
            } finally {
                exchange.close()
            }
        }
        server.start()
        val directory = createTempDir(prefix = "bgutils-timeout")
        val target = File(directory, "runtime.apk")
        try {
            val url = "http://127.0.0.1:${server.address.port}/runtime"
            val error = assertFails {
                BgUtilsRuntimeManager.downloadVerified(url, target, "0".repeat(64), 1024, 120) { _, _ -> }
            }
            assertTrue(error is java.net.SocketTimeoutException)
            assertFalse(target.exists())
            assertFalse(File(directory, "runtime.apk.part").exists())
        } finally {
            server.stop(0)
            directory.deleteRecursively()
        }
    }

    @Test
    fun explicitCancellationDisconnectsActiveHttpRequestAndCleansPartFile() {
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        val firstChunkSent = CountDownLatch(1)
        server.createContext("/slow") { exchange ->
            exchange.sendResponseHeaders(200, 0)
            try {
                exchange.responseBody.write(byteArrayOf(1))
                exchange.responseBody.flush()
                firstChunkSent.countDown()
                Thread.sleep(2_000)
                exchange.responseBody.write(byteArrayOf(2))
            } catch (_: Exception) {
            } finally {
                exchange.close()
            }
        }
        server.start()
        val directory = createTempDir(prefix = "bgutils-cancel-active")
        val target = File(directory, "runtime.apk")
        var failure: Throwable? = null
        val worker = Thread {
            try {
                BgUtilsRuntimeManager.downloadVerified(
                    "http://127.0.0.1:${server.address.port}/slow",
                    target,
                    "0".repeat(64),
                    1024,
                    5_000
                ) { _, _ -> }
            } catch (error: Throwable) {
                failure = error
            }
        }
        try {
            worker.start()
            assertTrue(firstChunkSent.await(2, TimeUnit.SECONDS))
            BgUtilsRuntimeManager.cancelActiveDownload()
            worker.join(2_000)
            assertFalse("cancelled download should exit promptly", worker.isAlive)
            assertNotNull(failure)
            assertFalse(target.exists())
            assertFalse(File(directory, "runtime.apk.part").exists())
        } finally {
            BgUtilsRuntimeManager.cancelActiveDownload()
            server.stop(0)
            directory.deleteRecursively()
        }
    }

    @Test
    fun interruptedDownloadCleansPartialFileAndDoesNotPublishTarget() {
        val payload = ByteArray(256 * 1024) { 7 }
        withServer(payload) { url ->
            val directory = createTempDir(prefix = "bgutils-cancel")
            val target = File(directory, "runtime.apk")
            var failure: Throwable? = null
            val worker = Thread {
                try {
                    BgUtilsRuntimeManager.downloadVerified(url, target, "0".repeat(64), payload.size.toLong() + 1, 5_000) { _, _ ->
                        Thread.currentThread().interrupt()
                    }
                } catch (error: Throwable) {
                    failure = error
                }
            }
            try {
                worker.start()
                worker.join(3_000)
                assertFalse("download worker should exit after cancellation", worker.isAlive)
                assertTrue(failure is InterruptedException)
                assertFalse(target.exists())
                assertFalse(File(directory, "runtime.apk.part").exists())
            } finally {
                worker.interrupt()
                directory.deleteRecursively()
            }
        }
    }

    @Test
    fun incompleteContentLengthIsNotPublished() {
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/short") { exchange ->
            exchange.sendResponseHeaders(200, 100)
            exchange.responseBody.write(byteArrayOf(1, 2, 3))
            exchange.close()
        }
        server.start()
        val directory = createTempDir(prefix = "bgutils-short")
        val target = File(directory, "runtime.apk")
        try {
            val url = "http://127.0.0.1:${server.address.port}/short"
            assertFails { BgUtilsRuntimeManager.downloadVerified(url, target, "0".repeat(64), 1024, 2_000) { _, _ -> } }
            assertFalse(target.exists())
            assertFalse(File(directory, "runtime.apk.part").exists())
        } finally {
            server.stop(0)
            directory.deleteRecursively()
        }
    }

    private fun withServer(payload: ByteArray, status: Int = 200, block: (String) -> Unit) {
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/runtime") { exchange ->
            exchange.sendResponseHeaders(status, payload.size.toLong())
            exchange.responseBody.use { it.write(payload) }
        }
        server.start()
        try {
            block("http://127.0.0.1:${server.address.port}/runtime")
        } finally {
            server.stop(0)
        }
    }

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    private fun assertFails(block: () -> Unit): Exception {
        try {
            block()
        } catch (error: Exception) {
            return error
        }
        fail("Expected operation to fail")
        throw AssertionError("unreachable")
    }
}
