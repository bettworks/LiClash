package com.appshub.liclash.modules

import android.app.Service
import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.getSystemService
import java.net.Inet4Address
import java.net.InetAddress

/**
 * 智能暂停模块
 * 功能：检测设备IP地址，当匹配用户设置的内网IP规则时，自动暂停内核
 */
class SmartSuspendModule(private val service: Service) {
    companion object {
        private const val TAG = "SmartSuspendModule"
        private const val DEBOUNCE_DELAY_MS = 500L  // 防抖延迟500ms
    }
    
    private var enabled = false
    private var ipRules = listOf<String>()  // IP规则列表
    
    private val connectivityManager by lazy {
        service.getSystemService<ConnectivityManager>()
    }
    
    private val handler = Handler(Looper.getMainLooper())
    private var debounceRunnable: Runnable? = null
    
    // 网络回调
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            Log.d(TAG, "onAvailable: $network")
            scheduleCheck()
        }
        
        override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
            Log.d(TAG, "onLinkPropertiesChanged: $network")
            scheduleCheck()
        }
        
        override fun onLost(network: Network) {
            Log.d(TAG, "onLost: $network")
            scheduleCheck()
        }
        
        override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
            // 网络能力变化时也检查
            scheduleCheck()
        }
    }
    
    /**
     * 安装模块
     */
    fun install() {
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        
        connectivityManager?.registerNetworkCallback(request, networkCallback)
        Log.d(TAG, "SmartSuspendModule installed")
    }
    
    /**
     * 卸载模块
     */
    fun uninstall() {
        try {
            connectivityManager?.unregisterNetworkCallback(networkCallback)
            handler.removeCallbacks(debounceRunnable ?: return)
            debounceRunnable = null
        } catch (e: Exception) {
            Log.e(TAG, "Error uninstalling: ${e.message}")
        }
        
        // 清除暂停状态
        SuspendManager.updateSuspend(SuspendSource.SMART_SUSPEND, false)
        Log.d(TAG, "SmartSuspendModule uninstalled")
    }
    
    /**
     * 更新配置
     * @param enabled 是否启用智能暂停
     * @param ips IP规则字符串，用逗号分隔，例如 "192.168.1.0/24,10.0.0.1"
     */
    fun updateConfig(enabled: Boolean, ips: String) {
        Log.d(TAG, "updateConfig: enabled=$enabled, ips=$ips")
        
        this.enabled = enabled
        this.ipRules = parseIpRules(ips)
        
        // 立即检查一次
        scheduleCheck()
    }
    
    /**
     * 解析IP规则字符串
     */
    private fun parseIpRules(ips: String): List<String> {
        if (ips.isBlank()) return emptyList()
        
        return ips.split(",")
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .take(2)  // 最多2个规则
    }
    
    /**
     * 调度检查（带防抖）
     */
    private fun scheduleCheck() {
        // 取消之前的检查任务
        debounceRunnable?.let { handler.removeCallbacks(it) }
        
        // 创建新的检查任务
        debounceRunnable = Runnable {
            checkAndNotify()
        }
        
        // 延迟500ms执行
        handler.postDelayed(debounceRunnable!!, DEBOUNCE_DELAY_MS)
    }
    
    /**
     * 检查并通知暂停管理器
     */
    private fun checkAndNotify() {
        if (!enabled) {
            // 功能未启用，确保不暂停
            SuspendManager.updateSuspend(SuspendSource.SMART_SUSPEND, false)
            return
        }
        
        if (ipRules.isEmpty()) {
            // 没有配置规则，不暂停
            SuspendManager.updateSuspend(SuspendSource.SMART_SUSPEND, false)
            return
        }
        
        // 获取当前设备IP地址
        val currentIps = getCurrentIpAddresses()
        Log.d(TAG, "Current IPs: $currentIps")
        
        // 检查是否匹配任一规则
        val matched = matchesAnyRule(currentIps)
        Log.d(TAG, "Matched: $matched")
        
        // 更新暂停状态
        SuspendManager.updateSuspend(SuspendSource.SMART_SUSPEND, matched)
    }
    
    /**
     * 获取当前设备的所有IPv4地址
     */
    private fun getCurrentIpAddresses(): List<String> {
        val ips = mutableListOf<String>()
        
        try {
            val networks = connectivityManager?.allNetworks ?: return emptyList()
            
            for (network in networks) {
                val linkProperties = connectivityManager?.getLinkProperties(network) ?: continue
                
                for (linkAddress in linkProperties.linkAddresses) {
                    val address = linkAddress.address
                    
                    // 只处理IPv4地址，排除回环地址
                    if (address is Inet4Address && !address.isLoopbackAddress) {
                        ips.add(address.hostAddress ?: "")
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting IP addresses: ${e.message}")
        }
        
        return ips.filter { it.isNotEmpty() }
    }
    
    /**
     * 检查当前IP是否匹配任一规则
     */
    private fun matchesAnyRule(currentIps: List<String>): Boolean {
        if (currentIps.isEmpty() || ipRules.isEmpty()) {
            return false
        }
        
        for (currentIp in currentIps) {
            for (rule in ipRules) {
                if (isIpInRange(currentIp, rule)) {
                    Log.d(TAG, "IP $currentIp matches rule $rule")
                    return true
                }
            }
        }
        
        return false
    }
    
    /**
     * 判断IP是否在规则范围内
     * @param ip 当前IP地址
     * @param rule 规则（支持单IP或CIDR格式）
     */
    private fun isIpInRange(ip: String, rule: String): Boolean {
        return try {
            if (rule.contains("/")) {
                // CIDR格式: 192.168.1.0/24
                matchCIDR(ip, rule)
            } else {
                // 单IP: 192.168.1.100
                ip == rule
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error matching IP $ip with rule $rule: ${e.message}")
            false
        }
    }
    
    /**
     * CIDR匹配
     */
    private fun matchCIDR(ip: String, cidr: String): Boolean {
        try {
            val parts = cidr.split("/")
            if (parts.size != 2) return false
            
            val networkAddr = parts[0]
            val prefixLength = parts[1].toIntOrNull() ?: return false
            
            if (prefixLength < 0 || prefixLength > 32) return false
            
            // 将IP地址转换为整数
            val ipInt = ipToInt(ip)
            val networkInt = ipToInt(networkAddr)
            
            // 创建子网掩码
            val mask = if (prefixLength == 0) {
                0
            } else {
                (-1 shl (32 - prefixLength))
            }
            
            // 比较网络地址部分
            return (ipInt and mask) == (networkInt and mask)
        } catch (e: Exception) {
            Log.e(TAG, "Error in CIDR matching: ${e.message}")
            return false
        }
    }
    
    /**
     * 将IP地址字符串转换为整数
     */
    private fun ipToInt(ip: String): Int {
        val addr = InetAddress.getByName(ip) as? Inet4Address ?: return 0
        val bytes = addr.address
        return ((bytes[0].toInt() and 0xFF) shl 24) or
               ((bytes[1].toInt() and 0xFF) shl 16) or
               ((bytes[2].toInt() and 0xFF) shl 8) or
               (bytes[3].toInt() and 0xFF)
    }
}
