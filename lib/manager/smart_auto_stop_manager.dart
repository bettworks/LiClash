import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:li_clash/clash/clash.dart';
import 'package:li_clash/common/common.dart';
import 'package:li_clash/common/network_matcher.dart';
import 'package:li_clash/models/models.dart';
import 'package:li_clash/plugins/service.dart';
import 'package:li_clash/providers/providers.dart';
import 'package:li_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Smart Auto Stop Manager
/// 
/// Monitors network changes and automatically stops/starts VPN based on
/// configured intranet IP/CIDR matching rules.
/// 
/// Logic:
/// - Android VPN running: Use native VPN code for network detection (more stable)
/// - Android VPN stopped: Use connectivity_plus (service closes with VPN)
/// - Other platforms: Always use connectivity_plus
class SmartAutoStopManager extends ConsumerStatefulWidget {
  final Widget child;

  const SmartAutoStopManager({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<SmartAutoStopManager> createState() => _SmartAutoStopManagerState();
}

class _SmartAutoStopManagerState extends ConsumerState<SmartAutoStopManager> {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  String? _lastCheckedIp;

  @override
  void initState() {
    super.initState();
    _initConnectivityListener();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listen to VPN settings changes to trigger check immediately if enabled
    ref.listenManual(vpnSettingProvider, (prev, next) {
      if (prev?.smartAutoStop != next.smartAutoStop ||
          prev?.smartAutoStopNetworks != next.smartAutoStopNetworks) {
        _onSettingsChanged();
      }
    });

    // We don't rely solely on runTimeProvider listener for Android status
    // because it might be out of sync. We rely more on network changes and polling.
  }

  void _initConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      _onConnectivityChanged(results);
    });
  }

  void _onSettingsChanged() {
    final vpnProps = ref.read(vpnSettingProvider);
    if (!vpnProps.smartAutoStop) {
      // Feature disabled, if we were smart-stopped, resume.
      final isSmartStopped = ref.read(isSmartStoppedProvider);
      if (isSmartStopped) {
        ref.read(isSmartStoppedProvider.notifier).state = false;
        _restartVpn();
      }
      return;
    }
    // Re-check current network
    _checkCurrentNetwork();
  }

  Future<void> _onConnectivityChanged(List<ConnectivityResult> results) async {
    final vpnProps = ref.read(vpnSettingProvider);
    if (!vpnProps.smartAutoStop) return;
    
    // Delay a bit to let network stabilize
    await Future.delayed(const Duration(milliseconds: 1000));
    await _checkCurrentNetwork();
  }

  Future<void> _checkCurrentNetwork() async {
    final vpnProps = ref.read(vpnSettingProvider);
    if (!vpnProps.smartAutoStop) return;
    
    final networks = vpnProps.smartAutoStopNetworks;
    // Empty networks rule = disable feature effectively
    if (networks.isEmpty) return; 

    // 1. Determine reliable Running state
    bool isRunning;
    if (system.isAndroid) {
      // On Android, always sync with native side
      await globalState.updateStartTime();
      // Also check runTimeProvider as a fallback/confirmation
      isRunning = globalState.isStart; 
    } else {
      isRunning = ref.read(runTimeProvider) != null;
    }

    final isSmartStopped = ref.read(isSmartStoppedProvider);

    // 2. Get current IP
    String? currentIp;
    if (system.isAndroid && isRunning) {
      // Android VPN running: use native detection
      currentIp = await _getNativeLocalIpAddress();
    } else {
      // Android VPN stopped or other platforms
      currentIp = await _getLocalIpAddress();
    }
    
    if (currentIp == null || currentIp.isEmpty) {
        commonPrint.log('Smart Auto Stop: No legitimate IP found. Skipping.');
        return;
    }
    
    // Dedup check to avoid repeated actions on same IP
    if (currentIp == _lastCheckedIp && 
       ((isRunning && !isSmartStopped) || (!isRunning && isSmartStopped))) {
         // State is stable matching current IP, skip
         return;
    }
    _lastCheckedIp = currentIp;

    // 3. Match Logic
    final shouldStop = NetworkMatcher.matchAny(currentIp, networks);
    
    commonPrint.log('SmartAutoStop: IP=$currentIp, RuleMatch=$shouldStop, Running=$isRunning, SmartStopped=$isSmartStopped');

    if (shouldStop) {
      // Rule matched: VPN should be STOPPED
      if (isRunning) {
        if (!isSmartStopped) {
           // Only mark as smart-stopped if we are currently running normally
           ref.read(isSmartStoppedProvider.notifier).state = true;
        }
        commonPrint.log('Smart Auto Stop: Stopping VPN...');
        await _stopVpn();
      }
    } else {
      // Rule NOT matched: VPN should be RUNNING (if it was smart-stopped)
      if (!isRunning && isSmartStopped) {
        ref.read(isSmartStoppedProvider.notifier).state = false;
        commonPrint.log('Smart Auto Stop: Restarting VPN...');
        await _restartVpn();
      }
    }
  }

  Future<String?> _getNativeLocalIpAddress() async {
    try {
      final serviceInstance = service;
      if (serviceInstance != null) {
        final ips = await serviceInstance.getLocalIpAddresses();
        if (ips.isNotEmpty) return ips.first;
      }
    } catch (e) {
      commonPrint.log('Smart Auto Stop: Native IP error: $e');
    }
    return await _getLocalIpAddress();
  }

  Future<String?> _getLocalIpAddress() async {
    return await utils.getLocalIpAddress();
  }

  Future<void> _stopVpn() async {
    if (system.isAndroid) {
      // Android: Enable smart-stop mode (Blank notification)
      // This keeps the service alive but stops the VPN logic
      await service?.setSmartStopped(true);
      await service?.smartStop();
      
      // Update Dart state to look "stopped"
      globalState.startTime = null;
      clashCore.resetTraffic();
      ref.read(trafficsProvider.notifier).clear();
      ref.read(totalTrafficProvider.notifier).value = Traffic();
      ref.read(runTimeProvider.notifier).value = null;
    } else {
      // Desktop: Full stop
      await globalState.appController.updateStatus(false);
    }
  }

  Future<void> _restartVpn() async {
    if (system.isAndroid) {
       // Android: Resume from smart-stop mode
       await service?.setSmartStopped(false);
       await service?.smartResume();
       
       // Update Dart state to look "running"
       globalState.startTime = DateTime.now();
       globalState.appController.addCheckIpNumDebounce();
    } else {
      // Desktop: Full start
      await globalState.appController.updateStatus(true);
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
