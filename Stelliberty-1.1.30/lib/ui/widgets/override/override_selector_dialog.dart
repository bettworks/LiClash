import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stelliberty/clash/data/override_model.dart';
import 'package:stelliberty/clash/providers/override_provider.dart';
import 'package:stelliberty/ui/common/modern_switch.dart';
import 'package:stelliberty/ui/common/modern_dialog.dart';
import 'package:stelliberty/i18n/i18n.dart';

// 覆写选择对话框 - 从全局覆写列表中选择
class OverrideSelectorDialog extends StatefulWidget {
  final List<String> initialSelectedIds;

  const OverrideSelectorDialog({super.key, required this.initialSelectedIds});

  static Future<List<String>?> show(
    BuildContext context, {
    required List<String> initialSelectedIds,
  }) {
    return showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          OverrideSelectorDialog(initialSelectedIds: initialSelectedIds),
    );
  }

  @override
  State<OverrideSelectorDialog> createState() => _OverrideSelectorDialogState();
}

class _OverrideSelectorDialogState extends State<OverrideSelectorDialog> {
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.initialSelectedIds);
  }

  @override
  Widget build(BuildContext context) {
    return ModernDialog(
      title: context.translate.overrideDialog.selectOverrides,
      titleIcon: Icons.checklist,
      maxWidth: 640,
      maxHeightRatio: 0.8,
      content: _buildContent(),
      actionsRight: [
        DialogActionButton(
          label: context.translate.common.cancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        DialogActionButton(
          label: context.translate.common.save,
          isPrimary: true,
          onPressed: () => Navigator.of(context).pop(_selectedIds.toList()),
        ),
      ],
      onClose: () => Navigator.of(context).pop(),
    );
  }

  Widget _buildContent() {
    return Consumer<OverrideProvider>(
      builder: (context, provider, child) {
        final overrides = provider.overrides;

        if (overrides.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.rule, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  context.translate.overrideDialog.noOverridesTitle,
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  context.translate.overrideDialog.noOverridesHint,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: overrides.length,
          itemBuilder: (context, index) {
            return _buildOverrideItem(overrides[index]);
          },
        );
      },
    );
  }

  Widget _buildOverrideItem(OverrideConfig override) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _selectedIds.contains(override.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.1 : 0.2),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  override.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  override.format.displayName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ModernSwitch(
            value: isSelected,
            onChanged: (value) {
              setState(() {
                if (value) {
                  _selectedIds.add(override.id);
                } else {
                  _selectedIds.remove(override.id);
                }
              });
            },
          ),
        ],
      ),
    );
  }
}
