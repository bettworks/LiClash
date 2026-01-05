import 'package:li_clash/common/common.dart';
import 'package:li_clash/l10n/l10n_temp_extension.dart';
import 'package:li_clash/plugins/vpn.dart';
import 'package:li_clash/providers/config.dart';
import 'package:li_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DozeSupportItem extends ConsumerWidget {
  const DozeSupportItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final dozeSupport = ref.watch(
      appSettingProvider.select((state) => state.dozeSupport),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.dozeSupport),
      subtitle: Text(appLocalizations.dozeSupportDesc),
      delegate: SwitchDelegate(
        value: dozeSupport,
        onChanged: (value) async {
          ref.read(appSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  dozeSupport: value,
                ),
              );
          // 通知Android端更新休眠支持状态
          vpn?.updateDozeSupport(value);
        },
      ),
    );
  }
}

class SmartSuspendItem extends ConsumerStatefulWidget {
  const SmartSuspendItem({super.key});

  @override
  ConsumerState<SmartSuspendItem> createState() => _SmartSuspendItemState();
}

class _SmartSuspendItemState extends ConsumerState<SmartSuspendItem> {
  void _showInputDialog(String currentValue) {
    final controller = TextEditingController(text: currentValue);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appLocalizations.smartSuspend),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: '192.168.1.0/24,10.0.0.1',
                helperText: appLocalizations.smartSuspendInputHint,
                helperMaxLines: 2,
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(appLocalizations.cancel),
          ),
          TextButton(
            onPressed: () {
              final newValue = controller.text.trim();
              
              // 验证输入
              if (!_isValidIpInput(newValue)) {
                // 显示错误提示
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(appLocalizations.smartSuspendInvalidInput),
                  ),
                );
                return;
              }
              
              // 保存并更新
              ref.read(appSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  smartSuspendIps: newValue,
                ),
              );
              
              // 通知Android端
              final enabled = ref.read(appSettingProvider).smartSuspendEnabled;
              vpn?.updateSmartSuspend(enabled, newValue);
              
              Navigator.pop(context);
            },
            child: Text(appLocalizations.save),
          ),
        ],
      ),
    );
  }
  
  bool _isValidIpInput(String input) {
    if (input.isEmpty) return true;  // 空值有效
    
    final parts = input.split(',');
    if (parts.length > 2) return false;  // 最多2个
    
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      
      if (!_isValidIpOrCidr(trimmed)) {
        return false;
      }
    }
    
    return true;
  }
  
  bool _isValidIpOrCidr(String value) {
    // 简单验证IP或CIDR格式
    final ipRegex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}(/\d{1,2})?$');
    if (!ipRegex.hasMatch(value)) return false;
    
    // 验证每个数字在0-255范围内
    final parts = value.split('/')[0].split('.');
    for (final part in parts) {
      final num = int.tryParse(part);
      if (num == null || num < 0 || num > 255) return false;
    }
    
    // 如果有CIDR前缀，验证范围
    if (value.contains('/')) {
      final prefix = int.tryParse(value.split('/')[1]);
      if (prefix == null || prefix < 0 || prefix > 32) return false;
    }
    
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(
      appSettingProvider.select((state) => state.smartSuspendEnabled),
    );
    final ips = ref.watch(
      appSettingProvider.select((state) => state.smartSuspendIps),
    );
    
    final listItem = ListItem.switchItem(
      title: Text(appLocalizations.smartSuspend),
      subtitle: Text(
        ips.isEmpty 
          ? appLocalizations.smartSuspendDesc 
          : ips
      ),
      delegate: SwitchDelegate(
        value: enabled,
        onChanged: (value) async {
          if (value) {
            // 开启时弹出输入框
            _showInputDialog(ips);
          } else {
            // 关闭时直接更新
            ref.read(appSettingProvider.notifier).updateState(
              (state) => state.copyWith(smartSuspendEnabled: false),
            );
            vpn?.updateSmartSuspend(false, ips);
          }
        },
      ),
    );
    
    // 如果已启用,允许点击整个item来编辑
    if (enabled) {
      return GestureDetector(
        onTap: () => _showInputDialog(ips),
        child: listItem,
      );
    }
    
    return listItem;
  }
}

class OtherSettingsView extends StatelessWidget {
  const OtherSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    List<Widget> items = [
      if (system.isAndroid) ...[
        SmartSuspendItem(),
        DozeSupportItem(),
      ],
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
