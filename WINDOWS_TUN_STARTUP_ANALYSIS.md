# Windows 虚拟网卡服务启动速度分析

## 当前启动流程

### 1. 核心启动流程 (`lib/clash/service.dart` - `reStart()`)

```
reStart()
  ├─ 等待 ServerSocket 就绪 (serverCompleter.future)
  ├─ Windows 分支：
  │   ├─ registerService()  ← 关键路径
  │   │   ├─ checkService()  ← 检查服务状态
  │   │   │   ├─ Process.run('sc', ['query', ...])  ← ~50-100ms
  │   │   │   └─ pingHelper()  ← HTTP 请求，2秒超时
  │   │   ├─ _killProcess()  ← 杀死占用端口的进程
  │   │   ├─ runas('cmd.exe', 'sc create ... && sc start ...')  ← ~200-500ms
  │   │   └─ Future.delayed(300ms)  ← 固定延迟等待服务启动
  │   └─ startCoreByHelper(arg)  ← HTTP POST，2秒超时
  │       └─ Helper 服务内部：
  │           ├─ sha256_file()  ← 计算文件哈希
  │           └─ Command::new().spawn()  ← 启动核心进程
  └─ 非 Windows 或失败回退：Process.start()
```

### 2. 关键延迟点分析

#### 延迟点 1: `checkService()` - 串行检查
**位置**: `lib/common/system.dart:204-218`

```dart
Future<WindowsHelperServiceStatus> checkService() async {
  final result = await Process.run('sc', ['query', appHelperService]);  // ~50-100ms
  if (result.exitCode != 0) {
    return WindowsHelperServiceStatus.none;
  }
  final output = result.stdout.toString();
  if (output.contains('RUNNING') && await request.pingHelper()) {  // ~10-2000ms
    return WindowsHelperServiceStatus.running;
  }
  return WindowsHelperServiceStatus.presence;
}
```

**问题**:
- `sc query` 和 `pingHelper()` 是串行执行的
- `pingHelper()` 有 2 秒超时，即使服务已启动也可能等待较久
- 如果服务已经在运行，这两个检查都是不必要的

**优化潜力**: ⭐⭐⭐⭐⭐ (可节省 50-2000ms)

#### 延迟点 2: `registerService()` - 固定延迟
**位置**: `lib/common/system.dart:221-256`

```dart
Future<bool> registerService() async {
  final status = await checkService();  // 包含上述延迟
  
  if (status == WindowsHelperServiceStatus.running) {
    return true;  // 快速路径
  }
  
  await _killProcess(helperPort);  // ~50-200ms
  
  final res = runas('cmd.exe', command);  // ~200-500ms
  
  await Future.delayed(Duration(milliseconds: 300));  // 固定 300ms 延迟
  
  return res;
}
```

**问题**:
- 固定 300ms 延迟可能不够（服务未完全启动）或过多（服务已启动）
- 没有验证服务是否真正启动成功
- `_killProcess()` 可能不必要（如果端口未被占用）

**优化潜力**: ⭐⭐⭐⭐ (可节省 100-300ms)

#### 延迟点 3: `startCoreByHelper()` - HTTP 超时
**位置**: `lib/common/request.dart:155-181`

```dart
Future<bool> startCoreByHelper(String arg) async {
  final response = await _dio.post(
    'http://$localhost:$helperPort/start',
    ...
  ).timeout(Duration(milliseconds: 2000));  // 2秒超时
  ...
}
```

**问题**:
- 2 秒超时可能过长（本地服务通常 < 100ms）
- Helper 服务内部计算 SHA256 需要读取整个文件（可能较慢）

**优化潜力**: ⭐⭐⭐ (可节省 0-500ms，取决于网络和文件大小)

#### 延迟点 4: Helper 服务内部 - SHA256 计算
**位置**: `services/helper/src/service/hub.rs:20-34`

```rust
fn sha256_file(path: &str) -> Result<String, Error> {
  let mut file = File::open(path)?;
  let mut hasher = Sha256::new();
  let mut buffer = [0; 4096];
  // 读取整个文件计算哈希
  ...
}
```

**问题**:
- 每次启动都要读取整个核心文件（可能几十 MB）
- 如果文件很大，计算哈希需要较长时间

**优化潜力**: ⭐⭐⭐ (可节省 50-500ms，取决于文件大小)

