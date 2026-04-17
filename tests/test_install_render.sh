#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

assert_contains() {
  local haystack=$1
  local needle=$2

  if [[ "$haystack" != *"$needle"* ]]; then
    echo "Expected output to contain: $needle" >&2
    exit 1
  fi
}

assert_not_contains() {
  local haystack=$1
  local needle=$2

  if [[ "$haystack" == *"$needle"* ]]; then
    echo "Did not expect output to contain: $needle" >&2
    exit 1
  fi
}

export INSTALL_SH_TESTING=1
# shellcheck source=./install.sh
source ./install.sh

REALITY_DOMAIN="reality.example.com"
CDN_DOMAIN="cdn.example.com"
UUID1="11111111-1111-4111-8111-111111111111"
UUID2="22222222-2222-4222-8222-222222222222"
PRIVATE_KEY="PRIVATE_KEY_EXAMPLE"
PUBLIC_KEY="PUBLIC_KEY_EXAMPLE"
SHORT_ID="1a2b3c4d"
XHTTP_PATH="/edge-1234"
VPS_IP="203.0.113.10"
SOCKET_DIR="/run/xhttp-cdn"
CADDY_ACME_EMAIL=""

xray_config=$(render_xray_config)
caddyfile=$(render_caddyfile)
mihomo_config=$(render_mihomo_config)

assert_contains "$xray_config" '"dest": "/run/xhttp-cdn/xhttp_in.sock"'
assert_contains "$xray_config" '"target": "/run/xhttp-cdn/tls_gate.sock"'
assert_contains "$xray_config" '"listen": "/run/xhttp-cdn/xhttp_in.sock,0666"'
assert_contains "$xray_config" '"path": "/edge-1234"'
assert_contains "$xray_config" '"id": "22222222-2222-4222-8222-222222222222"'

assert_contains "$caddyfile" 'reality.example.com, cdn.example.com {'
assert_contains "$caddyfile" 'bind unix//run/xhttp-cdn/tls_gate.sock'
assert_contains "$caddyfile" '@xhttp path /edge-1234 /edge-1234/*'
assert_contains "$caddyfile" 'handle @xhttp {'
assert_contains "$caddyfile" 'reverse_proxy unix//run/xhttp-cdn/xhttp_in.sock {'
assert_not_contains "$caddyfile" 'tls /etc/caddy/certs'

assert_contains "$mihomo_config" 'proxies:'
assert_contains "$mihomo_config" 'name: "出站1-XTLS+Reality"'
assert_contains "$mihomo_config" 'network: xhttp'
assert_contains "$mihomo_config" 'path: /edge-1234'
assert_contains "$mihomo_config" 'reuse-settings:'
assert_contains "$mihomo_config" 'download-settings:'
assert_contains "$mihomo_config" 'server: "203.0.113.10"'
assert_contains "$mihomo_config" 'server: "cdn.example.com"'

echo "install.sh render tests passed"
