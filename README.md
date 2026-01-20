# v2node / V2bX 一键安装脚本

这是一个用于在 Linux 系统上自动安装和配置 **v2node** 或 **V2bX** 后端的 Shell 脚本。

## 支持系统

- CentOS 7+
- Debian 8+
- Ubuntu 16+
- Alpine Linux
- Arch Linux

支持架构：`amd64` (x86_64), `arm64`, `s390x`

## 快速开始

### 1. 安装 v2node (默认)

适用于 v2node 后端对接。

```bash
bash install.sh --backend-url "https://api.example.com" --backend-key "your_key" --node-id 1
```

### 2. 安装 V2bX

适用于 V2bX 后端对接，支持多种核心配置。

**基础安装 (无证书):**
```bash
bash install.sh --type v2bx \
  --backend-url "https://api.example.com" \
  --backend-key "your_key" \
  --node-id 1 \
  --core-type xray \
  --transport-type tcp
```

**自动申请证书安装 (Cloudflare DNS):**
```bash
bash install.sh --type v2bx \
  --backend-url "https://api.example.com" \
  --backend-key "your_key" \
  --node-id 1 \
  --core-type xray \
  --transport-type trojan \
  --cert-domain "node.example.com" \
  --acme-email "admin@example.com" \
  --cf-key "YOUR_CF_KEY" \
  --cf-email "YOUR_CF_EMAIL"
```

## 详细参数说明

| 参数 | 简写 | 描述 | 示例 |
| :--- | :--- | :--- | :--- |
| `--type` | `-t` | 安装类型: `v2node` (默认) 或 `v2bx` | `--type v2bx` |
| `--version` | `-v` | 指定安装版本 | `--version v0.4.1` |
| `--config` | `-c` | 指定配置文件路径 (yml/yaml/txt) | `--config config.yml` |
| `--backend-url` | | 面板 API 地址 | `--backend-url https://api.site.com` |
| `--backend-key` | | 面板通信密钥 | `--backend-key password` |
| `--node-id` | | 面板节点 ID | `--node-id 5` |
| `--core-type` | | (V2bX) 核心类型: `xray`, `sing`, `hysteria2` | `--core-type xray` |
| `--transport-type` | | (V2bX) 传输协议类型 | `--transport-type tcp` |
| `--cert-domain` | | (V2bX) 证书域名，填写则自动申请 | `--cert-domain node.site.com` |
| `--acme-email` | | ACME 申请证书邮箱 | `--acme-email admin@site.com` |
| `--cf-key` | | Cloudflare Global API Key | |
| `--cf-email` | | Cloudflare Account Email | |
| `--force-reinstall` | | 强制重新安装 | |

## 配置文件方式安装

除了命令行参数，你也可以创建一个配置文件（例如 `config.yml`）来管理配置。

**config.yml 示例:**
```yaml
backend_url: https://api.example.com
backend_key: password123
node_id: 10
# 以下为 V2bX 必需
core_type: xray
transport_type: tcp
cert_domain: node.example.com
```

**运行命令:**
```bash
bash install.sh --type v2bx --config config.yml
```

## 服务管理命令

安装完成后，脚本会自动配置系统服务（Systemd 或 OpenRC）并提供快捷命令。

### v2node
```bash
v2node start    # 启动
v2node stop     # 停止
v2node restart  # 重启
v2node status   # 查看状态
v2node log      # 查看日志
v2node config   # 查看配置文件
```

### V2bX
```bash
v2bx start    # 启动
v2bx stop     # 停止
v2bx restart  # 重启
v2bx status   # 查看状态
v2bx log      # 查看日志
v2bx config   # 查看配置文件
```

## 目录结构

- **安装目录**:
  - v2node: `/usr/local/v2node/`
  - V2bX: `/usr/local/V2bX/`
- **配置文件**:
  - v2node: `/etc/v2node/config.json`
  - V2bX: `/etc/V2bX/config.json`
