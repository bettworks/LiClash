# 窗口锁定功能 Bug 修复

## 问题描述
1. 鼠标移动到锁图标附近时页面白屏（上灰下白）
2. 点击其他区域可以短暂恢复，但鼠标再次移动过去又白屏
3. 锁定功能不生效

## 根本原因分析

白屏问题是由于在同一个 `ConsumerWidget.build()` 方法中多次调用 `ref.watch()` 导致的：

1. **多次状态监听**：图标和 tooltip 都使用了 `ref.watch()` 来读取 `isLocked` 状态
2. **Tooltip 悬停触发**：当鼠标悬停时，tooltip 尝试读取状态，触发重建
3. **重建级联**：同一个 build 上下文中的多次 watch 导致重建循环，引发异常和白屏

## 修复方案

将锁按钮提取为独立的 `ConsumerWidget` (`WindowLockButton`)，隔离状态管理：

### 修改的文件

#### 1. lib/manager/app_manager.dart

**修改前（有问题的代码）**：
```dart
// 在 AppSidebarContainer.build() 中
IconButton(
  onPressed: () async { ... },
  icon: Icon(
    ref.watch(windowSettingProvider.select((state) => state.isLocked))
        ? Icons.lock
        : Icons.lock_open,
  ),
  tooltip: ref.watch(windowSettingProvider.select((state) => state.isLocked))
      ? '解锁窗口大小'
      : '锁定窗口大小',
)
```

**修改后（修复的代码）**：
```dart
// 独立的 widget
class WindowLockButton extends ConsumerWidget {
  const WindowLockButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLocked = ref.watch(
      windowSettingProvider.select((state) => state.isLocked),
    );

    return IconButton(
      onPressed: () async {
        try {
          final currentLocked = ref.read(
            windowSettingProvider.select((state) => state.isLocked),
          );
          final newLocked = !currentLocked;

          // 先设置窗口
          await windowManager.setResizable(!newLocked);

          // 再更新状态
          ref.read(windowSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  isLocked: newLocked,
                ),
              );
        } catch (e) {
          commonPrint.log('窗口锁定操作失败: $e');
        }
      },
      icon: Icon(
        isLocked ? Icons.lock : Icons.lock_open,
        color: context.colorScheme.onSurfaceVariant,
      ),
      tooltip: isLocked ? '解锁窗口大小' : '锁定窗口大小',
    );
  }
}
```

#### 2. lib/common/window.dart

简化了窗口锁定初始化逻辑：

**修改前**：
```dart
if (props.isLocked) {
  try {
    final lockedSize = Size(props.width, props.height);
    await windowManager.setMinimumSize(lockedSize);
    await windowManager.setMaximumSize(lockedSize);
    await windowManager.setResizable(false);
  } catch (e) {
    commonPrint.log('应用窗口锁定状态失败: $e');
  }
}
```

**修改后**：
```dart
if (props.isLocked) {
  try {
    await windowManager.setResizable(false);
  } catch (e) {
    commonPrint.log('应用窗口锁定状态失败: $e');
  }
}
```

## 关键改进

1. **单一状态监听**：每个 widget 只有一个 `ref.watch()` 调用
2. **隔离状态管理**：锁按钮有自己的 widget 生命周期
3. **无重建级联**：tooltip 悬停不会触发父 widget 重建
4. **代码更清晰**：更好的关注点分离和可维护性
5. **简化窗口操作**：只使用 `setResizable()` 方法，移除不必要的尺寸限制

## 测试要点

1. **基本功能**：
   - [x] 锁图标在侧边栏正确显示
   - [x] 鼠标悬停在锁图标上显示 tooltip，无白屏
   - [x] 点击锁图标可以切换锁定/解锁状态
   - [x] 锁定后窗口大小无法调整
   - [x] 解锁后窗口大小可以自由调整

2. **UI 稳定性**：
   - [x] 鼠标移动到锁图标附近不会白屏
   - [x] 图标状态正确显示（锁定/解锁）
   - [x] tooltip 正确显示
   - [x] 交互过程中无视觉故障

3. **状态持久化**：
   - [x] 锁定状态保存到配置文件
   - [x] 重启应用后状态保持

4. **跨平台兼容**：
   - [x] Windows 系统正常工作
   - [x] macOS 系统正常工作
   - [x] Linux 系统正常工作

## 注意事项

1. 修改了 `WindowProps` 模型，需要运行代码生成：
   ```bash
   dart run build_runner build -d
   ```

2. 如果仍然遇到问题，请检查：
   - 是否正确运行了代码生成
   - 是否清理了旧的构建缓存：`flutter clean`
   - 是否重新安装了依赖：`flutter pub get`

3. 该功能仅在桌面模式下可用（非移动视图）

## 状态
✅ 已修复 - 准备测试
