import 'package:li_clash/common/common.dart';
import 'package:li_clash/enum/enum.dart';
import 'package:li_clash/providers/providers.dart';
import 'package:li_clash/state.dart';
import 'package:li_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

typedef OnSelected = void Function(int index);

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return HomeBackScope(
      child: Material(
        color: context.colorScheme.surface,
        child: Consumer(
          builder: (context, ref, __) {
            final state = ref.watch(navigationStateProvider);
            final isMobile = state.viewMode == ViewMode.mobile;
            final navigationItems = state.navigationItems;
            final pageView = _HomePageView(pageBuilder: (_, index) {
              final navigationItem = state.navigationItems[index];
              final navigationView = navigationItem.builder(context);
              final view = isMobile
                  ? KeepScope(
                      keep: navigationItem.keep,
                      child: navigationView,
                    )
                  : KeepScope(
                      keep: navigationItem.keep,
                      child: Navigator(
                        onGenerateRoute: (_) {
                          return CommonRoute(
                            builder: (_) => navigationView,
                          );
                        },
                      ),
                    );
              return view;
            });
            final currentIndex = state.currentIndex;
            final bottomNavigationBar = NavigationBarTheme(
              data: _NavigationBarDefaultsM3(context),
              child: NavigationBar(
                destinations: navigationItems
                    .map(
                      (e) => NavigationDestination(
                        icon: e.icon,
                        label: Intl.message(e.label.name),
                      ),
                    )
                    .toList(),
                onDestinationSelected: (index) {
                  globalState.appController.toPage(
                    navigationItems[index].label,
                  );
                },
                selectedIndex: currentIndex,
              ),
            );
            if (isMobile) {
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: globalState.appState.systemUiOverlayStyle.copyWith(
                  systemNavigationBarColor:
                      context.colorScheme.surfaceContainer,
                ),
                child: Column(
                  children: [
                    Flexible(
                      flex: 1,
                      child: MediaQuery.removePadding(
                        removeTop: false,
                        removeBottom: true,
                        removeLeft: true,
                        removeRight: true,
                        context: context,
                        child: pageView,
                      ),
                    ),
                    MediaQuery.removePadding(
                      removeTop: true,
                      removeBottom: false,
                      removeLeft: true,
                      removeRight: true,
                      context: context,
                      child: bottomNavigationBar,
                    ),
                  ],
                ),
              );
            } else {
              return pageView;
            }
          },
        ),
      ),
    );
  }
}

class _HomePageView extends ConsumerStatefulWidget {
  final IndexedWidgetBuilder pageBuilder;

  const _HomePageView({
    required this.pageBuilder,
  });

  @override
  ConsumerState createState() => _HomePageViewState();
}

class _HomePageViewState extends ConsumerState<_HomePageView> {
  late PageController _pageController;

  @override
  initState() {
    super.initState();
    _pageController = PageController(
      initialPage: _pageIndex,
    );
    ref.listenManual(currentPageLabelProvider, (prev, next) {
      if (prev != next) {
        _toPage(next);
      }
    });
    ref.listenManual(currentNavigationItemsStateProvider, (prev, next) {
      if (prev?.value.length != next.value.length ||
          prev?.value.map((e) => e.label).join(',') !=
              next.value.map((e) => e.label).join(',')) {
        _updatePageController();
      }
    });
  }

  int get _pageIndex {
    final navigationItems = ref.read(currentNavigationItemsStateProvider).value;
    final index = navigationItems.indexWhere(
      (item) => item.label == globalState.appState.pageLabel,
    );
    // 如果当前页面不在导航项中，返回 0（第一个页面）
    return index == -1 ? 0 : index;
  }

