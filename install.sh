#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SOCKET_DIR="/run/xhttp-cdn"
XRAY_CONFIG_PATH="/usr/local/etc/xray/config.json"
CADDYFILE_PATH="/etc/caddy/Caddyfile"
CLIENT_CONFIG_NAME="mihomo-config.yaml"
DECOY_ROOT="/var/www/html"

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    error "请使用 root 用户运行此脚本"
  fi

  return 0
}

detect_os() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_ID="$ID"
    PRETTY_NAME_VALUE="$PRETTY_NAME"
  else
    error "无法识别当前系统发行版"
  fi

  case "$OS_ID" in
    debian|ubuntu)
      pkg_update()  { apt update -y; }
      pkg_install() { apt install -y "$@"; }
      ;;
    centos|rhel|almalinux|rocky|ol|amzn)
      pkg_update()  { yum makecache; }
      pkg_install() { yum install -y "$@"; }
      ;;
    fedora)
      pkg_update()  { dnf makecache; }
      pkg_install() { dnf install -y "$@"; }
      ;;
    opensuse*|sles)
      pkg_update()  { zypper refresh; }
      pkg_install() { zypper install -y "$@"; }
      ;;
    *)
      error "不支持的发行版: $OS_ID，目前支持 Debian/Ubuntu/CentOS/RHEL/Fedora/openSUSE/SLES"
      ;;
  esac

  info "检测到系统: $PRETTY_NAME_VALUE"
}

resolve_user_home() {
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    USER_HOME=$(eval echo "~$SUDO_USER")
  else
    USER_HOME=$(getent passwd 1000 | cut -d: -f6 || true)
  fi

  [[ -z "${USER_HOME:-}" || ! -d "$USER_HOME" ]] && USER_HOME="/root"
  CLIENT_CONFIG_PATH="$USER_HOME/$CLIENT_CONFIG_NAME"
}

show_intro() {
  echo -e "\n${CYAN}[+] XHTTP + CDN 一键部署脚本（Xray + Caddy + Mihomo）${NC}\n"
  echo -e "${GREEN}[+] 推荐系统: Ubuntu 24.04 / Debian 12${NC}"
  echo -e "${YELLOW}[+] 前置条件:${NC}"
  echo "  1. Reality 域名 DNS → 仅 DNS (灰色云朵)"
  echo "  2. CDN 域名 DNS    → 代理开启 (橙色云朵)"
  echo "  3. Cloudflare SSL/TLS 加密 → 完全 (严格)"
  echo "  4. 服务器的 80/443 端口已放行"
  echo "  5. 若本机装过旧版 Nginx 脚本，脚本会停止 nginx 以便 Caddy 自动签证书"
  echo ""
}

prompt_inputs() {
  read -rp "请输入 Reality 域名 (如 reality.example.com): " REALITY_DOMAIN
  [[ -z "$REALITY_DOMAIN" ]] && error "域名不能为空"

  read -rp "请输入 CDN 域名 (如 cdn.example.com): " CDN_DOMAIN
  [[ -z "$CDN_DOMAIN" ]] && error "域名不能为空"

  echo ""
  echo "  1) IPv4"
  echo "  2) IPv6"
  read -rp "请选择客户端直连 IP 类型 [1/2] (默认 1): " IP_CHOICE
  IP_CHOICE=${IP_CHOICE:-1}

  read -rp "请输入 Caddy 证书通知邮箱 (可选，直接回车跳过): " CADDY_ACME_EMAIL

  echo ""
  info "Reality: $REALITY_DOMAIN"
  info "CDN:     $CDN_DOMAIN"
  info "IP 类型: $IP_CHOICE"
  echo ""
}

