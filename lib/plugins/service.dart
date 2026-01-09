import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:li_clash/common/system.dart';
import 'package:li_clash/state.dart';
import 'package:flutter/services.dart';

import '../clash/lib.dart';

class Service {
  static Service? _instance;
  late MethodChannel methodChannel;
  ReceivePort? receiver;

  Service._internal() {
    methodChannel = const MethodChannel('service');
  }

  factory Service() {
    _instance ??= Service._internal();
    return _instance!;
  }

  Future<bool?> init() async {
    return await methodChannel.invokeMethod<bool>('init');
  }

  Future<bool?> destroy() async {
    return await methodChannel.invokeMethod<bool>('destroy');
  }

  Future<bool?> startVpn() async {
    final options = await clashLib?.getAndroidVpnOptions();
    final jsonMap = options?.toJson() ?? {};
    jsonMap['disableIcmpForwarding'] = globalState.config.patchClashConfig.tun.disableIcmpForwarding;

    return await methodChannel.invokeMethod<bool>('startVpn', {
      'data': json.encode(jsonMap),
    });
  }

  Future<bool?> stopVpn() async {
    return await methodChannel.invokeMethod<bool>('stopVpn');
  }

  /// Smart stop: Stop VPN but keep foreground service running.
  /// Used by Smart Auto Stop feature.
  Future<bool?> smartStop() async {
    return await methodChannel.invokeMethod<bool>('smartStop');
  }

  /// Smart resume: Resume VPN from smart-stopped state.
  Future<bool?> smartResume() async {
    final options = await clashLib?.getAndroidVpnOptions();
    final jsonMap = options?.toJson() ?? {};
    jsonMap['disableIcmpForwarding'] = globalState.config.patchClashConfig.tun.disableIcmpForwarding;

    return await methodChannel.invokeMethod<bool>('smartResume', {
      'data': json.encode(jsonMap),
    });
  }

  /// Set the smart-stopped state in native code.
  Future<void> setSmartStopped(bool value) async {
    await methodChannel.invokeMethod<bool>('setSmartStopped', {'value': value});
  }

  /// Get local IP addresses from native Android code.
  /// More reliable than connectivity_plus when VPN is running.
  Future<List<String>> getLocalIpAddresses() async {
    final result = await methodChannel.invokeMethod<List<dynamic>>('getLocalIpAddresses');
    return result?.cast<String>() ?? [];
  }
}

Service? get service =>
    system.isAndroid && !globalState.isService ? Service() : null;
