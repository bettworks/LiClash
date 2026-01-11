import 'dart:async';

import 'package:li_clash/clash/clash.dart';
import 'package:li_clash/common/common.dart';
import 'package:li_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';

class FcmStatusData {
  final int? minutes;
  final bool isConnected;

  const FcmStatusData({
    this.minutes,
    required this.isConnected,
  });
}

final _fcmStatusNotifier = ValueNotifier<FcmStatusData>(
  const FcmStatusData(isConnected: false),
);

class FcmStatus extends StatefulWidget {
  const FcmStatus({super.key});

  @override
  State<FcmStatus> createState() => _FcmStatusState();
}

class _FcmStatusState extends State<FcmStatus> {
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _updateFcmStatus();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _updateFcmStatus() async {
    if (!mounted) return;

    try {
      final connections = await clashCore.getConnections();
      
      // 筛选 FCM 连接：host 包含 google.com + 端口 5228/5229/5230
      final fcmConnections = connections.where((conn) {
        final host = conn.metadata.host.toLowerCase();
        final port = conn.metadata.destinationPort;
        return host.contains('google.com') &&
            (port == '5228' || port == '5229' || port == '5230');
      }).toList();

      if (fcmConnections.isEmpty) {
        _fcmStatusNotifier.value = const FcmStatusData(isConnected: false);
      } else {
        // 选择最长的连接（start 最早的）
        final longestConnection = fcmConnections.reduce(
          (a, b) => a.start.isBefore(b.start) ? a : b,
        );
        final duration = DateTime.now().difference(longestConnection.start);
        final minutes = duration.inMinutes;
        _fcmStatusNotifier.value = FcmStatusData(
          minutes: minutes,
          isConnected: true,
        );
      }
    } catch (e) {
      // 忽略错误，保持当前值
    }

    if (!mounted) return;

    // 每5秒更新一次
    timer = Timer(const Duration(seconds: 5), _updateFcmStatus);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: getWidgetHeight(1),
        child: CommonCard(
          info: const Info(
            iconData: Icons.cloud_outlined,
            label: 'FCM',
          ),
          child: Container(
            padding: baseInfoEdgeInsets.copyWith(
              top: 0,
            ),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: ValueListenableBuilder<FcmStatusData>(
                valueListenable: _fcmStatusNotifier,
                builder: (_, status, __) {
                  if (status.isConnected && status.minutes != null) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '${status.minutes}',
                          style: context.textTheme.bodyLarge?.toLight
                              .adjustSize(2),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          ' Minutes',
                          style: context.textTheme.bodyMedium?.toLight
                              .adjustSize(0),
                        ),
                      ],
                    );
                  } else {
                    return Text(
                      appLocalizations.noStatusAvailable,
                      style: context.textTheme.bodyMedium?.toLight
                          .adjustSize(0),
                    );
                  }
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
