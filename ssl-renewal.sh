#!/bin/bash

LOG_FILE="/var/log/ssl-renewal.log"
RENEWAL_DAYS=30

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

check_and_renew() {
    log "Starting SSL certificate renewal check..."

    local dry_run_output
    dry_run_output=$(certbot renew --dry-run 2>&1) || true

    if echo "$dry_run_output" | grep -q "No renewals attempted"; then
        log "No certificates need renewal"
        return 0
    fi

    if echo "$dry_run_output" | grep -q "Certificate is due"; then
        log "Certificate needs renewal, attempting renew..."

        if certbot renew --quiet --non-interactive; then
            log "Certificate renewed successfully"
            systemctl reload nginx
            log "nginx reloaded"
        else
            log "ERROR: Certificate renewal failed"
            return 1
        fi
    else
        log "Certificate is not due for renewal yet"
    fi
}

main() {
    check_and_renew
    log "Renewal check completed"
}

main "$@"