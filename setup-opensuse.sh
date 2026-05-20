#!/usr/bin/env bash
#
# openSUSE Leap / Tumbleweed / SLES
#
# TESTED STACK (edit PHP_MAJOR below — openSUSE package prefix php8, php7, etc.):
#   MariaDB 10.x  |  Apache 2.4  |  PHP 8.3 FPM (distribution packages)
#
#
# Usage:
#   sudo ./setup-opensuse.sh --domain example.com --email you@example.com
#
set -euo pipefail

# --- Edit PHP major for zypper packages (e.g. 8 → php8-fpm, php8-mysql) ---
PHP_MAJOR="${PHP_MAJOR:-8}"
PHP_VERSION="${PHP_VERSION:-8.3}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export WP_OPT_LIB_ONLY=1
# shellcheck source=setup.sh
source "${SCRIPT_DIR}/setup.sh"

CONFIG_DIR="${SCRIPT_DIR}/configs/opensuse"
WEB_USER="wwwrun"
HTTPD_SVC="apache2"
PHPFPM_SVC="php${PHP_MAJOR}-fpm"
MYSQL_SVC="mariadb"
PHP_ETC="/etc/php${PHP_MAJOR}"
PHP_PKG_PREFIX="php${PHP_MAJOR}"

log()  { echo "[opensuse] $*"; }
warn() { echo "[opensuse] WARNING: $*" >&2; }

usage_opensuse() {
  cat <<EOF
openSUSE / SLES setup.

Tested: Apache 2.4, MariaDB 10.x, PHP ${PHP_VERSION} (php${PHP_MAJOR}-* packages).
Edit PHP_MAJOR / PHP_VERSION at top of setup-opensuse.sh.

  sudo ./setup-opensuse.sh --domain example.com --email you@example.com
  sudo ./setup-opensuse.sh --help

After deploys: sudo systemctl reload php8-fpm

Docs: docs/SETUP-OPENSUSE.md
EOF
}

require_opensuse() {
  [[ -f /etc/os-release ]] || die "Cannot detect OS"
  # shellcheck source=/dev/null
  source /etc/os-release
  case "${ID}" in
    opensuse-leap|opensuse-tumbleweed|opensuse|sles|sl-micro)
      log "Detected: ${NAME} (${VERSION_ID:-unknown})"
      ;;
    *)
      die "This script is for openSUSE/SLES. Detected ID=${ID}. Use setup.sh or setup-rhel.sh."
      ;;
  esac
  command -v zypper >/dev/null 2>&1 || die "zypper is required"
}

install_packages() {
  log "Installing packages (zypper)..."
  run zypper refresh -y
  log "Installing PHP ${PHP_VERSION} (${PHP_PKG_PREFIX}-* packages)..."
  run zypper install -y \
    apache2 apache2-mod_proxy apache2-mod_proxy_fcgi apache2-mod_rewrite \
    apache2-mod_headers apache2-mod_ssl apache2-mod_http2 apache2-mod_deflate \
    apache2-mod_expires apache2-mod_remoteip \
    "${PHPFPM_SVC}" "${PHP_PKG_PREFIX}" "${PHP_PKG_PREFIX}-mysql" "${PHP_PKG_PREFIX}-xml" \
    "${PHP_PKG_PREFIX}-mbstring" "${PHP_PKG_PREFIX}-curl" "${PHP_PKG_PREFIX}-zip" \
    "${PHP_PKG_PREFIX}-gd" "${PHP_PKG_PREFIX}-intl" "${PHP_PKG_PREFIX}-bcmath" \
    "${PHP_PKG_PREFIX}-opcache" \
    mariadb mariadb-client \
    fail2ban certbot python3-certbot-apache \
    git unzip firewalld

  # imagick/redis if available
  run zypper install -y "${PHP_PKG_PREFIX}-pear" "${PHP_PKG_PREFIX}-devel" 2>/dev/null || true
  run zypper install -y "${PHP_PKG_PREFIX}-redis" redis 2>/dev/null || true

  run systemctl enable "${HTTPD_SVC}" "${PHPFPM_SVC}" "${MYSQL_SVC}" firewalld 2>/dev/null || true
}

