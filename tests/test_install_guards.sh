#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

export INSTALL_SH_TESTING=1
# shellcheck source=./install.sh
source ./install.sh

require_root_def=$(declare -f require_root)

if [[ "$require_root_def" != *"return 0"* ]]; then
  echo "require_root must explicitly return 0 when already running as root" >&2
  exit 1
fi

echo "install.sh guard tests passed"
