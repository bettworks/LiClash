import 'package:li_clash/common/common.dart';
import 'package:li_clash/providers/config.dart';
import 'package:li_clash/providers/providers.dart';
import 'package:li_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DozeSuspendItem extends ConsumerWidget {
  const DozeSuspendItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dozeSuspend = ref.watch(
      vpnSettingProvider.select((state) => state.dozeSuspend),
    );
    return ListItem.switchItem(
      title: Text(appLocalizations.dozeSuspend),
      subtitle: Text(appLocalizations.dozeSuspendDesc),
      delegate: SwitchDelegate(
        value: dozeSuspend,
        onChanged: (bool value) {
          ref.read(vpnSettingProvider.notifier).updateState(
                (state) => state.copyWith(
                  dozeSuspend: value,
                ),
              );
        },
      ),
    );
  }
}

class OtherSettingView extends StatelessWidget {
  const OtherSettingView({super.key});

  @override
  Widget build(BuildContext context) {
    List<Widget> items = [
      if (system.isAndroid) const DozeSuspendItem(),
    ];
    
    if (items.isEmpty) {
      return const Center(
        child: Text('No settings available'),
      );
    }
    
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
