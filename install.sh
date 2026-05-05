#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/nginx.template.conf"
RENEWAL_SCRIPT="$SCRIPT_DIR/ssl-renewal.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "[INFO] $1"
    echo -e "[INFO] $1" >> /var/log/install-ssl.log
}

log_warn() {
    echo -e "[WARN] $1"
    echo -e "[WARN] $1" >> /var/log/install-ssl.log
}

log_error() {
    echo -e "[ERROR] $1"
    echo -e "[ERROR] $1" >> /var/log/install-ssl.log
}

show_usage() {
    cat << 'EOF'
Usage: install.sh --domains <domain:doc-root[,domain:doc-root>] [options]

Options:
    --domains    Domain and document root pairs (required)
                 Format: domain1:/path/to/docroot,domain2:/path/to/docroot
    --download  Enable download server mode (default: 100G)
    --gzip     Enable gzip compression (default: on for download mode)

Examples:
    install.sh --domains "example.com:/var/www/html"
    install.sh --domains "example.com:/var/www/download" --download
EOF
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

parse_domains() {
    local domains_str="$1"
    IFS=',' read -ra DOMAINS_RAW <<< "$domains_str"

    DOMAINS=()
    DOC_ROOTS=()
    PRIMARY_DOMAIN=""

    for entry in "${DOMAINS_RAW[@]}"; do
        domain="${entry%%:*}"
        doc_root="${entry#*:}"

        if [[ -z "$domain" || -z "$doc_root" || "$domain" == "$entry" ]]; then
            log_error "Invalid format: $entry (expected domain:doc-root)"
            exit 1
        fi

        DOMAINS+=("$domain")
        DOC_ROOTS+=("$doc_root")

        if [[ -z "$PRIMARY_DOMAIN" ]]; then
            PRIMARY_DOMAIN="$domain"
        fi
    done

    log_info "Primary domain: $PRIMARY_DOMAIN"
    log_info "Total domains: ${#DOMAINS[@]}"
}

install_requirements() {
    log_info "Checking requirements..."

    if ! which nginx >/dev/null 2>&1 && ! command -v nginx >/dev/null 2>&1; then
        log_info "Installing nginx..."
        apt update
        apt install -y nginx
    else
        log_info "nginx already installed, skipping"
    fi

    if ! which certbot >/dev/null 2>&1 && ! command -v certbot >/dev/null 2>&1; then
        log_info "Installing certbot..."
        apt update
        apt install -y certbot python3-certbot-nginx
    else
        log_info "certbot already installed, skipping"
    fi
}

check_ports() {
    log_info "Checking ports 80 and 443..."

    if command -v netstat &> /dev/null; then
        if netstat -tuln 2>/dev/null | grep -q ':80 '; then
            log_warn "Port 80 in use, stopping services..."
            systemctl stop nginx 2>/dev/null || true
            systemctl stop apache2 2>/dev/null || true
        fi
    elif command -v ss &> /dev/null; then
        if ss -tuln 2>/dev/null | grep -q ':80 '; then
            log_warn "Port 80 in use, stopping services..."
            systemctl stop nginx 2>/dev/null || true
            systemctl stop apache2 2>/dev/null || true
        fi
    fi
}

create_doc_roots() {
    log_info "Creating document roots..."

    for doc_root in "${DOC_ROOTS[@]}"; do
        if [[ ! -d "$doc_root" ]]; then
            log_info "Creating directory: $doc_root"
            mkdir -p "$doc_root"
            echo "<html><body><h1>$doc_root</h1></body></html>" > "$doc_root/index.html"
        else
            log_info "Directory already exists: $doc_root"
        fi
    done
}

request_ssl_cert() {
    log_info "Requesting SSL certificate..."

    local domains_arg="${DOMAINS[0]}"
    for i in "${!DOMAINS[@]}"; do
        if [[ $i -gt 0 ]]; then
            domains_arg="$domains_arg,${DOMAINS[$i]}"
        fi
    done

    log_info "Requesting certificate for: $domains_arg"

    certbot certonly --nginx -d "$domains_arg" --non-interactive --agree-tos --register-unsafely-without-email

    log_info "Certificate obtained successfully"
}

generate_server_block() {
    local domain="$1"
    local doc_root="$2"
    
    local block="    server {
        listen 80;
        listen [::]:80;
        server_name $domain;

        root $doc_root;
        index index.html index.htm;
"
    
    if [[ "$DOWNLOAD_MODE" == "on" ]]; then
        block="${block}        client_max_body_size $DOWNLOAD_SIZE;
        autoindex on;
        autoindex_exact_size on;
        autoindex_localtime on;
        add_header Cache-Control \"no-store, no-cache, must-revalidate\";
"
    fi
    
    block="${block}
        location / {
            try_files \$uri \$uri/ =404;
        }
    }"
    
    echo "$block"
}

