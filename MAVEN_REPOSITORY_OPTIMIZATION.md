# Maven 仓库配置优化说明

## 问题

在 GitHub Actions 中使用阿里云 Maven 镜像可能反而会变慢，因为：
1. GitHub Actions 服务器在国外，访问 Google 和 Maven Central 通常很快
2. 从国外访问阿里云服务器可能更慢
3. 阿里云镜像主要面向国内网络环境优化

## 解决方案

### 优化策略

**优先使用官方源，阿里云镜像作为备用**

1. **官方源优先**：`google()`, `mavenCentral()`, `gradlePluginPortal()`
   - 在 GitHub Actions 等国外环境中，这些源通常很快
   - 直接访问，无需经过镜像

2. **阿里云镜像备用**：当官方源失败或超时时自动回退
   - 适合国内开发环境
   - 作为官方源的备用方案

### 配置说明

#### `android/settings.gradle.kts` (插件管理)

```kotlin
repositories {
    // 优先使用官方源
    google()
    mavenCentral()
    gradlePluginPortal()
    // 阿里云镜像作为备用
    maven {
        name = "Aliyun Google"
        url = uri("https://maven.aliyun.com/repository/google")
    }
    maven {
        name = "Aliyun Central"
        url = uri("https://maven.aliyun.com/repository/central")
    }
    maven {
        name = "Aliyun Gradle Plugin"
        url = uri("https://maven.aliyun.com/repository/gradle-plugin")
    }
}
```

#### `android/build.gradle.kts` (项目依赖)

```kotlin
allprojects {
    repositories {
        // 优先使用官方源
        google()
        mavenCentral()
        // 阿里云镜像作为备用
        maven {
            name = "Aliyun Google"
            url = uri("https://maven.aliyun.com/repository/google")
        }
        maven {
            name = "Aliyun Central"
            url = uri("https://maven.aliyun.com/repository/central")
        }
        maven {
            name = "Aliyun Public"
            url = uri("https://maven.aliyun.com/repository/public")
        }
    }
}
```

## 工作原理

Gradle 会按顺序尝试每个仓库：
1. 首先尝试官方源（`google()`, `mavenCentral()`）
2. 如果官方源失败或超时，自动尝试下一个仓库
3. 如果所有官方源都失败，会尝试阿里云镜像

## 优势

1. **GitHub Actions 优化**：优先使用官方源，构建更快
2. **国内环境兼容**：官方源失败时自动使用阿里云镜像
3. **自动回退**：无需手动配置，自动选择最快的源
4. **灵活性**：同时支持国内外环境

## 测试建议

### GitHub Actions
- 观察构建日志，确认优先使用官方源
- 检查构建时间是否有所改善

### 国内环境
- 如果官方源访问慢，会自动回退到阿里云镜像
- 构建应该能正常完成

## 如果需要强制使用阿里云镜像

如果需要在特定环境强制使用阿里云镜像，可以通过环境变量控制：

```kotlin
val useAliyunMirror = System.getenv("USE_ALIYUN_MIRROR") == "true"

repositories {
    if (useAliyunMirror) {
        // 强制使用阿里云镜像
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
    } else {
        // 优先使用官方源
        google()
        mavenCentral()
        // 阿里云镜像作为备用
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
    }
}
```

但通常不需要这样做，因为 Gradle 会自动选择最快的源。

