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
TIER_LABEL=""
USE_CALCULATED_TUNING=0
DETECTED_RAM_GB=0
DETECTED_CPU_COUNT=0
# Tuning variables (set by apply_tier or calculate_tuning_from_hardware)
TUNE_MAX_CONN=""
TUNE_BUFFER_POOL=""
TUNE_POOL_INST=""
TUNE_TMP=""
TUNE_HEAP=""
TUNE_OPC_MEM=""
TUNE_OPC_STRINGS=""
TUNE_MAX_CHILDREN=""
TUNE_START_SERVERS=""
TUNE_MIN_SPARE=""
TUNE_MAX_SPARE=""
TUNE_MAX_WORKERS=""
TUNE_SERVER_LIMIT=""
TUNE_MEMORY_LIMIT=""
TUNE_OPC_VALIDATE=""
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
  --tier TIER           128 | 64 | 32 | 16 | 8  (GB RAM class, default: 64)
  --skip-certbot        Do not run Certbot (HTTP only)
  --skip-ufw            Do not configure UFW
  --reset-mysql-logs    Stop MySQL and remove ib_logfile* before start
  --with-redis          Install Redis server + php8.3-redis (Laravel/cache/queues)
  --dry-run             Print actions only
  --help                Show this help

Examples:
  sudo ./setup.sh --domain example.com --email admin@example.com
  sudo ./setup.sh --with-redis --domain example.com --email admin@example.com
  sudo ./setup.sh --tier 128 --domain example.com --email admin@example.com
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
    128|xxl|XXL) TIER="128" ;;
    64|xl|XL)  TIER="64" ;;
    32|l|L)    TIER="32" ;;
    16|m|M)    TIER="16" ;;
    8|s|S)     TIER="8" ;;
    *) die "Invalid --tier: ${TIER}. Use 128, 64, 32, 16, or 8." ;;
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

clamp() {
  local v=$1 min=$2 max=$3
  (( v < min )) && v=$min
  (( v > max )) && v=$max
  echo "$v"
}

detect_hardware() {
  local ram_kb
  ram_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo)"
  DETECTED_RAM_GB=$(( ram_kb / 1024 / 1024 ))
  (( DETECTED_RAM_GB < 1 )) && DETECTED_RAM_GB=1
  DETECTED_CPU_COUNT="$(nproc 2>/dev/null || echo 1)"
  DETECTED_CPU_COUNT="$(clamp "${DETECTED_CPU_COUNT}" 1 128)"
}

nearest_fixed_tier() {
  local ram=$1
  if (( ram >= 96 )); then echo 128
  elif (( ram >= 48 )); then echo 64
  elif (( ram >= 24 )); then echo 32
  elif (( ram >= 12 )); then echo 16
  else echo 8
  fi
}

