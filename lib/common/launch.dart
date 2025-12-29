import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

import 'constant.dart';
import 'enum/enum.dart';
import 'system.dart';

enum AutoLaunchMode {
  none, // 未启用
  normal, // 普通模式（注册表）
  admin, // 管理员模式（任务计划）
}

class AutoLaunch {
  static AutoLaunch? _instance;

  AutoLaunch._internal() {
    launchAtStartup.setup(
      appName: appName,
      appPath: Platform.resolvedExecutable,
    );
  }

  factory AutoLaunch() {
    _instance ??= AutoLaunch._internal();
    return _instance!;
  }

  // 获取当前自启动模式
  Future<AutoLaunchMode> getCurrentMode() async {
    if (system.isWindows) {
      // Windows: 优先检查任务计划（管理员模式）
      final taskExists = await windows?.isTaskExists(appName) ?? false;
      if (taskExists) {
        return AutoLaunchMode.admin;
      }
      // 检查注册表（普通模式）
      final normalEnabled = await launchAtStartup.isEnabled();
      if (normalEnabled) {
        return AutoLaunchMode.normal;
      }
    } else {
      // 其他平台：只检查普通模式
      final normalEnabled = await launchAtStartup.isEnabled();
      if (normalEnabled) {
        return AutoLaunchMode.normal;
      }
    }
    return AutoLaunchMode.none;
  }

  // 检查是否已启用（任意模式）
  Future<bool> get isEnable async {
    final mode = await getCurrentMode();
    return mode != AutoLaunchMode.none;
  }

  // 智能启用自启动（Windows优先管理员模式，失败回退普通模式）
  Future<bool> enable({bool preferAdmin = true}) async {
    if (kDebugMode) {
      return true;
    }

    if (system.isWindows && preferAdmin) {
      // Windows: 优先尝试管理员模式
      final isAdmin = await system.checkIsAdmin();
      if (!isAdmin) {
        // 请求管理员权限
        final code = await system.authorizeCore();
        if (code == AuthorizeCode.success) {
          // 权限获取成功，注册任务计划
          final success = await windows?.registerTask(appName) ?? false;
          if (success) {
            // 管理员模式启用成功，禁用普通模式（避免冲突）
            await launchAtStartup.disable();
            return true;
          }
        }
        // 管理员模式失败，回退到普通模式
      } else {
        // 已有管理员权限，直接注册任务计划
        final success = await windows?.registerTask(appName) ?? false;
        if (success) {
          await launchAtStartup.disable();
          return true;
        }
      }
    }

    // 使用普通模式（注册表）
    final success = await launchAtStartup.enable();
    if (success && system.isWindows) {
      // 普通模式启用成功，删除可能存在的任务计划（避免冲突）
      await windows?.deleteTask(appName);
    }
    return success;
  }

  // 禁用自启动（同时禁用两种模式）
  Future<bool> disable() async {
    if (kDebugMode) {
      return true;
    }

    bool allSuccess = true;

    // 禁用普通模式
    try {
      await launchAtStartup.disable();
    } catch (_) {
      allSuccess = false;
    }

    // 禁用管理员模式（Windows）
    if (system.isWindows) {
      try {
        await windows?.deleteTask(appName);
      } catch (_) {
        allSuccess = false;
      }
    }

    return allSuccess;
  }

  // 更新自启动状态（智能选择模式）
  Future<void> updateStatus(bool isAutoLaunch, {bool preferAdmin = true}) async {
    if (kDebugMode) {
      return;
    }

    final currentMode = await getCurrentMode();
    final isCurrentlyEnabled = currentMode != AutoLaunchMode.none;

    // 状态未变化，无需操作
    if (isCurrentlyEnabled == isAutoLaunch) {
      return;
    }

    if (isAutoLaunch) {
      await enable(preferAdmin: preferAdmin);
    } else {
      await disable();
    }
  }

  // 获取当前模式的描述文本
  Future<String> getModeDescription() async {
    final mode = await getCurrentMode();
    switch (mode) {
      case AutoLaunchMode.none:
        return '';
      case AutoLaunchMode.normal:
        return '（普通模式）';
      case AutoLaunchMode.admin:
        return '（管理员模式）';
    }
  }
}

final autoLaunch = system.isDesktop ? AutoLaunch() : null;
