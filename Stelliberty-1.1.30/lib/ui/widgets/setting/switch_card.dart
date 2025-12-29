import 'package:flutter/material.dart';
import 'package:stelliberty/ui/common/modern_feature_card.dart';

// 通用的带开关的卡片组件
class SwitchCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SwitchCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ModernFeatureToggleCard(
      icon: icon,
      title: title,
      subtitle: subtitle,
      value: value,
      onChanged: onChanged,
    );
  }
}
