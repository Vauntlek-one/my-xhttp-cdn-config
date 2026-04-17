{
  "log": {
    "loglevel": "info" // 调试完成后可改为 "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0", // 如果需要 IPv6，改为监听 "::"
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "UUID_01", // 对应客户端出站 1
            "level": 0,
            "email": "vision-user",
            "flow": "xtls-rprx-vision"
          },
          {
            "id": "UUID_02", // 对应客户端出站 2/3/4/5
            "level": 0,
            "email": "xhttp-user"
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": "/run/xhttp-cdn/xhttp_in.sock",
            // 处理“直连”的 XHTTP 请求 (对应客户端出站 2/3/5 的直连部分)
            // 当 Reality 识别出 VLESS 协议但没有 flow 时，直接丢给内部 XHTTP Socket
            "xver": 0
          }
        ]
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "target": "/run/xhttp-cdn/tls_gate.sock",
          // 处理“CDN 转发”或“普通 HTTPS”请求 (对应客户端出站 3/4/5 的 CDN 部分)
          // 任何 Reality 不识别的流量都丢给 Caddy 处理
          "xver": 0,
          "serverNames": [
            "reality.example.com",
            "cdn.example.com"
          ],
          "privateKey": "YOUR_REALITY_PRIVATE_KEY",
          "shortIds": ["YOUR_SHORT_ID"]
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
      "listen": "/run/xhttp-cdn/xhttp_in.sock,0666",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "UUID_02",
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
          "path": "/your-xhttp-path", 
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
    { "protocol": "freedom", "tag": "direct", "settings": {} },
    { "protocol": "blackhole", "tag": "blocked", "settings": {} }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      { "type": "field", "ip": ["geoip:private"], "outboundTag": "blocked" }
    ]
  }
}
