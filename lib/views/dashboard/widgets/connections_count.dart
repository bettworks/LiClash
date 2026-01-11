import 'dart:async';

import 'package:li_clash/clash/clash.dart';
import 'package:li_clash/common/common.dart';
import 'package:li_clash/views/connection/connections.dart';
import 'package:li_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';

class ConnectionsCount extends StatefulWidget {
  const ConnectionsCount({super.key});

  @override
  State<ConnectionsCount> createState() => _ConnectionsCountState();
}

class _ConnectionsCountState extends State<ConnectionsCount> {
  Timer? _timer;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _updateConnections();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _updateConnections() async {
    if (!mounted) return;

    try {
      final connections = await clashCore.getConnections();
      if (mounted) {
        setState(() {
          _count = connections.length;
        });
      }
    } catch (e) {
      // 忽略错误，保持当前值
    }

    if (!mounted) return;

    _timer = Timer(const Duration(seconds: 1), _updateConnections);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: getWidgetHeight(1),
      child: CommonCard(
        info: Info(
          iconData: Icons.swap_horiz,
          label: appLocalizations.connection,
        ),
        onPressed: () {
          showExtend(
            context,
            builder: (_, type) {
              return const ConnectionsView();
            },
          );
        },
        child: Container(
          padding: baseInfoEdgeInsets.copyWith(
            top: 0,
          ),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$_count',
                  style: context.textTheme.bodyLarge?.toLight.adjustSize(2),
                ),
                const SizedBox(width: 4),
                Text(
                  ' Connections',
                  style: context.textTheme.bodyMedium?.toLight.adjustSize(0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
