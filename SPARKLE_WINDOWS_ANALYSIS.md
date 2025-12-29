# Sparkle Windows 平台实现分析

## 概述

本文档详细分析 Sparkle 1.6.16 在 Windows 平台上关于虚拟网卡（TUN）启动、服务提权和开机启动等核心功能的实现逻辑。

---

## 1. 虚拟网卡（TUN）启动逻辑

### 1.1 TUN 配置管理

**位置**: `src/main/core/manager.ts`

**关键代码**:
```typescript
const { tun } = await getControledMihomoConfig()

// 启动前检查 TUN 配置
if (tun?.enable && autoSetDNSMode !== 'none') {
  try {
    await setPublicDNS()
  } catch (error) {
    // 记录错误但继续启动
  }
}
```

**特点**:
- TUN 配置存储在 `controledMihomoConfig` 中
- 支持 `enable`、`device`、`stack` 等配置项
- Windows 默认设备名称为 `mihomo`

### 1.2 TUN 启动流程

**位置**: `src/main/core/manager.ts` - `startCore()`

**流程**:
1. **生成配置文件**: `await generateProfile()` - 生成包含 TUN 配置的 mihomo 配置文件
2. **检查配置**: `await checkProfile()` - 验证配置文件有效性
3. **停止旧进程**: `await stopCore()` - 确保没有残留进程
4. **设置 DNS**（如果启用）: `await setPublicDNS()` - 仅在 macOS 上执行
5. **启动核心进程**: `spawn(corePath, [...])` - 使用 Node.js `spawn` 启动 mihomo 核心

**关键代码**:
```typescript
child = spawn(
  corePath,
  [
    '-d',
    diffWorkDir ? mihomoProfileWorkDir(current) : mihomoWorkDir(),
    ctlParam,  // Windows: '-ext-ctl-pipe'
    mihomoIpcPath()
  ],
  {
    detached: detached,
    stdio: detached ? 'ignore' : undefined,
    env: env
  }
)
```

### 1.3 TUN 权限错误处理

**位置**: `src/main/core/manager.ts` - `startCore()` 中的 stdout 监听

**关键代码**:
```typescript
if (
  logLine.includes(
    'Start TUN listening error: configure tun interface: Connect: operation not permitted'
  )
) {
  patchControledMihomoConfig({ tun: { enable: false } })
  mainWindow?.webContents.send('controledMihomoConfigUpdated')
  ipcMain.emit('updateTrayMenu')
  reject('虚拟网卡启动失败，前往内核设置页尝试手动授予内核权限')
}
```

**处理策略**:
- 检测到权限错误时，自动禁用 TUN
- 通知前端更新 UI
- 提示用户手动授予权限

### 1.4 Windows 特殊处理

**位置**: `src/main/index.ts`

**关键代码**:
```typescript
if (process.platform === 'win32' && is.dev) {
  patchControledMihomoConfig({ tun: { enable: false } })
}
```

**说明**: 开发模式下自动禁用 TUN，避免权限问题

---

## 2. 服务提权逻辑

### 2.1 提权方式选择

Sparkle 在 Windows 上支持两种提权模式：

#### 模式 1: Task Scheduler 提权（默认，非服务模式）

**位置**: `src/main/sys/misc.ts` - `createElevateTaskSync()`

**实现**:
```typescript
const elevateTaskXml = `<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Principals>
    <Principal id="Author">
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>  // 关键：最高权限
    </Principal>
  </Principals>
  <Actions Context="Author">
    <Exec>
      <Command>"${path.join(taskDir(), `sparkle-run.exe`)}"</Command>
      <Arguments>"${exePath()}"</Arguments>
    </Exec>
  </Actions>
</Task>`
```

**特点**:
- 使用 Windows Task Scheduler 创建提权任务
- 任务名: `sparkle-run`
- 通过 `sparkle-run.exe` 启动主程序（这是一个 UAC 提权包装器）
- 首次启动时自动创建任务

#### 模式 2: Windows 服务模式（可选）

**位置**: `src/main/service/manager.ts`

