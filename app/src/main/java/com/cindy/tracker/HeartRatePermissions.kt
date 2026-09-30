package com.cindy.tracker

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat

/**
 * What "Bluetooth is allowed" means, which depends on how old the phone is.
 *
 * API 31 split Bluetooth into its own runtime permissions and stopped tying a scan to location
 * at all. Below that, the platform has no concept of a BLE scan that is not also a location
 * lookup, so the permission it insists on is [Manifest.permission.ACCESS_FINE_LOCATION] even
 * though this app never reads a coordinate — see [locationSwitchBlocksScan] for the other half
 * of that same fact.
 */
object HeartRatePermissions {

    /** The runtime permissions [start] needs granted before it can scan or connect. */
    fun required(sdk: Int = Build.VERSION.SDK_INT): Array<String> =
        if (sdk >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    /** Whether every permission [required] lists has actually been granted. */
    fun granted(context: Context): Boolean =
        required().all {
            ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
        }

    /**
     * True only on API 30 and below, with system Location switched off.
     *
     * On those versions a BLE scan silently returns nothing while Location is off, whatever
     * permissions are granted — the platform's doing, not this app's, and the one thing that
     * lets the menu explain a scan that found nothing rather than leave it unexplained.
     */
    fun locationSwitchBlocksScan(context: Context): Boolean {
        if (Build.VERSION.SDK_INT > Build.VERSION_CODES.R) return false
        val locationManager =
            context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return true
        return !LocationManagerCompat.isLocationEnabled(locationManager)
    }
}
