# Android 构建错误修复

## 问题描述

GitHub Actions 中 Android 构建失败，错误信息：
```
[!] Gradle threw an error while downloading artifacts from the network.
Gradle task assembleRelease failed with exit code 1
```

## 原因分析

1. **网络问题**：Gradle 在从网络下载依赖时超时或失败
2. **缺少重试机制**：网络临时故障导致构建失败
3. **超时时间过短**：默认超时时间可能不足以完成下载

## 修复方案

### 1. 增强 Gradle 网络配置

**文件：`android/gradle.properties`**

已添加以下配置：
- 增加连接和套接字超时时间（120秒）
- 添加重试次数配置（5次）
- 启用 Gradle 缓存和并行构建

### 2. 在 GitHub Actions 中添加重试机制

**文件：`.github/workflows/build.yaml`**

已添加：
- **Gradle 配置步骤**：在构建前配置全局 Gradle 属性
- **重试机制**：Android 构建最多重试3次
- **缓存清理**：失败后清理 Gradle 缓存再重试

### 3. 使用阿里云镜像

**文件：`android/settings.gradle.kts`**

已配置阿里云 Maven 镜像作为主要源，Google 和 Maven Central 作为备用源。

## 修改详情

### `android/gradle.properties`
```properties
# 网络超时配置（单位：毫秒）
systemProp.http.connectionTimeout=120000
systemProp.http.socketTimeout=120000
systemProp.https.connectionTimeout=120000
systemProp.https.socketTimeout=120000

# 重试配置
systemProp.http.retryCount=5
systemProp.https.retryCount=5
```

### `.github/workflows/build.yaml`
```yaml
- name: Configure Gradle for Network Issues
  if: startsWith(matrix.platform,'android')
  run: |
    mkdir -p ~/.gradle
    cat >> ~/.gradle/gradle.properties << EOF
    org.gradle.daemon=true
    org.gradle.parallel=true
    org.gradle.configureondemand=true
    org.gradle.caching=true
    org.gradle.jvmargs=-Xmx4096m -XX:MaxMetaspaceSize=512m
    systemProp.http.connectionTimeout=60000
    systemProp.http.socketTimeout=60000
    systemProp.http.retryCount=3
    EOF

- name: Setup
  if: startsWith(matrix.platform,'android')
  run: |
    # 重试机制：最多重试3次
    for i in {1..3}; do
      echo "Attempt $i of 3"
      if dart setup.dart ...; then
        echo "Build succeeded on attempt $i"
        exit 0
      else
        echo "Build failed on attempt $i"
        if [ $i -lt 3 ]; then
          echo "Waiting 10 seconds before retry..."
          sleep 10
          # 清理 Gradle 缓存
          rm -rf ~/.gradle/caches/
          rm -rf android/.gradle/
        fi
      fi
    done
    exit 1
```

## 预期效果

1. **提高成功率**：重试机制可以处理临时网络故障
2. **减少超时**：增加的超时时间可以处理慢速网络
3. **加速下载**：阿里云镜像可以加速依赖下载（特别是在国内网络环境）

## 测试建议

1. 在 GitHub Actions 中触发构建
2. 观察构建日志，确认：
   - Gradle 配置是否正确应用
   - 重试机制是否正常工作
   - 网络超时是否足够

## 如果问题仍然存在

如果构建仍然失败，可以尝试：

1. **增加重试次数**：将重试次数从3次增加到5次
2. **增加超时时间**：将超时时间从120秒增加到180秒
3. **使用 VPN 或代理**：在 GitHub Actions 中配置代理（如果可用）
4. **检查依赖版本**：确保所有依赖版本都是最新的稳定版本
