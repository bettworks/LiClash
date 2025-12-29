import 'dart:io';

import 'package:li_clash/common/common.dart';

/// 端口管理器：检查端口占用并自动清理
class PortManager {
  static PortManager? _instance;

  PortManager._internal();

  factory PortManager() {
    _instance ??= PortManager._internal();
    return _instance!;
  }

  String? _netstatCache;
  DateTime? _cacheTime;
  static const _cacheDuration = Duration(seconds: 5);

  /// 获取 netstat 输出（带缓存）
  Future<String> _getNetstatOutput() async {
    final now = DateTime.now();
    if (_netstatCache != null &&
        _cacheTime != null &&
        now.difference(_cacheTime!) < _cacheDuration) {
      return _netstatCache!;
    }

    try {
      final result = await Process.run(
        'netstat',
        ['-ano'],
        runInShell: true,
      );
      _netstatCache = result.stdout.toString();
      _cacheTime = now;
      return _netstatCache!;
    } catch (e) {
      commonPrint.log('获取 netstat 输出失败: $e');
      return '';
    }
  }

  /// 清除 netstat 缓存
  void _clearNetstatCache() {
    _netstatCache = null;
    _cacheTime = null;
  }

  /// 从 netstat 输出中解析端口是否被占用
  bool _parsePortInOutput(String output, int port) {
    if (output.isEmpty) {
      return false;
    }

    final lines = output.split('\n');
    final portPattern = RegExp(r':' + port.toString() + r'\b');

    for (final line in lines) {
      // 必须同时满足：包含 LISTENING 状态 + 精确匹配端口号
      if (line.contains('LISTENING') && portPattern.hasMatch(line)) {
        return true;
      }
    }

    return false;
  }

  /// 检查端口是否被占用
  Future<bool> isPortInUse(int port) async {
    if (!system.isWindows) {
      return false; // 非 Windows 系统暂不检查
    }

    try {
      final output = await _getNetstatOutput();
      final inUse = _parsePortInOutput(output, port);

      if (inUse) {
        commonPrint.log('检测到端口 $port 正在被监听');
      }

      return inUse;
    } catch (e) {
      commonPrint.log('检查端口占用失败：$e');
      return false;
    }
  }

  /// 等待端口释放
  Future<void> waitForPortRelease(
    int port, {
    required Duration maxWait,
  }) async {
    final stopwatch = Stopwatch()..start();
    const checkInterval = Duration(milliseconds: 100);

    while (stopwatch.elapsed < maxWait) {
      final inUse = await isPortInUse(port);
      if (!inUse) {
        commonPrint.log(
          '端口 $port 已释放 (耗时：${stopwatch.elapsedMilliseconds}ms)',
        );
        return;
      }
      await Future.delayed(checkInterval);
    }

    commonPrint.log(
      '端口 $port 在 ${maxWait.inSeconds} 秒后仍未释放',
    );
  }

  /// 终止占用指定端口的进程
  Future<bool> killProcessUsingPort(int port) async {
    if (!system.isWindows) {
      return false;
    }

    try {
      final output = await _getNetstatOutput();
      if (output.isEmpty) {
        commonPrint.log('无法查询端口占用：netstat 失败');
        return false;
      }

      final lines = output.split('\n');
      final portPattern = RegExp(r':' + port.toString() + r'\b');

      // 查找包含该端口的行
      for (final line in lines) {
        if (portPattern.hasMatch(line) && line.contains('LISTENING')) {
          // 提取 PID（最后一列）
          final parts = line.trim().split(RegExp(r'\s+'));
          if (parts.isNotEmpty) {
            final pidStr = parts.last;
            // 验证 PID 是否为数字
            final pid = int.tryParse(pidStr);
            if (pid == null) {
              commonPrint.log('无效的 PID: $pidStr');
              continue;
            }
            commonPrint.log('发现占用端口 $port 的进程 PID=$pid，正在终止…');

            // 使用 taskkill 终止进程
            final killResult = await Process.run(
              'taskkill',
              ['/F', '/PID', pid.toString()],
              runInShell: true,
            );
            if (killResult.exitCode == 0) {
              commonPrint.log('成功终止进程 PID=$pid');

              // 进程被终止，清除缓存
              _clearNetstatCache();

              // 等待端口释放
              await waitForPortRelease(
                port,
                maxWait: const Duration(seconds: 1),
              );
              return true;
            } else {
              final error = killResult.stderr.toString();
              commonPrint.log('终止进程失败：$error');
              return false;
            }
          }
        }
      }

      commonPrint.log('未发现占用端口 $port 的进程');
      return false;
    } catch (e) {
      commonPrint.log('终止占用端口进程失败：$e');
      return false;
    }
  }

  /// 确保端口可用（如果被占用则尝试清理）
  Future<bool> ensurePortAvailable(int port) async {
    final inUse = await isPortInUse(port);

    if (!inUse) {
      commonPrint.log('端口 $port 可用');
      return true;
    }

    // 端口被占用，尝试清理（最多3次）
    for (int attempt = 1; attempt <= 3; attempt++) {
      commonPrint.log(
        '端口 $port 被占用（尝试 $attempt/3），查找并终止占用进程…',
      );
      final success = await killProcessUsingPort(port);

      if (success) {
        // 再次检查是否成功释放
        final stillInUse = await isPortInUse(port);
        if (!stillInUse) {
          commonPrint.log('端口 $port 已成功释放');
          return true;
        }
      }

      // 最后一次尝试后仍被占用
      if (attempt == 3) {
        commonPrint.log('端口 $port 在 3 次尝试后仍被占用，启动可能失败');
        return false;
      }

      // 等待后重试
      await Future.delayed(const Duration(seconds: 1));
    }

    return false;
  }
}

final portManager = system.isWindows ? PortManager() : null;

