# VPS Traffic Reporter 📊

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Shell-Script-green.svg)](https://www.gnu.org/software/bash/)

[English](#english) | [中文](#中文)

---

## English

### Description

VPS Traffic Reporter monitors your VPS network traffic and sends daily reports to Telegram. Track your monthly bandwidth usage and avoid overage charges.

### Features

- 📊 Daily traffic reports via Telegram
- 🔄 Automatic billing cycle management
- 📈 Visual progress bars and usage statistics
- ⚠️ Smart alerts for high traffic usage
- ⚙️ Easy configuration with interactive setup

### Quick Install

Install with a single command:

```bash
curl -Ls https://raw.githubusercontent.com/uniquMonte/server-traffic-reporter/main/install.sh | sudo bash
```

Or download first:
```bash
curl -Ls https://raw.githubusercontent.com/uniquMonte/server-traffic-reporter/main/install.sh -o install.sh
sudo bash install.sh
```

### Setup

Run the setup script:
```bash
./setup.sh
```

You'll need:
1. **Telegram Bot Token** - Get from [@BotFather](https://t.me/BotFather)
2. **Telegram Chat ID** - Get from [@userinfobot](https://t.me/userinfobot)
3. **Traffic Reset Day** - Day of month when traffic resets (1-31)
4. **Monthly Traffic Limit** - Your limit in GB
5. **Network Interface** - Usually auto-detected (eth0, ens3, etc.)

### Usage

View configuration:
```bash
./setup.sh  # Select option 1
```

Update settings:
```bash
./setup.sh  # Select option 2
```

Test notification:
```bash
./setup.sh  # Select option 4
```

Run manual report:
```bash
./setup.sh  # Select option 5
```

### Report Format

```
📊 Daily Traffic Report
🖥️ DMIT-LAX.EB.INTRO

📈 Today's Usage
├  Usage: 2.16 GB
├  Average: 2.16 GB
└  Status: 1.0x ✅

💳 Billing Cycle
├  Limit: 500 GB
├  Used: 2.16 GB
└  ▓▓░░░░░░░░ 0.43%

🔄 Cycle Info
├  Days: 1 / 23 (22 remaining)
└  Resets: 29th of each month
```

### Troubleshooting

**Notifications not received?**
- Test with `./setup.sh` option 4
- Check Telegram bot token and chat ID
- Verify network access: `curl -I https://api.telegram.org`

**Traffic not tracking?**
- Check network interface: `ip link show`
- Verify traffic data: `cat data/traffic.db`

**Cron not running?**
- Check service: `systemctl status cron`
- View jobs: `crontab -l`
- Check logs: `cat data/cron.log`

### Uninstall

```bash
./setup.sh  # Select option 6
```

### License

MIT License - see LICENSE file for details.

---

## 中文

### 项目描述

VPS Traffic Reporter 监控 VPS 网络流量，每天通过 Telegram 发送报告。追踪月度带宽使用，避免超额费用。

### 功能特点

- 📊 通过 Telegram 发送每日流量报告
- 🔄 自动账单周期管理
- 📈 可视化进度条和使用统计
- ⚠️ 高流量使用智能提醒
- ⚙️ 交互式简易配置

### 快速安装

一键安装：

```bash
curl -Ls https://raw.githubusercontent.com/uniquMonte/server-traffic-reporter/main/install.sh | sudo bash
```

或先下载：
```bash
curl -Ls https://raw.githubusercontent.com/uniquMonte/server-traffic-reporter/main/install.sh -o install.sh
sudo bash install.sh
```

### 设置

运行设置脚本：
```bash
./setup.sh
```

需要提供：
1. **Telegram Bot Token** - 从 [@BotFather](https://t.me/BotFather) 获取
2. **Telegram Chat ID** - 从 [@userinfobot](https://t.me/userinfobot) 获取
3. **流量重置日期** - 每月流量重置日期（1-31）
4. **月流量限制** - 流量限制（GB）
5. **网络接口** - 通常自动检测（eth0, ens3 等）

### 使用方法

查看配置：
```bash
./setup.sh  # 选择选项 1
```

更新设置：
```bash
./setup.sh  # 选择选项 2
```

测试通知：
```bash
./setup.sh  # 选择选项 4
```

手动运行报告：
```bash
./setup.sh  # 选择选项 5
```

### 报告格式

```
📊 Daily Traffic Report
🖥️ DMIT-LAX.EB.INTRO

📈 Today's Usage
├  Usage: 2.16 GB
├  Average: 2.16 GB
└  Status: 1.0x ✅

💳 Billing Cycle
├  Limit: 500 GB
├  Used: 2.16 GB
└  ▓▓░░░░░░░░ 0.43%

🔄 Cycle Info
├  Days: 1 / 23 (22 remaining)
└  Resets: 29th of each month
```

### 故障排除

**收不到通知？**
- 使用 `./setup.sh` 选项 4 测试
- 检查 Telegram bot token 和 chat ID
- 验证网络访问：`curl -I https://api.telegram.org`

**流量统计不正确？**
- 检查网络接口：`ip link show`
- 验证流量数据：`cat data/traffic.db`

**定时任务未运行？**
- 检查服务：`systemctl status cron`
- 查看任务：`crontab -l`
- 检查日志：`cat data/cron.log`

### 卸载

```bash
./setup.sh  # 选择选项 6
```

### 许可证

MIT 许可证 - 详见 LICENSE 文件。

---

Made with ❤️ by uniquMonte
