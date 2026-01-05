package com.appshub.liclash.modules

import android.util.Log
import com.appshub.liclash.core.Core

/**
 * 暂停源类型（按优先级排序）
 */
enum class SuspendSource(val priority: Int) {
    SMART_SUSPEND(100),  // 智能暂停 (优先级最高)
    DOZE(50)            // Doze休眠 (优先级低)
}

/**
 * 暂停管理器 - 统一管理多个暂停源
 * 优先级规则：高优先级的暂停源会覆盖低优先级的
 */
object SuspendManager {
    private const val TAG = "SuspendManager"
    
    // 记录每个暂停源的状态
    private val suspendStates = mutableMapOf<SuspendSource, Boolean>()
    
    // 当前实际暂停状态
    private var currentSuspended = false
    
    // 回调：用于通知栏更新
    var onSuspendReasonChanged: ((SuspendSource?) -> Unit)? = null
    
    // 智能暂停激活时的提示文本（本地化）
    var smartSuspendActiveText: String = "Smart Suspend Active"
    
    /**
     * 更新某个暂停源的状态
     */
    @Synchronized
    fun updateSuspend(source: SuspendSource, shouldSuspend: Boolean) {
        Log.d(TAG, "updateSuspend: source=$source, shouldSuspend=$shouldSuspend")
        
        // 更新状态记录
        suspendStates[source] = shouldSuspend
        
        // 计算最终暂停状态
        val finalShouldSuspend = calculateFinalSuspendState()
        
        // 如果状态发生变化，则更新内核
        if (finalShouldSuspend != currentSuspended) {
            currentSuspended = finalShouldSuspend
            Core.suspended(finalShouldSuspend)
            
            // 通知暂停原因变化
            onSuspendReasonChanged?.invoke(getSuspendReason())
            
            Log.d(TAG, "Core.suspended($finalShouldSuspend) - reason: ${getSuspendReason()}")
        }
    }
    
    /**
     * 计算最终暂停状态（根据优先级）
     */
    private fun calculateFinalSuspendState(): Boolean {
        // 按优先级从高到低检查
        val sortedSources = SuspendSource.values().sortedByDescending { it.priority }
        
        for (source in sortedSources) {
            val state = suspendStates[source]
            if (state == true) {
                // 找到第一个要求暂停的高优先级源
                return true
            }
        }
        
        // 没有任何源要求暂停
        return false
    }
    
    /**
     * 获取当前暂停原因（优先级最高的那个）
     */
    fun getSuspendReason(): SuspendSource? {
        if (!currentSuspended) return null
        
        // 返回优先级最高的激活源
        return SuspendSource.values()
            .sortedByDescending { it.priority }
            .firstOrNull { suspendStates[it] == true }
    }
    
    /**
     * 清除所有暂停状态
     */
    @Synchronized
    fun clear() {
        suspendStates.clear()
        if (currentSuspended) {
            currentSuspended = false
            Core.suspended(false)
            onSuspendReasonChanged?.invoke(null)
        }
    }
    
    /**
     * 获取当前暂停状态
     */
    fun isSuspended(): Boolean = currentSuspended
}
