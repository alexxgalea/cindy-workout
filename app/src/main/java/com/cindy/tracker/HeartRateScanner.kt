package com.cindy.tracker

import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid

/** One device a scan saw: its address, its best guess at a name, and how strong it came in. */
data class FoundDevice(val address: String, val name: String, val rssi: Int)

/**
 * A time-boxed search for nearby heart-rate broadcasters, for the menu's "FIND MY WATCH" flow.
 *
 * Kept apart from [BleHeartRateSource], which does its own short scan to chase a watch that
 * changed address — that one runs unattended in the background, while this one exists to be
 * watched: the menu shows every device as it turns up, sorted by signal, so the athlete can tell
 * their own watch from a stranger's chest strap in the next room.
 */
class HeartRateScanner(private val context: Context) {

    private val handler = Handler(Looper.getMainLooper())
    private var callback: ScanCallback? = null
    private val seen = linkedMapOf<String, FoundDevice>()

    /**
     * Scans for [SCAN_WINDOW_MS], calling [onFound] with the growing, strongest-first list of
     * matches as they come in, and [onDone] once the window closes on its own. Replaces a scan
     * already running rather than layering onto it.
     */
    @SuppressLint("MissingPermission") // The menu only calls this once HeartRatePermissions.granted().
    fun start(onFound: (List<FoundDevice>) -> Unit, onDone: () -> Unit) {
        stop()
        val scanner = adapter()?.bluetoothLeScanner ?: return onDone()
        val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(HeartRateGatt.SERVICE)).build()
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                handler.post {
                    seen[result.device.address] = result.toFoundDevice()
                    onFound(seen.values.sortedByDescending { it.rssi })
                }
            }
        }
        callback = cb
        try {
            scanner.startScan(listOf(filter), settings, cb)
        } catch (e: SecurityException) {
            callback = null
            return onDone()
        }
        handler.postDelayed(
            {
                // Only if this is still the scan that was started above — stop() may already
                // have replaced or ended it by the time this runs.
                if (callback === cb) {
                    stop()
                    onDone()
                }
            },
            SCAN_WINDOW_MS
        )
    }

    /**
     * Ends the scan, if one is running, without calling `onDone` — the two callers that stop a
     * scan early, a dismissed sheet and a device already picked, already know why it ended and do
     * not need to be told again.
     */
    @SuppressLint("MissingPermission")
    fun stop() {
        val cb = callback ?: return
        callback = null
        seen.clear()
        handler.removeCallbacksAndMessages(null)
        try {
            adapter()?.bluetoothLeScanner?.stopScan(cb)
        } catch (e: SecurityException) {
            // The scan is already on its way out either way.
        }
    }

    private fun adapter() =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    /** Name resolution falls back twice: the advertised name, then the bonded name, then this. */
    @SuppressLint("MissingPermission")
    private fun ScanResult.toFoundDevice(): FoundDevice {
        val name = scanRecord?.deviceName
            ?: try {
                device.name
            } catch (e: SecurityException) {
                null
            }
            ?: "Heart-rate sensor"
        return FoundDevice(device.address, name, rssi)
    }

    private companion object {
        const val SCAN_WINDOW_MS = 12_000L
    }
}
