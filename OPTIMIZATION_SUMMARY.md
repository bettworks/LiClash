# Windows平台优化实施总结

## 已完成的优化

### 1. ✅ 权限检查优化

**修改文件：** `lib/common/system.dart`

**改进内容：**
- 优先使用`net session`命令检查管理员权限（更直接可靠）
- 保留服务状态检查作为备用方案
- 参考Stelliberty的实现方式

**代码变更：**
```dart
Future<bool> checkIsAdmin() async {
  if (system.isWindows) {
    // 优先使用 net session 检查（更直接可靠）
    try {
      final result = await Process.run('net', ['session'], runInShell: true);
      if (result.exitCode == 0) {
        return true;
      }
    } catch (_) {
      // net session 失败，回退到服务检查
    }
    // 备用方案：检查Helper服务状态
    final result = await windows?.checkService();
    return result == WindowsHelperServiceStatus.running;
  }
  // ...
}
```

### 2. ✅ 开机自启动优化

**修改文件：** `lib/common/system.dart`

**改进内容：**
- 添加任务计划描述信息
- 添加5秒延迟启动（避免Win11启动延迟）
- 添加静默启动参数（`--silent-start`）
- 优化任务计划配置（参考Stelliberty）
- 新增`deleteTask()`和`isTaskExists()`方法

**关键改进：**
```xml
<RegistrationInfo>
  <Description>LiClash开机自启动（管理员模式）</Description>
</RegistrationInfo>
<Triggers>
  <LogonTrigger>
    <Enabled>true</Enabled>
    <Delay>PT5S</Delay>  <!-- 5秒延迟 -->
  </LogonTrigger>
</Triggers>
<Actions Context="Author">
  <Exec>
    <Command>"${Platform.resolvedExecutable}"</Command>
    <Arguments>--silent-start</Arguments>  <!-- 静默启动 -->
  </Exec>
</Actions>
```

### 3. ✅ 管理员自启动UI接入

**修改文件：**
- `lib/models/config.dart` - 添加`adminAutoLaunch`字段
- `lib/views/application_setting.dart` - 添加`AdminAutoLaunchItem`组件

**功能特性：**
- 自动检查管理员权限
- 权限不足时自动请求提升
- 注册/删除任务计划
- 状态同步和错误处理

**UI位置：** 设置页面 → 应用设置 → 管理员自启动（仅在Windows显示）

## 待实施的优化

### 1. ⚠️ 进程管理优化（解决CMD黑框）

**问题：** 非管理员模式下启动核心进程会显示CMD黑框

**解决方案：**
- 方案A：修改Dart代码使用Win32 API创建隐藏进程
- 方案B：确保所有启动都通过Helper服务（已实现但需优化）

**优先级：** 高

**参考实现：** Stelliberty的`native/hub/src/clash/process.rs`

### 2. ⚠️ Helper服务增强

**需要添加：**
- 心跳机制（70秒超时）
- 系统休眠检测
- IPC协议增强（心跳、状态查询、日志流）

**优先级：** 中

**参考实现：** Stelliberty的`native/stelliberty_service/src/service/runner.rs`

### 3. ⚠️ 端口管理

**需要添加：**
- 启动前端口占用检查
- 自动清理占用端口的进程
- netstat缓存优化（100ms）

**优先级：** 中

**参考实现：** Stelliberty的`lib/clash/services/process_service.dart`

### 4. ⚠️ TUN接口清理

**需要添加：**
- 启动前清理残留TUN适配器
- 停止时清理TUN接口

**优先级：** 中

**实现位置：** `lib/clash/service.dart`

## 对比分析

### Stelliberty的优势

1. **服务架构更完善**
   - 独立服务进程，更好的权限管理
   - IPC通信更规范（Named Pipe）
   - 心跳机制确保服务稳定性

2. **进程管理更优雅**
   - 使用Job Object确保进程树清理
   - 使用`CREATE_NO_WINDOW`完全隐藏窗口
   - 使用`CREATE_SUSPENDED`确保Job Object绑定

3. **权限检查更直接**
   - 使用`net session`命令，简单可靠
   - 不依赖服务状态

4. **开机自启动更完善**
   - 支持延迟启动
   - 支持静默启动参数
   - 状态验证带重试机制

### LiClash的当前状态

1. **已实现：**
   - ✅ Helper服务基础功能
   - ✅ 权限检查和提升
   - ✅ 普通开机自启动
   - ✅ 管理员自启动代码（已接入UI）

2. **待优化：**
   - ⚠️ 进程管理（CMD黑框问题）
   - ⚠️ Helper服务功能增强
   - ⚠️ 端口管理
   - ⚠️ TUN接口清理

## 下一步行动

### 立即测试

1. **权限检查测试**
   ```dart
   // 测试net session检查
   final isAdmin = await system.checkIsAdmin();
   ```

2. **管理员自启动测试**
   - 在设置中启用"管理员自启动"
   - 验证任务计划是否正确创建
   - 重启电脑验证是否自动启动

3. **任务计划验证**
   ```powershell
   # 查看任务
   schtasks /query /tn LiClash
   
   # 测试运行
   schtasks /run /tn LiClash
   ```

### 后续优化

1. **进程管理优化** - 解决CMD黑框问题
2. **Helper服务增强** - 添加心跳和状态管理
3. **端口管理** - 添加端口检查和清理
4. **TUN清理** - 启动前清理残留接口

## 注意事项

1. **向后兼容**：确保现有配置不受影响
2. **错误处理**：所有新功能都要有完善的错误处理
3. **用户体验**：权限请求要有清晰的提示
4. **测试覆盖**：关键功能都要充分测试

## 参考文档

- `STELLIBERTY_OPTIMIZATION_PLAN.md` - 详细优化方案
- `WINDOWS_PLATFORM_ANALYSIS.md` - Windows平台分析
- `WINDOWS_TUN_ISSUES_SOLUTION.md` - TUN问题解决方案