install_optional_extras() {
  [[ "${WITH_REDIS}" -eq 1 ]] || return 0
  log "Installing Redis..."
  run zypper install -y redis "${PHP_PKG_PREFIX}-redis"
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
  log "Enabling apache2 modules..."
  run a2enmod proxy proxy_fcgi rewrite headers ssl http2 deflate expires remoteip 2>/dev/null || true
  run a2enmod mpm_event 2>/dev/null || true
  run a2enconf "${PHPFPM_SVC}" 2>/dev/null || true
}

deploy_configs() {
  log "Deploying tuned configs (backup: ${BACKUP_DIR})..."

  backup_file /etc/apache2/conf.d/wp-mpm.conf
  run cp "${STAGING_DIR}/apache-mpm.conf" /etc/apache2/conf.d/wp-mpm.conf

  backup_file /etc/apache2/conf.d/wp-vhost.conf
  run cp "${STAGING_DIR}/apache-vhost-http.conf" /etc/apache2/conf.d/wp-vhost.conf

  backup_file /etc/my.cnf.d/wp-optimisation.cnf
  run mkdir -p /etc/my.cnf.d
  run cp "${STAGING_DIR}/mysqld.cnf" /etc/my.cnf.d/wp-optimisation.cnf

  local php_ini="${PHP_ETC}/fpm/php.ini"
  [[ -f "${php_ini}" ]] || php_ini="${PHP_ETC}/cli/php.ini"
  backup_file "${php_ini}"
  run cp "${STAGING_DIR}/php.ini" "${php_ini}"

  backup_file "${PHP_ETC}/fpm/conf.d/10-opcache-custom.ini"
  run mkdir -p "${PHP_ETC}/fpm/conf.d"
  run cp "${STAGING_DIR}/opcache.ini" "${PHP_ETC}/fpm/conf.d/10-opcache-custom.ini"

  backup_file "${PHP_ETC}/fpm/php-fpm.d/www.conf"
  run mkdir -p "${PHP_ETC}/fpm/php-fpm.d"
  run cp "${STAGING_DIR}/php-fpm-www.conf" "${PHP_ETC}/fpm/php-fpm.d/www.conf"

  run mkdir -p /var/log/php /var/log/php8-fpm
  run chown "${WEB_USER}:www" /var/log/php 2>/dev/null || true
  run chown -R "${WEB_USER}:www" /var/www/html 2>/dev/null || true
}

reset_mysql_logs_if_needed() {
  [[ "${RESET_MYSQL_LOGS}" -eq 1 ]] || return 0
  warn "Resetting InnoDB log files (downtime)..."
  run systemctl stop "${MYSQL_SVC}"
  run rm -f /var/lib/mysql/ib_logfile*
}

validate_and_restart() {
  log "Validating configuration..."
  run "${PHPFPM_SVC}" -t 2>/dev/null || warn "${PHPFPM_SVC} -t skipped"
  run mysqld --validate-config 2>/dev/null || run mariadbd --validate-config 2>/dev/null || true
  run apache2ctl configtest 2>/dev/null || run apachectl configtest

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
  ssl_site="$(find /etc/apache2/conf.d -name '*-le-ssl.conf' 2>/dev/null | head -1)"
  [[ -z "${ssl_site}" ]] && ssl_site="/etc/apache2/conf.d/wp-vhost-le-ssl.conf"

  if [[ -f "${STAGING_DIR}/apache-vhost-ssl.conf" ]]; then
    log "Applying hardened SSL vhost to ${ssl_site}..."
    backup_file "${ssl_site}"
    run cp "${STAGING_DIR}/apache-vhost-ssl.conf" "${ssl_site}"
    run apache2ctl configtest 2>/dev/null || run apachectl configtest
    run systemctl reload "${HTTPD_SVC}"
  fi

  run certbot renew --dry-run
}

print_summary() {
  cat <<EOF

================================================================================
openSUSE setup complete (${TIER_LABEL:-tier ${TIER} GB})
================================================================================
Tested stack: Apache 2.4, MariaDB 10.x, PHP ${PHP_VERSION} (${PHPFPM_SVC})
Configs: ${CONFIG_DIR}

Services:
  systemctl status apache2 ${PHPFPM_SVC} mariadb

Reload PHP after deploys:
  sudo systemctl reload ${PHPFPM_SVC}

Docs: docs/SETUP-OPENSUSE.md
================================================================================
EOF
}

main_opensuse() {
  [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && usage_opensuse && exit 0
  parse_args "$@"
  require_root
  require_opensuse
  require_configs
  trap cleanup EXIT
  run_install_pipeline
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main_opensuse "$@"
fi
