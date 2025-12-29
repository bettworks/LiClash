# 基于Stelliberty的Windows平台优化方案

## 一、Stelliberty核心优势分析

### 1.1 Windows服务架构

**Stelliberty的服务架构：**
- **独立服务进程**：`stelliberty-service`作为Windows服务运行
- **IPC通信**：通过Named Pipe进行主程序与服务通信
- **心跳机制**：70秒超时，超时后只停止Clash核心，服务继续运行
- **系统休眠检测**：自动检测系统休眠唤醒并重置心跳

**关键代码位置：**
- `native/stelliberty_service/src/service/runner.rs` - 服务运行逻辑
- `native/stelliberty_service/src/service/handler.rs` - IPC命令处理
- `native/stelliberty_service/src/service/installer.rs` - 服务安装/卸载

### 1.2 进程管理优化

**Stelliberty的进程管理：**
```rust
// 使用Job Object确保子进程跟随父进程终止
let job_handle = CreateJobObjectW(ptr::null_mut(), ptr::null());
job_info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;

// 隐藏窗口
CREATE_NO_WINDOW | CREATE_SUSPENDED
startup_info.wShowWindow = SW_HIDE as u16;
```

**优势：**
- ✅ 使用Job Object，确保进程树正确清理
- ✅ 使用`CREATE_NO_WINDOW`标志，完全隐藏CMD窗口
- ✅ 使用`CREATE_SUSPENDED`创建后恢复，确保Job Object绑定成功

### 1.3 权限检查

**Stelliberty的权限检查：**
```dart
// 使用 net session 命令检查管理员权限
final result = await Process.run('net', ['session'], runInShell: true);
_isElevated = result.exitCode == 0;
```

**优势：**
- ✅ 简单可靠，`net session`只有管理员能执行
- ✅ 不依赖服务状态，更直接

### 1.4 开机自启动

**Stelliberty的实现：**
- Windows: 使用任务计划程序（Task Scheduler）
- 支持5秒延迟启动（避免Win11启动延迟）
- 使用`RunLevel: LeastPrivilege`（普通权限）或`HighestAvailable`（管理员权限）
- 通过`ShellExecuteW`触发UAC提升权限

**关键特性：**
- ✅ 支持延迟启动（`<Delay>PT5S</Delay>`）
- ✅ 支持静默启动参数（`--silent-start`）
- ✅ 状态验证带重试机制（最多10次）

### 1.5 端口管理

**Stelliberty的端口管理：**
- 启动前检查端口占用
- 自动清理占用端口的进程
- 使用netstat缓存优化性能（100ms缓存）
- 支持批量端口检查

## 二、LiClash优化方案

### 2.1 进程管理优化（高优先级）

**问题：** 当前使用`Process.start()`会显示CMD黑框

**解决方案：** 参考Stelliberty，使用Win32 API创建进程

**实现位置：** `lib/clash/service.dart`

**修改方案：**

#### 方案A：修改Dart代码使用Win32 API（推荐）

创建新文件 `lib/common/process_windows.dart`：

```dart
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class ProcessWindows {
  static Future<Process> startHidden(
    String executable,
    List<String> arguments,
  ) async {
    // 使用Win32 API创建隐藏进程
    // 参考Stelliberty的Rust实现
    // 需要调用CreateProcessW with CREATE_NO_WINDOW
  }
}
```

#### 方案B：通过Helper服务启动（已实现，但需优化）

当前实现已支持，但需要：
1. 确保Helper服务始终可用
2. 优化服务启动逻辑
3. 添加服务状态检查

### 2.2 权限检查优化

**当前问题：** 通过服务状态判断，可能不够准确

**优化方案：** 参考Stelliberty使用`net session`

**修改位置：** `lib/common/system.dart:44`

