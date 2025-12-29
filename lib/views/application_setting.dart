import 'package:li_clash/common/common.dart';
import 'package:li_clash/enum/enum.dart';
import 'package:li_clash/providers/config.dart';
import 'package:li_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class CloseConnectionsItem extends ConsumerWidget {
  const CloseConnectionsItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final closeConnections = ref.watch(
      appSettingProvider.select((state) => state.closeConnections),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.autoCloseConnections),
      subtitle: Text(appLocalizations.autoCloseConnectionsDesc),
      delegate: SwitchDelegate(
        value: closeConnections,
        onChanged: (value) async {
          ref.read(appSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  closeConnections: value,
                ),
              );
        },
      ),
    );
  }
}

class UsageItem extends ConsumerWidget {
  const UsageItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final onlyStatisticsProxy = ref.watch(
      appSettingProvider.select((state) => state.onlyStatisticsProxy),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.onlyStatisticsProxy),
      subtitle: Text(appLocalizations.onlyStatisticsProxyDesc),
      delegate: SwitchDelegate(
        value: onlyStatisticsProxy,
        onChanged: (bool value) async {
          ref.read(appSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  onlyStatisticsProxy: value,
                ),
              );
        },
      ),
    );
  }
}

class MinimizeItem extends ConsumerWidget {
  const MinimizeItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minimizeOnExit = ref.watch(
      appSettingProvider.select((state) => state.minimizeOnExit),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.minimizeOnExit),
      subtitle: Text(appLocalizations.minimizeOnExitDesc),
      delegate: SwitchDelegate(
        value: minimizeOnExit,
        onChanged: (bool value) {
          ref.read(appSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  minimizeOnExit: value,
                ),
              );
        },
      ),
    );
  }
}

class AutoLaunchItem extends ConsumerStatefulWidget {
  const AutoLaunchItem({super.key});

  @override
  ConsumerState<AutoLaunchItem> createState() => _AutoLaunchItemState();
}

class _AutoLaunchItemState extends ConsumerState<AutoLaunchItem> {
  String _modeDescription = '';
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _updateModeDescription();
  }

  Future<void> _updateModeDescription() async {
    if (system.isWindows) {
      final description = await autoLaunch?.getModeDescription() ?? '';
      if (mounted) {
        setState(() {
          _modeDescription = description;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoLaunchEnabled = ref.watch(
      appSettingProvider.select((state) => state.autoLaunch),
    );

    // 当状态变化时更新模式描述
    ref.listenManual(
      appSettingProvider.select((state) => state.autoLaunch),
      (prev, next) {
        if (prev != next) {
          _updateModeDescription();
        }
      },
    );

    // 构建副标题（包含模式描述）
    final subtitle = system.isWindows && _modeDescription.isNotEmpty
        ? '${appLocalizations.autoLaunchDesc}$_modeDescription'
        : appLocalizations.autoLaunchDesc;

    return ListItem.switchItem(
      title: Text(appLocalizations.autoLaunch),
      subtitle: Text(subtitle),
      delegate: SwitchDelegate(
        value: autoLaunchEnabled,
        onChanged: _isUpdating
            ? null
            : (bool value) async {
                setState(() {
                  _isUpdating = true;
                });

                // 更新配置状态
                ref.read(appSettingProvider.notifier).updateState(
                      (state) => state.copyWith(
                        autoLaunch: value,
                      ),
                    );

                // 实际启用/禁用自启动（智能选择模式）
                if (value) {
                  // Windows平台优先尝试管理员模式
                  final success = await autoLaunch?.enable(
                        preferAdmin: system.isWindows,
                      ) ??
                      false;
                  if (!success) {
                    // 启用失败，恢复开关状态
                    ref.read(appSettingProvider.notifier).updateState(
                          (state) => state.copyWith(autoLaunch: false),
                        );
                  }
                } else {
                  // 禁用自启动（同时禁用两种模式）
                  await autoLaunch?.disable();
                }

                // 更新模式描述
                await _updateModeDescription();

                if (mounted) {
                  setState(() {
                    _isUpdating = false;
                  });
                }
              },
      ),
    );
  }
}

class SilentLaunchItem extends ConsumerWidget {
  const SilentLaunchItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final silentLaunch = ref.watch(
      appSettingProvider.select((state) => state.silentLaunch),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.silentLaunch),
      subtitle: Text(appLocalizations.silentLaunchDesc),
      delegate: SwitchDelegate(
        value: silentLaunch,
        onChanged: (bool value) {
          ref.read(appSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  silentLaunch: value,
                ),
              );
        },
      ),
    );
  }
}

