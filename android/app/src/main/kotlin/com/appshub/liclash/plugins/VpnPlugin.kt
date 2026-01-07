package com.appshub.liclash.plugins

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.IBinder
import androidx.core.content.getSystemService
import com.appshub.liclash.LiClashApplication
import com.appshub.liclash.GlobalState
import com.appshub.liclash.RunState
import com.appshub.liclash.core.Core
import com.appshub.liclash.extensions.awaitResult
import com.appshub.liclash.extensions.resolveDns
import com.appshub.liclash.models.StartForegroundParams
import com.appshub.liclash.models.VpnOptions
import com.appshub.liclash.modules.SuspendModule
import com.appshub.liclash.services.BaseServiceInterface
import com.appshub.liclash.services.LiClashService
import com.appshub.liclash.services.LiClashVpnService
import com.google.gson.Gson
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.InetSocketAddress
import kotlin.concurrent.withLock

data object VpnPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var flutterMethodChannel: MethodChannel
    private var liClashService: BaseServiceInterface? = null
    private var options: VpnOptions? = null
    private var isBind: Boolean = false
    private lateinit var scope: CoroutineScope
    private var lastStartForegroundParams: StartForegroundParams? = null
    private var timerJob: Job? = null
    private val uidPageNameMap = mutableMapOf<Int, String>()
    private var suspendModule: SuspendModule? = null

    private val connectivity by lazy {
        LiClashApplication.getAppContext().getSystemService<ConnectivityManager>()
    }

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(className: ComponentName, service: IBinder) {
            isBind = true
            liClashService = when (service) {
                is LiClashVpnService.LocalBinder -> service.getService()
                is LiClashService.LocalBinder -> service.getService()
                else -> throw Exception("invalid binder")
            }
            handleStartService()
        }

        override fun onServiceDisconnected(arg: ComponentName) {
            isBind = false
            liClashService = null
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        scope = CoroutineScope(Dispatchers.Default)
        scope.launch {
            registerNetworkCallback()
        }
        flutterMethodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "vpn")
        flutterMethodChannel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        unRegisterNetworkCallback()
        flutterMethodChannel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val data = call.argument<String>("data")
                result.success(handleStart(Gson().fromJson(data, VpnOptions::class.java)))
            }

            "stop" -> {
                handleStop()
                result.success(true)
            }

            "getLocalIpAddresses" -> {
                result.success(getLocalIpAddresses())
            }

            "setSmartStopped" -> {
                val value = call.argument<Boolean>("value") ?: false
                GlobalState.isSmartStopped = value
                result.success(true)
            }

            "isSmartStopped" -> {
                result.success(GlobalState.isSmartStopped)
            }

            "smartStop" -> {
                handleSmartStop()
                result.success(true)
            }

            "smartResume" -> {
                val data = call.argument<String>("data")
                result.success(handleSmartResume(Gson().fromJson(data, VpnOptions::class.java)))
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    /**
     * Get local IP addresses from all non-VPN networks.
     * This is more reliable than connectivity_plus when VPN is running.
     */
    fun getLocalIpAddresses(): List<String> {
        val ipAddresses = mutableListOf<String>()
        try {
            for (network in networks) {
                val linkProperties = connectivity?.getLinkProperties(network) ?: continue
                for (linkAddress in linkProperties.linkAddresses) {
                    val address = linkAddress.address
                    if (address != null && !address.isLoopbackAddress) {
                        val hostAddress = address.hostAddress
                        if (hostAddress != null && !hostAddress.contains(":")) {
                            // Only IPv4 addresses
                            ipAddresses.add(hostAddress)
                        }
                    }
                }
            }
        } catch (e: Exception) {
            // Ignore errors
        }
        return ipAddresses
    }

    fun handleStart(options: VpnOptions): Boolean {
        onUpdateNetwork();
        if (options.enable != this.options?.enable) {
            this.liClashService = null
        }
        this.options = options
        when (options.enable) {
            true -> handleStartVpn()
            false -> handleStartService()
        }
        return true
    }

    private fun handleStartVpn() {
        GlobalState.getCurrentAppPlugin()?.requestVpnPermission {
            handleStartService()
        }
    }

    fun requestGc() {
        flutterMethodChannel.invokeMethod("gc", null)
    }

    val networks = mutableSetOf<Network>()

    fun onUpdateNetwork() {
        val dns = networks.flatMap { network ->
            connectivity?.resolveDns(network) ?: emptyList()
        }.toSet().joinToString(",")
        scope.launch {
            withContext(Dispatchers.Main) {
                flutterMethodChannel.invokeMethod("dnsChanged", dns)
            }
        }
    }

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            networks.add(network)
            onUpdateNetwork()
        }

        override fun onLost(network: Network) {
            networks.remove(network)
            onUpdateNetwork()
        }
    }

    private val request = NetworkRequest.Builder().apply {
        addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
    }.build()

    private fun registerNetworkCallback() {
        networks.clear()
        connectivity?.registerNetworkCallback(request, callback)
    }

    private fun unRegisterNetworkCallback() {
        connectivity?.unregisterNetworkCallback(callback)
        networks.clear()
        onUpdateNetwork()
    }

    private suspend fun startForeground() {
        GlobalState.runLock.lock()
        try {
            if (GlobalState.runState.value != RunState.START) return
            val data = flutterMethodChannel.awaitResult<String>("getStartForegroundParams")
            val startForegroundParams = if (data != null) Gson().fromJson(
                data, StartForegroundParams::class.java
            ) else StartForegroundParams(
                title = "", content = ""
            )
            if (lastStartForegroundParams != startForegroundParams) {
                lastStartForegroundParams = startForegroundParams
                liClashService?.startForeground(
                    startForegroundParams.title,
                    startForegroundParams.content,
                )
            }
        } finally {
            GlobalState.runLock.unlock()
        }
    }

    private fun startForegroundJob() {
        stopForegroundJob()
        timerJob = CoroutineScope(Dispatchers.Main).launch {
            while (isActive) {
                startForeground()
                delay(1000)
            }
        }
    }

    private fun stopForegroundJob() {
        timerJob?.cancel()
        timerJob = null
    }


    suspend fun getStatus(): Boolean? {
        return withContext(Dispatchers.Default) {
            flutterMethodChannel.awaitResult<Boolean>("status", null)
        }
    }

    private fun handleStartService() {
        if (liClashService == null) {
            bindService()
            return
        }
        GlobalState.runLock.withLock {
            if (GlobalState.runState.value == RunState.START) return
            GlobalState.runState.value = RunState.START
            val fd = liClashService?.start(options!!)
            Core.startTun(
                fd = fd ?: 0,
                protect = this::protect,
                resolverProcess = this::resolverProcess,
            )
            startForegroundJob()
            // Install SuspendModule if dozeSuspend is enabled
            if (options?.dozeSuspend == true) {
                suspendModule?.uninstall()
                suspendModule = SuspendModule(LiClashApplication.getAppContext())
                suspendModule?.install()
            }
        }
    }

    private fun protect(fd: Int): Boolean {
        return (liClashService as? LiClashVpnService)?.protect(fd) == true
    }

    private fun resolverProcess(
        protocol: Int,
        source: InetSocketAddress,
        target: InetSocketAddress,
        uid: Int,
    ): String {
        val nextUid = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            connectivity?.getConnectionOwnerUid(protocol, source, target) ?: -1
        } else {
            uid
        }
        if (nextUid == -1) {
            return ""
        }
        if (!uidPageNameMap.containsKey(nextUid)) {
            uidPageNameMap[nextUid] =
                LiClashApplication.getAppContext().packageManager?.getPackagesForUid(nextUid)
                    ?.first() ?: ""
        }
        return uidPageNameMap[nextUid] ?: ""
    }

    fun handleStop() {
        GlobalState.runLock.withLock {
            if (GlobalState.runState.value == RunState.STOP) return
            GlobalState.runState.value = RunState.STOP
            // Uninstall SuspendModule
            suspendModule?.uninstall()
            suspendModule = null
            liClashService?.stop()
            stopForegroundJob()
            Core.stopTun()
            GlobalState.handleTryDestroy()
        }
    }

    /**
     * Smart stop: Stop the TUN but keep the foreground service running.
     * Used by Smart Auto Stop feature to maintain notification while VPN is paused.
     */
    fun handleSmartStop() {
        GlobalState.runLock.withLock {
            if (GlobalState.runState.value == RunState.STOP) return
            GlobalState.runState.value = RunState.STOP
            GlobalState.isSmartStopped = true
            // Uninstall SuspendModule
            suspendModule?.uninstall()
            suspendModule = null
            // Stop TUN but keep service running
            Core.stopTun()
            // Keep foreground job running to update notification
            // The notification will show "智能启停服务运行中"
        }
    }

    /**
     * Smart resume: Resume VPN from smart-stopped state.
     * Restarts the TUN without rebinding the service.
     */
    fun handleSmartResume(options: VpnOptions): Boolean {
        GlobalState.runLock.withLock {
            if (GlobalState.runState.value == RunState.START) return true
            GlobalState.isSmartStopped = false
            this.options = options
            
            if (liClashService == null) {
                // Service was destroyed, need to rebind
                bindService()
                return true
            }
            
            GlobalState.runState.value = RunState.START
            val fd = liClashService?.start(options)
            Core.startTun(
                fd = fd ?: 0,
                protect = this::protect,
                resolverProcess = this::resolverProcess,
            )
            // Install SuspendModule if dozeSuspend is enabled
            if (options.dozeSuspend == true) {
                suspendModule?.uninstall()
                suspendModule = SuspendModule(LiClashApplication.getAppContext())
                suspendModule?.install()
            }
            return true
        }
    }

    private fun bindService() {
        if (isBind) {
            LiClashApplication.getAppContext().unbindService(connection)
        }
        val intent = when (options?.enable == true) {
            true -> Intent(LiClashApplication.getAppContext(), LiClashVpnService::class.java)
            false -> Intent(LiClashApplication.getAppContext(), LiClashService::class.java)
        }
        LiClashApplication.getAppContext().bindService(intent, connection, Context.BIND_AUTO_CREATE)
    }
}