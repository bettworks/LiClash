package com.appshub.liclash.modules

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.content.getSystemService
import com.appshub.liclash.core.Core

class SuspendModule(private val context: Context) {
    companion object {
        private const val TAG = "SuspendModule"
    }

    private var isInstalled = false

    private val powerManager: PowerManager? by lazy {
        context.getSystemService<PowerManager>()
    }

    private fun isScreenOn(): Boolean {
        return powerManager?.isInteractive ?: true
    }

    private val isDeviceIdleMode: Boolean
        get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            powerManager?.isDeviceIdleMode ?: false
        } else {
            false
        }

    private fun updateSuspendState() {
        val screenOn = isScreenOn()
        val deviceIdle = isDeviceIdleMode
        
        Log.d(TAG, "updateSuspendState - screenOn: $screenOn, deviceIdle: $deviceIdle")
        
        if (screenOn) {
            Log.i(TAG, "Screen ON - Resume from suspend")
            Core.suspended(false)
            return
        }
        
        if (deviceIdle) {
            Log.i(TAG, "Device Idle Mode - Suspend enabled")
            Core.suspended(true)
        } else {
            Log.d(TAG, "Screen OFF but not in Device Idle - No suspend")
            Core.suspended(false)
        }
    }

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_ON -> {
                    Log.d(TAG, "Received ACTION_SCREEN_ON")
                    updateSuspendState()
                }
                Intent.ACTION_SCREEN_OFF -> {
                    Log.d(TAG, "Received ACTION_SCREEN_OFF")
                    updateSuspendState()
                }
                PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED -> {
                    Log.d(TAG, "Received ACTION_DEVICE_IDLE_MODE_CHANGED")
                    updateSuspendState()
                }
            }
        }
    }

    fun install() {
        if (isInstalled) return
        isInstalled = true
        
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
            }
        }
        context.registerReceiver(receiver, filter)
        
        // Initial state
        updateSuspendState()
        Log.i(TAG, "SuspendModule installed - SDK: ${Build.VERSION.SDK_INT}")
    }

    fun uninstall() {
        if (!isInstalled) return
        isInstalled = false
        
        try {
            context.unregisterReceiver(receiver)
            // Resume on uninstall
            Core.suspended(false)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to unregister receiver: ${e.message}")
        }
        Log.i(TAG, "SuspendModule uninstalled")
    }
}
