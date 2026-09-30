package com.cindy.tracker

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Handler
import android.os.Looper
import java.util.UUID

/**
 * One device the search turned up: its address, its best guess at a name, and how strong it came
 * in.
 *
 * [rssi] is null for a device that was only found through its existing connection to this phone
 * (see [HeartRateScanner]) and never heard advertising, so there is no signal figure to show.
 * [connected] is true whenever the phone already holds a link to it — a Garmin paired through
 * Garmin Connect, typically.
 */
data class FoundDevice(
    val address: String,
    val name: String,
    val rssi: Int?,
    val connected: Boolean = false
)

/**
 * Which advertisements are worth showing, kept free of Android types so it can be tested as it is.
 *
 * The Heart Rate service UUID is the real signal. The Garmin manufacturer ID is the fallback for
 * a watch that advertises its broadcast without listing the service up front: connecting to it is
 * what settles the question, and [BleHeartRateSource] already reports a device that turns out not
 * to send heart rate.
 */
object HeartRateAdvert {

    /** Bluetooth SIG company identifier for Garmin International. */
    const val GARMIN_COMPANY_ID = 0x0087

    fun matches(serviceUuids: Collection<UUID>?, manufacturerIds: Collection<Int>): Boolean =
        serviceUuids?.contains(HeartRateGatt.SERVICE) == true || GARMIN_COMPANY_ID in manufacturerIds

    /**
     * The list the sheet shows: devices already connected to the phone first — that is almost
     * always the athlete's own watch — then everything heard advertising, strongest first. A
     * connected device that was also heard advertising is listed once, keeping its signal.
     */
    fun merge(connected: List<FoundDevice>, advertising: Collection<FoundDevice>): List<FoundDevice> {
        val heard = advertising.associateBy { it.address }
        val linked = connected.map { c ->
            heard[c.address]?.let { c.copy(rssi = it.rssi) } ?: c
        }
        val linkedAddresses = linked.map { it.address }.toSet()
        return linked + advertising
            .filter { it.address !in linkedAddresses }
            .sortedByDescending { it.rssi ?: Int.MIN_VALUE }
    }
}

/**
 * A time-boxed search for nearby heart-rate broadcasters, for the menu's "FIND MY WATCH" flow.
 *
 * Kept apart from [BleHeartRateSource], which does its own short scan to chase a watch that
 * changed address — that one runs unattended in the background, while this one exists to be
 * watched: the menu shows every device as it turns up, sorted by signal, so the athlete can tell
 * their own watch from a stranger's chest strap in the next room.
 *
 * Two things make a Garmin easy to miss with a plain filtered scan, and this search covers both:
 *
 * - A watch already paired to this phone through Garmin Connect holds a live connection to it,
 *   and a peripheral with a live connection to a phone does not necessarily advertise to that
 *   same phone. It can still serve heart rate over the link it already has, so every device
 *   already connected over Bluetooth LE is listed up front, found or not by the scan.
 * - Where the Heart Rate service UUID sits in an advertisement — the main packet or the scan
 *   response — decides whether a hardware-offloaded scan filter sees it on some phones. The scan
 *   here is therefore unfiltered, and [HeartRateAdvert.matches] does the filtering on the full,
 *   merged record instead. That is only safe because this scan runs with the screen on and the
 *   sheet open, where Android delivers unfiltered results.
 */
class HeartRateScanner(private val context: Context) {

    private val handler = Handler(Looper.getMainLooper())
    private var callback: ScanCallback? = null
    private val seen = linkedMapOf<String, FoundDevice>()
    private var connected = listOf<FoundDevice>()

    /**
     * Scans for [SCAN_WINDOW_MS], calling [onFound] with the growing list of matches as they come
     * in, and [onDone] once the window closes on its own. Replaces a scan already running rather
     * than layering onto it.
     */
    @SuppressLint("MissingPermission") // The menu only calls this once HeartRatePermissions.granted().
    fun start(onFound: (List<FoundDevice>) -> Unit, onDone: () -> Unit) {
        stop()
        connected = connectedDevices()
        if (connected.isNotEmpty()) onFound(HeartRateAdvert.merge(connected, emptyList()))
        val scanner = adapter()?.bluetoothLeScanner ?: return onDone()
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                if (!result.advertisesHeartRate()) return
                val found = result.toFoundDevice()
                handler.post {
                    if (callback !== this) return@post
                    seen[found.address] = found
                    onFound(HeartRateAdvert.merge(connected, seen.values))
                }
            }
        }
        callback = cb
        try {
            scanner.startScan(null, settings, cb)
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
        connected = emptyList()
        handler.removeCallbacksAndMessages(null)
        try {
            adapter()?.bluetoothLeScanner?.stopScan(cb)
        } catch (e: SecurityException) {
            // The scan is already on its way out either way.
        }
    }

    private fun manager() = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager

    private fun adapter() = manager()?.adapter

    /**
     * Every device the phone already has a Bluetooth LE link to, from any app. Whether one of
     * them actually serves heart rate is only known once connected, which is
     * [BleHeartRateSource]'s job and which it reports on.
     */
    @SuppressLint("MissingPermission")
    private fun connectedDevices(): List<FoundDevice> =
        try {
            manager()?.getConnectedDevices(BluetoothProfile.GATT).orEmpty()
                .filter { it.type != BluetoothDevice.DEVICE_TYPE_CLASSIC }
                .map { FoundDevice(it.address, it.name ?: "Connected device", rssi = null, connected = true) }
        } catch (e: SecurityException) {
            emptyList()
        }

    private fun ScanResult.advertisesHeartRate(): Boolean {
        val record = scanRecord ?: return false
        val makers = record.manufacturerSpecificData
        val makerIds = (0 until (makers?.size() ?: 0)).map { makers!!.keyAt(it) }
        return HeartRateAdvert.matches(record.serviceUuids?.map { it.uuid }, makerIds)
    }

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