## 优化方案

### 方案 1: 并行检查服务状态 ⭐⭐⭐⭐⭐

**当前**:
```dart
final result = await Process.run('sc', ['query', ...]);
if (output.contains('RUNNING') && await request.pingHelper()) {
  // 串行执行
}
```

**优化后**:
```dart
final futures = [
  Process.run('sc', ['query', appHelperService]),
  request.pingHelper(),
].wait();  // 并行执行

// 如果 sc query 显示 RUNNING 且 pingHelper 成功，直接返回
```

**预期收益**: 节省 50-2000ms（取决于 pingHelper 响应时间）

### 方案 2: 智能延迟替代固定延迟 ⭐⭐⭐⭐

**当前**:
```dart
await Future.delayed(Duration(milliseconds: 300));
return res;
```

**优化后**:
```dart
// 轮询检查服务是否真正启动（最多等待 1 秒，每次 50ms）
for (int i = 0; i < 20; i++) {
  await Future.delayed(Duration(milliseconds: 50));
  if (await request.pingHelper()) {
    return true;  // 服务已启动，立即返回
  }
}
return false;  // 超时
```

**预期收益**: 
- 如果服务快速启动（< 100ms）：节省 200ms
- 如果服务启动较慢（> 300ms）：可能增加等待时间，但更可靠

### 方案 3: 缓存服务状态 ⭐⭐⭐

**当前**: 每次启动都检查服务状态

**优化后**:
```dart
// 在应用启动时检查一次，缓存结果
// 如果服务已经在运行，后续启动直接跳过检查
static bool? _cachedServiceRunning;

Future<bool> registerService() async {
  if (_cachedServiceRunning == true) {
    // 快速路径：直接尝试启动核心
    return await request.startCoreByHelper(arg) != null;
  }
  // 否则执行完整检查流程
  ...
}
```

**预期收益**: 如果服务已运行，节省 50-2000ms

### 方案 4: 优化 HTTP 超时和连接 ⭐⭐⭐

**当前**:
```dart
.timeout(Duration(milliseconds: 2000))
```

**优化后**:
```dart
// 本地服务，使用更短的超时
.timeout(Duration(milliseconds: 500))
// 或者使用连接池、keep-alive
```

**预期收益**: 节省 0-500ms（取决于实际响应时间）

### 方案 5: 预计算或缓存 SHA256 ⭐⭐

**当前**: 每次启动都计算文件 SHA256

**优化后**:
- 在构建时或首次启动时计算并缓存 SHA256
- 或者使用文件修改时间 + 大小作为快速检查

**预期收益**: 节省 50-500ms（取决于文件大小）

### 方案 6: 跳过不必要的进程清理 ⭐⭐

**当前**: 总是执行 `_killProcess(helperPort)`

**优化后**:
```dart
// 先检查端口是否被占用
if (await isPortInUse(helperPort)) {
  await _killProcess(helperPort);
}
```

**预期收益**: 如果端口未被占用，节省 50-200ms

## 综合优化建议

### 优先级 1（高收益，易实现）:
1. **并行检查服务状态** - 预期节省 50-2000ms
2. **智能延迟替代固定延迟** - 预期节省 100-300ms
3. **缓存服务状态** - 预期节省 50-2000ms（如果服务已运行）

### 优先级 2（中等收益）:
4. **优化 HTTP 超时** - 预期节省 0-500ms
5. **跳过不必要的进程清理** - 预期节省 50-200ms

### 优先级 3（低优先级）:
6. **预计算 SHA256** - 预期节省 50-500ms，但实现复杂度较高

## 预期总体收益

如果实施优先级 1 的所有优化：
- **最佳情况**（服务已运行）: 节省 **200-2300ms** (0.2-2.3 秒)
- **一般情况**（服务未运行，需要注册）: 节省 **150-500ms** (0.15-0.5 秒)
- **最差情况**（服务启动较慢）: 节省 **100-300ms** (0.1-0.3 秒)

## 注意事项

1. **服务启动时间不稳定**: Windows 服务启动时间可能因系统负载而变化，智能延迟需要设置合理的上限
2. **并发安全**: 缓存服务状态需要考虑并发场景
3. **错误处理**: 优化后需要确保错误处理逻辑仍然正确
4. **测试覆盖**: 需要测试各种场景（服务已运行/未运行/启动失败等）