generate_nginx_config() {
    log_info "Generating nginx configuration..."

    local config_file="/etc/nginx/sites-available/${PRIMARY_DOMAIN}.conf"
    local config_link="/etc/nginx/sites-enabled/${PRIMARY_DOMAIN}.conf"

    cp "$TEMPLATE_FILE" "$config_file"

    sed -i "s|{{PRIMARY_DOMAIN}}|$PRIMARY_DOMAIN|g" "$config_file"

    local server_blocks=""
    for i in "${!DOMAINS[@]}"; do
        local block
        block=$(generate_server_block "${DOMAINS[$i]}" "${DOC_ROOTS[$i]}")
        server_blocks="${server_blocks}
${block}"
    done

    sed -i "s|{{SERVER_BLOCKS}}|$server_blocks|g" "$config_file"

    local domains_nginx=""
    for domain in "${DOMAINS[@]}"; do
        if [[ -n "$domains_nginx" ]]; then
            domains_nginx+=" "
        fi
        domains_nginx+="$domain"
    done
    sed -i "s|{{DOMAINS}}|$domains_nginx|g" "$config_file"

    if [[ -n "$GZIP_ENABLED" ]]; then
        if [[ "$GZIP_ENABLED" == "on" ]]; then
            sed -i 's|{{GZIP_CONFIG}}|    gzip on;\n    gzip_types *;|g' "$config_file"
        else
            sed -i 's|{{GZIP_CONFIG}}|    # gzip disabled|g' "$config_file"
        fi
    else
        sed -i 's|{{GZIP_CONFIG}}|    gzip on;\n    gzip_types *;|g' "$config_file"
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

    DOMAINS_PARAM=""
    DOWNLOAD_MODE=""
    DOWNLOAD_SIZE="100G"
    GZIP_ENABLED=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --domains)
                DOMAINS_PARAM="$2"
                shift 2
                ;;
            --download)
                DOWNLOAD_MODE="on"
                if [[ "${2:-}" != "" && "${2:-}" != --* ]]; then
                    DOWNLOAD_SIZE="$2"
                    shift
                fi
                shift
                ;;
            --download=*)
                DOWNLOAD_MODE="on"
                DOWNLOAD_SIZE="${1#*=}"
                shift
                ;;
            --gzip)
                GZIP_ENABLED="on"
                shift
                ;;
            --nogzip)
                GZIP_ENABLED="off"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                ;;
        esac
    done

    if [[ -z "$DOMAINS_PARAM" ]]; then
        log_error "--domains is required"
        show_usage
    fi

    log_info "Starting SSL certificate setup..."

    log_info "Step 1: Checking root..."
    check_root
    
    log_info "Step 2: Parsing domains..."
    parse_domains "$DOMAINS_PARAM"
    
    log_info "Step 3: Installing requirements (nginx, certbot)..."
    install_requirements
    
    log_info "Step 4: Checking ports 80/443..."
    check_ports
    
    log_info "Step 5: Creating document roots..."
    create_doc_roots
    
    log_info "Step 6: Requesting SSL certificate..."
    request_ssl_cert
    
    log_info "Step 7: Generating nginx config..."
    generate_nginx_config
    
    log_info "Step 8: Reloading nginx..."
    reload_nginx
    
    log_info "Step 9: Setting up cron renewal..."
    setup_cron_renewal

    log_info "========================================="
    log_info "SSL certificate setup completed!"
    log_info "========================================="
    log_info "Primary domain: $PRIMARY_DOMAIN"
    log_info "Certificate path: /etc/letsencrypt/live/$PRIMARY_DOMAIN/"
    log_info "Nginx config: /etc/nginx/sites-available/$PRIMARY_DOMAIN.conf"
    log_info "Renewal: automatic (weekly check)"
    [[ -n "$DOWNLOAD_MODE" ]] && log_info "Download mode: enabled (max $DOWNLOAD_SIZE)"
    [[ "$GZIP_ENABLED" == "on" ]] && log_info "Gzip: enabled"
}

main "$@"