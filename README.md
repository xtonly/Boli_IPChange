# 🚀 Boli_IPChange - HKT 网络与双栈 IP 综合管理脚本

![Platform](https://img.shields.io/badge/Platform-Debian%20%7C%20Ubuntu-blue?style=flat-square&logo=linux)
![IPv6](https://img.shields.io/badge/IPv6-SLAAC%20Auto%20Prefix-success?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)

专为 **Boil HKT** 动态前缀 VPS 打造的全能网络管理工具，支持 IPv6 动态子网前缀自动识别修复、自定义后缀绑定，以及 IPv4 API 一键换 IP。

---

### ✨ 核心功能

- 🔍 **智能网卡识别**：自动适配 `eth0`、`ens18` 等不同系统的主网卡名称（完美支持 DD 系统后恢复网络）。
- 🌐 **IPv6 动态前缀自愈**：自动唤醒宿主机网关获取最新 `/64` 动态前缀，自动绑定 `::8888` 固定后缀。
- ⏱️ **Crontab 定时保活**：支持开启后台每 5 分钟静默巡检，母鸡切换前缀时自动清理废 IP 并无缝更新。
- 🔄 **IPv4 API 面板集成**：内置 Boil 官方 `getIP` / `changeIP` 接口调用，支持面板内随时更新 Bearer Token。

---

### ⚡ 一键安装与运行

请使用 `root` 用户登录 SSH，复制以下命令一键安装依赖并启动管理面板：

```bash
apt update -y && apt install -y dnsutils curl ndisc6 && FILE="IPChange.sh" && curl -sSL "https://raw.githubusercontent.com/xtonly/Boli_IPChange/main/IPChange.sh" | tr -d '\r' > $FILE && chmod +x $FILE && ./$FILE
