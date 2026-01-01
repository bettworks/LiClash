import 'package:li_clash/common/common.dart';
import 'package:li_clash/enum/enum.dart';
import 'package:li_clash/models/models.dart';
import 'package:li_clash/providers/providers.dart';
import 'package:li_clash/state.dart';
import 'package:li_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StartButton extends ConsumerWidget {
  const StartButton({super.key});

  void _handleStart(WidgetRef ref) {
    final isStart = ref.read(runTimeProvider) != null;
    final newState = !isStart;
    
    debouncer.call(
      FunctionTag.updateStatus,
      () {
        globalState.appController.updateStatus(newState);
      },
      duration: commonDuration,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(startButtonSelectorStateProvider);
    final runTime = ref.watch(runTimeProvider);
    final startingStatus = ref.watch(startingStatusProvider);
    final isStart = runTime != null;
    
    return SizedBox(
      height: getWidgetHeight(1),
      child: CommonCard(
        info: Info(
          label: isStart ? appLocalizations.runTime : appLocalizations.powerSwitch,
          iconData: Icons.power_settings_new,
        ),
        onPressed: state.isInit && state.hasProfile ? () => _handleStart(ref) : null,
        child: Container(
          padding: baseInfoEdgeInsets.copyWith(
            top: 0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(
                height: globalState.measure.bodyMediumHeight + 2,
                child: FadeThroughBox(
                  child: _buildContent(context, ref, state, isStart, runTime, startingStatus),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    StartButtonSelectorState state,
    bool isStart,
    int? runTime,
    String? startingStatus,
  ) {
    if (!state.isInit) {
      return Container(
        padding: EdgeInsets.all(2),
        child: AspectRatio(
          aspectRatio: 1,
          child: CircularProgressIndicator(
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (!state.hasProfile) {
      return Text(
        appLocalizations.checkOrAddProfile,
        style: context.textTheme.bodyMedium?.toLight.adjustSize(1),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    // 显示启动加载状态
    if (startingStatus != null) {
      String statusText;
      switch (startingStatus) {
        case 'loadingService':
          statusText = appLocalizations.loadingService;
        case 'securityVerification':
          statusText = appLocalizations.securityVerification;
        case 'starting':
          statusText = appLocalizations.starting;
        default:
          statusText = appLocalizations.starting;
      }
      
      return _AnimatedLoadingText(text: statusText);
    }

    if (!isStart) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Icon(
            Icons.play_arrow,
            size: 16,
            color: context.colorScheme.primary,
          ),
          SizedBox(width: 4),
          Expanded(
            child: Text(
              appLocalizations.serviceReady,
              style: context.textTheme.bodyMedium?.toLight.adjustSize(1),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    // 启动状态：显示暂停图标 + 运行时间
    final timeText = _formatRunTime(runTime);
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Icon(
          Icons.pause,
          size: 16,
          color: context.colorScheme.primary,
        ),
        SizedBox(width: 4),
        Text(' ', style: context.textTheme.bodyMedium?.toLight.adjustSize(1)),
        Expanded(
          child: Text(
            timeText,
            style: context.textTheme.bodyMedium?.toLight.adjustSize(1),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _formatRunTime(int? timeStamp) {
    if (timeStamp == null) return '00:00:00';
    
    final diff = timeStamp / 1000;
    int inHours = (diff / 3600).floor();
    int inMinutes = (diff / 60 % 60).floor();
    int inSeconds = (diff % 60).floor();
    
    // 限制最大显示为 999:59:59
    if (inHours > 999) {
      inHours = 999;
      inMinutes = 59;
      inSeconds = 59;
    }
    
    // 小于100小时显示2位，大于等于100小时显示3位
    final hourStr = inHours < 100 
        ? inHours.toString().padLeft(2, '0')
        : inHours.toString().padLeft(3, '0');
    
    return '$hourStr:${inMinutes.toString().padLeft(2, '0')}:${inSeconds.toString().padLeft(2, '0')}';
  }
}

// 动态省略号加载文本组件
class _AnimatedLoadingText extends StatefulWidget {
  final String text;

  const _AnimatedLoadingText({required this.text});

  @override
  State<_AnimatedLoadingText> createState() => _AnimatedLoadingTextState();
}

class _AnimatedLoadingTextState extends State<_AnimatedLoadingText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _dotCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..addListener(() {
        if (_controller.value == 1.0) {
          setState(() {
            _dotCount = (_dotCount + 1) % 4; // 0, 1, 2, 3 循环
          });
          _controller.reset();
          _controller.forward();
        }
      });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dots = '.' * _dotCount;
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Icon(
          Icons.hourglass_empty,
          size: 16,
          color: context.colorScheme.primary,
        ),
        SizedBox(width: 4),
        Expanded(
          child: Text(
            '${widget.text}$dots',
            style: context.textTheme.bodyMedium?.toLight.adjustSize(1),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
