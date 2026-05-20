#!/usr/bin/env bash
#
# RHEL / CentOS Stream / Rocky / AlmaLinux / Oracle Linux
# Apache httpd + PHP 8.3 (Remi) + MariaDB + tuning
#
# Usage:
#   sudo ./setup-rhel.sh --domain example.com --email you@example.com
#   sudo ./setup-rhel.sh --tier 64 --with-redis --domain example.com --email you@example.com
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export WP_OPT_LIB_ONLY=1
# shellcheck source=setup.sh
source "${SCRIPT_DIR}/setup.sh"

CONFIG_DIR="${SCRIPT_DIR}/configs/rhel"
WEB_USER="apache"
HTTPD_SVC="httpd"
PHPFPM_SVC="php-fpm"
MYSQL_SVC="mariadb"

log()  { echo "[rhel] $*"; }
warn() { echo "[rhel] WARNING: $*" >&2; }

usage_rhel() {
  cat <<EOF
RHEL-family setup (Rocky, Alma, CentOS Stream, RHEL, Oracle Linux).

Same options as setup.sh. Tested on EL 8 / 9 (PHP 8.3 via Remi).

  sudo ./setup-rhel.sh --domain example.com --email you@example.com
  sudo ./setup-rhel.sh --tier 128 --with-redis --domain example.com --email you@example.com
  sudo ./setup-rhel.sh --help

After deploys: sudo systemctl reload php-fpm

Note: SELinux enforcing — script sets httpd_can_network_connect. Laravel/Redis queues may need extra booleans.
EOF
}

require_rhel() {
  [[ -f /etc/os-release ]] || die "Cannot detect OS"
  # shellcheck source=/dev/null
  source /etc/os-release
  case "${ID}" in
    rhel|centos|rocky|almalinux|ol|fedora)
      log "Detected: ${NAME} (${VERSION_ID:-unknown})"
      ;;
    *)
      die "This script is for RHEL family systems. Detected ID=${ID}. Use setup.sh (Debian/Ubuntu) or setup-opensuse.sh."
      ;;
  esac
  command -v dnf >/dev/null 2>&1 || die "dnf is required"
}

install_packages() {
  log "Installing packages (dnf + Remi PHP 8.3)..."
  local el_major remi_rpm
  el_major="${VERSION_ID%%.*}"
  [[ -z "${el_major}" || "${el_major}" -lt 8 ]] && el_major=9

  run dnf install -y epel-release
  if [[ "${el_major}" -ge 9 ]]; then
    remi_rpm="https://rpms.remirepo.net/enterprise/remi-release-9.rpm"
  else
    remi_rpm="https://rpms.remirepo.net/enterprise/remi-release-8.rpm"
  fi
  run dnf install -y "${remi_rpm}" || warn "Remi repo may already be installed"
  run dnf module reset php -y 2>/dev/null || true
  run dnf module enable php:remi-8.3 -y 2>/dev/null || run dnf module enable php:remi-8.2 -y 2>/dev/null || true

  run dnf install -y \
    php php-fpm php-cli php-common php-mysqlnd php-xml php-mbstring \
    php-curl php-zip php-gd php-intl php-bcmath php-pecl-imagick php-opcache \
    httpd mod_ssl mod_http2 mod_proxy mod_proxy_fcgi mod_rewrite mod_headers \
    mod_deflate mod_expires mod_remoteip \
    mariadb-server mariadb \
    fail2ban mod_security certbot python3-certbot-apache \
    git unzip firewalld policycoreutils-python-utils

  run systemctl enable "${HTTPD_SVC}" "${PHPFPM_SVC}" "${MYSQL_SVC}" firewalld 2>/dev/null || true
}

install_optional_extras() {
  [[ "${WITH_REDIS}" -eq 1 ]] || return 0
  log "Installing Redis..."
  run dnf install -y redis php-pecl-redis
  run systemctl enable redis
  run systemctl restart redis
}

configure_firewall() {
  [[ "${SKIP_UFW}" -eq 1 ]] && return 0
  log "Configuring firewalld..."
  run systemctl enable firewalld 2>/dev/null || true
  run systemctl start firewalld 2>/dev/null || true
  run firewall-cmd --permanent --add-service=ssh
  run firewall-cmd --permanent --add-service=http
  run firewall-cmd --permanent --add-service=https
  run firewall-cmd --reload
}

configure_apache_modules() {
  log "Configuring httpd (event MPM + PHP-FPM proxy)..."
  local mpm_conf="/etc/httpd/conf.modules.d/00-mpm.conf"
  if [[ -f "${mpm_conf}" ]]; then
    run sed -i 's/^\s*LoadModule mpm_prefork/#LoadModule mpm_prefork/' "${mpm_conf}" 2>/dev/null || true
    run sed -i 's/^\s*LoadModule mpm_worker/#LoadModule mpm_worker/' "${mpm_conf}" 2>/dev/null || true
    if ! grep -q 'mpm_event_module' "${mpm_conf}" 2>/dev/null; then
      echo 'LoadModule mpm_event_module modules/mod_mpm_event.so' >> "${mpm_conf}"
    fi
  fi
  run mkdir -p /etc/httpd/conf.d
}

