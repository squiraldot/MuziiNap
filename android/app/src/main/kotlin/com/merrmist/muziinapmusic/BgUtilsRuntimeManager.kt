package com.merrmist.muziinapmusic

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.zip.ZipInputStream
import java.util.concurrent.TimeUnit
import java.net.SocketTimeoutException
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Local BgUtils runtime bootstrap. The Node runtime is an independently installed,
 * user-approved helper package; it is never silently installed by MuziiNap.
 */
internal object BgUtilsRuntimeManager {
    const val HELPER_PACKAGE = "com.deniscerri.ytdl.nodejs"
    const val PORT = 4416
    // Android network security config permits cleartext localhost, not the 127.0.0.1 literal.
    internal const val HEALTH_CHECK_URL = "http://localhost:4416/ping"
    @Volatile private var activeDownloadConnection: HttpURLConnection? = null
    private const val PROVIDER_VERSION = "2.0.2"
    private const val RUNTIME_VERSION = "26.12.1"
    @Volatile var runtimeInstallState: String = "missing"
        private set
    @Volatile var runtimeDownloadInProgress: Boolean = false
        private set
    @Volatile var runtimeDownloadBytes: Long = 0L
        private set
    @Volatile var runtimeDownloadTotalBytes: Long = 0L
        private set
    private val runtimeAssets = mapOf(
        "arm64-v8a" to ("app-nodejs-arm64-v8a-release.apk" to "57d6928e5ae7f715b6ac2ba9b15795fba1901d114c9125844bfbfb9d35b53ac6"),
        "armeabi-v7a" to ("app-nodejs-armeabi-v7a-release.apk" to "e2e107cebd5fc2e2e7e66cbbbbabb5dd506592a7865038fa6b22522439a58536"),
        "x86" to ("app-nodejs-x86-release.apk" to "83590a4b1becacad92bad14816a854738f2bbb01b9ffdf0b655a4a29a83be3aa"),
        "x86_64" to ("app-nodejs-x86_64-release.apk" to "59732f645404da8eab408bd1c9a9502acf450155bda125ff598cbc5ad095c596")
    )
    private const val PROVIDER_URL = "https://codeload.github.com/Brainicism/bgutil-ytdlp-pot-provider/zip/26475e9d3665b972c4aeb83b4dbaafcf64b88438"

    internal fun cancelActiveDownload() {
        activeDownloadConnection?.disconnect()
    }

    internal fun runtimeAssetForAbi(abi: String): Pair<String, String>? = runtimeAssets[abi]

    internal fun runtimeUrlForAbi(abi: String): String? {
        val asset = runtimeAssets[abi]?.first ?: return null
        return "https://github.com/deniscerri/ytdlnis-packages/releases/download/nodejs-$RUNTIME_VERSION/$asset"
    }

