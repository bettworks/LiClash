import 'package:flutter/foundation.dart';
import 'package:stelliberty/dev_test/override_test.dart';
import 'package:stelliberty/dev_test/ipc_api_test.dart';

// 开发测试管理器
// 用法：flutter run --dart-define=TEST_TYPE=override
// 测试模式仅在 Debug 模式可用，Release 模式下禁用
class TestManager {
  // 获取测试类型
  static String? get testType {
    // Release 模式禁用测试
    if (kReleaseMode) {
      return null;
    }

    const type = String.fromEnvironment('TEST_TYPE');
    return type.isEmpty ? null : type;
  }

  // 运行指定类型的测试
  static Future<void> runTest(String testType) async {
    // 双重保险：Release 模式拒绝运行
    if (kReleaseMode) {
      throw Exception('测试模式在 Release 模式下不可用');
    }

    switch (testType) {
      case 'override':
        await OverrideTest.run();
        break;
      case 'ipc-api':
        await IpcApiTest.run();
        break;
      default:
        throw Exception('未知的测试类型: $testType');
    }
  }
}
