package com.merrmist.muziinapmusic

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ThemeWidgetLimitPolicyTest {
    @Test
    fun allowsFirstAndSecondWidget() {
        assertTrue(ThemeWidgetLimitPolicy.canRegister(0, false))
        assertTrue(ThemeWidgetLimitPolicy.canRegister(1, false))
    }

    @Test
    fun rejectsThirdWidgetAcrossProviderSizes() {
        assertFalse(ThemeWidgetLimitPolicy.canRegister(2, false))
        assertFalse(ThemeWidgetLimitPolicy.canRegister(3, false))
    }

    @Test
    fun keepsExistingWidgetWhenCapIsReached() {
        assertTrue(ThemeWidgetLimitPolicy.canRegister(2, true))
    }

    @Test
    fun treatsNegativeRegistryCountAsEmpty() {
        assertTrue(ThemeWidgetLimitPolicy.canRegister(-1, false))
    }
}