repair_caddy_repo_before_apt() {
  local caddy_list="/etc/apt/sources.list.d/caddy-stable.list"
  local disabled_caddy_list="${caddy_list}.disabled-by-install-sh"
  local keyring_path="/usr/share/keyrings/caddy-stable-archive-keyring.gpg"
  local key_url="https://dl.cloudsmith.io/public/caddy/stable/gpg.key"
  local list_url="https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt"

  case "$OS_ID" in
    debian|ubuntu)
      ;;
    *)
      return 0
      ;;
  esac

  if [[ ! -f "$caddy_list" && ! -f "$disabled_caddy_list" ]]; then
    return 0
  fi

  install -m 0755 -d /usr/share/keyrings

  if command -v gpg >/dev/null 2>&1; then
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL "$key_url" | gpg --dearmor --yes -o "$keyring_path"
      chmod o+r "$keyring_path"
      curl -fsSL "$list_url" -o "$caddy_list"
      rm -f "$disabled_caddy_list"
      return 0
    fi

    if command -v wget >/dev/null 2>&1; then
      wget -qO- "$key_url" | gpg --dearmor --yes -o "$keyring_path"
      chmod o+r "$keyring_path"
      wget -qO "$caddy_list" "$list_url"
      rm -f "$disabled_caddy_list"
      return 0
    fi
  fi

  if [[ -f "$caddy_list" ]]; then
    warn "检测到残留的 Caddy APT 源，但当前环境缺少修复所需工具，先暂时禁用它，稍后在安装 Caddy 阶段重新写入。"
    mv -f "$caddy_list" "$disabled_caddy_list"
  fi

  return 0
}

install_base_packages() {
  info "[1/5] 安装基础环境"

  repair_caddy_repo_before_apt
  pkg_update

  command -v curl >/dev/null 2>&1 || pkg_install curl
  command -v sudo >/dev/null 2>&1 || pkg_install sudo
  if ! command -v gpg >/dev/null 2>&1; then
    case "$OS_ID" in
      debian|ubuntu)
        pkg_install gnupg
        ;;
      *)
        pkg_install gnupg2 || pkg_install gnupg
        ;;
    esac
  fi

  case "$OS_ID" in
    debian|ubuntu)
      pkg_install ca-certificates debian-keyring debian-archive-keyring apt-transport-https
      ;;
    *)
      pkg_install ca-certificates
      ;;
  esac
}

install_xray() {
  info "安装 Xray..."
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root
  export PATH="/usr/local/bin:$PATH"
}

install_caddy() {
  info "安装 Caddy..."

  if command -v caddy >/dev/null 2>&1; then
    info "检测到 Caddy 已存在，跳过安装"
    return
  fi

  case "$OS_ID" in
    debian|ubuntu)
      install -m 0755 -d /usr/share/keyrings
      curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
      chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg
      curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt -o /etc/apt/sources.list.d/caddy-stable.list
      pkg_update
      pkg_install caddy
      ;;
    *)
      pkg_install caddy
      ;;
  esac

  command -v caddy >/dev/null 2>&1 || error "Caddy 安装失败，请检查软件源配置"
}

stop_legacy_nginx_if_needed() {
  if systemctl list-unit-files 2>/dev/null | grep -q '^nginx.service'; then
    info "检测到 nginx.service，停止旧版 Nginx 以释放 80 端口..."
    systemctl stop nginx 2>/dev/null || true
    systemctl disable nginx 2>/dev/null || true
  fi
}

stop_caddy_if_running() {
  if systemctl list-unit-files 2>/dev/null | grep -q '^caddy.service'; then
    if systemctl is-active --quiet caddy; then
      info "检测到 Caddy 已自动启动，先停止它以完成 80 端口检查..."
      systemctl stop caddy 2>/dev/null || true
    fi
  fi
}

check_http_port() {
  if command -v ss >/dev/null 2>&1; then
    local listeners
    listeners=$(ss -ltn '( sport = :80 )' | tail -n +2 || true)
    if [[ -n "$listeners" ]]; then
      error "80 端口仍被占用，Caddy 无法自动签发证书，请先释放 80 端口后重试"
    fi
  fi
}

generate_params() {
  info "[2/5] 生成参数"

  UUID1=$(xray uuid)
  UUID2=$(xray uuid)

  KEY_OUTPUT=$(xray x25519 2>&1)
  PRIVATE_KEY=$(echo "$KEY_OUTPUT" | grep -i "private" | awk -F': ' '{print $2}' | tr -d '[:space:]')
  PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep -i "public" | awk -F': ' '{print $2}' | tr -d '[:space:]')

  [[ -z "$PRIVATE_KEY" ]] && error "未能提取 Private Key，xray x25519 输出: $KEY_OUTPUT"
  [[ -z "$PUBLIC_KEY" ]] && error "未能提取 Public Key，xray x25519 输出: $KEY_OUTPUT"

  SHORT_ID=$(echo "$UUID1" | tr -d '-' | cut -c1-8)
  XHTTP_PATH="/$(echo "$UUID2" | tr -d '-' | cut -c1-8)"

  if [[ "$IP_CHOICE" == "2" ]]; then
    XRAY_LISTEN_HOST="::"
    VPS_IP=$(curl -6 -s --max-time 5 ip.sb)
    [[ -z "$VPS_IP" ]] && error "无法获取 IPv6 地址"
  else
    XRAY_LISTEN_HOST="0.0.0.0"
    VPS_IP=$(curl -4 -s --max-time 5 ip.sb)
    [[ -z "$VPS_IP" ]] && error "无法获取 IPv4 地址"
  fi

  info "UUID1 (Vision): $UUID1"
  info "UUID2 (XHTTP):  $UUID2"
  info "Private Key:    $PRIVATE_KEY"
  info "Public Key:     $PUBLIC_KEY"
  info "Short ID:       $SHORT_ID"
  info "Path:           $XHTTP_PATH"
  info "VPS IP:         $VPS_IP"
  echo ""
}

