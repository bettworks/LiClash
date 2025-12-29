import 'dart:async';
import 'package:flutter/material.dart';
import 'package:stelliberty/clash/data/clash_model.dart';
import 'package:stelliberty/utils/logger.dart';
import 'package:stelliberty/clash/config/clash_defaults.dart';
import 'package:stelliberty/clash/network/api_client.dart';

// 延迟测试工具类
class DelayTester {
  // 默认测试URL
  static String get defaultTestUrl => ClashDefaults.defaultTestUrl;

  // 超时时间（毫秒）
  static int get timeoutMs => ClashDefaults.proxyDelayTestTimeout;

  // Clash API 客户端（用于统一延迟测试）
  static ClashApiClient? _apiClient;

  // 设置 Clash API 客户端（在 Clash 启动时调用）
  static void setApiClient(ClashApiClient? client) {
    _apiClient = client;
    if (client != null) {
      Logger.info('Clash API 客户端已设置，统一延迟测试已启用');
    } else {
      Logger.warning('Clash API 客户端已移除，延迟测试不可用');
    }
  }

  // 检查延迟测试是否可用
  static bool get isAvailable => _apiClient != null;

  // 测试单个代理节点的延迟
  //
  // [proxyNode] 要测试的代理节点
  // [testUrl] 测试URL，默认使用Google的204页面
  // 返回延迟毫秒数，-1表示测试失败
  static Future<int> testProxyDelay(
    ProxyNode proxyNode, {
    String? testUrl,
  }) async {
    // 检查节点名称是否有效
    if (proxyNode.name.isEmpty) {
      Logger.warning('无效的代理节点：节点名称为空');
      return -1;
    }

    if (_apiClient == null) {
      Logger.error('Clash API 客户端未设置，无法进行延迟测试。请先启动 Clash。');
      return -1;
    }

    final url = testUrl ?? defaultTestUrl;
    Logger.info('开始测试代理 ${proxyNode.name} 的延迟（统一延迟测试）：$url');

    try {
      final delay = await _apiClient!.testProxyDelay(
        proxyNode.name,
        testUrl: url,
        timeoutMs: timeoutMs,
      );

      if (delay > 0) {
        Logger.info('延迟测试成功：${proxyNode.name} - ${delay}ms');
      } else {
        Logger.warning('延迟测试失败：${proxyNode.name} - 超时或协议错误');
      }

      return delay;
    } catch (e) {
      Logger.error('测试代理 ${proxyNode.name} 延迟失败：$e');
      return -1;
    }
  }

  // 统一延迟测试方法
  // 这个方法提供了更统一的接口，用于处理所有类型的延迟测试
  //
  // [nodeName] 节点名称
  // [proxyNode] 代理节点对象
  // [testUrl] 测试URL
  // [onStart] 测试开始的回调
  // [onComplete] 测试完成的回调
  static Future<int> unifiedDelayTest({
    required String nodeName,
    required ProxyNode proxyNode,
    String? testUrl,
    VoidCallback? onStart,
    Function(int delay)? onComplete,
  }) async {
    // 触发开始回调（设置延迟为0表示正在测试）
    onStart?.call();

    // 执行实际的延迟测试
    final delay = await testProxyDelay(proxyNode, testUrl: testUrl);

    // 触发完成回调
    onComplete?.call(delay);

    return delay;
  }
}
