#!/usr/bin/env bash
#
# WordPress server one-shot setup (Ubuntu 22.04 / 24.04)
# Apache event MPM + PHP 8.3 FPM + MySQL 8 + tuning from configs/
#
# Usage:
#   sudo ./setup.sh --domain example.com --email you@example.com
#   sudo ./setup.sh --tier 32 --domain example.com --email you@example.com
#   sudo ./setup.sh --tier 16 --skip-certbot
#   sudo ./setup.sh --help
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/configs"
STAGING_DIR=""
BACKUP_DIR=""

DOMAIN=""
EMAIL=""
TIER="64"
SKIP_CERTBOT=0
SKIP_UFW=0
RESET_MYSQL_LOGS=0
WITH_REDIS=0
DRY_RUN=0

log()  { echo "[setup] $*"; }
warn() { echo "[setup] WARNING: $*" >&2; }
die()  { echo "[setup] ERROR: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
PHP application server setup (WordPress, Laravel, CodeIgniter) — stack + optimisations.

Required for SSL:
  --domain DOMAIN       Primary domain (e.g. example.com)
  --email EMAIL         Email for Let's Encrypt

Optional:
  --tier TIER           64 | 32 | 16 | 8  (GB RAM class, default: 64)
  --skip-certbot        Do not run Certbot (HTTP only)
  --skip-ufw            Do not configure UFW
  --reset-mysql-logs    Stop MySQL and remove ib_logfile* before start
  --with-redis          Install Redis server + php8.3-redis (Laravel/cache/queues)
  --dry-run             Print actions only
  --help                Show this help

Examples:
  sudo ./setup.sh --domain example.com --email admin@example.com
  sudo ./setup.sh --with-redis --domain example.com --email admin@example.com
  sudo ./setup.sh --tier 32 --domain example.com --email admin@example.com
  sudo ./setup.sh --tier 8 --skip-certbot

After app deploys (OPcache production mode):
  sudo systemctl reload php8.3-fpm
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain) DOMAIN="${2:-}"; shift 2 ;;
      --email)  EMAIL="${2:-}"; shift 2 ;;
      --tier)   TIER="${2:-}"; shift 2 ;;
      --skip-certbot) SKIP_CERTBOT=1; shift ;;
      --skip-ufw)     SKIP_UFW=1; shift ;;
      --reset-mysql-logs) RESET_MYSQL_LOGS=1; shift ;;
      --with-redis) WITH_REDIS=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      --help|-h) usage; exit 0 ;;
      *) die "Unknown option: $1 (use --help)" ;;
    esac
  done

  case "${TIER}" in
    64|xl|XL) TIER="64" ;;
    32|l|L)  TIER="32" ;;
    16|m|M)  TIER="16" ;;
    8|s|S)   TIER="8" ;;
    *) die "Invalid --tier: ${TIER}. Use 64, 32, 16, or 8." ;;
  esac

  if [[ "${SKIP_CERTBOT}" -eq 0 ]]; then
    [[ -n "${DOMAIN}" ]] || die "--domain is required unless --skip-certbot is set"
    [[ -n "${EMAIL}"  ]] || die "--email is required unless --skip-certbot is set"
  fi
}

run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "[dry-run] $*"
  else
    "$@"
  fi
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Run as root: sudo ./setup.sh ..."
  fi
}

require_ubuntu() {
  [[ -f /etc/os-release ]] || die "Cannot detect OS"
  source /etc/os-release
  [[ "${ID}" == "ubuntu" ]] || warn "This script is tested on Ubuntu; you are on: ${ID}"
}

require_configs() {
  local f
  for f in mysqld.cnf php.ini opcache.ini php-fpm-www.conf apache-mpm.conf \
           apache-vhost-http.conf apache-vhost-ssl.conf; do
    [[ -f "${CONFIG_DIR}/${f}" ]] || die "Missing ${CONFIG_DIR}/${f}"
  done
}

init_staging() {
  STAGING_DIR="$(mktemp -d /tmp/wp-opt-staging.XXXXXX)"
  BACKUP_DIR="/root/wp-opt-backup-$(date +%Y%m%d-%H%M%S)"
  cp -a "${CONFIG_DIR}/." "${STAGING_DIR}/"
  log "Staging configs in ${STAGING_DIR}"
}

