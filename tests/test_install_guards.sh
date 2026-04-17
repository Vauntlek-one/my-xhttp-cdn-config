#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

export INSTALL_SH_TESTING=1
# shellcheck source=./install.sh
source ./install.sh

require_root_def=$(declare -f require_root)
install_caddy_def=$(declare -f install_caddy)

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

echo "install.sh guard tests passed"
