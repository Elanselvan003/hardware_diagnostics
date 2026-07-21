package com.example.hardware_diagnostics

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.hardware_diagnostics/info"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getRAMInfo" -> {
                    val ramInfo = getRAMInfo()
                    result.success(ramInfo)
                }
                "getStorageInfo" -> {
                    val storageInfo = getStorageInfo()
                    result.success(storageInfo)
                }
                "getCPUInfo" -> {
                    val cpuInfo = getCPUInfo()
                    result.success(cpuInfo)
                }
                "getBatteryInfo" -> {
                    val batteryInfo = getBatteryInfo()
                    result.success(batteryInfo)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getRAMInfo(): Map<String, Long> {
        val actManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        actManager.getMemoryInfo(memInfo)
        return mapOf(
            "total" to memInfo.totalMem,
            "avail" to memInfo.availMem,
            "lowMemory" to if (memInfo.lowMemory) 1L else 0L
        )
    }

    private fun getStorageInfo(): Map<String, Long> {
        val path = Environment.getDataDirectory()
        val stat = StatFs(path.path)
        val blockSize = stat.blockSizeLong
        val totalBlocks = stat.blockCountLong
        val availableBlocks = stat.availableBlocksLong
        return mapOf(
            "total" to totalBlocks * blockSize,
            "avail" to availableBlocks * blockSize
        )
    }

    private fun getCPUInfo(): Map<String, Any> {
        val cores = Runtime.getRuntime().availableProcessors()
        val abis = Build.SUPPORTED_ABIS.toList()
        var cpuModel = "Unknown"
        try {
            val file = File("/proc/cpuinfo")
            if (file.exists()) {
                file.forEachLine { line ->
                    if (line.contains("Hardware") || line.contains("model name") || line.contains("Processor")) {
                        val parts = line.split(":")
                        if (parts.size > 1) {
                            cpuModel = parts[1].trim()
                        }
                    }
                }
            }
        } catch (e: Exception) {
            // Ignore
        }
        return mapOf(
            "cores" to cores,
            "abis" to abis,
            "model" to cpuModel,
            "hardware" to Build.HARDWARE,
            "board" to Build.BOARD
        )
    }

    private fun getBatteryInfo(): Map<String, Any> {
        val intentFilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        val batteryStatus: Intent? = registerReceiver(null, intentFilter)
        
        val level = batteryStatus?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = batteryStatus?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val batteryPct = if (level >= 0 && scale > 0) (level / scale.toFloat() * 100).toInt() else -1
        
        val status = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
        
        val temp = batteryStatus?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0
        val tempCelsius = temp / 10.0
        
        val health = batteryStatus?.getIntExtra(BatteryManager.EXTRA_HEALTH, BatteryManager.BATTERY_HEALTH_UNKNOWN) ?: BatteryManager.BATTERY_HEALTH_UNKNOWN
        val healthStr = when (health) {
            BatteryManager.BATTERY_HEALTH_GOOD -> "Good"
            BatteryManager.BATTERY_HEALTH_OVERHEAT -> "Overheat"
            BatteryManager.BATTERY_HEALTH_DEAD -> "Dead"
            BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "Over Voltage"
            BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE -> "Unspecified Failure"
            else -> "Unknown"
        }

        return mapOf(
            "level" to batteryPct,
            "isCharging" to isCharging,
            "temperature" to tempCelsius,
            "health" to healthStr
        )
    }
}
