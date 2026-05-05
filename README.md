# Nginx SSL Auto Setup

一键配置 Nginx HTTPS 域名证书，支持自动续期。

## 一键安装

```bash
curl -sSL https://raw.githubusercontent.com/evaworks/domain/main/install.sh | sudo bash -s -- \
  --domains "example.com:/var/www/html"
```

## 参数说明

| 参数 | 说明 | 示例 |
|------|------|------|
| `--domains` | 域名和文档根目录 | `domain:/var/www/html` |
| `--download` | 下载服务器模式（默认100G） | `--download` |
| `--download=size` | 自定义最大文件大小 | `--download=500G` |
| `--gzip` | 启用 gzip 压缩 | `--gzip` |
| `--nogzip` | 禁用 gzip | `--nogzip` |

### domains 格式

```
domain1:/path/to/docroot,domain2:/path/to/docroot
```

多个域名用逗号分隔，每个域名独立配置 doc-root。

## 使用示例

### 普通网站

```bash
curl -sSL https://raw.githubusercontent.com/evaworks/domain/main/install.sh | sudo bash -s -- \
  --domains "example.com:/var/www/html"
```

### 多域名

```bash
curl -sSL https://raw.githubusercontent.com/evaworks/domain/main/install.sh | sudo bash -s -- \
  --domains "example.com:/var/www/html,sub.example.com:/var/www/sub"
```

### 下载服务器

```bash
curl -sSL https://raw.githubusercontent.com/evaworks/domain/main/install.sh | sudo bash -s -- \
  --domains "download.example.com:/var/www/download" \
  --download
```

### 下载服务器 + gzip

```bash
curl -sSL https://raw.githubusercontent.com/evaworks/domain/main/install.sh | sudo bash -s -- \
  --domains "download.example.com:/var/www/download" \
  --download --gzip
```

## 本地使用

```bash
git clone https://github.com/evaworks/domain.git
cd domain
chmod +x install.sh ssl-renewal.sh
sudo ./install.sh --domains "example.com:/var/www/html"
```

## 功能特性

- 自动申请 Let's Encrypt SSL 证书（SAN 证书）
- 自动配置 Nginx HTTPS
- 自动配置 HTTP → HTTPS 重定向
- 自动续期（证书剩余 30 天时）
- 支持多域名
- 下载服务器优化（100G+ 大文件、目录列表）
- 每周自动检测续期

## 文件说明

```
.
├── install.sh             # 主入口
├── nginx.template.conf   # Nginx 配置模板
├── ssl-renewal.sh       # 自动续期脚本
└── README.md           # 说明文档
```

## 证书路径

- 证书：`/etc/letsencrypt/live/{domain}/`
- Nginx 配置：`/etc/nginx/sites-available/{domain}.conf`

## 自动续期

- 每周日凌晨 3 点自动检测
- 证书剩余 ≤30 天时自动续期
- 日志：`/var/log/ssl-renewal.log`

## 依赖

- Ubuntu Server
- nginx
- certbot

脚本会自动安装依赖。