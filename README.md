# V2bX 一键安装脚本

这是一个用于在 Linux 系统上自动安装、配置和管理 **V2bX** 后端的 Shell 脚本。

脚本会自动从 GitHub 获取项目的最新 Release 版本进行安装，并提供开箱即用的最佳实践配置。

## ✨ 功能特性

- **自动安装**: 自动检测系统架构 (amd64/arm64/s390x) 并下载对应版本的程序。
- **系统优化**: 默认开启 **BBR 加速** 并优化系统内核参数 (如 `fs.file-max`, `tcp_max_syn_backlog` 等)。
- **依赖管理**: 自动安装 `curl`, `wget`, `unzip`, `socat`, `cron` 等必要组件。
- **配置生成**: 
  - 自动生成符合最佳实践的 `config.json`。
  - V2bX: 自动配置路由规则 (`route.json`) 拦截广告和回环地址，配置出站规则 (`custom_outbound.json`) 支持 IPv4/IPv6 双栈。
  - 自动检测 IPv6 环境并配置监听地址。
- **证书管理**: 集成 `acme.sh`，支持通过 Cloudflare API 自动申请和续期 SSL 证书。
- **服务管理**: 生成系统服务 (Systemd/OpenRC) 及全局管理命令 (`v2bx`)。

## 🐧 支持系统

| 系统 | 版本要求 |
| :--- | :--- |
| **CentOS** | 7+ (以及 RedHat, Rocky, AlmaLinux, Oracle Linux) |
| **Debian** | 8+ |
| **Ubuntu** | 16+ |
| **Alpine** | 3.x+ |
| **Arch** | 滚动更新 |

**支持架构**: `amd64` (x86_64), `arm64` (aarch64), `s390x`

## 🚀 快速开始

下载脚本并添加执行权限：

```bash
wget -N https://raw.githubusercontent.com/LiukerSun/v2server/main/install.sh && chmod +x install.sh
```
*(注意：请将 URL 替换为实际存放 `install.sh` 的仓库地址)*

### 1. 安装 V2bX

V2bX 是一个基于 Xray/Sing-box/Hysteria2 的高性能后端。

**基础安装 (无证书):**

```bash
bash install.sh --type v2bx \
  --backend-url "https://api.example.com" \
  --backend-key "your_panel_key" \
  --node-id 1 \
  --core-type xray \
  --transport-type tcp
```

**进阶安装 (自动申请 SSL 证书):**

如果你的节点需要 TLS (如 Trojan, Hysteria2)，脚本支持使用 Cloudflare API 自动申请证书。

```bash
bash install.sh --type v2bx \
  --backend-url "https://api.example.com" \
  --backend-key "your_panel_key" \
  --node-id 1 \
  --core-type hysteria2 \
  --transport-type hysteria2 \
  --cert-domain "node.example.com" \
  --acme-email "admin@example.com" \
  --cf-key "YOUR_CLOUDFLARE_GLOBAL_API_KEY" \
  --cf-email "YOUR_CLOUDFLARE_EMAIL"
```

---

## 📄 配置文件方式安装 (推荐)

对于复杂的配置，建议创建一个配置文件（例如 `config.yml`），然后通过脚本读取安装。

1. 创建 `install_config.yml`:

```yaml
# 面板对接信息
backend_url: https://api.example.com
backend_key: password123
node_id: 10

# V2bX 核心配置 (v2bx 必需)
core_type: sing          # 可选: xray, sing, hysteria2
transport_type: shadowsock # 对应面板的传输协议类型

# 证书配置 (可选，填写则自动申请)
cert_domain: node.example.com
acme_email: admin@example.com
# Cloudflare API 凭证 (用于申请证书)
cf_key: xxxxxxxxxxxxxxxxxxxxx
cf_email: admin@example.com
```

2. 运行安装命令:

```bash
# 使用 -c 参数
bash install.sh --type v2bx --config install_config.yml

# 或者直接跟文件名
bash install.sh install_config.yml
```

---

## 🛠 参数说明

| 参数 | 简写 | 必填 | 描述 | 示例 |
| :--- | :--- | :--- | :--- | :--- |
| `--type` | `-t` | 否 | 安装类型: `v2bx` (默认) | `--type v2bx` |
| `--version` | `-v` | 否 | 指定安装版本 (默认自动获取最新版) | `--version v0.4.1` |
| `--config` | `-c` | 否 | 读取配置文件路径 | `--config config.yml` |
| `--backend-url` | | 是* | 面板 API 地址 | `--backend-url https://api.site.com` |
| `--backend-key` | | 是* | 面板通信密钥 (Token) | `--backend-key mypassword` |
| `--node-id` | | 是* | 面板节点 ID | `--node-id 5` |
| `--core-type` | | V2bX | V2bX 核心类型: `xray`, `sing`, `hysteria2` | `--core-type xray` |
| `--transport-type` | | V2bX | 传输协议类型 (需与面板一致) | `--transport-type tcp` |
| `--cert-domain` | | 否 | 证书域名，填写则自动通过 DNS 申请证书 | `--cert-domain node.site.com` |
| `--acme-email` | | 否 | Let's Encrypt 注册邮箱 | `--acme-email admin@site.com` |
| `--cf-key` | | 否 | Cloudflare Global API Key | |
| `--cf-email` | | 否 | Cloudflare 账户邮箱 | |
| `--force-reinstall` | | 否 | 强制重新安装 (覆盖现有程序) | `--force-reinstall` |
| `--repo-base` | `-r` | 否 | 自定义下载仓库地址 | |

*\* 如果使用配置文件 (--config)，则命令行参数可选。*

---

## 💻 服务管理

安装完成后，脚本会注册系统服务，并提供简化的管理命令 `v2bx`。

### V2bX 管理命令

| 命令 | 说明 |
| :--- | :--- |
| `v2bx start` | 启动服务 |
| `v2bx stop` | 停止服务 |
| `v2bx restart` | 重启服务 |
| `v2bx status` | 查看运行状态 |
| `v2bx log` | 查看实时日志 |
| `v2bx config` | 查看当前配置文件内容 |
| `v2bx version` | 查看当前安装版本 |

---

## 📂 目录结构

| 路径 | 说明 |
| :--- | :--- |
| **/usr/local/V2bX/** | V2bX 程序安装目录 |
| **/etc/V2bX/** | V2bX 配置文件目录 (`config.json`, `route.json` 等) |
| **/var/log/** | 系统日志目录 (部分系统) |
| **/usr/bin/v2bx** | 全局管理命令软链接 |

## ❓ 常见问题

1. **证书申请失败？**
   - 目前脚本仅支持 Cloudflare DNS 验证。
   - 确保提供了正确的 `Global API Key` (不是 Token) 和 `Email`。
   - 脚本使用 `acme.sh` 申请证书，日志中会有详细的 acme 执行过程。

2. **启动失败？**
   - 使用 `v2bx log` 查看报错信息。
   - 检查配置文件 `/etc/V2bX/config.json` 是否生成正确。
   - 确保端口没有被占用。

3. **如何更新版本？**
   - 重新运行安装脚本即可，脚本会自动下载最新版覆盖安装。
   - 配置文件通常不会被覆盖，除非使用 `--force-reinstall` 或手动删除。