render_xray_config() {
  local xray_listen_host=${XRAY_LISTEN_HOST:-0.0.0.0}

  cat <<EOF
{
  "log": {
    "loglevel": "info"
  },
  "inbounds": [
    {
      "listen": "${xray_listen_host}",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID1}",
            "level": 0,
            "email": "vision-user",
            "flow": "xtls-rprx-vision"
          },
          {
            "id": "${UUID2}",
            "level": 0,
            "email": "xhttp-user"
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": "${SOCKET_DIR}/xhttp_in.sock",
            "xver": 0
          }
        ]
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "target": "${SOCKET_DIR}/tls_gate.sock",
          "xver": 0,
          "serverNames": [
            "${REALITY_DOMAIN}",
            "${CDN_DOMAIN}"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [
            "${SHORT_ID}"
          ]
        },
        "sockopt": {
          "tcpFastOpen": true,
          "tcpcongestion": "bbr",
          "tcpMptcp": true,
          "tcpNoDelay": true
        }
      },
      "tag": "REALITY_INBOUND"
    },
    {
      "listen": "${SOCKET_DIR}/xhttp_in.sock,0666",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID2}",
            "level": 0,
            "email": "xhttp-user"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": {
          "host": "",
          "path": "${XHTTP_PATH}",
          "mode": "auto",
          "extra": {
            "noSSEHeader": true,
            "scMaxEachPostBytes": 1000000,
            "xPaddingBytes": "100-1000"
          }
        }
      },
      "tag": "XHTTP_INBOUND"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "tag": "blocked",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF
}

