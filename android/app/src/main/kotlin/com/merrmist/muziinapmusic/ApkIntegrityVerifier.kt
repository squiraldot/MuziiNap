package com.merrmist.muziinapmusic

import android.content.Context
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.os.Build
import android.util.Log
import java.security.MessageDigest

/** Best-effort local APK identity check, not a trust boundary against a patched client. */
internal object ApkIntegrityVerifier {
    private const val TAG = "MuziiNap-Integrity"

    fun verifyAtStartup(context: Context): ApkIntegrityPolicy.Status {
        return try {
            val trusted = ApkIntegrityPolicy.normalizeFingerprints(BuildConfig.TRUSTED_RELEASE_CERT_SHA256S)
            val actual = installedSignerFingerprints(context)
            val status = ApkIntegrityPolicy.evaluate(
                BuildConfig.APPLICATION_ID == context.packageName,
                BuildConfig.DEBUG,
                trusted,
                actual
            )
            when (status) {
                ApkIntegrityPolicy.Status.TRUSTED_RELEASE -> Log.i(TAG, "Release signing identity verified.")
                ApkIntegrityPolicy.Status.DEBUG_BUILD -> Log.i(TAG, "Debug build; release pinning is not applied.")
                ApkIntegrityPolicy.Status.UNCONFIGURED -> Log.w(TAG, "Release signing pin unavailable; integrity is unverified.")
                ApkIntegrityPolicy.Status.PACKAGE_ID_MISMATCH -> Log.e(TAG, "Installed package identity mismatch.")
                ApkIntegrityPolicy.Status.SIGNATURE_MISMATCH -> Log.e(TAG, "Installed APK signer is not trusted.")
            }
            status
        } catch (error: Exception) {
            Log.w(TAG, "APK integrity verification unavailable; startup continues.", error)
            ApkIntegrityPolicy.Status.UNCONFIGURED
        }
    }

    private fun installedSignerFingerprints(context: Context): Set<String> {
        // PackageManager exposes platform arrays with projected/nullability types;
        // normalize both API paths to List<Signature> before hashing.
        val signatures: List<Signature> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val info = context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            val signingInfo = info.signingInfo ?: return emptySet()
            if (signingInfo.hasMultipleSigners()) signingInfo.apkContentsSigners.toList()
            else signingInfo.signingCertificateHistory.toList()
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_SIGNATURES)
                .signatures.orEmpty().toList()
        }
        val digest = MessageDigest.getInstance("SHA-256")
        return signatures.map { signature ->
            digest.digest(signature.toByteArray()).joinToString("") { "%02X".format(it) }
        }.toSet()
    }
}

internal object ApkIntegrityPolicy {
    enum class Status { TRUSTED_RELEASE, DEBUG_BUILD, UNCONFIGURED, PACKAGE_ID_MISMATCH, SIGNATURE_MISMATCH }

    fun normalizeFingerprints(value: String): Set<String> =
        value.split(Regex("[,;\\s]+"))
            .map { it.replace(":", "").trim().uppercase() }
            .filter { it.matches(Regex("[A-F0-9]{64}")) }
            .toSet()

    fun evaluate(
        packageIdMatches: Boolean,
        debugBuild: Boolean,
        trustedFingerprints: Set<String>,
        actualFingerprints: Set<String>
    ): Status {
        if (!packageIdMatches) return Status.PACKAGE_ID_MISMATCH
        if (debugBuild) return Status.DEBUG_BUILD
        if (trustedFingerprints.isEmpty()) return Status.UNCONFIGURED
        return if (actualFingerprints.any { it.uppercase() in trustedFingerprints }) Status.TRUSTED_RELEASE
        else Status.SIGNATURE_MISMATCH
    }
}
