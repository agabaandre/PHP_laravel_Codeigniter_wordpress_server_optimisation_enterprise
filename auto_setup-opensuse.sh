#!/usr/bin/env bash
#
# Interactive auto setup — openSUSE / SLES
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export WP_OPT_LIB_ONLY=1
# shellcheck source=setup-opensuse.sh
source "${SCRIPT_DIR}/setup-opensuse.sh"

NEAREST_TIER=""

log()  { echo "[auto-suse] $*"; }

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
  PHP Application Server — Interactive Auto Setup (openSUSE)
  Leap · Tumbleweed · SLES
================================================================================

EOF
}

detect_and_show_hardware() {
  detect_hardware
  NEAREST_TIER="$(nearest_fixed_tier "${DETECTED_RAM_GB}")"
  log "Detected: ${DETECTED_RAM_GB} GB RAM, ${DETECTED_CPU_COUNT} CPU(s)"
  log "Nearest preset tier: ${NEAREST_TIER} GB"
}

choose_tuning_mode() {
  echo ""
  echo "  1) Auto-calculate  2) Nearest tier (${NEAREST_TIER})  3) Manual tier"
  case "$(prompt "Choose 1, 2, or 3" "1")" in
    1) calculate_tuning_from_hardware "${DETECTED_RAM_GB}" "${DETECTED_CPU_COUNT}"; USE_CALCULATED_TUNING=1 ;;
    2) TIER="${NEAREST_TIER}"; set_tuning_vars_from_tier "${TIER}"; USE_CALCULATED_TUNING=0 ;;
    3)
      TIER="$(prompt "Tier: 128/64/32/16/8" "${NEAREST_TIER}")"
      set_tuning_vars_from_tier "${TIER}"; USE_CALCULATED_TUNING=0
      ;;
    *) die "Invalid choice" ;;
  esac
  print_tuning_plan
}

collect_ssl_and_options() {
  if prompt_yn "Run Certbot for SSL?" "y"; then
    SKIP_CERTBOT=0
    DOMAIN="$(prompt "Domain" "")"
    EMAIL="$(prompt "Email" "")"
  else
    SKIP_CERTBOT=1
  fi
  prompt_yn "Install Redis?" "n" && WITH_REDIS=1 || WITH_REDIS=0
  prompt_yn "Configure firewalld?" "y" && SKIP_UFW=0 || SKIP_UFW=1
  prompt_yn "Reset InnoDB logs if needed?" "n" && RESET_MYSQL_LOGS=1 || RESET_MYSQL_LOGS=0
}

main_auto_opensuse() {
  show_banner
  require_root
  require_opensuse
  require_configs
  trap cleanup EXIT
  detect_and_show_hardware
  choose_tuning_mode
  collect_ssl_and_options
  prompt_yn "Proceed?" "y" || exit 0
  run_install_pipeline
}

main_auto_opensuse