    fun isRuntimeInstalled(context: Context): Boolean = try {
        if (Build.VERSION.SDK_INT >= 33) {
            context.packageManager.getApplicationInfo(HELPER_PACKAGE, PackageManager.ApplicationInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getApplicationInfo(HELPER_PACKAGE, 0)
        }
        runtimeInstallState = "installed"
        android.util.Log.i("MuziiNap-BgUtils", "Node.js runtime package is installed")
        true
    } catch (error: Exception) {
        runtimeInstallState = "missing"
        android.util.Log.w("MuziiNap-BgUtils", "Node.js runtime package is not installed", error)
        false
    }

    fun prepareInstaller(context: Context, onProgress: (Long, Long) -> Unit = { _, _ -> }): File {
        android.util.Log.i("MuziiNap-BgUtils", "Runtime setup requested; supported ABIs=" + Build.SUPPORTED_ABIS.joinToString())
        val abi = Build.SUPPORTED_ABIS.firstOrNull { runtimeAssets.containsKey(it) }
            ?: throw IllegalStateException("No compatible Node runtime is published for this device ABI.")
        android.util.Log.i("MuziiNap-BgUtils", "Selected runtime ABI=" + abi)
        val (assetName, digest) = runtimeAssets.getValue(abi)
        val url = "https://github.com/deniscerri/ytdlnis-packages/releases/download/nodejs-$RUNTIME_VERSION/$assetName"
        val dir = File(context.filesDir, "bgutils").apply { mkdirs() }
        val apk = File(dir, "nodejs-$RUNTIME_VERSION-$abi.apk")
        if (!apk.exists() || !verifySha256(apk, digest)) {
            android.util.Log.i("MuziiNap-BgUtils", "Runtime APK missing or invalid; downloading asset=" + assetName + " host=" + URL(url).host)
            runtimeInstallState = "downloading"
            apk.delete()
            runtimeDownloadBytes = 0L
            runtimeDownloadTotalBytes = 0L
            runtimeDownloadInProgress = true
            try {
                downloadVerified(url, apk, digest, 100L * 1024L * 1024L) { downloaded, total ->
                    runtimeDownloadBytes = downloaded
                    runtimeDownloadTotalBytes = total
                    onProgress(downloaded, total)
                    android.util.Log.d("MuziiNap-BgUtils", "Runtime download bytes=" + downloaded + " total=" + total)
                }
            } catch (error: Exception) {
                runtimeInstallState = "failed"
                android.util.Log.e("MuziiNap-BgUtils", "Runtime APK download/verification failed", error)
                throw error
            } finally {
                runtimeDownloadInProgress = false
            }
            runtimeInstallState = "verified"
            android.util.Log.i("MuziiNap-BgUtils", "Runtime APK verified: " + apk.length() + " bytes")
        } else {
            runtimeInstallState = "verified"
        }
        return apk
    }

    fun launchInstaller(activity: Activity, apk: File): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !activity.packageManager.canRequestPackageInstalls()) {
            val settingsIntent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                .setData(Uri.parse("package:${activity.packageName}"))
            activity.startActivity(settingsIntent)
            runtimeInstallState = "awaiting_install_permission"
            android.util.Log.i("MuziiNap-BgUtils", "Waiting for unknown-app installation permission")
            return "allow_install_from_this_source"
        }
        val uri = FileProvider.getUriForFile(
            activity,
            "${activity.packageName}.fileprovider",
            apk
        )
        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        activity.startActivity(intent)
        runtimeInstallState = "awaiting_installation"
        android.util.Log.i("MuziiNap-BgUtils", "Android package installer launched")
        return "installer_opened"
    }

    fun startService(context: Context) {
        val intent = Intent(context, BgUtilsPotService::class.java)
        androidx.core.content.ContextCompat.startForegroundService(context, intent)
    }

    fun stopService(context: Context) {
        context.stopService(Intent(context, BgUtilsPotService::class.java))
    }

    fun prepareServer(context: Context, status: (String) -> Unit) {
        check(isRuntimeInstalled(context)) { "Install the Node.js runtime helper first." }
        val appInfo = if (Build.VERSION.SDK_INT >= 33) {
            context.packageManager.getApplicationInfo(HELPER_PACKAGE, PackageManager.ApplicationInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getApplicationInfo(HELPER_PACKAGE, 0)
        }
        val nativeDir = File(appInfo.nativeLibraryDir)
        val node = File(nativeDir, "libnode.so")
        val zipLibrary = File(nativeDir, "libnode.zip.so")
        check(node.isFile && zipLibrary.isFile) { "Installed Node runtime is missing its native executable." }

        val root = File(context.filesDir, "bgutils").apply { mkdirs() }
        val runtimeDir = File(root, "node-runtime")
        val npmCli = File(runtimeDir, "usr/lib/node_modules/npm/bin/npm-cli.js")
        if (!npmCli.isFile) {
            status("Preparing Node.js runtime")
            runtimeDir.deleteRecursively()
            runtimeDir.mkdirs()
            ZipInputStream(zipLibrary.inputStream().buffered()).use { zip ->
                while (true) {
                    val entry = zip.nextEntry ?: break
                    val output = safeChild(runtimeDir, entry.name)
                    if (entry.isDirectory) output.mkdirs() else {
                        output.parentFile?.mkdirs()
                        FileOutputStream(output).use { out -> zip.copyTo(out) }
                    }
                    zip.closeEntry()
                }
            }
            check(npmCli.isFile) { "Node runtime npm files could not be extracted." }
        }

        val serverDir = File(root, "provider-$PROVIDER_VERSION/server")
        val ready = File(serverDir, ".muziinap-ready-$PROVIDER_VERSION")
        if (!ready.isFile || !File(serverDir, "build/main.js").isFile) {
            status("Downloading BgUtils provider $PROVIDER_VERSION")
            val archive = File(root, "provider-$PROVIDER_VERSION.zip")
            downloadPinnedArchive(PROVIDER_URL, archive, 30L * 1024L * 1024L)
            val sourceRoot = File(root, "provider-$PROVIDER_VERSION").apply {
                deleteRecursively()
                mkdirs()
            }
            ZipInputStream(archive.inputStream().buffered()).use { zip ->
                while (true) {
                    val entry = zip.nextEntry ?: break
                    val relative = entry.name.substringAfter('/', "")
                    if (relative.isNotEmpty()) {
                        val output = safeChild(sourceRoot, relative)
                        if (entry.isDirectory) output.mkdirs() else {
                            output.parentFile?.mkdirs()
                            FileOutputStream(output).use { out -> zip.copyTo(out) }
                        }
                    }
                    zip.closeEntry()
                }
            }
            archive.delete()
            val packageJson = File(serverDir, "package.json")
            check(packageJson.isFile && packageJson.readText().contains("\"version\": \"$PROVIDER_VERSION\"")) {
                "Pinned BgUtils server package/version is missing from the source archive."
            }

            status("Installing BgUtils dependencies")
            val env = nodeEnvironment(nativeDir, runtimeDir, context)
            val lock = File(serverDir, "package-lock.json")
            val installArgs = if (lock.isFile) listOf("ci") else listOf("install")
            runCommand(
                listOf(node.absolutePath, npmCli.absolutePath) + installArgs +
                    listOf("--ignore-scripts", "--no-audit", "--no-fund"),
                serverDir, env, 12 * 60
            )
            status("Compiling BgUtils server")
            runCommand(
                listOf(node.absolutePath, File(serverDir, "node_modules/typescript/bin/tsc").absolutePath, "--outDir", "build"),
                serverDir, env, 3 * 60
            )
            check(File(serverDir, "build/main.js").isFile) { "BgUtils server compilation did not produce build/main.js." }
            ready.writeText(PROVIDER_VERSION)
        }
    }

    fun launchServer(context: Context): Process {
        val appInfo = if (Build.VERSION.SDK_INT >= 33) {
            context.packageManager.getApplicationInfo(HELPER_PACKAGE, PackageManager.ApplicationInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getApplicationInfo(HELPER_PACKAGE, 0)
        }
        val nativeDir = File(appInfo.nativeLibraryDir)
        val runtimeDir = File(context.filesDir, "bgutils/node-runtime")
        val serverDir = File(context.filesDir, "bgutils/provider-$PROVIDER_VERSION/server")
        val node = File(nativeDir, "libnode.so")
        check(File(serverDir, "build/main.js").isFile) { "BgUtils server is not prepared." }
        val process = ProcessBuilder(
            node.absolutePath, "build/main.js", "--host", "127.0.0.1", "--port", PORT.toString()
        ).directory(serverDir).redirectErrorStream(true).apply {
            environment().putAll(nodeEnvironment(nativeDir, runtimeDir, context))
        }.start()
        Thread {
            process.inputStream.bufferedReader().useLines { lines ->
                lines.forEach { android.util.Log.i("MuziiNap-BgUtils", it) }
            }
        }.apply { name = "BgUtils-stdout"; isDaemon = true; start() }
        return process
    }

    fun isServerReady(): Boolean = try {
        val connection = URL(HEALTH_CHECK_URL).openConnection() as HttpURLConnection
        connection.connectTimeout = 800
        connection.readTimeout = 800
        connection.useCaches = false
        try {
            val response = connection.responseCode
            if (response != 200) {
                logInfo("BgUtils health check returned HTTP " + response)
                false
            } else {
                val body = connection.inputStream.bufferedReader().use { it.readText() }
                val healthy = isHealthyPingResponse(body)
                if (!healthy) logInfo("BgUtils /ping returned unexpected response: " + body.take(300))
                healthy
            }
        } finally {
            connection.disconnect()
        }
    } catch (error: Exception) {
        logInfo("BgUtils health check failed: " + error.message)
        false
    }

    internal fun isHealthyPingResponse(body: String): Boolean =
        Regex("\\\"version\\\"\\s*:\\s*\\\"$PROVIDER_VERSION\\\"").containsMatchIn(body) &&
            Regex("\\\"server_uptime\\\"\\s*:\\s*[0-9]+(\\.[0-9]+)?").containsMatchIn(body)

    private fun nodeEnvironment(nativeDir: File, runtimeDir: File, context: Context): Map<String, String> {
        val home = File(context.filesDir, "bgutils/node-home").apply { mkdirs() }
        val dnsPatch = File(context.filesDir, "bgutils/node-dns.js")
        if (!dnsPatch.exists()) dnsPatch.writeText(DNS_PATCH)
        val usr = File(runtimeDir, "usr")
        val cert = File(usr, "etc/tls/cert.pem")
        return buildMap {
            put("HOME", home.absolutePath)
            put("TMPDIR", context.cacheDir.absolutePath)
            put("LD_LIBRARY_PATH", listOf(nativeDir.absolutePath, File(usr, "lib").absolutePath).joinToString(":"))
            put("PATH", "/system/bin:${nativeDir.absolutePath}:${File(usr, "bin").absolutePath}")
            put("NODE_OPTIONS", "--require ${dnsPatch.absolutePath}")
            if (cert.isFile) {
                put("SSL_CERT_FILE", cert.absolutePath)
                put("NODE_EXTRA_CA_CERTS", cert.absolutePath)
            }
        }
    }

    private fun runCommand(command: List<String>, directory: File, env: Map<String, String>, timeoutMinutes: Long) {
        val process = ProcessBuilder(command).directory(directory).redirectErrorStream(true).apply {
            environment().putAll(env)
        }.start()
        val output = StringBuilder()
        val reader = Thread {
            process.inputStream.bufferedReader().useLines { lines ->
                lines.forEach { line ->
                    output.append(line).append('
')
                    android.util.Log.i("MuziiNap-BgUtils-Setup", line)
                }
            }
        }.apply { isDaemon = true; start() }
        if (!process.waitFor(timeoutMinutes, TimeUnit.MINUTES)) {
            process.destroyForcibly()
            throw IllegalStateException("BgUtils setup command timed out.")
        }
        reader.join(2_000)
        check(process.exitValue() == 0) {
            "BgUtils setup command failed (exit ${process.exitValue()}): ${output.takeLast(3000)}"
        }
    }

    private fun downloadPinnedArchive(url: String, target: File, maxBytes: Long, overallTimeoutMillis: Long = 180_000L) {
        target.parentFile?.mkdirs()
        val part = File(target.parentFile, target.name + ".part")
        part.delete()
        val connection = URL(url).openConnection() as HttpURLConnection
        activeDownloadConnection = connection
        activeDownloadConnection = connection
        connection.connectTimeout = 20_000
        connection.readTimeout = 20_000
        connection.instanceFollowRedirects = true
        val expired = AtomicBoolean(false)
        val finished = AtomicBoolean(false)
        val startedAt = System.currentTimeMillis()
        val watchdog = Thread({
            try {
                Thread.sleep(overallTimeoutMillis)
                if (finished.compareAndSet(false, true)) {
                    expired.set(true)
                    logError("BgUtils source archive exceeded overall download deadline", null)
                    connection.disconnect()
                }
            } catch (_: InterruptedException) { }
        }, "BgUtils-source-deadline").apply { isDaemon = true; start() }
        try {
            val response = connection.responseCode
            logInfo("BgUtils source archive HTTP " + response + " host=" + connection.url.host)
            check(response in 200..299) { "BgUtils source download failed: HTTP " + response }
            val declared = connection.contentLength.toLong()
            check(declared <= maxBytes || declared < 0) { "BgUtils source archive exceeds the allowed size." }
            var total = 0L
            FileOutputStream(part).use { output ->
                connection.inputStream.use { input ->
                    val buffer = ByteArray(32 * 1024)
                    while (true) {
                        if (expired.get() || System.currentTimeMillis() - startedAt >= overallTimeoutMillis) throw SocketTimeoutException("BgUtils source download timed out.")
                        if (Thread.currentThread().isInterrupted) throw InterruptedException("BgUtils source download cancelled.")
                        val count = input.read(buffer)
                        if (count < 0) break
                        total += count
                        check(total <= maxBytes) { "BgUtils source archive exceeds the allowed size." }
                        output.write(buffer, 0, count)
                    }
                }
            }
            if (expired.get() || System.currentTimeMillis() - startedAt >= overallTimeoutMillis) throw SocketTimeoutException("BgUtils source download timed out.")
            check(part.isFile && part.length() > 0L) { "BgUtils source download returned an empty file." }
            if (declared >= 0L) check(total == declared) { "BgUtils source download was incomplete." }
            check(part.renameTo(target)) { "Could not atomically publish BgUtils source archive." }
        } catch (error: Exception) {
            part.delete()
            if (expired.get()) throw SocketTimeoutException("BgUtils source download timed out.")
            if (Thread.currentThread().isInterrupted) throw InterruptedException("BgUtils source download cancelled.")
            logError("BgUtils source archive download failed", error)
            throw error
        } finally {
            finished.set(true)
            watchdog.interrupt()
            connection.disconnect()
            if (activeDownloadConnection === connection) activeDownloadConnection = null
            if (part.exists()) part.delete()
        }
    }
    /** Downloads to a sibling .part file and publishes only after size and SHA-256 verification. */
    internal fun downloadVerified(url: String, target: File, expectedSha256: String, maxBytes: Long, overallTimeoutMillis: Long = 180_000L, onProgress: (Long, Long) -> Unit) {
        target.parentFile?.mkdirs()
        val part = File(target.parentFile, target.name + ".part")
        part.delete()
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 20_000
        connection.readTimeout = 20_000
        connection.instanceFollowRedirects = true
        val expired = AtomicBoolean(false)
        val finished = AtomicBoolean(false)
        val startedAt = System.currentTimeMillis()
        val watchdog = Thread({
            try {
                Thread.sleep(overallTimeoutMillis)
                if (finished.compareAndSet(false, true)) {
                    expired.set(true)
                    logError("Runtime download exceeded overall deadline " + overallTimeoutMillis + "ms", null)
                    connection.disconnect()
                }
            } catch (_: InterruptedException) { }
        }, "BgUtils-download-deadline").apply { isDaemon = true; start() }
        try {
            val response = connection.responseCode
            logInfo("Runtime download HTTP " + response + " host=" + connection.url.host)
            check(response in 200..299) { "Runtime download failed: HTTP " + response }
            val declared = connection.contentLength.toLong()
            check(declared <= maxBytes || declared < 0) { "Runtime download exceeds the allowed size." }
            var total = 0L
            FileOutputStream(part).use { output ->
                connection.inputStream.use { input ->
                    val buffer = ByteArray(32 * 1024)
                    while (true) {
                        if (expired.get() || System.currentTimeMillis() - startedAt >= overallTimeoutMillis) throw SocketTimeoutException("Runtime download timed out after " + (overallTimeoutMillis / 1000) + " seconds.")
                        if (Thread.currentThread().isInterrupted) throw InterruptedException("Runtime download cancelled.")
                        val count = input.read(buffer)
                        if (count < 0) break
                        total += count
                        check(total <= maxBytes) { "Runtime download exceeds the allowed size." }
                        output.write(buffer, 0, count)
                        onProgress(total, declared)
                    }
                }
            }
            if (expired.get() || System.currentTimeMillis() - startedAt >= overallTimeoutMillis) throw SocketTimeoutException("Runtime download timed out after " + (overallTimeoutMillis / 1000) + " seconds.")
            check(part.isFile && part.length() > 0L) { "Runtime download returned an empty file." }
            if (declared >= 0L) check(total == declared) { "Runtime download was incomplete: received " + total + " of " + declared + " bytes." }
            val valid = verifySha256(part, expectedSha256)
            logInfo("Runtime SHA-256 verification result=" + valid)
            check(valid) { "Downloaded runtime failed SHA-256 verification." }
            // Same-directory rename maps to the filesystem rename operation and atomically replaces an existing target on Android/Linux.
            check(part.renameTo(target)) { "Could not atomically publish the verified runtime APK." }
        } catch (error: Exception) {
            part.delete()
            if (expired.get()) throw SocketTimeoutException("Runtime download timed out after " + (overallTimeoutMillis / 1000) + " seconds.")
            if (Thread.currentThread().isInterrupted) throw InterruptedException("Runtime download cancelled.")
            logError("Runtime download failed", error)
            throw error
        } finally {
            finished.set(true)
            watchdog.interrupt()
            connection.disconnect()
            if (activeDownloadConnection === connection) activeDownloadConnection = null
            if (part.exists()) part.delete()
        }
    }

    private fun logInfo(message: String) { try { android.util.Log.i("MuziiNap-BgUtils", message) } catch (_: RuntimeException) { } }
    private fun logError(message: String, error: Throwable?) { try { android.util.Log.e("MuziiNap-BgUtils", message, error) } catch (_: RuntimeException) { } }

    internal fun verifySha256(file: File, expected: String): Boolean {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(32 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        val actual = digest.digest().joinToString("") { "%02x".format(it) }
        return actual.equals(expected, ignoreCase = true)
    }

    private fun safeChild(root: File, relative: String): File {
        val target = File(root, relative).canonicalFile
        val rootPath = root.canonicalPath
        val targetPath = target.canonicalPath
        check(targetPath == rootPath || targetPath.startsWith(rootPath + File.separator)) {
            "Archive contains an unsafe path."
        }
        return target
    }

    private val DNS_PATCH = """
        const dns = require('dns');
        const net = require('net');
        const resolver = new dns.Resolver();
        resolver.setServers(['8.8.8.8', '1.1.1.1']);
        dns.lookup = function(host, options, callback) {
          if (typeof options === 'function') { callback = options; options = {}; }
          options = options || {};
          const ip = net.isIP(host);
          if (ip) return callback(null, host, ip);
          if (host === 'localhost') return callback(null, '127.0.0.1', 4);
          const family = options.family || 4;
          resolver[family === 6 ? 'resolve6' : 'resolve4'](host, (error, addresses) => {
            if (error) return callback(error);
            const values = addresses.map(address => ({ address, family }));
            if (options.all) return callback(null, values);
            callback(null, values[0].address, family);
          });
        };
    """.trimIndent()
}
