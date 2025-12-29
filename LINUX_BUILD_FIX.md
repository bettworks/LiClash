# Linux 构建错误修复

## 问题描述

GitHub Actions 中 Linux 构建失败，错误信息：
```
CMake Error: The following required packages were not found:
  - gtk+-3.0
```

## 原因分析

Flutter Linux 应用需要 GTK3 和相关系统库来构建。CMake 在配置阶段就需要这些依赖，但 GitHub Actions 的 Ubuntu 镜像默认没有安装这些库。

## 修复方案

在 GitHub Actions workflow 中添加 Linux 依赖安装步骤，在构建前安装所有必需的依赖。

### 安装的依赖

1. **构建工具**
   - `cmake` - CMake 构建系统
   - `ninja-build` - Ninja 构建工具
   - `build-essential` - 基本编译工具链
   - `pkg-config` - 包配置工具

2. **GTK3 和相关库**
   - `libgtk-3-dev` - GTK3 开发库（必需）
   - `libglib2.0-dev` - GLib 开发库（Flutter Linux 需要）

3. **应用功能支持**
   - `libayatana-appindicator3-dev` - 系统托盘支持
   - `libkeybinder-3.0-dev` - 快捷键支持

4. **打包工具（仅 amd64）**
   - `rpm` - RPM 包构建工具
   - `patchelf` - ELF 文件修补工具
   - `libfuse2` - FUSE 文件系统支持（AppImage 需要）
   - `appimagetool` - AppImage 打包工具

## 修改详情

### `.github/workflows/build.yaml`

添加了新的步骤：
```yaml
- name: Install Linux Dependencies
  if: startsWith(matrix.platform,'linux')
  run: |
    sudo apt-get update -y
    # CMake 和构建工具
    sudo apt-get install -y cmake ninja-build build-essential pkg-config
    # GTK3 和相关依赖（Flutter Linux 必需）
    sudo apt-get install -y libgtk-3-dev libglib2.0-dev
    # 系统托盘和快捷键支持
    sudo apt-get install -y libayatana-appindicator3-dev
    sudo apt-get install -y libkeybinder-3.0-dev
    # 其他工具
    sudo apt-get install -y locate
    # amd64 架构额外依赖（用于打包）
    if [ "${{ matrix.arch }}" == "amd64" ] || [ "${{ matrix.arch }}" == "" ]; then
      sudo apt-get install -y rpm patchelf libfuse2
      wget -O appimagetool https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
      chmod +x appimagetool
      sudo mv appimagetool /usr/local/bin/
    fi
```

## 依赖说明

### 必需依赖（所有架构）

- **libgtk-3-dev**: GTK3 开发库，Flutter Linux 应用的核心 GUI 库
- **libglib2.0-dev**: GLib 开发库，GTK 的基础库
- **pkg-config**: 用于查找和配置库的工具

### 可选依赖（功能支持）

- **libayatana-appindicator3-dev**: 系统托盘图标支持
- **libkeybinder-3.0-dev**: 全局快捷键支持

### 打包依赖（仅 amd64）

- **rpm**: 用于构建 RPM 包
- **patchelf**: 用于修补 ELF 文件的库路径
- **libfuse2**: AppImage 运行时需要
- **appimagetool**: 用于创建 AppImage 包

## 注意事项

1. **安装顺序**: 依赖安装步骤必须在 `dart setup.dart` 之前执行，因为 CMake 配置阶段就需要这些库

2. **架构差异**: 
   - amd64 架构需要额外的打包工具（rpm, patchelf, libfuse2, appimagetool）
   - arm64 架构只需要基本的构建依赖

3. **缓存**: 这些依赖安装可能需要一些时间，但 GitHub Actions 会缓存 apt 包，后续构建会更快

## 测试建议

1. 在 GitHub Actions 中触发 Linux 构建
2. 观察构建日志，确认：
   - 依赖安装成功
   - CMake 配置成功找到 GTK3
   - 构建过程正常

## 如果问题仍然存在

如果构建仍然失败，可以尝试：

1. **检查依赖版本**: 确保安装的 GTK3 版本与 Flutter 要求兼容
2. **添加更多依赖**: 如果缺少其他库，根据错误信息添加
3. **使用不同的 Ubuntu 版本**: 如果当前版本有问题，可以尝试其他 Ubuntu 版本

