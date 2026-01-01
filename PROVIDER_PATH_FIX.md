# Provider Path 修复文档

## 问题描述

之前的实现中，即使用户在配置文件中设置了 `path` 字段，程序也会忽略用户设置，始终使用 URL 的 MD5 作为文件名。

## 参考文档

- [Rule Providers 配置](https://wiki.metacubex.one/config/rule-providers)
- [Path 字段说明](https://wiki.metacubex.one/config/rule-providers/#path)

## 修复方案

### 1. 新的处理逻辑

**优先级**：
1. 如果用户设置了 `path` 字段，使用用户设置的文件名
2. 如果没有设置 `path`，使用 URL 的 MD5 作为文件名

**安全限制**：
- 路径被限制在 HomeDir（通过 `-d` 参数配置）中
- 只提取文件名部分，移除任何路径分隔符（`/` 或 `\`）
- 防止路径遍历攻击（如 `../../etc/passwd`）

### 2. 实现细节

#### lib/state.dart - patchRawConfig 方法

**Proxy Providers 处理**：
```dart
if (rawConfig['proxy-providers'] != null) {
  final proxyProviders = rawConfig['proxy-providers'] as Map;
  for (final key in proxyProviders.keys) {
    final proxyProvider = proxyProviders[key];
    if (proxyProvider['type'] != 'http') {
      continue;
    }
    
    // 如果用户设置了 path，使用用户设置的路径（限制在 HomeDir 中）
    if (proxyProvider['path'] != null && proxyProvider['path'] is String) {
      final userPath = proxyProvider['path'] as String;
      // 只保留文件名，移除任何路径分隔符，确保安全
      final fileName = userPath.split(RegExp(r'[/\\]')).last;
      if (fileName.isNotEmpty) {
        proxyProvider['path'] = await appPath.getProvidersFilePath(
          profile.id,
          'proxies',
          fileName,
        );
      } else if (proxyProvider['url'] != null) {
        // 如果文件名为空，回退到使用 URL 的 MD5
        proxyProvider['path'] = await appPath.getProvidersFilePath(
          profile.id,
          'proxies',
          proxyProvider['url'],
        );
      }
    } else if (proxyProvider['url'] != null) {
      // 如果没有设置 path，使用 URL 的 MD5
      proxyProvider['path'] = await appPath.getProvidersFilePath(
        profile.id,
        'proxies',
        proxyProvider['url'],
      );
    }
  }
}
```

**Rule Providers 处理**：
```dart
if (rawConfig['rule-providers'] != null) {
  final ruleProviders = rawConfig['rule-providers'] as Map;
  for (final key in ruleProviders.keys) {
    final ruleProvider = ruleProviders[key];
    if (ruleProvider['type'] != 'http') {
      continue;
    }
    
    // 如果用户设置了 path，使用用户设置的路径（限制在 HomeDir 中）
    if (ruleProvider['path'] != null && ruleProvider['path'] is String) {
      final userPath = ruleProvider['path'] as String;
      // 只保留文件名，移除任何路径分隔符，确保安全
      final fileName = userPath.split(RegExp(r'[/\\]')).last;
      if (fileName.isNotEmpty) {
        ruleProvider['path'] = await appPath.getProvidersFilePath(
          profile.id,
          'rules',
          fileName,
        );
      } else if (ruleProvider['url'] != null) {
        // 如果文件名为空，回退到使用 URL 的 MD5
        ruleProvider['path'] = await appPath.getProvidersFilePath(
          profile.id,
          'rules',
          ruleProvider['url'],
        );
      }
    } else if (ruleProvider['url'] != null) {
      // 如果没有设置 path，使用 URL 的 MD5
      ruleProvider['path'] = await appPath.getProvidersFilePath(
        profile.id,
        'rules',
        ruleProvider['url'],
      );
    }
  }
}
```

### 3. 路径结构

最终的文件路径结构：
```
HomeDir/
  profiles/
    providers/
      {profile_id}/
        proxies/
          {user_filename or url_md5}
        rules/
          {user_filename or url_md5}
```

### 4. 安全措施

1. **路径限制**：所有文件都存储在 `HomeDir/profiles/providers/{profile_id}/{type}/` 目录下
2. **文件名提取**：使用 `split(RegExp(r'[/\\]')).last` 只提取文件名部分
3. **路径遍历防护**：移除所有路径分隔符，防止 `../` 攻击
4. **空值检查**：如果提取的文件名为空，回退到使用 URL 的 MD5

### 5. 示例

#### 用户配置示例 1：设置了 path
```yaml
rule-providers:
  my-rules:
    type: http
    behavior: domain
    url: "https://example.com/rules.yaml"
    path: ./my-custom-rules.yaml
    interval: 86400
```

**处理结果**：
- 提取文件名：`my-custom-rules.yaml`
- 最终路径：`HomeDir/profiles/providers/{profile_id}/rules/my-custom-rules.yaml`

#### 用户配置示例 2：未设置 path
```yaml
rule-providers:
  my-rules:
    type: http
    behavior: domain
    url: "https://example.com/rules.yaml"
    interval: 86400
```

**处理结果**：
- 使用 URL MD5：`md5("https://example.com/rules.yaml")`
- 最终路径：`HomeDir/profiles/providers/{profile_id}/rules/{url_md5}`

#### 用户配置示例 3：尝试路径遍历（安全防护）
```yaml
rule-providers:
  my-rules:
    type: http
    behavior: domain
    url: "https://example.com/rules.yaml"
    path: ../../etc/passwd
    interval: 86400
```

**处理结果**：
- 提取文件名：`passwd`（只保留最后一部分）
- 最终路径：`HomeDir/profiles/providers/{profile_id}/rules/passwd`
- ✅ 路径遍历攻击被阻止

### 6. 兼容性

- ✅ 向后兼容：没有设置 `path` 的配置继续使用 URL MD5
- ✅ 符合 Mihomo 规范：支持用户自定义 `path`
- ✅ 安全性：路径限制在 HomeDir 中，防止路径遍历

### 7. 测试要点

1. **基本功能**
   - [ ] 用户设置 `path` 后，使用用户设置的文件名
   - [ ] 未设置 `path` 时，使用 URL 的 MD5
   - [ ] 文件正确存储在 HomeDir 的 providers 目录下

2. **安全性**
   - [ ] 路径遍历攻击被阻止（`../../etc/passwd`）
   - [ ] 绝对路径被转换为文件名（`/etc/passwd` → `passwd`）
   - [ ] Windows 路径分隔符正确处理（`C:\Windows\file.yaml` → `file.yaml`）

3. **边界情况**
   - [ ] 空文件名回退到 URL MD5
   - [ ] 只有路径分隔符的 path 回退到 URL MD5
   - [ ] 特殊字符文件名正确处理

4. **兼容性**
   - [ ] 旧配置（无 path）继续正常工作
   - [ ] 新配置（有 path）按预期工作
   - [ ] proxy-providers 和 rule-providers 都正确处理

## 状态
✅ 实现完成 - 等待测试