configure_selinux() {
  if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce 2>/dev/null)" == "Enforcing" ]]; then
    log "Applying SELinux booleans for httpd + PHP-FPM..."
    run setsebool -P httpd_can_network_connect 1 2>/dev/null || warn "setsebool httpd_can_network_connect failed"
    run restorecon -Rv /var/www/html 2>/dev/null || true
  fi
}

deploy_configs() {
  log "Deploying tuned configs (backup: ${BACKUP_DIR})..."

  backup_file /etc/httpd/conf.d/wp-mpm.conf
  run cp "${STAGING_DIR}/apache-mpm.conf" /etc/httpd/conf.d/wp-mpm.conf

  backup_file /etc/httpd/conf.d/wp-vhost.conf
  run cp "${STAGING_DIR}/apache-vhost-http.conf" /etc/httpd/conf.d/wp-vhost.conf

  backup_file /etc/my.cnf.d/wp-optimisation.cnf
  run mkdir -p /etc/my.cnf.d
  run cp "${STAGING_DIR}/mysqld.cnf" /etc/my.cnf.d/wp-optimisation.cnf

  backup_file /etc/php.ini
  run cp "${STAGING_DIR}/php.ini" /etc/php.ini

  backup_file /etc/php.d/10-opcache-custom.ini
  run mkdir -p /etc/php.d
  run cp "${STAGING_DIR}/opcache.ini" /etc/php.d/10-opcache-custom.ini

  backup_file /etc/php-fpm.d/www.conf
  run cp "${STAGING_DIR}/php-fpm-www.conf" /etc/php-fpm.d/www.conf

  run mkdir -p /var/log/php /var/log/php-fpm
  run chown "${WEB_USER}:${WEB_USER}" /var/log/php 2>/dev/null || run chown apache:apache /var/log/php
  run chown -R "${WEB_USER}:${WEB_USER}" /var/www/html 2>/dev/null || true
  configure_selinux
}

reset_mysql_logs_if_needed() {
  [[ "${RESET_MYSQL_LOGS}" -eq 1 ]] || return 0
  warn "Resetting InnoDB log files (downtime)..."
  run systemctl stop "${MYSQL_SVC}"
  run rm -f /var/lib/mysql/ib_logfile*
}

validate_and_restart() {
  log "Validating configuration..."
  run php-fpm -t 2>/dev/null || run php-fpm8.3 -t 2>/dev/null || warn "php-fpm -t skipped"
  run mysqld --validate-config 2>/dev/null || run mariadbd --validate-config 2>/dev/null || warn "DB validate skipped"
  run apachectl configtest

  reset_mysql_logs_if_needed

  log "Restarting services..."
  run systemctl enable "${MYSQL_SVC}" "${PHPFPM_SVC}" "${HTTPD_SVC}" certbot.timer 2>/dev/null || true
  run systemctl restart "${MYSQL_SVC}"
  run systemctl restart "${PHPFPM_SVC}"
  run systemctl restart "${HTTPD_SVC}"
  run systemctl start certbot.timer 2>/dev/null || true
}

run_certbot() {
  [[ "${SKIP_CERTBOT}" -eq 1 ]] && return 0
  log "Running Certbot for ${DOMAIN}..."
  run certbot --apache \
    -d "${DOMAIN}" -d "www.${DOMAIN}" \
    --email "${EMAIL}" \
    --agree-tos --non-interactive --redirect

  local ssl_site=""
  ssl_site="$(find /etc/httpd/conf.d -name '*-le-ssl.conf' 2>/dev/null | head -1)"
  [[ -z "${ssl_site}" ]] && ssl_site="/etc/httpd/conf.d/wp-vhost-le-ssl.conf"

  if [[ -f "${STAGING_DIR}/apache-vhost-ssl.conf" ]]; then
    log "Applying hardened SSL vhost to ${ssl_site}..."
    backup_file "${ssl_site}"
    run cp "${STAGING_DIR}/apache-vhost-ssl.conf" "${ssl_site}"
    run apachectl configtest
    run systemctl reload "${HTTPD_SVC}"
  fi

  run certbot renew --dry-run
}

print_summary() {
  cat <<EOF

================================================================================
RHEL-family setup complete (${TIER_LABEL:-tier ${TIER} GB})
================================================================================
Configs: ${CONFIG_DIR}
Backups: ${BACKUP_DIR}

Services:
  systemctl status httpd php-fpm mariadb

Reload PHP after deploys:
  sudo systemctl reload php-fpm

Database (manual):
  sudo mysql -e "CREATE DATABASE wordpress CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  sudo mysql -e "CREATE USER 'wpuser'@'localhost' IDENTIFIED BY 'STRONG_PASSWORD';"
  sudo mysql -e "GRANT ALL ON wordpress.* TO 'wpuser'@'localhost'; FLUSH PRIVILEGES;"

Docs: docs/SETUP-RHEL.md
================================================================================
EOF
}

main_rhel() {
  [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && usage_rhel && exit 0
  parse_args "$@"
  require_root
  require_rhel
  require_configs
  trap cleanup EXIT
  run_install_pipeline
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main_rhel "$@"
fi