set_tuning_vars_from_tier() {
  local tier=$1
  TIER="${tier}"
  case "${TIER}" in
    128)
      TUNE_MAX_CONN=400; TUNE_BUFFER_POOL="32G"; TUNE_POOL_INST=16
      TUNE_TMP="768M"; TUNE_HEAP="768M"
      TUNE_OPC_MEM=2048; TUNE_OPC_STRINGS=192; TUNE_MAX_CHILDREN=96
      TUNE_START_SERVERS=12; TUNE_MIN_SPARE=12; TUNE_MAX_SPARE=24
      TUNE_MAX_WORKERS=700; TUNE_SERVER_LIMIT=28
      TUNE_MEMORY_LIMIT="256M"; TUNE_OPC_VALIDATE=0
      ;;
    64)
      TUNE_MAX_CONN=300; TUNE_BUFFER_POOL="16G"; TUNE_POOL_INST=8
      TUNE_TMP="512M"; TUNE_HEAP="512M"
      TUNE_OPC_MEM=1024; TUNE_OPC_STRINGS=128; TUNE_MAX_CHILDREN=56
      TUNE_START_SERVERS=8; TUNE_MIN_SPARE=8; TUNE_MAX_SPARE=16
      TUNE_MAX_WORKERS=400; TUNE_SERVER_LIMIT=16
      TUNE_MEMORY_LIMIT="256M"; TUNE_OPC_VALIDATE=0
      ;;
    32)
      TUNE_MAX_CONN=200; TUNE_BUFFER_POOL="8G"; TUNE_POOL_INST=4
      TUNE_TMP="256M"; TUNE_HEAP="256M"
      TUNE_OPC_MEM=512; TUNE_OPC_STRINGS=64; TUNE_MAX_CHILDREN=28
      TUNE_START_SERVERS=4; TUNE_MIN_SPARE=4; TUNE_MAX_SPARE=8
      TUNE_MAX_WORKERS=200; TUNE_SERVER_LIMIT=16
      TUNE_MEMORY_LIMIT="256M"; TUNE_OPC_VALIDATE=0
      ;;
    16)
      TUNE_MAX_CONN=150; TUNE_BUFFER_POOL="4G"; TUNE_POOL_INST=4
      TUNE_TMP="128M"; TUNE_HEAP="128M"
      TUNE_OPC_MEM=256; TUNE_OPC_STRINGS=32; TUNE_MAX_CHILDREN=14
      TUNE_START_SERVERS=2; TUNE_MIN_SPARE=2; TUNE_MAX_SPARE=4
      TUNE_MAX_WORKERS=150; TUNE_SERVER_LIMIT=16
      TUNE_MEMORY_LIMIT="256M"; TUNE_OPC_VALIDATE=0
      ;;
    8|*)
      TUNE_MAX_CONN=100; TUNE_BUFFER_POOL="2G"; TUNE_POOL_INST=2
      TUNE_TMP="64M"; TUNE_HEAP="64M"
      TUNE_OPC_MEM=128; TUNE_OPC_STRINGS=16; TUNE_MAX_CHILDREN=8
      TUNE_START_SERVERS=2; TUNE_MIN_SPARE=2; TUNE_MAX_SPARE=3
      TUNE_MAX_WORKERS=100; TUNE_SERVER_LIMIT=16
      TUNE_MEMORY_LIMIT="192M"; TUNE_OPC_VALIDATE=1
      TIER=8
      ;;
  esac
}

calculate_tuning_from_hardware() {
  local ram_gb=$1 cpu_count=$2
  local buffer_gb pool_inst tmp_mb opc_mem mem_mb max_children start spare_max \
        max_workers server_limit max_conn

  buffer_gb="$(clamp $(( ram_gb / 4 )) 2 32)"
  pool_inst="$(clamp "${cpu_count}" 2 16)"
  tmp_mb="$(clamp $(( ram_gb * 16 )) 64 768)"
  opc_mem="$(clamp $(( ram_gb * 16 )) 128 2048)"
  TUNE_OPC_STRINGS="$(clamp $(( opc_mem / 8 )) 16 192)"

  if (( ram_gb < 12 )); then
    mem_mb=192
    TUNE_OPC_VALIDATE=1
  else
    mem_mb=256
    TUNE_OPC_VALIDATE=0
  fi

  max_children="$(clamp $(( cpu_count * 7 )) 4 128)"
  local ram_cap=$(( ram_gb * 3 / 4 ))
  (( max_children > ram_cap )) && max_children=$ram_cap
  (( max_children < 4 )) && max_children=4

  start="$(clamp $(( max_children / 7 )) 2 12)"
  TUNE_MIN_SPARE="${start}"
  TUNE_START_SERVERS="${start}"
  TUNE_MAX_SPARE="$(clamp $(( max_children / 4 )) 3 24)"
  TUNE_MAX_CHILDREN="${max_children}"

  max_workers="$(clamp $(( max_children * 8 )) 100 800)"
  server_limit="$(clamp $(( (max_workers + 24) / 25 )) 8 32)"

  max_conn="$(clamp $(( max_children * 4 + 50 )) 100 500)"

  TUNE_MAX_CONN="${max_conn}"
  TUNE_BUFFER_POOL="${buffer_gb}G"
  TUNE_POOL_INST="${pool_inst}"
  TUNE_TMP="${tmp_mb}M"
  TUNE_HEAP="${tmp_mb}M"
  TUNE_OPC_MEM="${opc_mem}"
  TUNE_MEMORY_LIMIT="${mem_mb}M"
  TUNE_MAX_WORKERS="${max_workers}"
  TUNE_SERVER_LIMIT="${server_limit}"

  TIER_LABEL="auto (${ram_gb} GB RAM / ${cpu_count} CPUs)"
  USE_CALCULATED_TUNING=1
}