apply_tier() {
  log "Applying tier: ${TIER} GB RAM class"

  local pool max_conn buffer_pool pool_inst tmp heap \
        opc_mem opc_strings max_children start_servers min_spare max_spare \
        max_workers memory_limit opc_validate

  case "${TIER}" in
    64)
      max_conn=300; buffer_pool="16G"; pool_inst=8; tmp="512M"; heap="512M"
      opc_mem=1024; opc_strings=128; max_children=56
      start_servers=8; min_spare=8; max_spare=16; max_workers=400
      memory_limit="256M"; opc_validate=0
      ;;
    32)
      max_conn=200; buffer_pool="8G"; pool_inst=4; tmp="256M"; heap="256M"
      opc_mem=512; opc_strings=64; max_children=28
      start_servers=4; min_spare=4; max_spare=8; max_workers=200
      memory_limit="256M"; opc_validate=0
      ;;
    16)
      max_conn=150; buffer_pool="4G"; pool_inst=4; tmp="128M"; heap="128M"
      opc_mem=256; opc_strings=32; max_children=14
      start_servers=2; min_spare=2; max_spare=4; max_workers=150
      memory_limit="256M"; opc_validate=0
      ;;
    8)
      max_conn=100; buffer_pool="2G"; pool_inst=2; tmp="64M"; heap="64M"
      opc_mem=128; opc_strings=16; max_children=8
      start_servers=2; min_spare=2; max_spare=3; max_workers=100
      memory_limit="192M"; opc_validate=1
      ;;
  esac

  sed -i \
    -e "s/^max_connections = .*/max_connections = ${max_conn}/" \
    -e "s/^innodb_buffer_pool_size = .*/innodb_buffer_pool_size = ${buffer_pool}/" \
    -e "s/^innodb_buffer_pool_instances = .*/innodb_buffer_pool_instances = ${pool_inst}/" \
    -e "s/^tmp_table_size = .*/tmp_table_size = ${tmp}/" \
    -e "s/^max_heap_table_size = .*/max_heap_table_size = ${heap}/" \
    "${STAGING_DIR}/mysqld.cnf"

  sed -i \
    -e "s/^memory_limit = .*/memory_limit = ${memory_limit}/" \
    "${STAGING_DIR}/php.ini"

  sed -i \
    -e "s/^opcache.memory_consumption=.*/opcache.memory_consumption=${opc_mem}/" \
    -e "s/^opcache.interned_strings_buffer=.*/opcache.interned_strings_buffer=${opc_strings}/" \
    -e "s/^opcache.validate_timestamps=.*/opcache.validate_timestamps=${opc_validate}/" \
    -e "s/^opcache.revalidate_freq=.*/opcache.revalidate_freq=$([[ "${opc_validate}" == "0" ]] && echo 0 || echo 60)/" \
    "${STAGING_DIR}/opcache.ini"

  sed -i \
    -e "s/^pm.max_children = .*/pm.max_children = ${max_children}/" \
    -e "s/^pm.start_servers = .*/pm.start_servers = ${start_servers}/" \
    -e "s/^pm.min_spare_servers = .*/pm.min_spare_servers = ${min_spare}/" \
    -e "s/^pm.max_spare_servers = .*/pm.max_spare_servers = ${max_spare}/" \
    "${STAGING_DIR}/php-fpm-www.conf"

  sed -i \
    -e "s/^    MaxRequestWorkers.*/    MaxRequestWorkers        ${max_workers}/" \
    "${STAGING_DIR}/apache-mpm.conf"
}

substitute_domain() {
  [[ -n "${DOMAIN}" ]] || return 0
  sed -i "s/YOUR_DOMAIN/${DOMAIN}/g" \
    "${STAGING_DIR}/apache-vhost-http.conf" \
    "${STAGING_DIR}/apache-vhost-ssl.conf"
}

backup_file() {
  local target="$1"
  if [[ -f "${target}" ]]; then
    mkdir -p "${BACKUP_DIR}"
    cp -a "${target}" "${BACKUP_DIR}/"
  fi
}

install_packages() {
  log "Updating system and installing packages..."
  export DEBIAN_FRONTEND=noninteractive
  run apt-get update -qq
  run apt-get upgrade -y -qq
  run apt-get install -y -qq \
    software-properties-common apt-transport-https ca-certificates \
    curl gnupg lsb-release ufw git unzip

  run add-apt-repository -y ppa:ondrej/php
  run apt-get update -qq

  run apt-get install -y -qq \
    php8.3 php8.3-fpm php8.3-cli php8.3-common \
    php8.3-mysql php8.3-xml php8.3-mbstring php8.3-curl php8.3-zip \
    php8.3-gd php8.3-intl php8.3-bcmath php8.3-imagick php8.3-opcache

  run apt-get install -y -qq \
    apache2 mysql-server mysql-client fail2ban libapache2-mod-security2

  run apt-get install -y -qq certbot python3-certbot-apache
}

install_optional_extras() {
  [[ "${WITH_REDIS}" -eq 1 ]] || return 0
  log "Installing Redis (server + PHP extension)..."
  run apt-get install -y -qq redis-server php8.3-redis
  run systemctl enable redis-server
  run systemctl restart redis-server
}

configure_firewall() {
  [[ "${SKIP_UFW}" -eq 1 ]] && return 0
  log "Configuring UFW..."
  run ufw allow OpenSSH
  run ufw allow 'Apache Full'
  run ufw --force enable || true
}

