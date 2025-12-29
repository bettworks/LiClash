# Windows TUN接口问题解决方案

## 问题分析

### 问题1: TUN接口创建失败 - "set ipv4 address: The parameter is incorrect"

**错误信息：**
```
[APP] Start TUN listening error: configure tun interface: set ipv4 address: The parameter is incorrect.
```

**原因分析：**

1. **旧TUN接口未清理干净**
   - 之前的软件卸载不完整，残留的TUN接口占用IP地址
   - Windows网络适配器列表中可能还有旧的TUN设备

2. **IP地址冲突**
   - 默认IPv4地址：`172.19.0.1/30`（定义在`core/state/state.go:5`）
   - 如果系统中已有网络适配器使用相同网段，会导致冲突

3. **网络适配器状态异常**
   - TUN接口处于异常状态（禁用但未删除）
   - 系统网络配置损坏

### 问题2: TUN Monitor日志 - "default interface changed by monitor"

**日志信息：**
```
[TUN] default interface changed by monitor, => WLAN
```

**原因分析：**

查看代码`core/Clash.Meta/listener/sing_tun/server.go:291`：
```go
if options.AutoRoute || options.AutoDetectInterface {
    // 启动NetworkUpdateMonitor和DefaultInterfaceMonitor
}
```

查看`lib/models/clash_config.dart:209-212`：
```dart
return switch (system.isDesktop) {
  true => copyWith(
      autoRoute: true,  // Windows桌面端自动启用autoRoute
      routeAddress: [],
    ),
  // ...
};
```

**结论：**
- Windows平台（桌面端）**自动启用`autoRoute: true`**
- 当`autoRoute`为true时，会启动`DefaultInterfaceMonitor`
- Monitor会监听默认网络接口变化并输出日志
- **这是正常行为**，不是bug

## 解决方案

### 方案1: 清理残留的TUN接口（推荐）

#### 步骤1: 检查网络适配器

1. 打开**设备管理器**（`devmgmt.msc`）
2. 展开"网络适配器"
3. 查找名称包含以下关键词的适配器：
   - `Wintun`
   - `TUN`
   - `TAP`
   - `Clash`
   - `LiClash`
   - `mihomo`

#### 步骤2: 手动删除残留适配器

**方法A: 通过设备管理器**
1. 右键点击残留的TUN适配器
2. 选择"卸载设备"
3. 勾选"删除此设备的驱动程序软件"（如果有）
4. 点击"卸载"

**方法B: 通过PowerShell（管理员权限）**
```powershell
# 列出所有网络适配器
Get-NetAdapter | Where-Object {$_.Name -like "*TUN*" -or $_.Name -like "*Wintun*"}

# 删除特定适配器（替换AdapterName为实际名称）
Remove-NetAdapter -Name "AdapterName" -Confirm:$false
```

**方法C: 通过命令行（管理员权限）**
```cmd
# 列出所有适配器
netsh interface show interface

# 删除特定适配器（替换"AdapterName"为实际名称）
netsh interface delete interface "AdapterName"
```

#### 步骤3: 清理网络配置

```cmd
# 刷新DNS缓存
ipconfig /flushdns

# 重置网络配置（谨慎使用，可能需要重启）
netsh winsock reset
netsh int ip reset
```

#### 步骤4: 重启网络服务

```cmd
# 停止网络服务
net stop netprofm
net stop nsi

# 启动网络服务
net start nsi
net start netprofm
```

### 方案2: 修改默认IP地址（如果方案1无效）

如果默认IP地址`172.19.0.1/30`与系统冲突，可以修改：

**修改位置：`core/state/state.go`**

```go
// 原代码
var DefaultIpv4Address = "172.19.0.1/30"

// 可以改为其他私有网段，例如：
var DefaultIpv4Address = "172.20.0.1/30"  // 或其他未使用的网段
```

**注意：** 修改后需要重新编译Go核心。

