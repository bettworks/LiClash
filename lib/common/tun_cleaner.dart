import 'dart:io';

import 'package:li_clash/common/common.dart';

/// TUN接口清理器：启动前清理残留适配器
class TunCleaner {
  static TunCleaner? _instance;

  TunCleaner._internal();

  factory TunCleaner() {
    _instance ??= TunCleaner._internal();
    return _instance!;
  }

  /// 检查是否有管理员权限
  Future<bool> _checkAdmin() async {
    if (!system.isWindows) {
      return false;
    }

    try {
      final result = await Process.run('net', ['session'], runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 获取TUN适配器列表
  Future<List<String>> _getTunAdapters() async {
    if (!system.isWindows) {
      return [];
    }

    try {
      final result = await Process.run(
        'powershell',
        [
          '-Command',
          r"Get-NetAdapter | Where-Object {$_.Name -like '*TUN*' -or $_.Name -like '*Wintun*' -or $_.Name -like '*TAP*' -or $_.Name -like '*Clash*' -or $_.Name -like '*LiClash*' -or $_.Name -like '*mihomo*'} | Select-Object -ExpandProperty Name",
        ],
        runInShell: true,
      );

      if (result.exitCode != 0) {
        return [];
      }

      final output = result.stdout.toString().trim();
      if (output.isEmpty) {
        return [];
      }

      return output
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
    } catch (e) {
      commonPrint.log('获取TUN适配器列表失败: $e');
      return [];
    }
  }

  /// 删除TUN适配器
  Future<bool> _removeAdapter(String adapterName) async {
    if (!system.isWindows) {
      return false;
    }

    try {
      // 使用 PowerShell 命令字符串，避免 $false 被解释为 Dart 字符串插值
      final command = 'Remove-NetAdapter -Name "$adapterName" -Confirm:\\\$false';
      final finalCommand = command.replaceAll(r'$adapterName', adapterName);
      final result = await Process.run(
        'powershell',
        [
          '-Command',
          finalCommand,
        ],
        runInShell: true,
      );

      return result.exitCode == 0;
    } catch (e) {
      commonPrint.log('删除适配器 $adapterName 失败: $e');
      return false;
    }
  }

  /// 清理所有TUN适配器
  Future<bool> cleanTunAdapters() async {
    if (!system.isWindows) {
      return true;
    }

    // 检查管理员权限
    final isAdmin = await _checkAdmin();
    if (!isAdmin) {
      commonPrint.log('清理TUN适配器需要管理员权限，跳过清理');
      return false;
    }

    try {
      final adapters = await _getTunAdapters();
      if (adapters.isEmpty) {
        commonPrint.log('未找到需要清理的TUN适配器');
        return true;
      }

      commonPrint.log('发现 ${adapters.length} 个TUN适配器，开始清理…');
      bool allSuccess = true;

      for (final adapter in adapters) {
        commonPrint.log('正在删除适配器: $adapter…');
        final success = await _removeAdapter(adapter);
        if (success) {
          commonPrint.log('✓ 已删除适配器: $adapter');
        } else {
          commonPrint.log('✗ 删除适配器失败: $adapter');
          allSuccess = false;
        }
      }

      if (allSuccess) {
        commonPrint.log('所有TUN适配器清理完成');
      } else {
        commonPrint.log('部分TUN适配器清理失败，可能需要手动清理');
      }

      return allSuccess;
    } catch (e) {
      commonPrint.log('清理TUN适配器时发生错误: $e');
      return false;
    }
  }

  /// 检查并清理TUN适配器（如果存在）
  Future<bool> checkAndClean() async {
    if (!system.isWindows) {
      return true;
    }

    final adapters = await _getTunAdapters();
    if (adapters.isEmpty) {
      return true;
    }

    commonPrint.log(
      '检测到 ${adapters.length} 个残留TUN适配器，开始清理…',
    );
    return await cleanTunAdapters();
  }
}

final tunCleaner = system.isWindows ? TunCleaner() : null;

