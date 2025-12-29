pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        // 优先使用官方源（GitHub Actions 等国外环境）
        google()
        mavenCentral()
        gradlePluginPortal()
        // 阿里云镜像作为备用（国内环境或官方源失败时使用）
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
}



plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}


include(":app")
include(":core")