class AutoRunItem extends ConsumerWidget {
  const AutoRunItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoRun = ref.watch(
      appSettingProvider.select((state) => state.autoRun),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.autoRun),
      subtitle: Text(appLocalizations.autoRunDesc),
      delegate: SwitchDelegate(
        value: autoRun,
        onChanged: (bool value) {
          ref.read(appSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  autoRun: value,
                ),
              );
        },
      ),
    );
  }
}

class HiddenItem extends ConsumerWidget {
  const HiddenItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(
      appSettingProvider.select((state) => state.hidden),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.exclude),
      subtitle: Text(appLocalizations.excludeDesc),
      delegate: SwitchDelegate(
        value: hidden,
        onChanged: (value) {
          ref.read(appSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  hidden: value,
                ),
              );
        },
      ),
    );
  }
}

class AnimateTabItem extends ConsumerWidget {
  const AnimateTabItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAnimateToPage = ref.watch(
      appSettingProvider.select((state) => state.isAnimateToPage),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.tabAnimation),
      subtitle: Text(appLocalizations.tabAnimationDesc),
      delegate: SwitchDelegate(
        value: isAnimateToPage,
        onChanged: (value) {
          ref.read(appSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  isAnimateToPage: value,
                ),
              );
        },
      ),
    );
  }
}

class OpenLogsItem extends ConsumerWidget {
  const OpenLogsItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openLogs = ref.watch(
      appSettingProvider.select((state) => state.openLogs),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.logcat),
      subtitle: Text(appLocalizations.logcatDesc),
      delegate: SwitchDelegate(
        value: openLogs,
        onChanged: (bool value) {
          ref.read(appSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  openLogs: value,
                ),
              );
        },
      ),
    );
  }
}

class AutoCheckUpdateItem extends ConsumerWidget {
  const AutoCheckUpdateItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoCheckUpdate = ref.watch(
      appSettingProvider.select((state) => state.autoCheckUpdate),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.autoCheckUpdate),
      subtitle: Text(appLocalizations.autoCheckUpdateDesc),
      delegate: SwitchDelegate(
        value: autoCheckUpdate,
        onChanged: (bool value) {
          ref.read(appSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  autoCheckUpdate: value,
                ),
              );
        },
      ),
    );
  }
}

class ApplicationSettingView extends StatelessWidget {
  const ApplicationSettingView({super.key});

  String getLocaleString(Locale? locale) {
    if (locale == null) return appLocalizations.defaultText;
    return Intl.message(locale.toString());
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> items = [
      MinimizeItem(),
      if (system.isDesktop) ...[
        AutoLaunchItem(),
        SilentLaunchItem(),
      ],
      AutoRunItem(),
      if (system.isAndroid) ...[
        HiddenItem(),
      ],
      AnimateTabItem(),
      OpenLogsItem(),
      CloseConnectionsItem(),
      UsageItem(),
      AutoCheckUpdateItem(),
    ];
    return ListView.separated(
      itemBuilder: (_, index) {
        final item = items[index];
        return item;
      },
      separatorBuilder: (_, __) {
        return const Divider(
          height: 0,
        );
      },
      itemCount: items.length,
    );
  }
}
