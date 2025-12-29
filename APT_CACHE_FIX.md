# APT 缓存问题修复

## 问题描述

GitHub Actions 中安装 Linux 依赖时，`apt-get update` 失败：
```
E: Failed to fetch ... Hash Sum mismatch
```

## 原因分析

这是 apt 缓存损坏或网络问题导致的常见问题：
1. **缓存损坏**：apt 缓存文件可能损坏或不完整
2. **网络问题**：下载过程中网络中断导致文件不完整
3. **镜像源问题**：Ubuntu 镜像源可能临时有问题

## 修复方案

### 1. 清理 apt 缓存
在 `apt-get update` 前清理缓存：
```bash
sudo rm -rf /var/lib/apt/lists/*
```

### 2. 添加重试机制
`apt-get update` 最多重试 3 次：
```bash
for i in {1..3}; do
  if sudo apt-get update -y; then
    break
  else
    if [ $i -lt 3 ]; then
      sudo rm -rf /var/lib/apt/lists/*
      sleep 2
    else
      exit 1
    fi
  fi
done
```

## 修改详情

在 `.github/workflows/build.yaml` 的 `Install Linux Dependencies` 步骤中：
1. 在 `apt-get update` 前清理缓存
2. 添加重试机制（最多3次）
3. 每次重试前清理缓存

## 预期效果

- 解决 Hash Sum mismatch 错误
- 提高 apt update 成功率
- 减少构建失败

## 如果问题仍然存在

如果重试3次后仍然失败，可以尝试：

1. **使用不同的镜像源**：
   ```bash
   sudo sed -i 's|http://archive.ubuntu.com|http://mirrors.aliyun.com|g' /etc/apt/sources.list
   ```

2. **增加重试次数**：从3次增加到5次

3. **添加超时设置**：
   ```bash
   sudo apt-get -o Acquire::http::Timeout=30 update -y
   ```

