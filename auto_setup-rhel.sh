#!/usr/bin/env bash
#
# Interactive auto setup — RHEL / CentOS / Rocky / AlmaLinux
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export WP_OPT_LIB_ONLY=1
# shellcheck source=setup-rhel.sh
source "${SCRIPT_DIR}/setup-rhel.sh"

NEAREST_TIER=""
TUNING_MODE=""

log()  { echo "[auto-rhel] $*"; }
warn() { echo "[auto-rhel] WARNING: $*" >&2; }

prompt() {
  local msg="$1" default="${2:-}" reply
  if [[ -n "${default}" ]]; then
    read -rp "${msg} [${default}]: " reply
    echo "${reply:-${default}}"
  else
    read -rp "${msg}: " reply
    echo "${reply}"
  fi
}

prompt_yn() {
  local msg="$1" default="${2:-y}" reply
  read -rp "${msg} [${default}]: " reply
  reply="${reply:-${default}}"
  [[ "${reply}" =~ ^[Yy] ]]
}

show_banner() {
  cat <<'EOF'

================================================================================
  PHP Application Server — Interactive Auto Setup (RHEL family)
  Rocky · Alma · CentOS Stream · RHEL · Oracle Linux
  Tested: MySQL/MariaDB 8 · Apache 2.4 · PHP 8.3 (edit PHP_VERSION in setup-rhel.sh)
================================================================================

EOF
}

detect_and_show_hardware() {
  detect_hardware
  NEAREST_TIER="$(nearest_fixed_tier "${DETECTED_RAM_GB}")"
  log "Detected: ${DETECTED_RAM_GB} GB RAM, ${DETECTED_CPU_COUNT} CPU(s)"
  log "Nearest preset tier: ${NEAREST_TIER} GB class"
}

choose_tuning_mode() {
  echo ""
  echo "  Tuning:"
  echo "    1) Auto-calculate from detected RAM/CPUs (recommended)"
  echo "    2) Use nearest preset tier (${NEAREST_TIER} GB)"
  echo "    3) Pick preset tier (128 / 64 / 32 / 16 / 8)"
  echo ""
  local choice
  choice="$(prompt "Choose 1, 2, or 3" "1")"
  case "${choice}" in
    1) calculate_tuning_from_hardware "${DETECTED_RAM_GB}" "${DETECTED_CPU_COUNT}"; USE_CALCULATED_TUNING=1 ;;
    2) TIER="${NEAREST_TIER}"; set_tuning_vars_from_tier "${TIER}"; TIER_LABEL="nearest tier ${TIER} GB"; USE_CALCULATED_TUNING=0 ;;
    3)
      local pick
      pick="$(prompt "Enter tier: 128, 64, 32, 16, or 8" "${NEAREST_TIER}")"
      TIER="${pick}"; set_tuning_vars_from_tier "${TIER}"; TIER_LABEL="manual tier ${TIER} GB"; USE_CALCULATED_TUNING=0
      ;;
    *) die "Invalid choice" ;;
  esac
  print_tuning_plan
}

collect_ssl_and_options() {
  echo ""
  if prompt_yn "Configure HTTPS with Certbot?" "y"; then
    SKIP_CERTBOT=0
    DOMAIN="$(prompt "Primary domain" "")"
    EMAIL="$(prompt "Let's Encrypt email" "")"
    [[ -n "${DOMAIN}" && -n "${EMAIL}" ]] || die "Domain and email required"
  else
    SKIP_CERTBOT=1
    prompt_yn "Set domain in HTTP vhost anyway?" "n" && DOMAIN="$(prompt "Primary domain" "")"
  fi
  prompt_yn "Install Redis (php-pecl-redis)?" "n" && WITH_REDIS=1 || WITH_REDIS=0
  prompt_yn "Configure firewalld (SSH + HTTP + HTTPS)?" "y" && SKIP_UFW=0 || SKIP_UFW=1
  prompt_yn "Reset InnoDB log files if MySQL fails to start?" "n" && RESET_MYSQL_LOGS=1 || RESET_MYSQL_LOGS=0
}

main_auto_rhel() {
  show_banner
  require_root
  require_rhel
  require_configs
  trap cleanup EXIT
  detect_and_show_hardware
  choose_tuning_mode
  collect_ssl_and_options
  prompt_yn "Proceed with installation?" "y" || exit 0
  log "Starting installation..."
  run_install_pipeline
}

main_auto_rhel
