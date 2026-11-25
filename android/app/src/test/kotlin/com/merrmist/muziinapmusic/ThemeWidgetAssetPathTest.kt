package com.merrmist.muziinapmusic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class ThemeWidgetAssetPathTest {
    @Test
    fun resolvesFourByTwoImagesOnlyFromFourByTwoFolder() {
        assertEquals(
            "assets/widget_assets/Dragon_Ball_Z/4x2/Widget1/Background.png",
            ThemeWidgetAssetPath.resolve("4x2", "Background.png")
        )
        assertEquals(
            "assets/widget_assets/Dragon_Ball_Z/4x2/Widget1/Border.png",
            ThemeWidgetAssetPath.resolve("4x2", "Border.png")
        )
        assertEquals(
            "assets/widget_assets/Dragon_Ball_Z/4x2/Widget1/Character.png",
            ThemeWidgetAssetPath.resolve("4x2", "Character.png")
        )
    }

    @Test
    fun resolvesFourByThreeImagesOnlyFromFourByThreeFolder() {
        assertEquals(
            "assets/widget_assets/Dragon_Ball_Z/4x3/Widget1/Background.png",
            ThemeWidgetAssetPath.resolve("4x3", "Background.png")
        )
    }

    @Test
    fun rejectsUnknownWidgetFoldersInsteadOfFallingBackToAnotherSize() {
        assertThrows(IllegalArgumentException::class.java) {
            ThemeWidgetAssetPath.resolve("4x2", "background.png")
        }
        assertThrows(IllegalArgumentException::class.java) {
            ThemeWidgetAssetPath.resolve("4x4", "Background.png")
        }
    }
}