render_caddyfile() {
  local socket_dir_no_leading_slash=${SOCKET_DIR#/}

  if [[ -n "${CADDY_ACME_EMAIL:-}" ]]; then
    cat <<EOF
{
    email ${CADDY_ACME_EMAIL}
}

${REALITY_DOMAIN}, ${CDN_DOMAIN} {
    bind unix//${socket_dir_no_leading_slash}/tls_gate.sock

    log {
        output file /var/log/caddy/access.log
    }

    @xhttp path ${XHTTP_PATH} ${XHTTP_PATH}/*
    handle @xhttp {
        reverse_proxy unix//${socket_dir_no_leading_slash}/xhttp_in.sock {
            transport http {
                versions 2
            }
        }
    }

    handle {
        root * ${DECOY_ROOT}
        file_server
    }
}
EOF
  else
    cat <<EOF
${REALITY_DOMAIN}, ${CDN_DOMAIN} {
    bind unix//${socket_dir_no_leading_slash}/tls_gate.sock

    log {
        output file /var/log/caddy/access.log
    }

    @xhttp path ${XHTTP_PATH} ${XHTTP_PATH}/*
    handle @xhttp {
        reverse_proxy unix//${socket_dir_no_leading_slash}/xhttp_in.sock {
            transport http {
                versions 2
            }
        }
    }

    handle {
        root * ${DECOY_ROOT}
        file_server
    }
}
EOF
  fi
}

render_mihomo_config() {
  cat <<EOF
proxies:
  # 1. XTLS(Vision)+Reality 直连
  - name: "出站1-XTLS+Reality"
    type: vless
    server: "${VPS_IP}"
    port: 443
    uuid: "${UUID1}"
    encryption: "none"
    flow: xtls-rprx-vision
    network: tcp
    tls: true
    alpn: [h2]
    servername: "${REALITY_DOMAIN}"
    client-fingerprint: chrome
    reality-opts:
      public-key: "${PUBLIC_KEY}"
      short-id: "${SHORT_ID}"

  # 2. xhttp+Reality 直连
  - name: "出站2-xhttp+Reality"
    type: vless
    server: "${VPS_IP}"
    port: 443
    uuid: "${UUID2}"
    encryption: "none"
    flow: ""
    network: xhttp
    tls: true
    alpn: [h2]
    servername: "${REALITY_DOMAIN}"
    client-fingerprint: chrome
    reality-opts:
      public-key: "${PUBLIC_KEY}"
      short-id: "${SHORT_ID}"
    xhttp-opts:
      path: ${XHTTP_PATH}
      mode: auto
      reuse-settings:
        max-concurrency: "16-32"
        c-max-reuse-times: "0"
        h-max-reusable-secs: "1800-3000"

  # 3. 上行 xhttp+TLS+CDN | 下行 xhttp+Reality
  - name: "出站3-cdn上行+xhttp下行"
    type: vless
    server: "${CDN_DOMAIN}"
    port: 443
    uuid: "${UUID2}"
    encryption: "none"
    flow: ""
    network: xhttp
    tls: true
    alpn: [h2]
    servername: "${CDN_DOMAIN}"
    client-fingerprint: chrome
    skip-cert-verify: true
    xhttp-opts:
      host: "${CDN_DOMAIN}"
      path: ${XHTTP_PATH}
      mode: auto
      reuse-settings:
        max-concurrency: "16-32"
        c-max-reuse-times: "0"
        h-max-reusable-secs: "1800-3000"
      download-settings:
        server: "${VPS_IP}"
        port: 443
        servername: "${REALITY_DOMAIN}"
        reality-opts:
          public-key: "${PUBLIC_KEY}"
          short-id: "${SHORT_ID}"
        reuse-settings:
          max-concurrency: "16-32"
          c-max-reuse-times: "0"
          h-max-reusable-secs: "1800-3000"

  # 4. xhttp+TLS+CDN (上下行不分离)
  - name: "出站4-cdn上下行"
    type: vless
    server: "${CDN_DOMAIN}"
    port: 443
    uuid: "${UUID2}"
    encryption: "none"
    flow: ""
    network: xhttp
    tls: true
    alpn: [h2]
    servername: "${CDN_DOMAIN}"
    client-fingerprint: chrome
    skip-cert-verify: true
    xhttp-opts:
      host: "${CDN_DOMAIN}"
      path: ${XHTTP_PATH}
      mode: auto
      reuse-settings:
        max-concurrency: "16-32"
        c-max-reuse-times: "0"
        h-max-reusable-secs: "1800-3000"

  # 5. 上行 xhttp+Reality | 下行 xhttp+TLS+CDN
  - name: "出站5-上xhttp+Reality下xhttp+TLS+CDN"
    type: vless
    server: "${VPS_IP}"
    port: 443
    uuid: "${UUID2}"
    encryption: "none"
    flow: ""
    network: xhttp
    tls: true
    alpn: [h2]
    servername: "${REALITY_DOMAIN}"
    client-fingerprint: chrome
    skip-cert-verify: true
    reality-opts:
      public-key: "${PUBLIC_KEY}"
      short-id: "${SHORT_ID}"
    xhttp-opts:
      host: "${CDN_DOMAIN}"
      path: ${XHTTP_PATH}
      mode: auto
      reuse-settings:
        max-concurrency: "16-32"
        c-max-reuse-times: "0"
        h-max-reusable-secs: "1800-3000"
      download-settings:
        path: ${XHTTP_PATH}
        host: ""
        server: "${CDN_DOMAIN}"
        port: 443
        tls: true
        alpn: [h2]
        servername: "${CDN_DOMAIN}"
        client-fingerprint: chrome
        skip-cert-verify: true
        reality-opts:
          public-key: ""
        reuse-settings:
          max-concurrency: "16-32"
          c-max-reuse-times: "0"
          h-max-reusable-secs: "1800-3000"
EOF
}

write_decoy_site() {
  mkdir -p "$DECOY_ROOT"
  cat > "$DECOY_ROOT/index.html" <<EOF
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Welcome</title>
    <style>
      body {
        margin: 0;
        font-family: Georgia, serif;
        background: #f6f1e8;
        color: #1f2937;
      }
      main {
        max-width: 720px;
        margin: 12vh auto;
        padding: 0 24px;
      }
      h1 {
        font-size: 40px;
        margin-bottom: 12px;
      }
      p {
        line-height: 1.7;
        font-size: 18px;
      }
    </style>
  </head>
  <body>
    <main>
      <h1>Research Notes</h1>
      <p>This site is online and serving content normally.</p>
      <p>Generated by the XHTTP + CDN deployment script.</p>
    </main>
  </body>
</html>
EOF
}

write_tmpfiles_config() {
  mkdir -p /etc/tmpfiles.d
  cat > /etc/tmpfiles.d/xhttp-cdn.conf <<EOF
d ${SOCKET_DIR} 0777 root root -
EOF
  systemd-tmpfiles --create /etc/tmpfiles.d/xhttp-cdn.conf
}

write_caddy_override() {
  mkdir -p /etc/systemd/system/caddy.service.d
  cat > /etc/systemd/system/caddy.service.d/override.conf <<EOF
[Service]
UMask=0000
EOF
}

write_configs() {
  info "[3/5] 生成配置文件"

  mkdir -p "$(dirname "$XRAY_CONFIG_PATH")"
  mkdir -p /etc/caddy
  mkdir -p /var/log/caddy

  render_xray_config > "$XRAY_CONFIG_PATH"
  render_caddyfile > "$CADDYFILE_PATH"
  render_mihomo_config > "$CLIENT_CONFIG_PATH"

  write_tmpfiles_config
  write_caddy_override
  write_decoy_site
}

enable_services() {
  systemctl daemon-reload
  systemctl enable xray >/dev/null 2>&1 || true
  systemctl enable caddy >/dev/null 2>&1 || true
}

validate_configs() {
  info "[4/5] 校验配置"
  xray -test -config "$XRAY_CONFIG_PATH"
  caddy validate --config "$CADDYFILE_PATH" --adapter caddyfile
}

start_services() {
  info "[5/5] 启动服务"

  systemctl restart xray
  systemctl restart caddy

  systemctl is-active --quiet xray && info "Xray 运行中" || warn "Xray 启动失败"
  systemctl is-active --quiet caddy && info "Caddy 运行中" || warn "Caddy 启动失败"
}

print_summary() {
  echo -e "\n${CYAN}[+] 部署完成${NC}\n"
  echo -e "${YELLOW}[+] 服务端参数${NC}"
  echo "Reality 域名:   $REALITY_DOMAIN"
  echo "CDN 域名:       $CDN_DOMAIN"
  echo "VPS IP:         $VPS_IP"
  echo "UUID1 (Vision): $UUID1"
  echo "UUID2 (XHTTP):  $UUID2"
  echo "Public Key:     $PUBLIC_KEY"
  echo "Private Key:    $PRIVATE_KEY"
  echo "Short ID:       $SHORT_ID"
  echo "Path:           $XHTTP_PATH"
  echo "Socket Dir:     $SOCKET_DIR"
  if [[ -n "${CADDY_ACME_EMAIL:-}" ]]; then
    echo "Caddy 邮箱:     $CADDY_ACME_EMAIL"
  fi
  echo ""
  echo -e "${YELLOW}[+] Mihomo 客户端配置已保存到 $CLIENT_CONFIG_PATH${NC}"
  cat "$CLIENT_CONFIG_PATH"
  echo ""
  warn "Caddy 首次签发证书依赖 80 端口可访问；若证书未签出，请先检查 80 端口、防火墙和 Cloudflare 代理状态"
  echo ""
  echo -e "${YELLOW}[+] 建议: 在 Cloudflare 配置缓存规则绕过 XHTTP 路径${NC}"
  echo "  Cloudflare → 缓存 → Cache Rules → 创建缓存规则"
  echo "  选择「自定义筛选表达式」→ 点击「编辑表达式」→ 输入:"
  echo ""
  echo "  (http.host eq \"${CDN_DOMAIN}\") and (http.request.uri.path contains \"${XHTTP_PATH}\")"
  echo ""
  echo "  缓存资格设置为「绕过缓存」→ 部署"
}

main() {
  require_root
  detect_os
  resolve_user_home
  show_intro
  prompt_inputs
  install_base_packages
  install_xray
  install_caddy
  stop_legacy_nginx_if_needed
  stop_caddy_if_running
  check_http_port
  generate_params
  write_configs
  enable_services
  validate_configs
  start_services
  print_summary
}

if [[ "${INSTALL_SH_TESTING:-0}" != "1" ]]; then
  main "$@"
fi
