# Windows TUN接口清理脚本
# 需要管理员权限运行

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  LiClash TUN接口清理工具" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 检查管理员权限
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "错误: 需要管理员权限运行此脚本！" -ForegroundColor Red
    Write-Host "请右键点击脚本，选择'以管理员身份运行'" -ForegroundColor Yellow
    pause
    exit 1
}

Write-Host "[1/5] 检查并停止相关进程..." -ForegroundColor Yellow
$processes = Get-Process | Where-Object {
    $_.ProcessName -like "*clash*" -or 
    $_.ProcessName -like "*liclash*" -or
    $_.ProcessName -like "*mihomo*"
}

if ($processes) {
    Write-Host "  找到以下进程:" -ForegroundColor Gray
    foreach ($proc in $processes) {
        Write-Host "    - $($proc.ProcessName) (PID: $($proc.Id))" -ForegroundColor Gray
    }
    $processes | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Host "  已停止相关进程" -ForegroundColor Green
    Start-Sleep -Seconds 2
} else {
    Write-Host "  未找到相关进程" -ForegroundColor Gray
}

Write-Host ""
Write-Host "[2/5] 检查网络适配器..." -ForegroundColor Yellow
$adapters = Get-NetAdapter | Where-Object {
    $_.Name -like "*TUN*" -or 
    $_.Name -like "*Wintun*" -or
    $_.Name -like "*TAP*" -or
    $_.Name -like "*Clash*" -or
    $_.Name -like "*LiClash*" -or
    $_.Name -like "*mihomo*"
}

if ($adapters) {
    Write-Host "  找到以下TUN适配器:" -ForegroundColor Gray
    foreach ($adapter in $adapters) {
        Write-Host "    - $($adapter.Name) (状态: $($adapter.Status))" -ForegroundColor Gray
    }
} else {
    Write-Host "  未找到TUN适配器" -ForegroundColor Gray
}

Write-Host ""
Write-Host "[3/5] 删除TUN适配器..." -ForegroundColor Yellow
if ($adapters) {
    foreach ($adapter in $adapters) {
        try {
            Write-Host "  正在删除: $($adapter.Name)..." -ForegroundColor Gray
            Remove-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
            Write-Host "    ✓ 已删除" -ForegroundColor Green
        } catch {
            Write-Host "    ✗ 删除失败: $_" -ForegroundColor Red
            # 尝试通过设备管理器删除
            Write-Host "    尝试通过设备管理器删除..." -ForegroundColor Yellow
            $pnpid = (Get-NetAdapter -Name $adapter.Name).InterfaceDescription
            if ($pnpid) {
                pnputil /remove-device $pnpid 2>$null
            }
        }
    }
} else {
    Write-Host "  无需删除" -ForegroundColor Gray
}

Write-Host ""
Write-Host "[4/5] 清理网络配置..." -ForegroundColor Yellow
try {
    Write-Host "  刷新DNS缓存..." -ForegroundColor Gray
    ipconfig /flushdns | Out-Null
    Write-Host "    ✓ DNS缓存已刷新" -ForegroundColor Green
} catch {
    Write-Host "    ✗ DNS刷新失败" -ForegroundColor Red
}

Write-Host ""
Write-Host "[5/5] 检查IP地址占用..." -ForegroundColor Yellow
$testIP = "172.19.0.1"
$pingResult = Test-Connection -ComputerName $testIP -Count 1 -Quiet -ErrorAction SilentlyContinue
if ($pingResult) {
    Write-Host "  警告: $testIP 已被占用" -ForegroundColor Yellow
    Write-Host "  可能需要修改默认IP地址" -ForegroundColor Yellow
} else {
    Write-Host "  $testIP 未被占用" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  清理完成！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "建议操作:" -ForegroundColor Yellow
Write-Host "  1. 重启计算机（推荐）" -ForegroundColor White
Write-Host "  2. 以管理员权限重新启动LiClash" -ForegroundColor White
Write-Host "  3. 尝试启用TUN功能" -ForegroundColor White
Write-Host ""
pause