```dart
Future<bool> checkIsAdmin() async {
  if (system.isWindows) {
    // 方案1：使用net session（推荐）
    try {
      final result = await Process.run('net', ['session'], runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
    
    // 方案2：保留原有服务检查作为备用
    // final result = await windows?.checkService();
    // return result == WindowsHelperServiceStatus.running;
  }
  // ...
}
```

### 2.3 开机自启动优化

**当前问题：** 管理员自启动功能未接入UI

**优化方案：** 参考Stelliberty的实现

**需要修改：**

1. **添加配置字段** (`lib/models/config.dart`):
```dart
@freezed
class AppSettingProps with _$AppSettingProps {
  const factory AppSettingProps({
    // ... 现有字段
    @Default(false) bool adminAutoLaunch,  // 新增
  }) = _AppSettingProps;
}
```

2. **实现UI组件** (`lib/views/application_setting.dart`):
```dart
class AdminAutoLaunchItem extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adminAutoLaunch = ref.watch(
      appSettingProvider.select((state) => state.adminAutoLaunch),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.adminAutoLaunch),
      subtitle: Text(appLocalizations.adminAutoLaunchDesc),
      delegate: SwitchDelegate(
        value: adminAutoLaunch,
        onChanged: (bool value) async {
          if (value) {
            // 检查是否有管理员权限
            final isAdmin = await system.checkIsAdmin();
            if (!isAdmin) {
              // 请求管理员权限
              final code = await system.authorizeCore();
              if (code != AuthorizeCode.success) {
                return; // 权限获取失败
              }
            }
            // 注册任务计划
            final success = await windows?.registerTask(appName);
            if (success) {
              ref.read(appSettingProvider.notifier).updateState(
                (state) => state.copyWith(adminAutoLaunch: true),
              );
            }
          } else {
            // 删除任务计划
            // 需要实现deleteTask方法
            ref.read(appSettingProvider.notifier).updateState(
              (state) => state.copyWith(adminAutoLaunch: false),
            );
          }
        },
      ),
    );
  }
}
```

3. **优化任务计划配置** (`lib/common/system.dart:258`):

参考Stelliberty，添加延迟启动和静默启动：

```dart
Future<bool> registerTask(String appName) async {
  final taskXml = '''
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>LiClash开机自启动（管理员模式）</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <Delay>PT5S</Delay>  <!-- 5秒延迟，避免Win11启动延迟 -->
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>  <!-- 管理员权限 -->
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
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
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>4</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>"${Platform.resolvedExecutable}"</Command>
      <Arguments>--silent-start</Arguments>  <!-- 静默启动参数 -->
    </Exec>
  </Actions>
</Task>''';
  // ... 其余代码
}
```

4. **添加删除任务方法**:

```dart
Future<bool> deleteTask(String appName) async {
  final command = '/delete /tn $appName /f';
  return runas('schtasks', command);
}
```

### 2.4 Helper服务优化

**当前问题：** Helper服务功能简单，缺少心跳和状态管理

**优化方案：** 参考Stelliberty的服务架构

**需要增强的功能：**

1. **心跳机制** (`services/helper/src/service/hub.rs`):
```rust
// 添加心跳超时检测
const HEARTBEAT_TIMEOUT: Duration = Duration::from_secs(70);
const CHECK_INTERVAL: Duration = Duration::from_secs(30);

// 心跳超时后只停止核心，服务继续运行
if elapsed > HEARTBEAT_TIMEOUT {
    // 停止Clash核心，但服务继续运行等待重连
    stop();
}
```

2. **系统休眠检测**:
```rust
// 检测系统休眠唤醒
let check_elapsed = now.duration_since(last_check_time);
if check_elapsed > Duration::from_secs(60) {
    // 重置心跳计时器
    last_heartbeat = Instant::now();
}
```

3. **IPC协议增强**:
- 添加心跳命令
- 添加状态查询命令
- 添加日志流命令

### 2.5 TUN接口清理优化

**当前问题：** 缺少TUN接口清理机制

**优化方案：** 参考Stelliberty的进程管理

