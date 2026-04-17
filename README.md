# XHTTP + CDN 配置指南

这个仓库现在聚焦于一套面向 `Mihomo/Clash` 客户端的 `Xray + Caddy + XHTTP + CDN` 搭建方案。

当前 `install.sh` 已完成这些工作：

- 安装 `Xray`
- 安装 `Caddy`
- 生成 `Reality + XHTTP` 的 Xray 服务端配置
- 生成使用 Unix Socket 转发的 `Caddyfile`
- 让 Caddy 自动申请并续签证书
- 输出可直接用于 Mihomo 的 YAML `proxies` 配置

## 当前文档

- [install.sh](./install.sh)：一键部署脚本，自动完成安装、配置生成、服务启动与 Mihomo 模板输出
- [docs/xray.md](./docs/xray.md)：当前使用的 Xray 服务端配置
- [docs/caddy.md](./docs/caddy.md)：当前使用的 Caddy 配置
- [docs/mihomo.md](./docs/mihomo.md)：当前使用的 Mihomo 客户端配置模板
- [客户端模板.txt](./客户端模板.txt)：带占位符的 Mihomo 模板，便于手动替换

## 一键部署

在 VPS 上执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Yulinanami/my-xhttp-cdn-config/refs/heads/master/install.sh)
```

或者下载后运行：

```bash
wget -O install.sh https://raw.githubusercontent.com/Yulinanami/my-xhttp-cdn-config/refs/heads/master/install.sh && bash install.sh
```

脚本会提示输入：

1. Reality 域名
2. CDN 域名
3. 客户端直连 IP 类型（IPv4 / IPv6）
4. Caddy 证书通知邮箱（可选）

其余参数会自动生成。部署完成后，Mihomo 节点配置会保存到 `~/mihomo-config.yaml`。

## 前置条件

运行脚本前，请确认：

1. Reality 域名 DNS 为 **仅 DNS**（灰色云朵）
2. CDN 域名 DNS 为 **代理开启**（橙色云朵）
3. Cloudflare `SSL/TLS` 加密模式为 **完全（严格）**
4. 服务器的 `80/443` 端口可访问
5. Cloudflare 缓存规则已对 XHTTP 路径设置 **绕过缓存**

> 注意：Caddy 自动签证书依赖 `80` 端口可访问。若首次启动后证书未签出，优先检查端口、防火墙和 Cloudflare 配置。

## 客户端模式

当前模板包含 5 种 Mihomo 出站模式：

1. `XTLS(Vision) + Reality` 直连
2. `XHTTP + Reality` 直连
3. 上行 `XHTTP + TLS + CDN`，下行 `XHTTP + Reality`
4. `XHTTP + TLS + CDN` 上下行不分离
5. 上行 `XHTTP + Reality`，下行 `XHTTP + TLS + CDN`

## 手动部署

如果你不使用一键脚本，可以按下面顺序手动配置：

1. 参考 [docs/xray.md](./docs/xray.md) 写入 `/usr/local/etc/xray/config.json`
2. 参考 [docs/caddy.md](./docs/caddy.md) 写入 `/etc/caddy/Caddyfile`
3. 参考 [docs/mihomo.md](./docs/mihomo.md) 填写 Mihomo 客户端节点

## 兼容性说明

- 当前仓库的主线方案已经不再面向 `v2rayN`
- 当前脚本不再使用 `acme.sh`
- 当前脚本不再生成 `vless://` 导入链接
- 当前脚本默认输出 Mihomo YAML，而不是 Xray 客户端链接

## 旧文档说明

仓库里的 [1.环境配置.md](./1.环境配置.md) 和 [2.文件配置.md](./2.文件配置.md) 保留了旧版 `Nginx + acme.sh + v2rayN` 方案的历史内容，已不代表当前 `install.sh` 的实际行为。阅读和部署时请优先使用 `docs/` 下的新文档。

## 参考资料

- Mihomo Discussion: https://github.com/MetaCubeX/mihomo/discussions/2669
- Xray XHTTP Discussion: https://github.com/XTLS/Xray-core/discussions/4118
