# 当前脚本使用 Caddy 自动证书，不再手工填写 tls 证书路径。
# 如需接收证书通知，可在全局块中加上 email。
#
# {
#     email admin@example.com
# }
#
# 记得换成你自己的两个子域名
# direct.example.com (小黄云 Proxy OFF)
# cdn.example.com    (小黄云 Proxy ON)
direct.example.com, cdn.example.com {

        bind unix//run/xhttp-cdn/tls_gate.sock

        log {
                output file /var/log/caddy/access.log
        }

        # 处理 CDN 传来的 XHTTP 流量 (对应客户端出站 3/4/5)
        # 只有路径匹配 /your-xhttp-path (记得换成你自己的路径) 时，才转发给 Xray 内部 XHTTP 模块
        @xhttp path /your-xhttp-path /your-xhttp-path/*
        handle @xhttp {
                reverse_proxy unix//run/xhttp-cdn/xhttp_in.sock {
                        transport http {
                                versions 2
                        }
                }
        }
        
        # 处理所有其他访问
        # 可以简单搭建一个博客伪装为正常网页
        # 或者跑个openlist，大流量小流量都有
        handle {
                # 伪装站路径：/var/www/html/index.html
                root * /var/www/html
                file_server
        }
}