### 方案3: 禁用TUN Monitor日志（可选）

如果不想看到monitor日志，可以修改代码：

**修改位置：`core/Clash.Meta/listener/sing_tun/server.go:316`**

```go
// 原代码
defaultInterfaceMonitor.RegisterCallback(func(defaultInterface *control.Interface, event int) {
    if defaultInterface != nil {
        log.Warnln("[TUN] default interface changed by monitor, => %s", defaultInterface.Name)
    } else {
        log.Errorln("[TUN] default interface lost by monitor")
    }
    // ...
})

// 修改为（降低日志级别或移除）
defaultInterfaceMonitor.RegisterCallback(func(defaultInterface *control.Interface, event int) {
    if defaultInterface != nil {
        log.Debugln("[TUN] default interface changed by monitor, => %s", defaultInterface.Name)  // Warn改为Debug
    } else {
        log.Warnln("[TUN] default interface lost by monitor")  // Error改为Warn
    }
    // ...
})
```

**注意：** 这会降低日志级别，但monitor功能仍然运行。

### 方案4: 禁用AutoRoute（不推荐）

如果确实不需要monitor，可以修改Windows平台的autoRoute默认值：

**修改位置：`lib/models/clash_config.dart:209`**

```dart
return switch (system.isDesktop) {
  true => copyWith(
      autoRoute: false,  // 改为false，禁用自动路由
      routeAddress: [],
    ),
  // ...
};
```

**警告：** 禁用autoRoute可能导致路由功能异常，**不推荐**。

## 验证步骤

### 1. 验证TUN接口已清理

```powershell
# 检查是否还有残留的TUN适配器
Get-NetAdapter | Where-Object {$_.Name -like "*TUN*" -or $_.Name -like "*Wintun*"}
```

应该返回空结果。

### 2. 验证IP地址未被占用

```cmd
# 检查172.19.0.1是否被占用
ping 172.19.0.1

# 检查路由表
route print | findstr "172.19"
```

### 3. 重新启动应用

1. 完全退出LiClash
2. 以**管理员权限**重新启动
3. 启用TUN功能
4. 检查日志是否还有错误

## 预防措施

### 1. 正确卸载软件

卸载LiClash时：
1. 先停止TUN功能
2. 等待几秒让系统清理
3. 再卸载软件

### 2. 定期清理

如果频繁遇到问题，可以创建清理脚本：

**`cleanup_tun.ps1`**（需要管理员权限）：
```powershell
# 停止所有相关进程
Get-Process | Where-Object {$_.ProcessName -like "*clash*" -or $_.ProcessName -like "*liclash*"} | Stop-Process -Force

# 删除TUN适配器
Get-NetAdapter | Where-Object {$_.Name -like "*TUN*" -or $_.Name -like "*Wintun*"} | Remove-NetAdapter -Confirm:$false

# 刷新DNS
ipconfig /flushdns

Write-Host "清理完成！"
```

## 常见问题

### Q: 为什么Windows会自动启用autoRoute？

**A:** 这是设计决策，因为Windows桌面端通常需要自动路由功能。代码在`lib/models/clash_config.dart:209`中硬编码了`autoRoute: true`。

### Q: Monitor日志会影响性能吗？

**A:** 不会。Monitor只是监听网络接口变化，日志输出对性能影响可忽略。

### Q: 可以完全禁用Monitor吗？

**A:** 可以，但不推荐。Monitor用于检测网络变化并自动调整路由，禁用可能导致网络切换时出现问题。

### Q: 修改代码后如何重新编译？

**A:** 
1. 修改Go代码后，运行`dart setup.dart windows --arch amd64`（或arm64）
2. 这会重新编译Go核心并打包应用

## 总结

1. **TUN创建失败**：主要是旧接口未清理，按方案1清理即可
2. **Monitor日志**：这是正常功能，不是bug，可以忽略或降低日志级别
3. **最佳实践**：卸载前先停止TUN，定期清理残留适配器