**实现**:
```typescript
export async function initService(): Promise<void> {
  const newKeyManager = new KeyManager()
  const keyPair = newKeyManager.generateKeyPair()
  initServiceAPI(newKeyManager)
  const publicKey = keyPair.publicKey
  const execPath = servicePath()
  
  // 使用提权执行服务初始化
  await execWithElevation(execPath, ['service', 'init', '--public-key', publicKey])
  
  await patchAppConfig({
    serviceAuthKey: `${keyPair.publicKey}:${keyPair.privateKey}`
  })
  
  keyManager = newKeyManager
}
```

**特点**:
- 使用独立的服务程序（`service.exe`）
- 通过 HTTP API（Unix Socket/命名管道）通信
- 使用 Ed25519 密钥对进行身份验证
- 服务运行在 SYSTEM 账户下，拥有最高权限

### 2.2 提权执行函数

**位置**: `src/main/utils/elevation.ts`

**实现**:
```typescript
export async function execWithElevation(command: string, args: string[]): Promise<void> {
  if (process.platform === 'win32') {
    try {
      if (await isRunningAsAdmin()) {
        // 已经是管理员，直接执行
        await execFilePromise(command, args, { timeout: 30000 })
      } else {
        // 不是管理员，使用 PowerShell 提权
        const psArgs = args
          .map((arg) => {
            const escaped = arg.replace(/'/g, "''")
            return `'${escaped}'`
          })
          .join(',')
        await execFilePromise(
          'powershell.exe',
          [
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-Command',
            `& { $p = Start-Process -FilePath '${command}' -ArgumentList @(${psArgs}) -Verb RunAs -WindowStyle Hidden -PassThru -Wait; exit $p.ExitCode }`
          ],
          { timeout: 30000 }
        )
      }
    } catch (error) {
      throw new Error(`Windows 提权执行失败：${error}`)
    }
  }
}
```

**关键点**:
- **检测管理员权限**: 使用 `net session` 命令检测
- **PowerShell 提权**: 使用 `Start-Process -Verb RunAs` 触发 UAC
- **隐藏窗口**: `-WindowStyle Hidden` 避免显示 CMD 黑框
- **等待完成**: `-PassThru -Wait` 确保命令执行完成

### 2.3 首次启动提权检查

**位置**: `src/main/index.ts`

**关键代码**:
```typescript
if (
  process.platform === 'win32' &&
  !is.dev &&
  !process.argv.includes('noadmin') &&
  syncConfig.corePermissionMode !== 'service'  // 非服务模式
) {
  try {
    createElevateTaskSync()  // 创建提权任务
  } catch (createError) {
    try {
      // 如果创建失败，尝试运行已存在的任务
      if (!existsSync(path.join(taskDir(), 'sparkle-run.exe'))) {
        throw new Error('sparkle-run.exe not found')
      } else {
        execSync('%SystemRoot%\\System32\\schtasks.exe /run /tn sparkle-run')
      }
    } catch (e) {
      dialog.showErrorBox('首次启动请以管理员权限运行', ...)
      app.exit()
    }
  }
}
```

**流程**:
1. 检查是否在 Windows 平台
2. 检查是否开发模式
3. 检查是否跳过管理员检查（`noadmin` 参数）
4. 检查是否使用服务模式
5. 尝试创建提权任务
6. 如果创建失败，尝试运行已存在的任务
7. 如果都失败，显示错误并退出

---

## 3. 开机启动逻辑

### 3.1 开机启动实现

**位置**: `src/main/sys/autoRun.ts`

**Windows 实现**:
```typescript
const taskXml = `<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <Delay>PT3S</Delay>  // 延迟 3 秒启动
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>  // 管理员权限
    </Principal>
  </Principals>
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
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>3</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>"${path.join(taskDir(), `sparkle-run.exe`)}"</Command>
      <Arguments>"${exePath()}"</Arguments>
    </Exec>
  </Actions>
</Task>`
```

**关键配置**:
- **触发器**: `LogonTrigger` - 用户登录时触发
- **延迟**: `PT3S` - 延迟 3 秒启动（避免系统启动时资源竞争）
- **权限**: `HighestAvailable` - 以最高可用权限运行（管理员）
- **启动器**: `sparkle-run.exe` - 提权包装器