  Future<void> _toPage(PageLabel pageLabel,
      [bool ignoreAnimateTo = false]) async {
    if (!mounted) {
      return;
    }
    final navigationItems = ref.read(currentNavigationItemsStateProvider).value;
    if (navigationItems.isEmpty) {
      return;
    }
    final index = navigationItems.indexWhere((item) => item.label == pageLabel);
    // 确保索引在有效范围内
    final validIndex = index == -1 
        ? 0 
        : index.clamp(0, navigationItems.length - 1);
    final isAnimateToPage = ref.read(appSettingProvider).isAnimateToPage;
    final isMobile = ref.read(isMobileViewProvider);
    
    if (index == -1) {
      // 如果目标页面不存在（例如关闭日志捕获时尝试切换到 logs 页面），
      // 保持当前页面不变，或者如果当前页面也不存在，则切换到第一个可用页面
      final currentPageLabel = globalState.appState.pageLabel;
      final currentIndex = navigationItems.indexWhere(
        (item) => item.label == currentPageLabel,
      );
      
      if (currentIndex != -1) {
        // 当前页面仍然存在，保持当前页面，不进行任何跳转
        return;
      }
      
      // 当前页面也不存在，切换到第一个可用页面
      final fallbackLabel = navigationItems[0].label;
      if (globalState.appState.pageLabel != fallbackLabel) {
        globalState.appState = globalState.appState.copyWith(
          pageLabel: fallbackLabel,
        );
      }
      // 直接跳转到第一个页面
      if (_pageController.hasClients) {
        if (isAnimateToPage && !ignoreAnimateTo && isMobile) {
          await _pageController.animateToPage(
            validIndex,
            duration: kTabScrollDuration,
            curve: Curves.easeOut,
          );
        } else {
          _pageController.jumpToPage(validIndex);
        }
      }
      return;
    }
    if (!_pageController.hasClients) {
      return;
    }
    if (isAnimateToPage && isMobile && !ignoreAnimateTo) {
      await _pageController.animateToPage(
        validIndex,
        duration: kTabScrollDuration,
        curve: Curves.easeOut,
      );
    } else {
      _pageController.jumpToPage(validIndex);
    }
  }

  void _updatePageController() {
    if (!mounted) {
      return;
    }
    final navigationItems = ref.read(currentNavigationItemsStateProvider).value;
    if (navigationItems.isEmpty) {
      return;
    }
    final pageLabel = globalState.appState.pageLabel;
    final index = navigationItems.indexWhere((item) => item.label == pageLabel);
    
    if (index == -1) {
      // 当前页面不在导航项中（例如关闭日志捕获时在 logs 页面），切换到第一个可用页面
      final fallbackLabel = navigationItems[0].label;
      globalState.appState = globalState.appState.copyWith(
        pageLabel: fallbackLabel,
      );
      // 使用 postFrameCallback 确保在下一帧执行，避免在 build 过程中修改状态
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _toPage(fallbackLabel, true);
        }
      });
    } else {
      // 当前页面仍然存在，保持当前页面，只需要确保 PageController 的索引正确
      final validIndex = index.clamp(0, navigationItems.length - 1);
      if (_pageController.hasClients) {
        final currentPage = _pageController.page?.round() ?? 0;
        // 只有当当前页面索引与目标索引不一致时，才进行跳转
        if (currentPage != validIndex) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pageController.hasClients) {
              _pageController.jumpToPage(validIndex);
            }
          });
        }
        // 如果索引已经正确，不需要任何操作，保持当前页面显示
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itemCount = ref.watch(currentNavigationItemsStateProvider
        .select((state) => state.value.length));
    return PageView.builder(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        return widget.pageBuilder(context, index);
      },
    );
  }
}

class _NavigationBarDefaultsM3 extends NavigationBarThemeData {
  _NavigationBarDefaultsM3(this.context)
      : super(
          height: 80.0,
          elevation: 3.0,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        );

  final BuildContext context;
  late final ColorScheme _colors = Theme.of(context).colorScheme;
  late final TextTheme _textTheme = Theme.of(context).textTheme;

  @override
  Color? get backgroundColor => _colors.surfaceContainer;

  @override
  Color? get shadowColor => Colors.transparent;

  @override
  Color? get surfaceTintColor => Colors.transparent;

  @override
  WidgetStateProperty<IconThemeData?>? get iconTheme {
    return WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      return IconThemeData(
        size: 24.0,
        color: states.contains(WidgetState.disabled)
            ? _colors.onSurfaceVariant.opacity38
            : states.contains(WidgetState.selected)
                ? _colors.onSecondaryContainer
                : _colors.onSurfaceVariant,
      );
    });
  }

  @override
  Color? get indicatorColor => _colors.secondaryContainer;

  @override
  ShapeBorder? get indicatorShape => const StadiumBorder();

  @override
  WidgetStateProperty<TextStyle?>? get labelTextStyle {
    return WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      final TextStyle style = _textTheme.labelMedium!;
      return style.apply(
          overflow: TextOverflow.ellipsis,
          color: states.contains(WidgetState.disabled)
              ? _colors.onSurfaceVariant.opacity38
              : states.contains(WidgetState.selected)
                  ? _colors.onSurface
                  : _colors.onSurfaceVariant);
    });
  }
}

class HomeBackScope extends StatelessWidget {
  final Widget child;

  const HomeBackScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (system.isAndroid) {
      return CommonPopScope(
        onPop: () async {
          final canPop = Navigator.canPop(context);
          if (canPop) {
            Navigator.pop(context);
          } else {
            await globalState.appController.handleBackOrExit();
          }
          return false;
        },
        child: child,
      );
    }
    return child;
  }
}
