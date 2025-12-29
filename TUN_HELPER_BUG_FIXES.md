# TUN 和 Helper 相关 Bug 修复

## 发现的 Bug 和修复

### 1. 进程终止顺序问题 ✅

**位置**: `services/helper/src/service/hub.rs` 和 `process.rs`

**问题**:
- 在 `kill()` 之后调用 `wait()`，但 `kill()` 已经关闭了 handle
- Windows 平台的 `wait()` 在 handle 已关闭时会失败

**修复**:
- 改为先尝试 `wait()`，如果失败再调用 `kill()`
- 在 `Drop` trait 中也使用相同的逻辑

```rust
// 修复前
handle.kill();
handle.wait(); // handle 已关闭，会失败

// 修复后
if handle.wait().is_err() {
    handle.kill(); // 只有在等待失败时才强制终止
}
```

### 2. 心跳重置的竞态条件 ✅

**位置**: `services/helper/src/service/hub.rs:57-59, 115-119`

**问题**:
- `tokio::spawn` 在同步函数中，但没有正确传递 `Arc` 引用
- 可能导致竞态条件

**修复**:
- 在 `spawn` 前克隆 `Arc`，确保异步任务有正确的所有权

```rust
// 修复前
tokio::spawn(async {
    *LAST_HEARTBEAT.write().await = Instant::now();
});

// 修复后
let last_heartbeat = Arc::clone(&LAST_HEARTBEAT);
tokio::spawn(async move {
    *last_heartbeat.write().await = Instant::now();
});
```

### 3. PowerShell 命令字符串转义问题 ✅

**位置**: `lib/common/tun_cleaner.dart:74-75`

**问题**:
- 适配器名称中的特殊字符可能导致 PowerShell 命令失败
- `$adapterName` 替换方式不安全

**修复**:
- 使用单引号包裹适配器名称，避免特殊字符问题
- 正确处理单引号转义（`'` -> `''`）

```dart
// 修复前
final command = 'Remove-NetAdapter -Name "$adapterName" -Confirm:\\\$false';
final finalCommand = command.replaceAll(r'$adapterName', adapterName);

// 修复后
final escapedName = adapterName.replaceAll("'", "''");
final command = "Remove-NetAdapter -Name '$escapedName' -Confirm:\\\$false";
```

### 4. PID 验证缺失 ✅

**位置**: `lib/common/port_manager.dart:136`

**问题**:
- 从 netstat 输出提取 PID 时没有验证是否为数字
- 如果格式异常，可能导致 `taskkill` 失败

**修复**:
- 添加 PID 数字验证
- 如果无效则跳过该行

```dart
// 修复前
final pid = parts.last;
await Process.run('taskkill', ['/F', '/PID', pid], ...);

// 修复后
final pidStr = parts.last;
final pid = int.tryParse(pidStr);
if (pid == null) {
  commonPrint.log('无效的 PID: $pidStr');
  continue;
}
await Process.run('taskkill', ['/F', '/PID', pid.toString()], ...);
```

### 5. 心跳错误处理缺失 ✅

**位置**: `lib/clash/service.dart:138-140`

**问题**:
- 心跳定时器中的异步操作没有错误处理
- 如果心跳失败，没有日志记录

**修复**:
- 添加 try-catch 错误处理
- 记录错误日志

```dart
// 修复前
_heartbeatTimer = Timer.periodic(
  const Duration(seconds: 30),
  (_) async {
    await request.sendHeartbeat();
  },
);

// 修复后
_heartbeatTimer = Timer.periodic(
  const Duration(seconds: 30),
  (_) async {
    try {
      await request.sendHeartbeat();
    } catch (e) {
      commonPrint.log('发送心跳失败: $e');
    }
  },
);
```

## 修复的文件

1. **`services/helper/src/service/hub.rs`**
   - 修复进程终止顺序
   - 修复心跳重置的竞态条件

2. **`services/helper/src/service/process.rs`**
   - 修复 Windows 平台 `wait()` 方法
   - 修复 `Drop` trait 中的终止逻辑

3. **`lib/common/tun_cleaner.dart`**
   - 修复 PowerShell 命令字符串转义

4. **`lib/common/port_manager.dart`**
   - 添加 PID 验证

5. **`lib/clash/service.dart`**
   - 添加心跳错误处理

## 测试建议

1. **进程终止测试**
   - 测试正常停止进程
   - 测试强制终止进程
   - 验证没有资源泄漏

2. **心跳机制测试**
   - 测试正常心跳
   - 测试心跳失败时的错误处理
   - 测试系统休眠唤醒后的心跳重置

3. **TUN 清理测试**
   - 测试包含特殊字符的适配器名称
   - 测试多个适配器的清理

4. **端口管理测试**
   - 测试正常端口检查
   - 测试异常 netstat 输出格式
   - 测试 PID 提取和验证

## 注意事项

- Windows 平台的进程管理需要特别注意 handle 的生命周期
- PowerShell 命令中的字符串需要正确转义
- 所有异步操作都应该有错误处理

