import 'dart:ffi';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:ffi/ffi.dart';
import 'package:li_clash/common/common.dart';
import 'package:li_clash/enum/enum.dart';
import 'package:li_clash/plugins/app.dart';
import 'package:li_clash/state.dart';
import 'package:li_clash/widgets/input.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';

class System {
  static System? _instance;

  System._internal();

  factory System() {
    _instance ??= System._internal();
    return _instance!;
  }

  bool get isDesktop => isWindows || isMacOS || isLinux;

  bool get isWindows => Platform.isWindows;

  bool get isMacOS => Platform.isMacOS;

  bool get isAndroid => Platform.isAndroid;

  bool get isLinux => Platform.isLinux;

  Future<int> get version async {
    final deviceInfo = await DeviceInfoPlugin().deviceInfo;
    return switch (Platform.operatingSystem) {
      'macos' => (deviceInfo as MacOsDeviceInfo).majorVersion,
      'android' => (deviceInfo as AndroidDeviceInfo).version.sdkInt,
      'windows' => (deviceInfo as WindowsDeviceInfo).majorVersion,
      String() => 0
    };
  }

  Future<bool> checkIsAdmin() async {
    final corePath = appPath.corePath.replaceAll(' ', '\\\\ ');
    if (system.isWindows) {
      final result = await windows?.checkService();
      return result == WindowsHelperServiceStatus.running;
    } else if (system.isMacOS) {
      final result = await Process.run('stat', ['-f', '%Su:%Sg %Sp', corePath]);
      final output = result.stdout.trim();
      if (output.startsWith('root:admin') && output.contains('rws')) {
        return true;
      }
      return false;
    } else if (Platform.isLinux) {
      final result = await Process.run('stat', ['-c', '%U:%G %A', corePath]);
      final output = result.stdout.trim();
      if (output.startsWith('root:') && output.contains('rws')) {
        return true;
      }
      return false;
    }
    return true;
  }

  Future<AuthorizeCode> authorizeCore() async {
    if (system.isAndroid) {
      return AuthorizeCode.error;
    }
    final corePath = appPath.corePath.replaceAll(' ', '\\\\ ');
    final isAdmin = await checkIsAdmin();
    if (isAdmin) {
      return AuthorizeCode.none;
    }

    if (system.isWindows) {
      final result = await windows?.registerService();
      if (result == true) {
        return AuthorizeCode.success;
      }
      return AuthorizeCode.error;
    }

    if (system.isMacOS) {
      final shell = 'chown root:admin $corePath; chmod +sx $corePath';
      final arguments = [
        '-e',
        'do shell script "$shell" with administrator privileges',
      ];
      final result = await Process.run('osascript', arguments);
      if (result.exitCode != 0) {
        return AuthorizeCode.error;
      }
      return AuthorizeCode.success;
    } else if (Platform.isLinux) {
      final shell = Platform.environment['SHELL'] ?? 'bash';
      final password = await globalState.showCommonDialog<String>(
        child: InputDialog(
          obscureText: true,
          title: appLocalizations.pleaseInputAdminPassword,
          value: '',
        ),
      );
      final arguments = [
        '-c',
        'echo "$password" | sudo -S chown root:root "$corePath" && echo "$password" | sudo -S chmod +sx "$corePath"'
      ];
      final result = await Process.run(shell, arguments);
      if (result.exitCode != 0) {
        return AuthorizeCode.error;
      }
      return AuthorizeCode.success;
    }
    return AuthorizeCode.error;
  }

  Future<void> back() async {
    await app?.moveTaskToBack();
    await window?.hide();
  }

  Future<void> exit() async {
    if (system.isAndroid) {
      await SystemNavigator.pop();
    }
    await window?.close();
  }

