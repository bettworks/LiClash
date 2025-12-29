
allprojects {
    repositories {
        // 优先使用官方源（GitHub Actions 等国外环境）
        google()
        mavenCentral()
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
            name = "Aliyun Public"
            url = uri("https://maven.aliyun.com/repository/public")
        }
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
