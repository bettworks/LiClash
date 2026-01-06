package com.appshub.liclash.modules

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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
        get() = powerManager?.isDeviceIdleMode ?: false

    private fun onUpdate(isScreenOn: Boolean) {
        if (isScreenOn) {
            Log.i(TAG, "Screen ON - Resume from suspend")
            Core.suspended(false)
            return
        }
        val shouldSuspend = isDeviceIdleMode
        if (shouldSuspend) {
            Log.i(TAG, "Device Idle Mode - Suspend enabled")
        }
        Core.suspended(shouldSuspend)
    }

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_ON -> onUpdate(true)
                Intent.ACTION_SCREEN_OFF -> onUpdate(false)
            }
        }
    }

    fun install() {
        if (isInstalled) return
        isInstalled = true
        
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
        }
        context.registerReceiver(screenReceiver, filter)
        
        // Initial state
        onUpdate(isScreenOn())
        Log.i(TAG, "SuspendModule installed")
    }

    fun uninstall() {
        if (!isInstalled) return
        isInstalled = false
        
        try {
            context.unregisterReceiver(screenReceiver)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to unregister receiver: ${e.message}")
        }
        Log.i(TAG, "SuspendModule uninstalled")
    }
}