apply_tuning_to_staging() {
  [[ -n "${STAGING_DIR}" && -d "${STAGING_DIR}" ]] || die "Staging directory not initialized"

  local label="${TIER_LABEL:-tier ${TIER} GB}"
  log "Applying tuning: ${label}"

  sed -i \
    -e "s/^max_connections = .*/max_connections = ${TUNE_MAX_CONN}/" \
    -e "s/^innodb_buffer_pool_size = .*/innodb_buffer_pool_size = ${TUNE_BUFFER_POOL}/" \
    -e "s/^innodb_buffer_pool_instances = .*/innodb_buffer_pool_instances = ${TUNE_POOL_INST}/" \
    -e "s/^tmp_table_size = .*/tmp_table_size = ${TUNE_TMP}/" \
    -e "s/^max_heap_table_size = .*/max_heap_table_size = ${TUNE_HEAP}/" \
    "${STAGING_DIR}/mysqld.cnf"

  sed -i \
    -e "s/^memory_limit = .*/memory_limit = ${TUNE_MEMORY_LIMIT}/" \
    "${STAGING_DIR}/php.ini"

  sed -i \
    -e "s/^opcache.memory_consumption=.*/opcache.memory_consumption=${TUNE_OPC_MEM}/" \
    -e "s/^opcache.interned_strings_buffer=.*/opcache.interned_strings_buffer=${TUNE_OPC_STRINGS}/" \
    -e "s/^opcache.validate_timestamps=.*/opcache.validate_timestamps=${TUNE_OPC_VALIDATE}/" \
    -e "s/^opcache.revalidate_freq=.*/opcache.revalidate_freq=$([[ "${TUNE_OPC_VALIDATE}" == "0" ]] && echo 0 || echo 60)/" \
    "${STAGING_DIR}/opcache.ini"

  sed -i \
    -e "s/^pm.max_children = .*/pm.max_children = ${TUNE_MAX_CHILDREN}/" \
    -e "s/^pm.start_servers = .*/pm.start_servers = ${TUNE_START_SERVERS}/" \
    -e "s/^pm.min_spare_servers = .*/pm.min_spare_servers = ${TUNE_MIN_SPARE}/" \
    -e "s/^pm.max_spare_servers = .*/pm.max_spare_servers = ${TUNE_MAX_SPARE}/" \
    "${STAGING_DIR}/php-fpm-www.conf"

  sed -i \
    -e "s/^    ServerLimit.*/    ServerLimit              ${TUNE_SERVER_LIMIT}/" \
    -e "s/^    MaxRequestWorkers.*/    MaxRequestWorkers        ${TUNE_MAX_WORKERS}/" \
    "${STAGING_DIR}/apache-mpm.conf"
}

apply_tier() {
  set_tuning_vars_from_tier "${TIER}"
  TIER_LABEL="tier ${TIER} GB"
  apply_tuning_to_staging
}

print_tuning_plan() {
  cat <<EOF

  Detected hardware: ${DETECTED_RAM_GB} GB RAM, ${DETECTED_CPU_COUNT} CPU(s)
  Nearest fixed tier: ${NEAREST_TIER:-$(nearest_fixed_tier "${DETECTED_RAM_GB}")} GB class

  Planned tuning (${TIER_LABEL:-pending}):
    MySQL buffer pool:     ${TUNE_BUFFER_POOL:-—}
    MySQL max_connections: ${TUNE_MAX_CONN:-—}
    PHP-FPM max_children:  ${TUNE_MAX_CHILDREN:-—}
    OPcache memory (MB):   ${TUNE_OPC_MEM:-—}
    Apache MaxRequestWorkers: ${TUNE_MAX_WORKERS:-—}
    PHP memory_limit:      ${TUNE_MEMORY_LIMIT:-—}
    Est. sustained users:  ~$(( ${TUNE_MAX_CHILDREN:-0} * 2 ))–$(( ${TUNE_MAX_CHILDREN:-0} * 3 )) concurrent PHP requests

EOF
}

run_install_pipeline() {
  init_staging
  if [[ "${USE_CALCULATED_TUNING}" -eq 1 ]]; then
    apply_tuning_to_staging
  else
    apply_tier
  fi
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
Setup complete (${TIER_LABEL:-tier ${TIER} GB})
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
  run_install_pipeline
}

if [[ "${WP_OPT_LIB_ONLY:-}" != "1" ]]; then
  main "$@"
fi