**实现建议：**

1. **启动前清理** (`lib/clash/service.dart`):
```dart
Future<void> _cleanupTunInterfaces() async {
  if (!system.isWindows) return;
  
  try {
    // 通过PowerShell删除残留的TUN适配器
    final result = await Process.run('powershell', [
      '-Command',
      '''
      Get-NetAdapter | Where-Object {
        $_.Name -like "*TUN*" -or 
        $_.Name -like "*Wintun*" -or
        $_.Name -like "*Clash*"
      } | Remove-NetAdapter -Confirm:$false
      '''
    ]);
  } catch (e) {
    commonPrint.log('清理TUN接口失败: $e');
  }
}
```

2. **停止时清理**:
在`shutdown()`方法中添加TUN清理逻辑

### 2.6 端口管理优化

**当前问题：** 缺少端口占用检查和清理

**优化方案：** 参考Stelliberty的端口管理

**实现位置：** `lib/clash/service.dart`

```dart
Future<void> _ensurePortsAvailable(List<int> ports) async {
  // 批量检查端口
  final portStatus = await _checkMultiplePorts(ports);
  
  for (final port in ports) {
    if (portStatus[port] == true) {
      // 端口被占用，尝试清理
      await _killProcessUsingPort(port);
      await _waitForPortRelease(port);
    }
  }
}

Future<void> _killProcessUsingPort(int port) async {
  // 使用netstat查找占用端口的进程
  final result = await Process.run('netstat', ['-ano']);
  // 解析PID并终止进程
  // ...
}
```

## 三、实施优先级

### 高优先级（立即实施）

1. ✅ **进程管理优化** - 解决CMD黑框问题
2. ✅ **权限检查优化** - 使用`net session`
3. ✅ **开机自启动UI** - 接入管理员自启动功能

### 中优先级（近期实施）

4. ⚠️ **Helper服务增强** - 添加心跳和状态管理
5. ⚠️ **端口管理** - 添加端口检查和清理
6. ⚠️ **TUN清理** - 启动前清理残留接口

### 低优先级（长期优化）

7. 📋 **服务架构重构** - 参考Stelliberty的完整服务架构
8. 📋 **IPC协议增强** - 添加更多命令和状态查询

## 四、代码修改清单

### 4.1 立即修改的文件

1. `lib/common/system.dart`
   - 修改`checkIsAdmin()`使用`net session`
   - 优化`registerTask()`添加延迟和静默启动
   - 添加`deleteTask()`方法

2. `lib/models/config.dart`
   - 添加`adminAutoLaunch`字段

3. `lib/views/application_setting.dart`
   - 添加`AdminAutoLaunchItem`组件

4. `lib/controller.dart`
   - 添加`updateAdminAutoLaunch()`方法

### 4.2 可选修改的文件

5. `lib/clash/service.dart`
   - 添加端口检查和清理
   - 添加TUN接口清理

6. `services/helper/src/service/hub.rs`
   - 添加心跳机制
   - 添加系统休眠检测

## 五、测试要点

1. **进程管理测试**
   - ✅ 验证无CMD黑框
   - ✅ 验证进程正确终止
   - ✅ 验证Job Object工作正常

2. **权限检查测试**
   - ✅ 管理员权限正确检测
   - ✅ 普通用户权限正确检测

3. **开机自启动测试**
   - ✅ 普通自启动功能正常
   - ✅ 管理员自启动功能正常
   - ✅ 延迟启动正常工作
   - ✅ 静默启动正常工作

4. **TUN功能测试**
   - ✅ TUN接口创建成功
   - ✅ 残留接口正确清理
   - ✅ IP地址冲突处理

## 六、注意事项

1. **向后兼容**：确保现有配置和功能不受影响
2. **错误处理**：所有新功能都要有完善的错误处理
3. **日志记录**：关键操作都要记录日志
4. **用户体验**：权限请求要有清晰的提示

