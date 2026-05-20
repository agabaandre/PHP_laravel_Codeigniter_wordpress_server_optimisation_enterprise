#!/usr/bin/env bash
#
# Interactive setup — detects server RAM/CPUs, calculates tuning, runs full install.
#
# Usage:
#   sudo ./auto_setup.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export WP_OPT_LIB_ONLY=1
# shellcheck source=setup.sh
source "${SCRIPT_DIR}/setup.sh"

NEAREST_TIER=""
TUNING_MODE=""   # calculated | tier | tier_override

log()  { echo "[auto] $*"; }
warn() { echo "[auto] WARNING: $*" >&2; }

prompt() {
  local msg="$1" default="${2:-}"
  local reply
  if [[ -n "${default}" ]]; then
    read -rp "${msg} [${default}]: " reply
    echo "${reply:-${default}}"
  else
    read -rp "${msg}: " reply
    echo "${reply}"
  fi
}

prompt_yn() {
  local msg="$1" default="${2:-y}"
  local reply
  read -rp "${msg} [${default}]: " reply
  reply="${reply:-${default}}"
  [[ "${reply}" =~ ^[Yy] ]]
}

show_banner() {
  cat <<'EOF'

================================================================================
  PHP Application Server — Interactive Auto Setup
  WordPress · Laravel · CodeIgniter
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
  echo "  How should tuning be applied?"
  echo "    1) Auto-calculate from detected RAM/CPUs (recommended)"
  echo "    2) Use nearest preset tier (${NEAREST_TIER} GB)"
  echo "    3) Pick a preset tier manually (128 / 64 / 32 / 16 / 8)"
  echo ""
  local choice
  choice="$(prompt "Choose 1, 2, or 3" "1")"

  case "${choice}" in
    1)
      TUNING_MODE="calculated"
      calculate_tuning_from_hardware "${DETECTED_RAM_GB}" "${DETECTED_CPU_COUNT}"
      ;;
    2)
      TUNING_MODE="tier"
      TIER="${NEAREST_TIER}"
      set_tuning_vars_from_tier "${TIER}"
      TIER_LABEL="nearest tier ${TIER} GB (detected ${DETECTED_RAM_GB} GB RAM)"
      ;;
    3)
      TUNING_MODE="tier_override"
      local pick
      pick="$(prompt "Enter tier: 128, 64, 32, 16, or 8" "${NEAREST_TIER}")"
      case "${pick}" in
        128|64|32|16|8) TIER="${pick}" ;;
        *) die "Invalid tier: ${pick}" ;;
      esac
      set_tuning_vars_from_tier "${TIER}"
      TIER_LABEL="manual tier ${TIER} GB"
      ;;
    *)
      die "Invalid choice: ${choice}"
      ;;
  esac

  USE_CALCULATED_TUNING=0
  [[ "${TUNING_MODE}" == "calculated" ]] && USE_CALCULATED_TUNING=1

  print_tuning_plan
}

collect_ssl_and_options() {
  echo ""
  if prompt_yn "Configure HTTPS with Certbot?" "y"; then
    SKIP_CERTBOT=0
    DOMAIN="$(prompt "Primary domain (e.g. example.com)" "")"
    [[ -n "${DOMAIN}" ]] || die "Domain is required for Certbot"
    EMAIL="$(prompt "Email for Let's Encrypt" "")"
    [[ -n "${EMAIL}" ]] || die "Email is required for Certbot"
  else
    SKIP_CERTBOT=1
    warn "Skipping SSL — HTTP only until you run Certbot later"
    if prompt_yn "Set domain in HTTP vhost anyway?" "n"; then
      DOMAIN="$(prompt "Primary domain" "")"
    fi
  fi

  echo ""
  if prompt_yn "Install Redis (php8.3-redis)? Recommended for Laravel/cache" "n"; then
    WITH_REDIS=1
  else
    WITH_REDIS=0
  fi

  if prompt_yn "Configure UFW firewall (SSH + Apache)?" "y"; then
    SKIP_UFW=0
  else
    SKIP_UFW=1
  fi

  if prompt_yn "Reset MySQL InnoDB log files if service fails to start?" "n"; then
    RESET_MYSQL_LOGS=1
  else
    RESET_MYSQL_LOGS=0
  fi
}

confirm_proceed() {
  echo ""
  if ! prompt_yn "Proceed with installation now?" "y"; then
    log "Cancelled by user."
    exit 0
  fi
}

main_auto() {
  show_banner
  require_root
  require_ubuntu
  require_configs
  trap cleanup EXIT

  detect_and_show_hardware
  choose_tuning_mode
  collect_ssl_and_options
  confirm_proceed

  log "Starting installation..."
  run_install_pipeline
}

main_auto
