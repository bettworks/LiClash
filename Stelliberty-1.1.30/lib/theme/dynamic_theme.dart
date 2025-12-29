import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:system_theme/system_theme.dart';
import 'package:stelliberty/providers/theme_provider.dart';
import 'package:stelliberty/providers/window_effect_provider.dart';
import 'package:stelliberty/ui/widgets/modern_toast.dart';
import 'package:stelliberty/i18n/i18n.dart';

// 动态主题应用根组件,监听主题状态变更并重建 MaterialApp
// 将主题传播到整个组件树
class DynamicThemeApp extends StatelessWidget {
  // 应用程序主入口组件
  final Widget home;

  const DynamicThemeApp({super.key, required this.home});

  // 基于响应式主题状态构建 MaterialApp
  // 作为主题状态与 UI 之间的桥梁,确保视觉主题实时更新
  @override
  Widget build(BuildContext context) {
    return Consumer2<ThemeProvider, WindowEffectProvider>(
      builder: (context, themeProvider, windowEffectProvider, _) {
        // 使用 SystemThemeBuilder 获取系统强调色
        return SystemThemeBuilder(
          builder: (context, accent) {
            return MaterialApp(
              navigatorKey: ModernToast.navigatorKey,
              locale: TranslationProvider.of(context).flutterLocale,
              supportedLocales: AppLocaleUtils.supportedLocales,
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                colorScheme: themeProvider.lightColorScheme,
                scaffoldBackgroundColor:
                    windowEffectProvider.windowEffectBackgroundColor,
                useMaterial3: true,
                textTheme: GoogleFonts.notoSansScTextTheme(
                  ThemeData.light().textTheme,
                ),
              ),
              darkTheme: ThemeData(
                colorScheme: themeProvider.darkColorScheme,
                scaffoldBackgroundColor:
                    windowEffectProvider.windowEffectBackgroundColor,
                useMaterial3: true,
                textTheme: GoogleFonts.notoSansScTextTheme(
                  ThemeData.dark().textTheme,
                ),
              ),
              themeMode: themeProvider.themeMode.toThemeMode(),
              home: Builder(
                builder: (context) {
                  // 此 context 位于 MaterialApp 内部,可获取正确的主题亮度
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    final brightness = Theme.of(context).brightness;
                    themeProvider.updateBrightness(brightness);
                    windowEffectProvider.updateBrightness(brightness);
                  });
                  return home;
                },
              ),
            );
          },
        );
      },
    );
  }
}