  /// 清理 Windows 上残留的 TUN 接口
  /// 使用 PowerShell 命令查找并删除以 "Meta" 开头的网络适配器
  /// 注意：删除网络适配器需要管理员权限
  /// 如果无法获取管理员权限，会静默跳过，不影响应用启动
  Future<void> cleanupTunInterfaces() async {
    if (!isWindows) {
      return;
    }

    try {
      // 注意：不预先检查权限，直接尝试删除
      // 如果没有权限，删除会失败，然后尝试通过 runas 请求权限
      // 如果用户拒绝 UAC，会静默跳过，不影响启动

      // 使用 PowerShell 获取所有网络适配器，查找以 "Meta" 开头的适配器
      // 使用 -WindowStyle Hidden 隐藏 PowerShell 窗口
      final getAdapterCmd =
          r'Get-NetAdapter | Where-Object { $_.Name -like "Meta*" } | Select-Object -ExpandProperty Name';

      final result = await Process.run(
        'powershell',
        [
          '-WindowStyle',
          'Hidden',
          '-NoProfile',
          '-Command',
          getAdapterCmd,
        ],
      );

      if (result.exitCode != 0) {
        return;
      }

      final output = result.stdout.toString().trim();
      if (output.isEmpty) {
        return;
      }

      final adapterNames = output
          .split('\n')
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .toList();

      if (adapterNames.isEmpty) {
        return;
      }

      // 删除找到的适配器（需要管理员权限）
      int successCount = 0;
      int failCount = 0;

      for (final adapterName in adapterNames) {
        // 转义适配器名称中的特殊字符（PowerShell 中需要转义 "）
        // 使用单引号包裹适配器名称，避免转义问题
        final removeCmd =
            "Remove-NetAdapter -Name '$adapterName' -Confirm:`\$false -ErrorAction SilentlyContinue";

        // 尝试直接删除（如果已有管理员权限）
        // 使用 -WindowStyle Hidden 隐藏 PowerShell 窗口
        final directResult = await Process.run(
          'powershell',
          [
            '-WindowStyle',
            'Hidden',
            '-NoProfile',
            '-Command',
            removeCmd,
          ],
        );

        // 如果直接删除失败（可能需要管理员权限），尝试使用 runas
        if (directResult.exitCode != 0) {
          // 使用 runas 以管理员权限执行删除命令
          // 注意：runas 会弹出 UAC 提示，但使用 SW_HIDE 隐藏窗口
          // 使用 Start-Process 以隐藏窗口方式执行 PowerShell 命令
          final hiddenCmd =
              'Start-Process powershell -ArgumentList "-Command", "$removeCmd" -WindowStyle Hidden -Wait';
          final runasSuccess = windows?.runas(
                'powershell.exe',
                '-Command "$hiddenCmd"'.replaceAll('\$hiddenCmd', hiddenCmd),
              ) ??
              false;

          if (runasSuccess) {
            // 等待一下，让删除操作完成
            await Future.delayed(const Duration(milliseconds: 500));
            // 验证是否删除成功
            final verifyResult = await Process.run(
              'powershell',
              [
                '-WindowStyle',
                'Hidden',
                '-NoProfile',
                '-Command',
                "Get-NetAdapter -Name '$adapterName' -ErrorAction SilentlyContinue",
              ],
            );
            if (verifyResult.exitCode != 0) {
              // 适配器不存在，说明删除成功
              successCount++;
              commonPrint.log('Cleaned up TUN interface: $adapterName');
            } else {
              failCount++;
              commonPrint.log(
                'Failed to cleanup TUN interface: $adapterName (user may have denied UAC)',
              );
            }
          } else {
            // runas 失败（用户拒绝 UAC 或无法获取权限）
            failCount++;
            commonPrint.log(
              'Cannot cleanup TUN interface: $adapterName (no admin permission)',
            );
          }
        } else {
          // 直接删除成功
          successCount++;
          commonPrint.log('Cleaned up TUN interface: $adapterName');
        }
      }

      if (successCount > 0) {
        commonPrint.log(
          'TUN cleanup completed: $successCount succeeded, $failCount failed',
        );
      } else if (failCount > 0) {
        commonPrint.log(
          'TUN cleanup failed: all $failCount interfaces could not be removed (may need admin permission)',
        );
      }
    } catch (e) {
      // 静默处理错误，避免影响启动流程
      commonPrint.log('Failed to cleanup TUN interfaces: $e');
    }
  }
}