configure_apache_modules() {
  log "Enabling Apache modules (event MPM + PHP-FPM)..."
  run a2dismod mpm_prefork 2>/dev/null || true
  for mod in php8.1 php8.2 php8.3; do
    run a2dismod "${mod}" 2>/dev/null || true
  done
  run a2enmod mpm_event ssl rewrite headers proxy proxy_fcgi setenvif \
    http2 expires deflate remoteip security2
  run a2enconf php8.3-fpm
}

deploy_configs() {
  log "Deploying tuned configs (backup: ${BACKUP_DIR})..."

  backup_file /etc/apache2/mods-available/mpm_event.conf
  run cp "${STAGING_DIR}/apache-mpm.conf" /etc/apache2/mods-available/mpm_event.conf

  backup_file /etc/apache2/sites-available/000-default.conf
  run cp "${STAGING_DIR}/apache-vhost-http.conf" /etc/apache2/sites-available/000-default.conf
  run a2ensite 000-default.conf 2>/dev/null || true

  backup_file /etc/mysql/mysql.conf.d/mysqld.cnf
  run cp "${STAGING_DIR}/mysqld.cnf" /etc/mysql/mysql.conf.d/mysqld.cnf

  backup_file /etc/php/8.3/fpm/php.ini
  run cp "${STAGING_DIR}/php.ini" /etc/php/8.3/fpm/php.ini

  backup_file /etc/php/8.3/fpm/conf.d/10-opcache-custom.ini
  run cp "${STAGING_DIR}/opcache.ini" /etc/php/8.3/fpm/conf.d/10-opcache-custom.ini

  backup_file /etc/php/8.3/fpm/pool.d/www.conf
  run cp "${STAGING_DIR}/php-fpm-www.conf" /etc/php/8.3/fpm/pool.d/www.conf

  run mkdir -p /var/log/php /var/log/php-fpm
  run chown www-data:www-data /var/log/php
  run chown -R www-data:www-data /var/www/html 2>/dev/null || true
}

reset_mysql_logs_if_needed() {
  [[ "${RESET_MYSQL_LOGS}" -eq 1 ]] || return 0
  warn "Resetting InnoDB log files (downtime)..."
  run systemctl stop mysql
  run rm -f /var/lib/mysql/ib_logfile*
}

validate_and_restart() {
  log "Validating configuration..."
  run mysqld --validate-config
  run apachectl configtest

  reset_mysql_logs_if_needed

  log "Restarting services..."
  run systemctl enable mysql php8.3-fpm apache2 certbot.timer
  run systemctl restart mysql
  run systemctl restart php8.3-fpm
  run systemctl restart apache2
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
  ssl_site="$(find /etc/apache2/sites-available -name '*-le-ssl.conf' 2>/dev/null | head -1)"
  if [[ -z "${ssl_site}" ]]; then
    ssl_site="/etc/apache2/sites-available/000-default-le-ssl.conf"
  fi

  if [[ -f "${STAGING_DIR}/apache-vhost-ssl.conf" ]]; then
    log "Applying hardened SSL vhost to ${ssl_site}..."
    backup_file "${ssl_site}"
    run cp "${STAGING_DIR}/apache-vhost-ssl.conf" "${ssl_site}"
    run a2ensite "$(basename "${ssl_site}")" 2>/dev/null || true
    run apachectl configtest
    run systemctl reload apache2
  fi

  run certbot renew --dry-run
}

print_summary() {
  cat <<EOF

================================================================================
Setup complete (tier: ${TIER} GB class)
================================================================================
Configs applied from: ${CONFIG_DIR}
Backups (if any):     ${BACKUP_DIR}

Services:
  systemctl status apache2 php8.3-fpm mysql

Redis (--with-redis): 127.0.0.1:6379

After each app deploy:
  sudo systemctl reload php8.3-fpm

Create WordPress database (manual):
  sudo mysql -e "CREATE DATABASE wordpress CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  sudo mysql -e "CREATE USER 'wpuser'@'localhost' IDENTIFIED BY 'STRONG_PASSWORD';"
  sudo mysql -e "GRANT ALL ON wordpress.* TO 'wpuser'@'localhost'; FLUSH PRIVILEGES;"

Scaling reference: docs/SCALING.md
================================================================================
EOF
}

cleanup() {
  [[ -n "${STAGING_DIR}" && -d "${STAGING_DIR}" ]] && rm -rf "${STAGING_DIR}"
}

main() {
  parse_args "$@"
  require_root
  require_ubuntu
  require_configs
  trap cleanup EXIT

  init_staging
  apply_tier
  substitute_domain

  install_packages
  install_optional_extras
  configure_firewall
  configure_apache_modules
  deploy_configs
  validate_and_restart
  run_certbot
  print_summary
}

main "$@"
