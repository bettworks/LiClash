# Windows平台实现分析

## 1. 虚拟网卡（TUN）服务实现

### 1.1 核心实现位置

#### Go内核层（core/）
- **`core/Clash.Meta/listener/sing_tun/server_windows.go`**
  - Windows平台TUN接口创建
  - 使用`github.com/metacubex/sing-tun`库
  - 重试机制：最多重试3次，处理"文件已存在"错误
  - Windows 10以下版本强制绑定接口

- **`core/Clash.Meta/listener/listener.go`**
  - `ReCreateTun()`: 重新创建TUN监听器
  - 配置变更时自动重建TUN接口

#### 配置层
- TUN配置通过`ClashConfig.tun`传递
- 关键参数：
  - `enable`: 是否启用TUN
  - `device`: 设备名称（Windows下自动生成，如`tun0`, `tun1`）
  - `stack`: 协议栈类型（system/gvisor）
  - `autoRoute`: 自动路由（Windows下通常为false）
  - `dnsHijack`: DNS劫持配置

### 1.2 管理员权限要求

**Windows平台TUN需要管理员权限的原因：**
- 创建虚拟网络适配器需要系统级权限
- 修改路由表需要管理员权限
- DNS劫持需要修改系统网络配置

**权限检查流程：**
```dart
// lib/controller.dart:276
Future<Result<bool>> _requestAdmin(bool enableTun) async {
  final realTunEnable = _ref.read(realTunEnableProvider);
  if (enableTun != realTunEnable && realTunEnable == false) {
    final code = await system.authorizeCore();  // 请求管理员权限
    // ...
  }
}
```

## 2. 开机启动实现

### 2.1 普通自启动（非管理员）

**实现位置：`lib/common/launch.dart`**

使用`launch_at_startup`插件：
- Windows: 通过注册表`HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run`
- 实现简单，但**无法以管理员权限启动**

```dart
class AutoLaunch {
  Future<bool> enable() async {
    return await launchAtStartup.enable();
  }
  
  Future<bool> disable() async {
    return await launchAtStartup.disable();
  }
}
```

### 2.2 管理员自启动

**实现位置：`lib/common/system.dart:258`**

使用**Windows任务计划程序（Task Scheduler）**：

```dart
Future<bool> registerTask(String appName) async {
  // 创建任务XML配置
  final taskXml = '''
  <Task version="1.3">
    <Principals>
      <Principal id="Author">
        <LogonType>InteractiveToken</LogonType>
        <RunLevel>HighestAvailable</RunLevel>  // 关键：以最高权限运行
      </Principal>
    </Principals>
    <Triggers>
      <LogonTrigger/>  // 登录时触发
    </Triggers>
    <Actions>
      <Exec>
        <Command>"${Platform.resolvedExecutable}"</Command>
      </Exec>
    </Actions>
  </Task>''';
  
  // 通过schtasks命令注册任务
  return runas('schtasks', '/Create /TN $appName /XML $taskPath /F');
}
```

**关键点：**
- `<RunLevel>HighestAvailable</RunLevel>`: 以最高可用权限运行（管理员）
- `<LogonTrigger/>`: 用户登录时触发
- 使用`runas`函数通过UAC提升权限注册任务

**注意：** 代码中定义了`registerTask`方法，但**未找到调用位置**。

**实际状态：**
- ✅ `registerTask`方法已实现（`lib/common/system.dart:258`）
- ❌ UI中**没有**管理员自启动选项
- ✅ 只有普通自启动选项（`AutoLaunchItem`在`lib/views/application_setting.dart:83`）
- ❌ 配置模型中**没有**`adminAutoLaunch`字段（只有`autoLaunch`）

**结论：** 管理员自启动功能**代码已实现但未接入UI**，需要：
1. 在`AppSettingProps`中添加`adminAutoLaunch`字段
2. 在`application_setting.dart`中添加`AdminAutoLaunchItem`组件
3. 在`controller.dart`中实现`updateAdminAutoLaunch`方法调用`registerTask`

## 3. 管理员权限处理

### 3.1 权限检查

**实现位置：`lib/common/system.dart:44`**

```dart
Future<bool> checkIsAdmin() async {
  if (system.isWindows) {
    // 通过检查Helper服务状态判断是否有管理员权限
    final result = await windows?.checkService();
    return result == WindowsHelperServiceStatus.running;
  }
  // macOS/Linux通过检查文件权限...
}
```

**Windows检查逻辑：**
- 检查`LiClashHelperService`服务是否运行
- 如果服务运行且可ping通，说明有管理员权限

### 3.2 权限提升

**实现位置：`lib/common/system.dart:67`**

```dart
Future<AuthorizeCode> authorizeCore() async {
  if (system.isWindows) {
    // 注册并启动Helper服务
    final result = await windows?.registerService();
    if (result == true) {
      return AuthorizeCode.success;
    }
    return AuthorizeCode.error;
  }
  // ...
}
```

**Windows权限提升流程：**

1. **注册Helper服务** (`registerService()`):
   ```dart
   // 通过sc命令创建Windows服务
   sc create LiClashHelperService binPath= "helper.exe路径" start= auto
   sc start LiClashHelperService
   ```

2. **使用ShellExecuteW提升权限**:
   ```dart
   bool runas(String command, String arguments) {
     // 调用ShellExecuteW，operation="runas"触发UAC
     shellExecute(
       nullptr,
       'runas',  // 关键：触发UAC提升
       commandPtr,
       argumentsPtr,
       nullptr,
       1,  // SW_SHOWNORMAL
     );
   }
   ```

