// 临时本地化扩展 - 等待Flutter Intl插件重新生成l10n.dart后可删除此文件
import 'package:li_clash/l10n/l10n.dart';

extension AppLocalizationsExtension on AppLocalizations {
  String get dozeSupport => 'Doze Support';
  String get dozeSupportDesc => 'Enable Doze mode support when turned on';
  String get smartSuspend => 'Smart Suspend';
  String get smartSuspendDesc => 'Auto suspend core when specified LAN IP detected';
  String get smartSuspendInputHint => 'Enter up to 2 IPs or IP ranges, comma separated';
  String get smartSuspendInvalidInput => 'Invalid IP format, please check input';
  String get smartSuspendActive => 'Smart Suspend Active';
}