final system = System();

class Windows {
  static Windows? _instance;
  late DynamicLibrary _shell32;

  Windows._internal() {
    _shell32 = DynamicLibrary.open('shell32.dll');
  }

  factory Windows() {
    _instance ??= Windows._internal();
    return _instance!;
  }

  bool runas(String command, String arguments) {
    final commandPtr = command.toNativeUtf16();
    final argumentsPtr = arguments.toNativeUtf16();
    final operationPtr = 'runas'.toNativeUtf16();

    final shellExecute = _shell32.lookupFunction<
        Int32 Function(
            Pointer<Utf16> hwnd,
            Pointer<Utf16> lpOperation,
            Pointer<Utf16> lpFile,
            Pointer<Utf16> lpParameters,
            Pointer<Utf16> lpDirectory,
            Int32 nShowCmd),
        int Function(
            Pointer<Utf16> hwnd,
            Pointer<Utf16> lpOperation,
            Pointer<Utf16> lpFile,
            Pointer<Utf16> lpParameters,
            Pointer<Utf16> lpDirectory,
            int nShowCmd)>('ShellExecuteW');

    // 使用 SW_HIDE(0) 隐藏被提权进程的主窗口，避免出现 cmd/PowerShell 黑框
    final result = shellExecute(
      nullptr,
      operationPtr,
      commandPtr,
      argumentsPtr,
      nullptr,
      0,
    );

    calloc.free(commandPtr);
    calloc.free(argumentsPtr);
    calloc.free(operationPtr);

    commonPrint.log('windows runas: $command $arguments resultCode:$result');

    if (result < 42) {
      return false;
    }
    return true;
  }

  Future<void> _killProcess(int port) async {
    final result = await Process.run('netstat', ['-ano']);
    final lines = result.stdout.toString().trim().split('\n');
    for (final line in lines) {
      if (!line.contains(':$port') || !line.contains('LISTENING')) {
        continue;
      }
      final parts = line.trim().split(RegExp(r'\s+'));
      final pid = int.tryParse(parts.last);
      if (pid != null) {
        await Process.run('taskkill', ['/PID', pid.toString(), '/F']);
      }
    }
  }

  Future<WindowsHelperServiceStatus> checkService() async {
    // final qcResult = await Process.run('sc', ['qc', appHelperService]);
    // final qcOutput = qcResult.stdout.toString();
    // if (qcResult.exitCode != 0 || !qcOutput.contains(appPath.helperPath)) {
    //   return WindowsHelperServiceStatus.none;
    // }
    final result = await Process.run('sc', ['query', appHelperService]);
    if (result.exitCode != 0) {
      return WindowsHelperServiceStatus.none;
    }
    final output = result.stdout.toString();
    if (output.contains('RUNNING') && await request.pingHelper()) {
      return WindowsHelperServiceStatus.running;
    }
    return WindowsHelperServiceStatus.presence;
  }

  Future<bool> registerService() async {
    final status = await checkService();

    if (status == WindowsHelperServiceStatus.running) {
      return true;
    }

    await _killProcess(helperPort);

    final command = [
      '/c',
      if (status == WindowsHelperServiceStatus.presence) ...[
        'sc',
        'delete',
        appHelperService,
        '/force',
        '&&',
      ],
      'sc',
      'create',
      appHelperService,
      'binPath= "${appPath.helperPath}"',
      'start= auto',
      '&&',
      'sc',
      'start',
      appHelperService,
    ].join(' ');

    final res = runas('cmd.exe', command);

    await Future.delayed(
      Duration(milliseconds: 300),
    );

    return res;
  }

