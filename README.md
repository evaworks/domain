# Nginx SSL Auto Setup

一键配置 Nginx HTTPS 域名证书，支持自动续期。

## 一键安装

```bash
curl -sSL https://raw.githubusercontent.com/evaworks/domain/master/install.sh | sudo bash -s -- \
  --domain example.com \
  --doc-root /var/www/html
```

## 参数说明

| 参数 | 说明 | 必填 |
|------|------|------|
| `--domain` | 域名 | ✅ |
| `--doc-root` | 文档根目录 | ✅ |
| `--download` | 下载服务器模式（100G、目录列表） | - |
| `--gzip` | 启用 gzip 压缩 | - |

## 使用示例

### 普通网站

```bash
curl -sSL https://raw.githubusercontent.com/evaworks/domain/master/install.sh | sudo bash -s -- \
  --domain example.com \
  --doc-root /var/www/html
```

### 下载服务器

```bash
curl -sSL https://raw.githubusercontent.com/evaworks/domain/master/install.sh | sudo bash -s -- \
  --domain download.example.com \
  --doc-root /var/www/download \
  --download
```

### 下载服务器 + gzip

```bash
curl -sSL https://raw.githubusercontent.com/evaworks/domain/master/install.sh | sudo bash -s -- \
  --domain download.example.com \
  --doc-root /var/www/download \
  --download \
  --gzip
```

## 本地使用

```bash
git clone https://github.com/evaworks/domain.git
cd domain
chmod +x install.sh ssl-renewal.sh
sudo ./install.sh --domain example.com --doc-root /var/www/html
```

## 功能特性

- 自动申请 Let's Encrypt SSL 证书
- 自动配置 Nginx HTTPS
- 自动配置 HTTP → HTTPS 重定向
- 自动续期（证书剩余 30 天时）
- 下载服务器模式（100G+ 大文件、自动目录列表）
- 每周自动检测续期
- 不影响其他 nginx 项目

## 证书和配置路径

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