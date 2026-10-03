package com.cindy.tracker

import android.Manifest
import android.content.pm.PackageManager
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowDialog

/**
 * What FIND MY WATCH does about the permission it needs.
 *
 * Android 11 and older tie a Bluetooth scan to the location permission, so the prompt that follows
 * is about location, to someone who asked to find a watch. Cindy says why first, and asks only
 * once the athlete has said CONTINUE. Android 12 and newer have a Bluetooth permission of their
 * own, which needs no explaining. The only test here off SDK 34 is the one that has to be.
 */
@RunWith(RobolectricTestRunner::class)
class HeartRatePermissionSheetTest {

    private val title = "Android asks for location to find a watch"

    private fun descendants(root: View): List<View> = buildList {
        add(root)
        if (root is ViewGroup) for (i in 0 until root.childCount) addAll(descendants(root.getChildAt(i)))
    }

    private fun byText(root: View, text: String): View? =
        descendants(root).firstOrNull { it is TextView && it.text.toString() == text }

    private fun byDescriptionPrefix(root: View, prefix: String): View? =
        descendants(root).firstOrNull { it.contentDescription?.toString()?.startsWith(prefix) == true }

    private fun latestSheet(): View? =
        ShadowDialog.getLatestDialog()?.takeIf { it.isShowing }?.window?.decorView

    /** Opens the menu on a phone with Bluetooth LE and taps through to FIND MY WATCH. */
    private fun tapFindMyWatch(): MenuActivity {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        shadowOf(context.packageManager).setSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE, true)
        val menu = Robolectric.buildActivity(
            MenuActivity::class.java, MenuActivity.intent(context, workoutLive = false)
        ).setup().get()
        val root = menu.findViewById<View>(android.R.id.content)

        byDescriptionPrefix(root, "Heart rate")!!.performClick()
        byText(latestSheet()!!, "FIND MY WATCH")!!.performClick()
        return menu
    }

    @Test
    @Config(sdk = [30])
    fun `before Android 12 the location prompt is explained first, and not asked for until CONTINUE`() {
        val menu = tapFindMyWatch()

        val sheet = latestSheet()
        assertNotNull("no explanation was shown", sheet)
        assertNotNull(byText(sheet!!, title))
        assertNull("the permission was asked for before the athlete said so",
            shadowOf(menu).lastRequestedPermission)

        byText(sheet, "CONTINUE")!!.performClick()
        val asked = shadowOf(menu).lastRequestedPermission
        assertNotNull("CONTINUE did not ask for the permission", asked)
        assertArrayEquals(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION), asked.requestedPermissions)
        menu.finish()
    }

    @Test
    @Config(sdk = [30])
    fun `NOT NOW before Android 12 asks for nothing`() {
        val menu = tapFindMyWatch()

        byText(latestSheet()!!, "NOT NOW")!!.performClick()
        assertNull(shadowOf(menu).lastRequestedPermission)
        menu.finish()
    }

    @Test
    @Config(sdk = [34])
    fun `from Android 12 the Bluetooth prompt comes straight away, with no explanation`() {
        val menu = tapFindMyWatch()

        val sheet = latestSheet()
        assertFalse("an explanation nobody needs", sheet != null && byText(sheet, title) != null)
        val asked = shadowOf(menu).lastRequestedPermission
        assertNotNull("the Bluetooth permission was not asked for", asked)
        assertEquals(
            setOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT),
            asked.requestedPermissions.toSet()
        )
        menu.finish()
    }
}
