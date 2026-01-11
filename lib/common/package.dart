import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import 'common.dart';

extension PackageInfoExtension on PackageInfo {
  String get ua => [
        'LiClash/Clash.Meta/Mihomo/ClashMetaForAndroid/v5.0',
      ].join(' ');
}
