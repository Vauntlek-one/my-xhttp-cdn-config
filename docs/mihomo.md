proxies:
  # 1. XTLS(Vision)+Reality 直连
  - name: "出站1-XTLS+Reality"
    type: vless
    server: "YOUR_VPS_IP"
    port: 443
    uuid: "YOUR_UUID_01"
    encryption: "none"
    flow: xtls-rprx-vision
    network: tcp
    tls: true
    alpn: [h2]
    servername: "reality.example.com" # Reality 伪装域名
    client-fingerprint: chrome
    reality-opts:
      public-key: "YOUR_PUB_KEY"
      short-id: "YOUR_SHORT_ID"

  # 2. xhttp+Reality 直连
  - name: "出站2-xhttp+Reality"
    type: vless
    server: "YOUR_VPS_IP"
    port: 443
    uuid: "UUID_02"
    encryption: "none"
    flow: ""
    network: xhttp
    tls: true
    alpn: [h2]
    servername: "reality.example.com" # Reality 伪装域名
    client-fingerprint: chrome
    reality-opts:
      public-key: "YOUR_PUB_KEY"
      short-id: "YOUR_SHORT_ID"
    xhttp-opts:
      path: /your-xhttp-path      # 必须与服务端配置的 path 一致
      mode: auto                  # Reality 模式下 auto 会自动选择 stream-one
      # host: "reality.example.com" # 直连时可省略，默认继承 servername
      reuse-settings:  # 链接复用设置（即XMUX）
        max-concurrency: "16-32" # 单连接最大并发请求数（0=不限制）
        # max-connections: "0" # 最大连接数（0=不限制）（与 max-concurrency 冲突，二选一）
        c-max-reuse-times: "0" # 单连接最大复用次数（0=不限制）
        # h-max-request-times: "600-900" # 单连接累计 HTTP 请求数（不严谨，慎用）
        h-max-reusable-secs: "1800-3000" # 单连接最长复用时间（秒）
        # h-keep-alive-period: 0  # [预计 v1.19.24 版本支持] [预计 v1.19.24 版本支持] H2/H3 保活间隔 (0=默认智能值, -1=关闭, 支持填正数范围(比如10-20)但不推荐)

  # 3. 上行 xhttp+TLS+CDN | 下行 xhttp+Reality
  - name: "出站3-cdn上行+xhttp下行"
    type: vless
    server: "cdn.example.com"     # CDN 域名或优选 IP (上行)
    port: 443
    uuid: "UUID_02"
    encryption: "none"
    flow: ""
    network: xhttp
    tls: true
    alpn: [h2]
    servername: "cdn.example.com" # 写你套 CDN 对应的子域名，CDN 通过它回源服务器
    client-fingerprint: chrome
    skip-cert-verify: true
    xhttp-opts:  # 上行设置
      host: "cdn.example.com"     # CDN 转发所需的 HTTP Host，与 servername 保持相同
      path: /your-xhttp-path
      mode: auto                  # CDN 模式下 auto 会自动选择 stream-up (H2)
      reuse-settings:  # 上行链接复用设置（即XMUX）
        max-concurrency: "16-32" # 单连接最大并发请求数（0=不限制）
        # max-connections: "0" # 最大连接数（0=不限制）（与 max-concurrency 冲突，二选一）
        c-max-reuse-times: "0" # 单连接最大复用次数（0=不限制）
        # h-max-request-times: "600-900" # 单连接累计 HTTP 请求数（不严谨，慎用）
        h-max-reusable-secs: "1800-3000" # 单连接最长复用时间（秒）
        # h-keep-alive-period: 0  # [预计 v1.19.24 版本支持] H2/H3 保活间隔 (0=默认智能值, -1=关闭, 支持正数范围但不推荐)
      download-settings:          # 下行设置
        server: "<YOUR_VPS_IP>"   # 下行地址 (VPS 直连)
        port: 443
        servername: "reality.example.com" # Reality 伪装域名
        reality-opts:
          public-key: "YOUR_PUB_KEY"
          short-id: "YOUR_SHORT_ID"
          # host 继承自外层或省略；mode 强制继承外层
        reuse-settings:  # 下行链接复用设置（即XMUX）
          max-concurrency: "16-32" # 单连接最大并发请求数（0=不限制）
          # max-connections: "0" # 最大连接数（0=不限制）（与 max-concurrency 冲突，二选一）
          c-max-reuse-times: "0" # 单连接最大复用次数（0=不限制）
          # h-max-request-times: "600-900" # 单连接累计 HTTP 请求数（不严谨，慎用）
          h-max-reusable-secs: "1800-3000" # 单连接最长复用时间（秒）
          # h-keep-alive-period: 0  # [预计 v1.19.24 版本支持] H2/H3 保活间隔 (0=默认智能值, -1=关闭, 支持正数范围但不推荐)

  # 4. xhttp+TLS+CDN (上下行不分离)
  - name: "出站4-cdn上下行"
    type: vless
    server: "cdn.example.com" # CDN 域名或优选 IP
    port: 443
    uuid: "UUID_02"
    encryption: "none"
    flow: ""
    network: xhttp
    tls: true
    alpn: [h2]
    servername: "cdn.example.com" # 写你套 CDN 对应的子域名，CDN 通过它回源服务器
    client-fingerprint: chrome
    skip-cert-verify: true
    xhttp-opts:
      host: "cdn.example.com" # CDN 转发所需的 HTTP Host，与 servername 保持相同
      path: /your-xhttp-path
      mode: auto
      reuse-settings:  # 链接复用设置（即XMUX）
        max-concurrency: "16-32" # 单连接最大并发请求数（0=不限制）
        # max-connections: "0" # 最大连接数（0=不限制）（与 max-concurrency 冲突，二选一）
        c-max-reuse-times: "0" # 单连接最大复用次数（0=不限制）
        # h-max-request-times: "600-900" # 单连接累计 HTTP 请求数（不严谨，慎用）
        h-max-reusable-secs: "1800-3000" # 单连接最长复用时间（秒）
        # h-keep-alive-period: 0  # [预计 v1.19.24 版本支持] H2/H3 保活间隔 (0=默认智能值, -1=关闭, 支持正数范围但不推荐)

  # 5. 上行 xhttp+Reality | 下行 xhttp+TLS+CDN
  - name: "出站5-上xhttp+Reality下xhttp+TLS+CDN"
    type: vless
    server: "YOUR_VPS_IP"
    port: 443
    uuid: "UUID_02"
    encryption: "none"
    flow: ""
    network: xhttp
    tls: true
    alpn: [h2]
    servername: "reality.example.com" # Reality 伪装域名
    client-fingerprint: chrome
    skip-cert-verify: true
    reality-opts:
      public-key: "YOUR_PUB_KEY"
      short-id: "YOUR_SHORT_ID"
    xhttp-opts:
      host: "cdn.example.com"     # CDN 转发所需的 HTTP Host，与 servername 保持相同
      path: /your-xhttp-path
      mode: auto
      reuse-settings:  # 上行链接复用设置（即XMUX）
        max-concurrency: "16-32" # 单连接最大并发请求数（0=不限制）
        # max-connections: "0" # 最大连接数（0=不限制）（与 max-concurrency 冲突，二选一）
        c-max-reuse-times: "0" # 单连接最大复用次数（0=不限制）
        # h-max-request-times: "600-900" # 单连接累计 HTTP 请求数（不严谨，慎用）
        h-max-reusable-secs: "1800-3000" # 单连接最长复用时间（秒）
        # h-keep-alive-period: 0  # [预计 v1.19.24 版本支持] H2/H3 保活间隔 (0=默认智能值, -1=关闭, 支持正数范围但不推荐)
      download-settings:          # 下行设置
        path: /your-xhttp-path
        host: ""                  # host 继承自外层或省略；mode 强制继承外层        
        server: "cdn.example.com" # CDN / 优选 IP (下行连接地址)
        port: 443
        tls: true
        alpn: [h2]
        servername: "cdn.example.com" # 写你套 CDN 对应的子域名，CDN 通过它回源服务器
        client-fingerprint: chrome
        skip-cert-verify: true
        reality-opts: { public-key: "" } # 强制清空 Reality 公钥，否则下行连接 CDN 将会携带 Reality 握手
        reuse-settings:  # 下行链接复用设置（即XMUX）
          max-concurrency: "16-32" # 单连接最大并发请求数（0=不限制）
          # max-connections: "0" # 最大连接数（0=不限制）（与 max-concurrency 冲突，二选一）
          c-max-reuse-times: "0" # 单连接最大复用次数（0=不限制）
          # h-max-request-times: "600-900" # 单连接累计 HTTP 请求数（不严谨，慎用）
          h-max-reusable-secs: "1800-3000" # 单连接最长复用时间（秒）
          # h-keep-alive-period: 0  # [预计 v1.19.24 版本支持] H2/H3 保活间隔 (0=默认智能值, -1=关闭, 支持正数范围但不推荐)