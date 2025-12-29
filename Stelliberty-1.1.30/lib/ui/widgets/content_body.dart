import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stelliberty/providers/window_effect_provider.dart';

// 页面主要内容区域的容器组件。
//
// 具有左上角圆角和自适应主题的背景色。
class ContentBody extends StatelessWidget {
  final Widget child;
  final Color? color;

  const ContentBody({super.key, required this.child, this.color});

  @override
  Widget build(BuildContext context) {
    return Consumer<WindowEffectProvider>(
      builder: (context, windowEffectProvider, _) {
        // 优先使用外部传入的 color，否则使用默认逻辑
        final backgroundColor =
            color ??
            windowEffectProvider.windowEffectBackgroundColor ??
            Theme.of(context).colorScheme.surface;

        return Container(
          decoration: BoxDecoration(color: backgroundColor),
          child: child,
        );
      },
    );
  }
}
