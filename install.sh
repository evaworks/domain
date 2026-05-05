#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RENEWAL_SCRIPT="$SCRIPT_DIR/ssl-renewal.sh"

NGINX_TEMPLATE='server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    server_name {{DOMAIN}};

    ssl_certificate /etc/letsencrypt/live/{{DOMAIN}}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/{{DOMAIN}}/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;

    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;

    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

    {{GZIP_CONFIG}}

    root {{DOC_ROOT}};
    index index.html index.htm;

    {{DOWNLOAD_CONFIG}}

    location / {
        try_files $uri $uri/ =404;
    }
}

server {
    listen 80;
    listen [::]:80;
    server_name {{DOMAIN}};

    return 301 https://$host$request_uri;
}'

log_info() {
    echo "[INFO] $1"
    echo "[INFO] $1" >> /var/log/install-ssl.log
}

log_warn() {
    echo "[WARN] $1"
    echo "[WARN] $1" >> /var/log/install-ssl.log
}

log_error() {
    echo "[ERROR] $1"
    echo "[ERROR] $1" >> /var/log/install-ssl.log
}

show_usage() {
    cat << 'EOF'
Usage: install.sh --domain DOMAIN --doc-root PATH [--download] [--gzip]

Options:
    --domain     Domain name (required)
    --doc-root  Document root path (required)
    --download Enable download mode (100G max file, autoindex)
    --gzip     Enable gzip compression

Examples:
    install.sh --domain example.com --doc-root /var/www/html
    install.sh --domain download.example.com --doc-root /var/www/download --download
EOF
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

install_requirements() {
    log_info "Checking requirements..."

    if ! which nginx >/dev/null 2>&1; then
        log_info "Installing nginx..."
        apt update
        apt install -y nginx
    else
        log_info "nginx already installed, skipping"
    fi

    if ! which certbot >/dev/null 2>&1; then
        log_info "Installing certbot..."
        apt update
        apt install -y certbot python3-certbot-nginx
    else
        log_info "certbot already installed, skipping"
    fi
}

check_ports() {
    log_info "Checking ports 80 and 443..."

    if which netstat >/dev/null 2>&1; then
        if netstat -tuln 2>/dev/null | grep -q ':80 '; then
            log_warn "Port 80 in use, stopping services..."
            systemctl stop nginx 2>/dev/null || true
            systemctl stop apache2 2>/dev/null || true
        fi
    elif which ss >/dev/null 2>&1; then
        if ss -tuln 2>/dev/null | grep -q ':80 '; then
            log_warn "Port 80 in use, stopping services..."
            systemctl stop nginx 2>/dev/null || true
            systemctl stop apache2 2>/dev/null || true
        fi
    fi
}

create_doc_root() {
    log_info "Creating document root: $DOC_ROOT"

    if [[ ! -d "$DOC_ROOT" ]]; then
        mkdir -p "$DOC_ROOT"
        echo "<html><body><h1>$DOC_ROOT</h1></body></html>" > "$DOC_ROOT/index.html"
    else
        log_info "Directory already exists: $DOC_ROOT"
    fi
}

request_ssl_cert() {
    log_info "Requesting SSL certificate for: $DOMAIN"

    certbot certonly --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email

    log_info "Certificate obtained successfully"
}

generate_nginx_config() {
    log_info "Generating nginx configuration..."

    local config_file="/etc/nginx/sites-available/${DOMAIN}.conf"
    local config_link="/etc/nginx/sites-enabled/${DOMAIN}.conf"

    echo "$NGINX_TEMPLATE" > "$config_file"
    sed -i "s|{{DOMAIN}}|$DOMAIN|g" "$config_file"

    if [[ "$DOWNLOAD_MODE" == "on" ]]; then
        sed -i 's|{{DOWNLOAD_CONFIG}}|client_max_body_size 100G;\n    autoindex on;\n    autoindex_exact_size on;\n    autoindex_localtime on;\n    add_header Cache-Control "no-store, no-cache, must-revalidate";|g' "$config_file"
    else
        sed -i 's|{{DOWNLOAD_CONFIG}}| |g' "$config_file"
    fi

    sed -i "s|{{DOC_ROOT}}|$DOC_ROOT|g" "$config_file"

    if [[ "$GZIP_ENABLED" == "on" ]]; then
        sed -i 's|{{GZIP_CONFIG}}|gzip on;\n    gzip_types *;|g' "$config_file"
    else
        sed -i 's|{{GZIP_CONFIG}}| |g' "$config_file"
    fi

    if [[ ! -L "$config_link" ]]; then
        ln -sf "$config_file" "$config_link"
    fi

    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

    log_info "Nginx config created: $config_file"
}

reload_nginx() {
    log_info "Testing and reloading nginx..."

    nginx -t
    systemctl reload nginx
    systemctl enable nginx

    log_info "nginx reloaded successfully"
}

setup_cron_renewal() {
    log_info "Setting up automatic renewal cron job..."

    local cron_entry="0 3 * * 0 $RENEWAL_SCRIPT >> /var/log/ssl-renewal.log 2>&1"

    (crontab -l 2>/dev/null | grep -v "$RENEWAL_SCRIPT"; echo "$cron_entry") | crontab -

    log_info "Cron job set up: weekly Sunday 3:00 AM"
}

main() {
    if [[ $# -eq 0 ]]; then
        show_usage
    fi

    DOMAIN=""
    DOC_ROOT=""
    DOWNLOAD_MODE=""
    GZIP_ENABLED=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --doc-root)
                DOC_ROOT="$2"
                shift 2
                ;;
            --download)
                DOWNLOAD_MODE="on"
                shift
                ;;
            --gzip)
                GZIP_ENABLED="on"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                ;;
        esac
    done

    if [[ -z "$DOMAIN" || -z "$DOC_ROOT" ]]; then
        log_error "--domain and --doc-root are required"
        show_usage
    fi

    log_info "Starting SSL certificate setup for: $DOMAIN"

    log_info "Step 1: Checking root..."
    check_root

    log_info "Step 2: Installing requirements..."
    install_requirements

    log_info "Step 3: Checking ports..."
    check_ports

    log_info "Step 4: Creating document root..."
    create_doc_root

    log_info "Step 5: Requesting SSL certificate..."
    request_ssl_cert

    log_info "Step 6: Generating nginx config..."
    generate_nginx_config

    log_info "Step 7: Reloading nginx..."
    reload_nginx

    log_info "Step 8: Setting up cron renewal..."
    setup_cron_renewal

    log_info "========================================="
    log_info "SSL certificate setup completed!"
    log_info "========================================="
    log_info "Domain: $DOMAIN"
    log_info "Doc root: $DOC_ROOT"
    log_info "Cert path: /etc/letsencrypt/live/$DOMAIN/"
    log_info "Nginx config: /etc/nginx/sites-available/$DOMAIN.conf"
    
    [[ "$DOWNLOAD_MODE" == "on" ]] && log_info "Download mode: enabled"
    [[ "$GZIP_ENABLED" == "on" ]] && log_info "Gzip: enabled"
}

main "$@"