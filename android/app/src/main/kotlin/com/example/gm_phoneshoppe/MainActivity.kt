package com.example.gm_phoneshoppe

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.io.OutputStream
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.gm_phoneshoppe/bluetooth_printer"
    private val TAG = "BluetoothPrinter"

    // Standard SPP UUID for serial port profile
    private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bluetoothSocket: BluetoothSocket? = null
    private var outputStream: OutputStream? = null
    private var connectedAddress: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "connect" -> {
                    val address = call.argument<String>("address")
                    if (address != null) {
                        connectToDevice(address, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "Address is required", null)
                    }
                }
                "disconnect" -> {
                    disconnect()
                    result.success(true)
                }
                "isConnected" -> {
                    result.success(isConnected())
                }
                "writeBytes" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes != null) {
                        writeBytes(bytes, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "Bytes are required", null)
                    }
                }
                "openCashDrawer" -> {
                    val pin = call.argument<Int>("pin") ?: 0
                    openCashDrawer(pin, result)
                }
                "getPairedDevices" -> {
                    getPairedDevices(result)
                }
                "isBluetoothAvailable" -> {
                    result.success(bluetoothAdapter != null)
                }
                "isBluetoothEnabled" -> {
                    result.success(bluetoothAdapter?.isEnabled == true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun connectToDevice(address: String, result: MethodChannel.Result) {
        Thread {
            try {
                // Disconnect existing connection first
                disconnect()

                val device: BluetoothDevice? = bluetoothAdapter?.getRemoteDevice(address)
                if (device == null) {
                    Handler(Looper.getMainLooper()).post {
                        result.error("DEVICE_NOT_FOUND", "Device not found: $address", null)
                    }
                    return@Thread
                }

                Log.d(TAG, "Connecting to ${device.name} ($address)...")

                // Create socket using SPP UUID
                bluetoothSocket = device.createRfcommSocketToServiceRecord(SPP_UUID)

                // Cancel discovery to speed up connection
                bluetoothAdapter?.cancelDiscovery()

                // Connect with timeout handling
                bluetoothSocket?.connect()

                // Get output stream
                outputStream = bluetoothSocket?.outputStream
                connectedAddress = address

                Log.d(TAG, "Connected successfully to ${device.name}")

                // Wait for connection to stabilize (important for some printers)
                Thread.sleep(500)

                Handler(Looper.getMainLooper()).post {
                    result.success(true)
                }
            } catch (e: IOException) {
                Log.e(TAG, "Connection failed: ${e.message}")
                disconnect()
                Handler(Looper.getMainLooper()).post {
                    result.error("CONNECTION_FAILED", e.message, null)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Unexpected error: ${e.message}")
                disconnect()
                Handler(Looper.getMainLooper()).post {
                    result.error("ERROR", e.message, null)
                }
            }
        }.start()
    }

    private fun disconnect() {
        try {
            outputStream?.close()
            bluetoothSocket?.close()
        } catch (e: IOException) {
            Log.e(TAG, "Error closing connection: ${e.message}")
        } finally {
            outputStream = null
            bluetoothSocket = null
            connectedAddress = null
        }
    }

    private fun isConnected(): Boolean {
        // Check if socket is still actually connected
        // bluetoothSocket?.isConnected can return true even if remote closed
        try {
            if (bluetoothSocket == null || outputStream == null) return false
            if (bluetoothSocket?.isConnected != true) return false
            return true
        } catch (e: Exception) {
            return false
        }
    }

    private fun ensureConnected(): Boolean {
        if (isConnected()) return true

        // Try to reconnect if we have a saved address
        val addressToReconnect = connectedAddress
        if (addressToReconnect != null) {
            Log.d(TAG, "Connection lost, attempting reconnect to $addressToReconnect")
            try {
                // Close socket without clearing address
                try {
                    outputStream?.close()
                    bluetoothSocket?.close()
                } catch (e: IOException) {
                    Log.e(TAG, "Error closing old socket: ${e.message}")
                }
                outputStream = null
                bluetoothSocket = null

                // Reconnect
                val device = bluetoothAdapter?.getRemoteDevice(addressToReconnect)
                if (device != null) {
                    bluetoothSocket = device.createRfcommSocketToServiceRecord(SPP_UUID)
                    bluetoothAdapter?.cancelDiscovery()
                    bluetoothSocket?.connect()
                    outputStream = bluetoothSocket?.outputStream
                    connectedAddress = addressToReconnect // Ensure address is preserved
                    Thread.sleep(500) // Longer stabilization for reliable connection
                    Log.d(TAG, "Reconnected successfully to $addressToReconnect")
                    return true
                }
            } catch (e: Exception) {
                Log.e(TAG, "Reconnect failed: ${e.message}")
                // Don't clear connectedAddress - allow future retry
            }
        }
        return false
    }

    private fun writeBytes(bytes: ByteArray, result: MethodChannel.Result) {
        Thread {
            try {
                // Auto-reconnect if connection was lost
                if (!ensureConnected()) {
                    Handler(Looper.getMainLooper()).post {
                        result.error("NOT_CONNECTED", "Printer not connected and reconnect failed", null)
                    }
                    return@Thread
                }

                Log.d(TAG, "Writing ${bytes.size} bytes...")

                // Verify outputStream is valid before writing
                val stream = outputStream
                if (stream == null) {
                    Log.e(TAG, "Output stream is null")
                    Handler(Looper.getMainLooper()).post {
                        result.error("NOT_CONNECTED", "Printer output stream not available", null)
                    }
                    return@Thread
                }

                // Write bytes directly to the output stream
                stream.write(bytes)
                stream.flush()

                Log.d(TAG, "Write successful")

                Handler(Looper.getMainLooper()).post {
                    result.success(true)
                }
            } catch (e: IOException) {
                Log.e(TAG, "Write failed: ${e.message}")
                Handler(Looper.getMainLooper()).post {
                    result.error("WRITE_FAILED", e.message, null)
                }
            }
        }.start()
    }

    private fun openCashDrawer(pin: Int, result: MethodChannel.Result) {
        Thread {
            try {
                // Try to reuse existing connection first (don't overwhelm printer's Bluetooth)
                // Only reconnect if socket is truly dead
                var needsReconnect = false

                if (bluetoothSocket == null || outputStream == null) {
                    needsReconnect = true
                    Log.d(TAG, "Socket is null, need to connect")
                } else {
                    // Test if socket is still alive by checking isConnected
                    try {
                        if (bluetoothSocket?.isConnected != true) {
                            needsReconnect = true
                            Log.d(TAG, "Socket reports not connected")
                        }
                    } catch (e: Exception) {
                        needsReconnect = true
                        Log.d(TAG, "Socket check failed: ${e.message}")
                    }
                }

                if (needsReconnect) {
                    val addressToUse = connectedAddress
                    if (addressToUse == null) {
                        Handler(Looper.getMainLooper()).post {
                            result.error("NOT_CONNECTED", "No printer address saved. Click Native Connect first.", null)
                        }
                        return@Thread
                    }

                    Log.d(TAG, "Reconnecting to $addressToUse...")

                    // Close old socket gently
                    try {
                        outputStream?.close()
                        bluetoothSocket?.close()
                    } catch (e: Exception) { }
                    outputStream = null
                    bluetoothSocket = null

                    // Wait for printer to be ready
                    Thread.sleep(500)

                    // Connect
                    val device = bluetoothAdapter?.getRemoteDevice(addressToUse)
                    if (device == null) {
                        Handler(Looper.getMainLooper()).post {
                            result.error("DEVICE_NOT_FOUND", "Device not found", null)
                        }
                        return@Thread
                    }

                    bluetoothSocket = device.createRfcommSocketToServiceRecord(SPP_UUID)
                    bluetoothAdapter?.cancelDiscovery()
                    bluetoothSocket?.connect()
                    outputStream = bluetoothSocket?.outputStream
                    connectedAddress = addressToUse

                    // Wait for connection to stabilize
                    Thread.sleep(500)
                    Log.d(TAG, "Reconnected successfully")
                } else {
                    Log.d(TAG, "Reusing existing connection")
                }

                // SIMPLE: Just send ONE cash drawer command like Loyverse does
                // ESC p m t1 t2 - standard ESC/POS cash drawer kick
                val command = byteArrayOf(
                    0x1B, 0x70,       // ESC p - Cash drawer kick
                    0x00,             // m = 0 (pin 2)
                    0x19,             // t1 = 25 × 2ms = 50ms ON
                    0x78              // t2 = 120 × 2ms = 240ms OFF
                )

                Log.d(TAG, "Sending simple ESC p command: ${command.joinToString(" ") { String.format("0x%02X", it) }}")

                // Verify outputStream is valid before writing
                val stream = outputStream
                if (stream == null) {
                    Log.e(TAG, "Output stream is null after connection attempt")
                    Handler(Looper.getMainLooper()).post {
                        result.error("NOT_CONNECTED", "Printer output stream not available", null)
                    }
                    return@Thread
                }

                // Single write, single flush
                stream.write(command)
                stream.flush()

                Log.d(TAG, "Cash drawer command sent")

                Handler(Looper.getMainLooper()).post {
                    result.success(true)
                }
            } catch (e: IOException) {
                Log.e(TAG, "Cash drawer command failed: ${e.message}")
                Handler(Looper.getMainLooper()).post {
                    result.error("COMMAND_FAILED", e.message, null)
                }
            }
        }.start()
    }

    private fun getPairedDevices(result: MethodChannel.Result) {
        try {
            val pairedDevices = bluetoothAdapter?.bondedDevices
            val deviceList = mutableListOf<Map<String, String>>()

            pairedDevices?.forEach { device ->
                deviceList.add(mapOf(
                    "name" to (device.name ?: "Unknown"),
                    "address" to device.address
                ))
            }

            result.success(deviceList)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    override fun onDestroy() {
        disconnect()
        super.onDestroy()
    }
}
