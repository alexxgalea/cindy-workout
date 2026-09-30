package com.cindy.tracker

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.os.SystemClock

/**
 * A live connection to one saved heart-rate [device], over the standard Bluetooth LE Heart Rate
 * profile.
 *
 * Every Bluetooth callback — connection state, service discovery, a notification, a scan result —
 * arrives on a binder thread the OS owns, not this app's main thread. Everything this class does
 * in response is therefore posted through [handler] first, so [listener] only ever hears from it
 * on the main thread, and every call back into the GATT client happens from there too: mixing
 * threads on a [BluetoothGatt] is exactly the kind of bug that only shows up as an occasional
 * crash on one phone in the field.
 *
 * [context] is expected to already be an application context — [HeartRateSources.forProfile] is
 * the one caller, and it passes one — so this connection cannot outlive the screen that opened it
 * by accident.
 */
class BleHeartRateSource(
    private val context: Context,
    private var device: HeartRateDevice,
    private val onDeviceMoved: (HeartRateDevice) -> Unit = {},
    private val clock: () -> Long = SystemClock::elapsedRealtime
) : HeartRateSource {

    private val handler = Handler(Looper.getMainLooper())

    private var listener: HeartRateListener? = null
    private var gatt: BluetoothGatt? = null
    private var scanCallback: ScanCallback? = null

    /** Whether [stop] has been called. False from construction until the first [start]. */
    private var wanted = false

    /** Reconnect attempts since the last successful connection; feeds [reconnectDelayMs]. */
    private var attempt = 0

    /** Consecutive failures with no successful connection between them — the address-change
     *  fallback's trigger, since one dropped connection is normal and not a reason to suspect the
     *  watch changed address. */
    private var consecutiveFailures = 0

    /** So [HeartRateStatus.CONNECTED] is reported once, on the first plausible reading, and not
     *  re-announced on every sample after it. */
    private var reportedConnected = false

    private var reconnectRunnable: Runnable? = null

    private fun bluetoothManager(): BluetoothManager? =
        context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager

    override fun start(listener: HeartRateListener) {
        this.listener = listener
        // Already connected, connecting, waiting to retry or chasing a moved address: a second
        // start only changes who hears about it. Connecting again here would open a second client
        // to the same device and orphan the first.
        if (wanted && (gatt != null || scanCallback != null || reconnectRunnable != null)) return
        wanted = true
        attempt = 0
        consecutiveFailures = 0
        connect()
    }

    override fun stop() {
        wanted = false
        reconnectRunnable?.let { handler.removeCallbacks(it) }
        reconnectRunnable = null
        scanCallback?.let { stopScan(it) }
        gatt?.let { closeGatt(it) }
        report(HeartRateStatus.OFF)
        listener = null
    }

    @SuppressLint("MissingPermission") // preflight() has just confirmed HeartRatePermissions.granted().
    private fun connect() {
        if (!wanted) return
        val blocked = preflight()
        if (blocked != null) {
            report(blocked)
            wanted = false
            return
        }
        report(HeartRateStatus.CONNECTING)
        reportedConnected = false
        // One client at a time. Whatever came before is finished with by now, and a client left
        // open is a slot in the phone's small connection pool that nothing will ever give back.
        gatt?.let { closeGatt(it) }
        try {
            val remote = bluetoothManager()?.adapter?.getRemoteDevice(device.address)
            gatt = remote?.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE)
            if (gatt == null) {
                report(HeartRateStatus.UNSUPPORTED)
                wanted = false
            }
        } catch (e: SecurityException) {
            report(HeartRateStatus.NO_PERMISSION)
            wanted = false
        } catch (e: IllegalArgumentException) {
            // A saved address the adapter will not parse. Nothing to retry with; pairing again is
            // the way out, and the menu offers it.
            report(HeartRateStatus.NOT_A_HEART_RATE_DEVICE)
            wanted = false
        }
    }

    /** Null when it is safe to connect; otherwise the status to report, with no retry. */
    private fun preflight(): HeartRateStatus? {
        if (!context.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)) {
            return HeartRateStatus.UNSUPPORTED
        }
        if (!HeartRatePermissions.granted(context)) return HeartRateStatus.NO_PERMISSION
        val adapter = bluetoothManager()?.adapter ?: return HeartRateStatus.UNSUPPORTED
        return try {
            if (adapter.isEnabled) null else HeartRateStatus.BLUETOOTH_OFF
        } catch (e: SecurityException) {
            HeartRateStatus.NO_PERMISSION
        }
    }

    /**
     * One callback object serves every client this source ever opens, and each event is posted
     * before it is acted on — so an event can arrive from a client that has since been closed and
     * replaced, most often across a stop and start on the way through a pause. Acting on one would
     * reconnect a second time or adopt a dead client over the live one. [current] is the guard:
     * only the client [gatt] points at now is listened to.
     */
    private fun current(g: BluetoothGatt): Boolean = wanted && g === gatt

    private val callback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            handler.post {
                if (!current(g)) return@post
                if (status == BluetoothGatt.GATT_SUCCESS && newState == BluetoothProfile.STATE_CONNECTED) {
                    consecutiveFailures = 0
                    attempt = 0
                    discoverServices(g)
                } else {
                    // Any other combination — a clean disconnect, or a connect that failed
                    // outright, status 133 included — has nothing left to salvage from this
                    // client. handleLost is what decides whether that is worth retrying.
                    handleLost(g)
                }
            }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            handler.post {
                if (!current(g)) return@post
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    handleLost(g)
                    return@post
                }
                val characteristic = g.getService(HeartRateGatt.SERVICE)
                    ?.getCharacteristic(HeartRateGatt.MEASUREMENT)
                if (characteristic == null) {
                    report(HeartRateStatus.NOT_A_HEART_RATE_DEVICE)
                    wanted = false
                    closeGatt(g)
                    return@post
                }
                enableNotifications(g, characteristic)
            }
        }

        // The platform calls exactly one of these two overloads per device, depending on the
        // phone's own API level, not this app's target — so both are implemented, and each is a
        // complete path to the same place.
        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            // Copied before posting: the characteristic's value is overwritten by the next
            // notification, which can arrive before this one is handled.
            val value = characteristic.value?.copyOf() ?: return
            handler.post { if (current(g)) deliver(value) }
        }

        override fun onCharacteristicChanged(
            g: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray
        ) {
            handler.post { if (current(g)) deliver(value) }
        }
    }

    @SuppressLint("MissingPermission") // preflight() gated the connect this callback follows from.
    private fun discoverServices(g: BluetoothGatt) {
        try {
            g.discoverServices()
        } catch (e: SecurityException) {
            report(HeartRateStatus.NO_PERMISSION)
            wanted = false
            closeGatt(g)
        }
    }

    @SuppressLint("MissingPermission") // Same gate as discoverServices().
    private fun enableNotifications(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
        try {
            g.setCharacteristicNotification(characteristic, true)
            val descriptor = characteristic.getDescriptor(HeartRateGatt.CLIENT_CONFIG) ?: return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                g.writeDescriptor(descriptor, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
            } else {
                @Suppress("DEPRECATION")
                descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                @Suppress("DEPRECATION")
                g.writeDescriptor(descriptor)
            }
        } catch (e: SecurityException) {
            report(HeartRateStatus.NO_PERMISSION)
            wanted = false
            closeGatt(g)
        }
    }

    private fun deliver(value: ByteArray) {
        val reading = HeartRateMeasurement.parse(value) ?: return
        if (!HeartRateMeasurement.plausible(reading)) return
        if (!reportedConnected) {
            reportedConnected = true
            report(HeartRateStatus.CONNECTED)
        }
        listener?.onHeartRate(reading.bpm, clock())
    }

    /**
     * The client just disconnected or errored. It is closed either way — a leaked
     * [BluetoothGatt] is the one Bluetooth bug that does not announce itself, it just slowly
     * starves the phone's connection pool — and, while still wanted, a reconnect is scheduled.
     *
     * After two of these in a row the schedule is replaced by [scanForMovedDevice]: a watch that
     * keeps refusing to answer at its last known address may simply have a new one, which a plain
     * reconnect loop would never discover.
     */
    private fun handleLost(g: BluetoothGatt) {
        closeGatt(g)
        if (!wanted) return
        consecutiveFailures++
        attempt++
        report(HeartRateStatus.CONNECTING)
        if (consecutiveFailures >= 2) scanForMovedDevice() else scheduleReconnect()
    }

    private fun scheduleReconnect() {
        reconnectRunnable?.let { handler.removeCallbacks(it) }
        val r = Runnable {
            reconnectRunnable = null
            connect()
        }
        reconnectRunnable = r
        handler.postDelayed(r, reconnectDelayMs(attempt))
    }

    @SuppressLint("MissingPermission") // Same gate connect() already passed before this runs.
    private fun scanForMovedDevice() {
        val scanner = bluetoothManager()?.adapter?.bluetoothLeScanner
        if (scanner == null) {
            scheduleReconnect()
            return
        }
        val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(HeartRateGatt.SERVICE)).build()
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        // A local var rather than a plain val: the callback needs to recognise its own identity
        // to ignore a stray result after it has already been superseded, and it cannot name
        // itself any other way from inside its own initialiser.
        var cb: ScanCallback? = null
        cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                handler.post {
                    if (scanCallback !== cb) return@post
                    val name = try {
                        result.scanRecord?.deviceName ?: result.device.name
                    } catch (e: SecurityException) {
                        null
                    }
                    if (name != null && name == device.name) {
                        stopScan(cb!!)
                        device = HeartRateDevice(result.device.address, device.name)
                        onDeviceMoved(device)
                        consecutiveFailures = 0
                        connect()
                    }
                }
            }
        }
        scanCallback = cb
        try {
            scanner.startScan(listOf(filter), settings, cb!!)
        } catch (e: SecurityException) {
            scanCallback = null
            report(HeartRateStatus.NO_PERMISSION)
            wanted = false
            return
        }
        handler.postDelayed(
            {
                if (scanCallback === cb) {
                    stopScan(cb!!)
                    scheduleReconnect()
                }
            },
            RECONNECT_SCAN_WINDOW_MS
        )
    }

    @SuppressLint("MissingPermission") // Only ever called on a scan this same gate already started.
    private fun stopScan(cb: ScanCallback) {
        scanCallback = null
        try {
            bluetoothManager()?.adapter?.bluetoothLeScanner?.stopScan(cb)
        } catch (e: SecurityException) {
            // The scan is already on its way out either way.
        }
    }

    @SuppressLint("MissingPermission") // The client being closed was only ever opened past the gate.
    private fun closeGatt(g: BluetoothGatt) {
        try {
            g.disconnect()
            g.close()
        } catch (e: SecurityException) {
            // Nothing left to guard: the client is being torn down regardless.
        }
        if (gatt === g) gatt = null
    }

    private fun report(status: HeartRateStatus) {
        listener?.onStatus(status)
    }

    companion object {
        /** 1 s, 2 s, 4 s, 8 s, then capped at 10 s. [attempt] is 1 for the first retry. */
        fun reconnectDelayMs(attempt: Int): Long = when {
            attempt <= 1 -> 1_000L
            attempt == 2 -> 2_000L
            attempt == 3 -> 4_000L
            attempt == 4 -> 8_000L
            else -> 10_000L
        }

        private const val RECONNECT_SCAN_WINDOW_MS = 10_000L
    }
}