  Future<bool> registerTask(String appName) async {
    final taskXml = '''
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Principals>
    <Principal id="Author">
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Triggers>
    <LogonTrigger/>
  </Triggers>
  <Settings>
    <MultipleInstancesPolicy>Parallel</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>false</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT72H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>"${Platform.resolvedExecutable}"</Command>
    </Exec>
  </Actions>
</Task>''';
    final taskPath = join(await appPath.tempPath, 'task.xml');
    await File(taskPath).create(recursive: true);
    await File(taskPath)
        .writeAsBytes(taskXml.encodeUtf16LeWithBom, flush: true);
    final commandLine = [
      '/Create',
      '/TN',
      appName,
      '/XML',
      '%s',
      '/F',
    ].join(' ');
    return runas(
      'schtasks',
      commandLine.replaceFirst('%s', taskPath),
    );
  }

  /// 取消 Windows 任务计划中的开机自启动任务
  Future<bool> unregisterTask(String appName) async {
    final commandLine = [
      '/Delete',
      '/TN',
      appName,
      '/F',
    ].join(' ');
    return runas(
      'schtasks',
      commandLine,
    );
  }
}

final windows = system.isWindows ? Windows() : null;

class MacOS {
  static MacOS? _instance;

  List<String>? originDns;

  MacOS._internal();

  factory MacOS() {
    _instance ??= MacOS._internal();
    return _instance!;
  }

  Future<String?> get defaultServiceName async {
    final result = await Process.run('route', ['-n', 'get', 'default']);
    final output = result.stdout.toString();
    final deviceLine = output
        .split('\n')
        .firstWhere((s) => s.contains('interface:'), orElse: () => '');
    final lineSplits = deviceLine.trim().split(' ');
    if (lineSplits.length != 2) {
      return null;
    }
    final device = lineSplits[1];
    final serviceResult = await Process.run(
      'networksetup',
      ['-listnetworkserviceorder'],
    );
    final serviceResultOutput = serviceResult.stdout.toString();
    final currentService = serviceResultOutput.split('\n\n').firstWhere(
          (s) => s.contains('Device: $device'),
          orElse: () => '',
        );
    if (currentService.isEmpty) {
      return null;
    }
    final currentServiceNameLine = currentService.split('\n').firstWhere(
        (line) => RegExp(r'^\(\d+\).*').hasMatch(line),
        orElse: () => '');
    final currentServiceNameLineSplits =
        currentServiceNameLine.trim().split(' ');
    if (currentServiceNameLineSplits.length < 2) {
      return null;
    }
    return currentServiceNameLineSplits[1];
  }

  Future<List<String>?> get systemDns async {
    final deviceServiceName = await defaultServiceName;
    if (deviceServiceName == null) {
      return null;
    }
    final result = await Process.run(
      'networksetup',
      ['-getdnsservers', deviceServiceName],
    );
    final output = result.stdout.toString().trim();
    if (output.startsWith("There aren't any DNS Servers set on")) {
      originDns = [];
    } else {
      originDns = output.split('\n');
    }
    return originDns;
  }

  Future<void> updateDns(bool restore) async {
    final serviceName = await defaultServiceName;
    if (serviceName == null) {
      return;
    }
    List<String>? nextDns;
    if (restore) {
      nextDns = originDns;
    } else {
      final originDns = await systemDns;
      if (originDns == null) {
        return;
      }
      final needAddDns = '223.5.5.5';
      if (originDns.contains(needAddDns)) {
        return;
      }
      nextDns = List.from(originDns)..add(needAddDns);
    }
    if (nextDns == null) {
      return;
    }
    await Process.run(
      'networksetup',
      [
        '-setdnsservers',
        serviceName,
        if (nextDns.isNotEmpty) ...nextDns,
        if (nextDns.isEmpty) 'Empty',
      ],
    );
  }
}

final macOS = system.isMacOS ? MacOS() : null;
