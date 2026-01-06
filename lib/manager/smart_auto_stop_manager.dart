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
    // Listen to VPN settings changes
    ref.listenManual(vpnSettingProvider, (prev, next) {
      if (prev?.smartAutoStop != next.smartAutoStop ||
          prev?.smartAutoStopNetworks != next.smartAutoStopNetworks) {
        _onSettingsChanged();
      }
    });
    
    // Listen to VPN running state changes
    ref.listenManual(runTimeProvider, (prev, next) {
      final wasRunning = prev != null;
      final isRunning = next != null;
      if (wasRunning != isRunning) {
        _onVpnStateChanged(isRunning);
      }
    });
  }

  void _initConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      _onConnectivityChanged(results);
    });
  }

  void _onSettingsChanged() {
    final vpnProps = ref.read(vpnSettingProvider);
    if (!vpnProps.smartAutoStop) {
      // Feature disabled, reset state
      final isSmartStopped = ref.read(isSmartStoppedProvider);
      if (isSmartStopped) {
        ref.read(isSmartStoppedProvider.notifier).state = false;
        // Restart VPN if it was smart-stopped
        _restartVpn();
      }
      return;
    }
    // Re-check current network
    _checkCurrentNetwork();
  }

  void _onVpnStateChanged(bool isRunning) {
    if (!ref.read(vpnSettingProvider).smartAutoStop) return;
    
    final isSmartStopped = ref.read(isSmartStoppedProvider);
    if (isRunning && isSmartStopped) {
      // VPN was manually started, clear smart-stopped state
      ref.read(isSmartStoppedProvider.notifier).state = false;
    }
  }

  Future<void> _onConnectivityChanged(List<ConnectivityResult> results) async {
    final vpnProps = ref.read(vpnSettingProvider);
    if (!vpnProps.smartAutoStop) return;
    
    // Delay a bit to let network stabilize
    await Future.delayed(const Duration(milliseconds: 500));
    await _checkCurrentNetwork();
  }

  Future<void> _checkCurrentNetwork() async {
    final vpnProps = ref.read(vpnSettingProvider);
    if (!vpnProps.smartAutoStop) return;
    
    final networks = vpnProps.smartAutoStopNetworks;
    if (networks.isEmpty) return;
    
    final isVpnRunning = ref.read(runTimeProvider) != null;
    final isSmartStopped = ref.read(isSmartStoppedProvider);
    
    // Get current IP
    String? currentIp;
    if (system.isAndroid && isVpnRunning) {
      // Android VPN running: use native detection (more stable)
      currentIp = await _getNativeLocalIpAddress();
    } else {
      // Android VPN stopped or other platforms: use connectivity_plus
      currentIp = await _getLocalIpAddress();
    }
    
    if (currentIp == null || currentIp.isEmpty) {
      commonPrint.log('Smart Auto Stop: No IP address detected');
      return;
    }
    
    commonPrint.log('Smart Auto Stop: Current IP=$currentIp, Last IP=$_lastCheckedIp, VPN running=$isVpnRunning, Smart stopped=$isSmartStopped');
    
    // Use NetworkMatcher for IP matching
    final shouldStop = NetworkMatcher.matchAny(currentIp, networks);
    commonPrint.log('Smart Auto Stop: Should stop=$shouldStop (matched against ${networks.join(", ")})');
    
    // Check if we need to take action
    if (shouldStop && isVpnRunning && !isSmartStopped) {
      // Stop VPN
      _lastCheckedIp = currentIp;
      ref.read(isSmartStoppedProvider.notifier).state = true;
      // Update native state for notification
      if (system.isAndroid) {
        await service?.setSmartStopped(true);
      }
      await _stopVpn();
      commonPrint.log('Smart Auto Stop: VPN stopped due to matching network $currentIp');
    } else if (!shouldStop && !isVpnRunning && isSmartStopped) {
      // Restart VPN
      _lastCheckedIp = currentIp;
      ref.read(isSmartStoppedProvider.notifier).state = false;
      // Update native state for notification
      if (system.isAndroid) {
        await service?.setSmartStopped(false);
      }
      await _restartVpn();
      commonPrint.log('Smart Auto Stop: VPN restarted due to network change $currentIp');
    } else {
      // No action needed, but update last checked IP if it changed
      if (currentIp != _lastCheckedIp) {
        _lastCheckedIp = currentIp;
        commonPrint.log('Smart Auto Stop: IP changed but no action needed');
      }
    }
  }

  /// Get local IP using native Android VPN code (more reliable when VPN is running)
  Future<String?> _getNativeLocalIpAddress() async {
    try {
      final serviceInstance = service;
      if (serviceInstance != null) {
        final ips = await serviceInstance.getLocalIpAddresses();
        if (ips.isNotEmpty) {
          return ips.first;
        }
      }
    } catch (e) {
      commonPrint.log('Smart Auto Stop: Error getting native IP: $e');
    }
    // Fallback to connectivity_plus
    return await _getLocalIpAddress();
  }

  Future<String?> _getLocalIpAddress() async {
    return await utils.getLocalIpAddress();
  }

  Future<void> _stopVpn() async {
    commonPrint.log('Smart Auto Stop: _stopVpn called, isInit=${globalState.isInit}, isAndroid=${system.isAndroid}');
    if (!globalState.isInit) {
      commonPrint.log('Smart Auto Stop: globalState not initialized, cannot stop VPN');
      return;
    }
    
    // On Android, use smartStop to keep foreground service running
    if (system.isAndroid) {
      commonPrint.log('Smart Auto Stop: Using Android smartStop, service=$service');
      final result = await service?.smartStop();
      commonPrint.log('Smart Auto Stop: smartStop result=$result');
      // Also update the Dart-side state
      globalState.startTime = null;
      clashCore.resetTraffic();
      ref.read(trafficsProvider.notifier).clear();
      ref.read(totalTrafficProvider.notifier).value = Traffic();
      ref.read(runTimeProvider.notifier).value = null;
      commonPrint.log('Smart Auto Stop: smartStop completed, Dart state updated');
    } else {
      // On other platforms, use regular stop
      commonPrint.log('Smart Auto Stop: Using regular stop (updateStatus)');
      await globalState.appController.updateStatus(false);
      commonPrint.log('Smart Auto Stop: updateStatus(false) completed');
    }
  }

  Future<void> _restartVpn() async {
    commonPrint.log('Smart Auto Stop: _restartVpn called, isInit=${globalState.isInit}, isAndroid=${system.isAndroid}');
    if (!globalState.isInit) {
      commonPrint.log('Smart Auto Stop: globalState not initialized, cannot restart VPN');
      return;
    }
    
    // On Android, use smartResume to restart from smart-stopped state
    if (system.isAndroid) {
      commonPrint.log('Smart Auto Stop: Using Android smartResume, service=$service');
      final result = await service?.smartResume();
      commonPrint.log('Smart Auto Stop: smartResume result=$result');
      // Also update the Dart-side state
      globalState.startTime = DateTime.now();
      globalState.appController.addCheckIpNumDebounce();
      commonPrint.log('Smart Auto Stop: smartResume completed, Dart state updated');
    } else {
      // On other platforms, use regular start
      commonPrint.log('Smart Auto Stop: Using regular start (updateStatus)');
      await globalState.appController.updateStatus(true);
      commonPrint.log('Smart Auto Stop: updateStatus(true) completed');
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
