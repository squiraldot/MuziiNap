package com.merrmist.muziinapmusic

import org.junit.Assert.assertEquals
import org.junit.Test

class ApkIntegrityPolicyTest {
    private val trusted = "A".repeat(64)

    @Test fun normalizesColonSeparatedFingerprints() {
        val formatted = trusted.chunked(2).joinToString(":").lowercase()
        assertEquals(setOf(trusted), ApkIntegrityPolicy.normalizeFingerprints("$formatted,invalid"))
    }

    @Test fun acceptsTrustedCurrentOrHistoricalSigner() {
        assertEquals(ApkIntegrityPolicy.Status.TRUSTED_RELEASE,
            ApkIntegrityPolicy.evaluate(true, false, setOf(trusted), setOf("B".repeat(64), trusted)))
    }

    @Test fun rejectsUnexpectedReleaseSigner() {
        assertEquals(ApkIntegrityPolicy.Status.SIGNATURE_MISMATCH,
            ApkIntegrityPolicy.evaluate(true, false, setOf(trusted), setOf("B".repeat(64))))
    }

    @Test fun keepsDebugBuildsSeparateFromReleasePinning() {
        assertEquals(ApkIntegrityPolicy.Status.DEBUG_BUILD,
            ApkIntegrityPolicy.evaluate(true, true, setOf(trusted), setOf("B".repeat(64))))
    }

    @Test fun missingPinIsUnconfiguredRatherThanTrusted() {
        assertEquals(ApkIntegrityPolicy.Status.UNCONFIGURED,
            ApkIntegrityPolicy.evaluate(true, false, emptySet(), setOf("B".repeat(64))))
    }

    @Test fun rejectsPackageIdentityMismatch() {
        assertEquals(ApkIntegrityPolicy.Status.PACKAGE_ID_MISMATCH,
            ApkIntegrityPolicy.evaluate(false, false, setOf(trusted), setOf(trusted)))
    }
}