### 3.2 启用开机启动

**实现**:
```typescript
export async function enableAutoRun(): Promise<void> {
  if (process.platform === 'win32') {
    const taskFilePath = path.join(taskDir(), `${appName}.xml`)
    // 写入 UTF-16LE BOM 编码的 XML 文件
    await writeFile(taskFilePath, Buffer.from(`\ufeff${taskXml}`, 'utf-16le'))
    // 使用提权执行创建任务
    await execWithElevation('schtasks.exe', [
      '/create',
      '/tn',
      `${appName}`,
      '/xml',
      `${taskFilePath}`,
      '/f'  // 强制覆盖已存在的任务
    ])
  }
}
```

**步骤**:
1. 生成 Task XML 文件（UTF-16LE 编码，带 BOM）
2. 使用 `schtasks.exe /create` 创建任务
3. 通过 `execWithElevation` 提权执行

### 3.3 检查开机启动状态

**实现**:
```typescript
export async function checkAutoRun(): Promise<boolean> {
  if (process.platform === 'win32') {
    const execFilePromise = promisify(execFile)
    try {
      const { stdout } = await execFilePromise('schtasks.exe', ['/query', '/tn', `${appName}`])
      return stdout.includes(appName)
    } catch (e) {
      return false
    }
  }
}
```

**方法**: 使用 `schtasks.exe /query` 查询任务是否存在

### 3.4 禁用开机启动

**实现**:
```typescript
export async function disableAutoRun(): Promise<void> {
  if (process.platform === 'win32') {
    await execWithElevation('schtasks.exe', ['/delete', '/tn', `${appName}`, '/f'])
  }
}
```

**方法**: 使用 `schtasks.exe /delete` 删除任务

---

## 4. 服务模式（可选）

### 4.1 服务架构

Sparkle 支持使用独立的 Windows 服务来处理需要管理员权限的操作。

**组件**:
- **服务程序**: `service.exe` - 运行在 SYSTEM 账户下的服务
- **通信方式**: HTTP API over Unix Socket（Windows 上使用命名管道）
- **身份验证**: Ed25519 密钥对签名

### 4.2 服务初始化

**位置**: `src/main/service/manager.ts`

**流程**:
1. 生成 Ed25519 密钥对
2. 初始化服务 API（设置 axios 拦截器）
3. 调用服务程序的 `init` 命令，传入公钥
4. 保存密钥对到配置文件

**关键代码**:
```typescript
export async function initService(): Promise<void> {
  const newKeyManager = new KeyManager()
  const keyPair = newKeyManager.generateKeyPair()
  initServiceAPI(newKeyManager)
  const publicKey = keyPair.publicKey
  const execPath = servicePath()
  
  await execWithElevation(execPath, ['service', 'init', '--public-key', publicKey])
  
  await patchAppConfig({
    serviceAuthKey: `${keyPair.publicKey}:${keyPair.privateKey}`
  })
  
  keyManager = newKeyManager
}
```

### 4.3 服务 API 通信

**位置**: `src/main/service/api.ts`

**实现**:
```typescript
serviceAxios = axios.create({
  baseURL: 'http://localhost',
  socketPath: serviceIpcPath(),  // Windows: 命名管道路径
  timeout: 15000,
  headers: {
    'Content-Type': 'application/json'
  }
})

// 请求拦截器：添加时间戳和签名
serviceAxios.interceptors.request.use((config) => {
  if (keyManager?.isInitialized()) {
    const timestamp = Math.floor(Date.now() / 1000).toString()
    const signature = keyManager.signData(timestamp)
    
    config.headers['X-Timestamp'] = timestamp
    config.headers['X-Signature'] = signature
  }
  return config
})
```

**API 端点**:
- `/ping` - 检查服务状态
- `/test` - 测试服务连接
- `/core/start` - 启动核心
- `/core/stop` - 停止核心
- `/core/restart` - 重启核心
- `/sysproxy/*` - 系统代理相关
- `/sys/dns/set` - DNS 设置

---

## 5. 关键设计特点

### 5.1 权限管理策略

