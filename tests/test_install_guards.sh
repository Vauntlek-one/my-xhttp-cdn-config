#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

export INSTALL_SH_TESTING=1
# shellcheck source=./install.sh
source ./install.sh

require_root_def=$(declare -f require_root)
install_caddy_def=$(declare -f install_caddy)
install_base_packages_def=$(declare -f install_base_packages)
repair_caddy_repo_def=$(declare -f repair_caddy_repo_before_apt)
stop_caddy_def=$(declare -f stop_caddy_if_running)
main_def=$(declare -f main)

if [[ "$require_root_def" != *"return 0"* ]]; then
  echo "require_root must explicitly return 0 when already running as root" >&2
  exit 1
fi

if [[ "$install_caddy_def" != *"/usr/share/keyrings/caddy-stable-archive-keyring.gpg"* ]]; then
  echo "install_caddy must use the official /usr/share/keyrings path for Caddy's apt keyring" >&2
  exit 1
fi

if [[ "$install_caddy_def" != *"chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg"* ]]; then
  echo "install_caddy must make the Caddy apt keyring world-readable" >&2
  exit 1
fi

if [[ "$install_base_packages_def" != *"repair_caddy_repo_before_apt"* ]]; then
  echo "install_base_packages must repair or disable a stale Caddy apt repo before apt update" >&2
  exit 1
fi

if [[ "$repair_caddy_repo_def" != *".disabled-by-install-sh"* ]]; then
  echo "repair_caddy_repo_before_apt must be able to disable a stale Caddy apt source when repair tools are unavailable" >&2
  exit 1
fi

if [[ "$repair_caddy_repo_def" != *"wget -qO-"* ]]; then
  echo "repair_caddy_repo_before_apt must support wget fallback when curl is unavailable" >&2
  exit 1
fi

if [[ "$stop_caddy_def" != *"systemctl stop caddy"* ]]; then
  echo "stop_caddy_if_running must stop an auto-started Caddy service before port checks" >&2
  exit 1
fi

if [[ "$main_def" != *"install_caddy;"*"stop_legacy_nginx_if_needed;"*"stop_caddy_if_running;"*"check_http_port;"* ]]; then
  echo "main must stop Caddy before checking whether port 80 is occupied" >&2
  exit 1
fi

echo "install.sh guard tests passed"