### 3.3 Helper服务（Rust实现）

**位置：`services/helper/`**

**功能：**
- 以Windows服务形式运行（需要管理员权限）
- 提供HTTP API（端口47890）供主程序调用
- 启动/停止核心进程（`core.exe`）
- 验证可执行文件SHA256（安全机制）

**服务注册：**
```rust
// services/helper/src/service/windows.rs
const SERVICE_NAME: &str = "LiClashHelperService";

pub fn start_service() -> Result<()> {
    service_dispatcher::start(SERVICE_NAME, serveice)
}
```

**API端点：**
- `GET /ping`: 检查服务状态
- `POST /start`: 启动核心进程（验证SHA256）
- `POST /stop`: 停止核心进程
- `GET /logs`: 获取日志

**安全机制：**
```rust
// 验证请求的可执行文件SHA256
fn start(start_params: StartParams) -> impl Reply {
    let sha256 = sha256_file(start_params.path.as_str())?;
    if sha256 != env!("TOKEN") {  // 编译时注入的SHA256
        return "SHA256 mismatch";
    }
    // 启动进程...
}
```

## 4. CMD黑框问题

### 4.1 问题来源

**核心进程启动方式：**

1. **通过Helper服务启动**（管理员模式）:
   ```dart
   // lib/clash/service.dart:89
   if (system.isWindows && await system.checkIsAdmin()) {
     final isSuccess = await request.startCoreByHelper(arg);
     if (isSuccess) {
       return;  // 通过服务启动，无黑框
     }
   }
   ```

2. **直接启动进程**（非管理员模式）:
   ```dart
   // lib/clash/service.dart:95
   process = await Process.start(
     appPath.corePath,
     [arg],
   );
   // 问题：Dart的Process.start会显示CMD窗口
   ```

### 4.2 解决方案

#### Go内核层隐藏窗口

**位置：`core/Clash.Meta/common/cmd/cmd_windows.go`**

```go
func prepareBackgroundCommand(cmd *exec.Cmd) {
    cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
}
```

**说明：**
- 这是Go内核内部执行命令时使用的
- 仅对内核内部命令有效（如iptables等）
- **不影响主进程启动**

#### Rust Helper服务启动

**位置：`services/helper/src/service/hub.rs:48`**

```rust
match Command::new(&start_params.path)
    .stderr(Stdio::piped())  // 重定向stderr
    .arg(&start_params.arg)
    .spawn()
{
    Ok(child) => {
        // 后台启动，无窗口
    }
}
```

**说明：**
- Rust的`Command::spawn()`默认不显示窗口
- 通过Helper服务启动时**无黑框**

#### 直接启动的问题

**问题代码：`lib/clash/service.dart:95`**

```dart
process = await Process.start(
  appPath.corePath,
  [arg],
);
```

**问题：**
- Dart的`Process.start()`在Windows上会显示CMD窗口
- 没有设置`CREATE_NO_WINDOW`标志

**解决方案（需要修改）：**

Windows平台需要隐藏窗口，可以：

1. **使用Win32 API**（推荐）:
   ```dart
   import 'package:win32/win32.dart';
   
   final process = await Process.start(
     appPath.corePath,
     [arg],
     mode: ProcessStartMode.detached,
   );
   
   // 获取进程句柄并隐藏窗口
   // 需要调用Win32 API设置CREATE_NO_WINDOW
   ```

2. **通过Helper服务启动**（已实现）:
   - 确保Helper服务运行
   - 所有启动都通过Helper服务

3. **修改Go核心**:
   - 在Go程序入口设置`CREATE_NO_WINDOW`
   - 需要修改`core/main.go`或添加Windows特定代码

### 4.3 当前实现状态

**有管理员权限时：**
- ✅ 通过Helper服务启动 → **无黑框**

**无管理员权限时：**
- ❌ 直接启动进程 → **有黑框**

## 5. 完整启动流程

### 5.1 普通启动（无TUN）

```
用户启动应用
  ↓
检查管理员权限 (checkIsAdmin)
  ↓ (无权限)
直接启动核心进程 (Process.start)
  ↓
显示CMD黑框 ❌
```

### 5.2 管理员启动（启用TUN）

```
用户启动应用
  ↓
检查管理员权限 (checkIsAdmin)
  ↓ (无权限)
请求管理员权限 (authorizeCore)
  ↓
注册Helper服务 (registerService)
  ↓ (通过UAC)
Helper服务运行
  ↓
通过Helper服务启动核心 (startCoreByHelper)
  ↓
无CMD黑框 ✅
```

### 5.3 开机自启动

**普通自启动：**
```
系统登录
  ↓
注册表启动项 (launch_at_startup)
  ↓
启动应用（普通权限）
  ↓
如果启用TUN → 需要手动授权
```

**管理员自启动（未完全实现）：**
```
系统登录
  ↓
任务计划程序触发 (registerTask)
  ↓
以管理员权限启动应用
  ↓
自动启用TUN ✅
```

## 6. 待优化点

1. **CMD黑框问题**:
   - 非管理员模式下仍有黑框
   - 需要修改`Process.start`或使用Helper服务

2. **管理员自启动**:
   - `registerTask`方法已实现但未找到调用位置
   - 需要完善UI设置和调用逻辑

3. **权限检查优化**:
   - 当前通过服务状态判断，可能不够准确
   - 可以添加更直接的权限检查方法

4. **错误处理**:
   - Helper服务启动失败时的降级处理
   - 权限获取失败的用户提示