1. **双重模式**:
   - Task Scheduler 模式（默认）：适合普通用户，按需提权
   - 服务模式（可选）：适合需要持续运行的高权限操作

2. **权限检测**:
   - 使用 `net session` 检测当前是否已拥有管理员权限
   - 如果已有权限，直接执行；否则触发 UAC

3. **UAC 处理**:
   - 使用 PowerShell `Start-Process -Verb RunAs` 触发 UAC
   - `-WindowStyle Hidden` 隐藏窗口，避免 CMD 黑框

### 5.2 进程管理

1. **启动方式**:
   - 使用 Node.js `spawn` 启动 mihomo 核心
   - Windows 上使用命名管道（`-ext-ctl-pipe`）进行 IPC

2. **进程监控**:
   - 监听 `close` 事件，自动重启（最多 10 次）
   - 监听 stdout，检测启动成功和错误

3. **优雅退出**:
   - 先发送 `SIGINT`，等待 3 秒
   - 如果未退出，发送 `SIGTERM`，再等待 3 秒
   - 最后发送 `SIGKILL` 强制终止

### 5.3 错误处理

1. **TUN 权限错误**:
   - 自动禁用 TUN
   - 提示用户手动授予权限

2. **用户取消操作**:
   - 检测 UAC 取消（退出码 -128）
   - 静默处理，不显示错误

3. **服务连接失败**:
   - 自动降级到直接启动模式

---

## 6. 与 LiClash 项目的对比

### 6.1 相同点

1. **都使用 Task Scheduler 实现开机启动**
2. **都使用 PowerShell 提权执行命令**
3. **都支持服务模式（可选）**

### 6.2 不同点

| 特性 | Sparkle | LiClash（当前） |
|------|---------|----------------|
| **提权方式** | Task Scheduler + sparkle-run.exe | Helper 服务（Rust） |
| **TUN 启动** | 直接 spawn mihomo 核心 | 通过 Helper 服务启动 |
| **权限检查** | `net session` | Helper 服务 API |
| **开机启动** | Task Scheduler（管理员模式） | Task Scheduler（管理员模式） |
| **服务通信** | HTTP + Unix Socket/命名管道 | HTTP + TCP |
| **身份验证** | Ed25519 密钥对 | SHA256 哈希 |

### 6.3 Sparkle 的优势

1. **更简洁的架构**: 直接启动核心，不需要额外的 Helper 服务（除非使用服务模式）
2. **更好的错误处理**: 自动检测和处理权限错误
3. **更灵活的权限模式**: 支持 Task Scheduler 和服务两种模式

---

## 7. 优化建议（针对 LiClash）

### 7.1 简化提权逻辑

**建议**: 参考 Sparkle 的实现，使用 Task Scheduler 创建提权任务，而不是每次都通过 Helper 服务。

**优势**:
- 减少对 Helper 服务的依赖
- 更快的启动速度
- 更简单的代码逻辑

### 7.2 改进 TUN 错误处理

**建议**: 参考 Sparkle 的自动禁用机制，当检测到 TUN 权限错误时，自动禁用并提示用户。

**实现**:
```dart
// 监听核心输出
process?.stderr.listen((data) {
  final error = utf8.decode(data);
  if (error.contains('operation not permitted')) {
    // 自动禁用 TUN
    patchControledMihomoConfig({ tun: { enable: false } });
    // 通知用户
    showError('虚拟网卡启动失败，请检查权限设置');
  }
});
```

### 7.3 统一开机启动实现

**建议**: 参考 Sparkle 的实现，使用统一的 Task Scheduler XML 模板，支持管理员模式。

**优势**:
- 代码更简洁
- 更容易维护
- 支持延迟启动（避免系统启动时资源竞争）

---

## 8. 总结

Sparkle 在 Windows 平台上的实现具有以下特点：

1. **灵活的权限管理**: 支持 Task Scheduler 和服务两种模式
2. **优雅的错误处理**: 自动检测和处理权限错误
3. **简洁的架构**: 直接启动核心，减少中间层
4. **良好的用户体验**: 隐藏窗口，避免 CMD 黑框

这些设计可以作为 LiClash 项目优化的参考。

