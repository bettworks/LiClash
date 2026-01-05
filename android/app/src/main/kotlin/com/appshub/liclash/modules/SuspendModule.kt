package com.appshub.liclash.modules

import android.app.Service
import android.content.Intent
import android.os.PowerManager
import androidx.core.content.getSystemService
import com.appshub.liclash.GlobalState
import com.appshub.liclash.core.Core
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

class SuspendModule(private val service: Service) {
    private val scope = CoroutineScope(Dispatchers.Default)
    private val screenStateFlow = MutableStateFlow(true)
    private val suspendEnabledFlow = MutableStateFlow(false)
    private var receiver: android.content.BroadcastReceiver? = null

    private fun isScreenOn(): Boolean {
        val pm = service.getSystemService<PowerManager>()
        return when (pm != null) {
            true -> pm.isInteractive
            false -> true
        }
    }

    private val isDeviceIdleMode: Boolean
        get() {
            return service.getSystemService<PowerManager>()?.isDeviceIdleMode ?: false
        }

    private fun onUpdate(isScreenOn: Boolean, isSuspendEnabled: Boolean) {
        if (!isSuspendEnabled) {
            // 如果功能未启用,通知暂停管理器
            SuspendManager.updateSuspend(SuspendSource.DOZE, false)
            return
        }

        // 计算是否需要暂停
        val shouldSuspend = !isScreenOn && isDeviceIdleMode
        
        // 通知暂停管理器（由管理器根据优先级决定最终状态）
        SuspendManager.updateSuspend(SuspendSource.DOZE, shouldSuspend)
    }

    fun install() {
        // 创建并注册BroadcastReceiver
        receiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(context: android.content.Context?, intent: Intent?) {
                val isScreenOn = intent?.action == Intent.ACTION_SCREEN_ON
                screenStateFlow.value = isScreenOn
            }
        }
        
        val intentFilter = android.content.IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
        }
        
        service.registerReceiver(receiver, intentFilter)
        
        // 初始化屏幕状态
        screenStateFlow.value = isScreenOn()

        // 监听状态变化
        scope.launch {
            combine(screenStateFlow, suspendEnabledFlow) { screenOn, enabled ->
                Pair(screenOn, enabled)
            }.collect { (screenOn, enabled) ->
                onUpdate(screenOn, enabled)
            }
        }
    }

    fun updateSuspendEnabled(enabled: Boolean) {
        suspendEnabledFlow.value = enabled
    }

    fun uninstall() {
        try {
            receiver?.let { service.unregisterReceiver(it) }
            receiver = null
        } catch (_: Exception) {
        }
        scope.cancel()
    }
}
