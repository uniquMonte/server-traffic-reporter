# VPS Traffic Reporter 📊

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Shell-Script-green.svg)](https://www.gnu.org/software/bash/)

[English](#english) | [中文](#中文)

---

## English

### Description

VPS Traffic Reporter is a lightweight bash script that monitors your VPS network traffic usage and sends daily reports to your Telegram account. Perfect for tracking your monthly bandwidth allocation and avoiding overage charges.

### Features

- 📊 **Daily Traffic Reports**: Automatic daily reports sent to your Telegram
- 🔄 **Billing Cycle Management**: Automatically resets on your specified billing day
- 📈 **Usage Statistics**:
  - Today's traffic usage
  - Current billing cycle total usage
  - Remaining traffic
  - Usage percentage with visual progress bar
- ⚠️ **Smart Alerts**: Warning notifications when approaching traffic limits
- 🎨 **Visual Reports**: Color-coded status indicators and progress bars
- ⚙️ **Easy Configuration**: Interactive setup with menu-driven interface
- 🔧 **Flexible Settings**: Customizable reset day, traffic limit, and report time
- 🧪 **Test Mode**: Test your Telegram notifications before going live

### Requirements

- Linux-based VPS
- Bash shell
- `curl` for Telegram API calls
- `bc` for calculations (usually pre-installed)
- Network access to Telegram API

### Installation

#### Quick Install (Recommended)

Install with a single command (choose one):

**Method 1 - Using curl:**
```bash
curl -Ls https://raw.githubusercontent.com/uniquMonte/server-traffic-reporter/main/install.sh | sudo bash
```

**Method 2 - Using wget:**
```bash
wget -qO- https://raw.githubusercontent.com/uniquMonte/server-traffic-reporter/main/install.sh | sudo bash
```

**Method 3 - Download then run:**
```bash
curl -Ls https://raw.githubusercontent.com/uniquMonte/server-traffic-reporter/main/install.sh -o install.sh
sudo bash install.sh
```

This will:
- Check system requirements and install missing dependencies
- Download the latest version from GitHub
- Set up necessary permissions
- Create a convenient command shortcut
- Guide you through initial configuration

#### Manual Installation

If you prefer to install manually:

1. **Clone the repository:**
   ```bash
   git clone https://github.com/uniquMonte/server-traffic-reporter.git
   cd server-traffic-reporter
   ```

2. **Make the setup script executable:**
   ```bash
   chmod +x setup.sh
   ```

3. **Run the setup:**
   ```bash
   ./setup.sh
   ```

### Initial Setup

When you run `./setup.sh` for the first time, you'll see a menu with options:

```
======================================
  VPS Traffic Reporter
======================================

1) View current configuration
2) Update configuration
3) Update scripts to latest version
4) Test notification
5) Run traffic report now
6) Uninstall
0) Exit (or just press Enter)
```

#### Step 1: Update Configuration (Option 2)

You'll need to provide:

1. **Server Name**: A friendly name for your VPS (e.g., "Production Server")
2. **Telegram Bot Token**:
   - Talk to [@BotFather](https://t.me/BotFather) on Telegram
   - Send `/newbot` and follow the instructions
   - Copy the bot token provided
3. **Telegram Chat ID**:
   - Talk to [@userinfobot](https://t.me/userinfobot) on Telegram
   - Copy your Chat ID
4. **Traffic Reset Day**: Day of the month when your traffic resets (1-31)
5. **Monthly Traffic Limit**: Your monthly traffic limit in GB (e.g., 500)
6. **Report Time**: When to send daily reports (HH:MM format, e.g., 09:00)
7. **Network Interface**: Usually auto-detected (e.g., eth0, ens3)

#### Step 2: Test Notification (Option 4)

Before setting up the cron job, test if your Telegram configuration works:
- Select option 4 from the menu
- Check your Telegram for a test message

#### Step 3: Install Cron Job

After updating configuration, you'll be asked if you want to install the cron job. Say "yes" to enable automatic daily reports.

### Usage

#### View Current Configuration
```bash
./setup.sh
# Select option 1
```

#### Update Configuration
```bash
./setup.sh
# Select option 2
```

#### Run Manual Report
```bash
./setup.sh
# Select option 5
```

Or run directly:
```bash
./scripts/traffic_monitor.sh daily
```

#### Update Scripts
```bash
./setup.sh
# Select option 3
```

### Report Format

Daily reports include:

```
📊 Daily Traffic Report - MyVPS

📅 Date: 2025-11-06
⏰ Time: 09:00:00

━━━━━━━━━━━━━━━━━━━━

📈 Today's Usage: 2.45 GB

📊 Billing Cycle Stats:
├ Used: 125.50 GB
├ Limit: 500 GB
├ Remaining: 374.50 GB
└ Usage: 25.10% 🟢

████████░░░░░░░░░░░░ 25.10%

━━━━━━━━━━━━━━━━━━━━

🔄 Cycle Info:
├ Reset Day: 03 of each month
└ Days until reset: 27
```

### Configuration File

Configuration is stored in `config/config.conf`:

```bash
SERVER_NAME="MyVPS"
TELEGRAM_BOT_TOKEN="your_bot_token"
TELEGRAM_CHAT_ID="your_chat_id"
TRAFFIC_RESET_DAY=3
MONTHLY_TRAFFIC_LIMIT=500
REPORT_TIME="09:00"
NETWORK_INTERFACE="eth0"
CRON_INSTALLED="yes"
```

### File Structure

```
server-traffic-reporter/
├── setup.sh                    # Main setup script
├── scripts/
│   ├── traffic_monitor.sh      # Traffic monitoring script
│   └── telegram_notify.sh      # Telegram notification handler
├── config/
│   └── config.conf             # Configuration file
├── data/
│   ├── traffic.db              # Traffic database
│   └── cron.log                # Cron job logs
└── README.md                   # This file
```

### Troubleshooting

#### Notifications Not Received

1. Check your Telegram configuration:
   ```bash
   ./setup.sh
   # Select option 1 to view configuration
   ```

2. Test notification:
   ```bash
   ./setup.sh
   # Select option 4
   ```

3. Check if curl can access Telegram:
   ```bash
   curl -I https://api.telegram.org
   ```

#### Traffic Not Tracking Correctly

1. Verify network interface:
   ```bash
   ip link show
   ```

2. Check if interface has traffic:
   ```bash
   cat /sys/class/net/YOUR_INTERFACE/statistics/rx_bytes
   cat /sys/class/net/YOUR_INTERFACE/statistics/tx_bytes
   ```

3. Review traffic database:
   ```bash
   cat data/traffic.db
   ```

#### Cron Job Not Running

1. Check cron service:
   ```bash
   systemctl status cron  # or 'crond' on some systems
   ```

2. View cron jobs:
   ```bash
   crontab -l
   ```

3. Check logs:
   ```bash
   cat data/cron.log
   ```

### Uninstallation

To uninstall:

```bash
./setup.sh
# Select option 6
```

This will:
- Remove the cron job
- Optionally delete configuration and data files

### Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### License

This project is licensed under the MIT License - see the LICENSE file for details.

### Support

If you encounter any issues or have questions:
- Open an issue on [GitHub](https://github.com/uniquMonte/server-traffic-reporter/issues)

---

## 中文

### 项目描述

VPS Traffic Reporter 是一个轻量级的 Bash 脚本，用于监控 VPS 网络流量使用情况，并每天通过 Telegram 发送报告。非常适合追踪每月带宽配额，避免超额费用。

### 功能特点

- 📊 **每日流量报告**: 自动发送每日报告到 Telegram
- 🔄 **账单周期管理**: 在指定的账单日自动重置
- 📈 **使用统计**:
  - 今日流量使用
  - 当前账单周期总使用量
  - 剩余流量
  - 使用百分比和可视化进度条
- ⚠️ **智能提醒**: 接近流量限制时发出警告通知
- 🎨 **可视化报告**: 带有颜色编码的状态指示器和进度条
- ⚙️ **简单配置**: 交互式设置，菜单驱动界面
- 🔧 **灵活设置**: 可自定义重置日期、流量限制和报告时间
- 🧪 **测试模式**: 在正式使用前测试 Telegram 通知

### 系统要求

- 基于 Linux 的 VPS
- Bash shell
- `curl` 用于 Telegram API 调用
- `bc` 用于计算（通常已预装）
- 能访问 Telegram API

### 安装步骤

#### 快速安装（推荐）

使用一条命令完成安装（三选一）：

**方法 1 - 使用 curl:**
```bash
curl -Ls https://raw.githubusercontent.com/uniquMonte/server-traffic-reporter/main/install.sh | sudo bash
```

**方法 2 - 使用 wget:**
```bash
wget -qO- https://raw.githubusercontent.com/uniquMonte/server-traffic-reporter/main/install.sh | sudo bash
```

**方法 3 - 下载后运行:**
```bash
curl -Ls https://raw.githubusercontent.com/uniquMonte/server-traffic-reporter/main/install.sh -o install.sh
sudo bash install.sh
```

安装程序将：
- 检查系统要求并安装缺失的依赖
- 从 GitHub 下载最新版本
- 设置必要的权限
- 创建便捷的命令快捷方式
- 引导您完成初始配置

#### 手动安装

如果您希望手动安装：

1. **克隆仓库:**
   ```bash
   git clone https://github.com/uniquMonte/server-traffic-reporter.git
   cd server-traffic-reporter
   ```

2. **设置脚本可执行权限:**
   ```bash
   chmod +x setup.sh
   ```

3. **运行设置:**
   ```bash
   ./setup.sh
   ```

### 初始设置

首次运行 `./setup.sh` 时，会看到菜单选项：

```
======================================
  VPS Traffic Reporter
======================================

1) View current configuration          查看当前配置
2) Update configuration                更新配置
3) Update scripts to latest version    更新脚本到最新版本
4) Test notification                   测试通知
5) Run traffic report now              立即运行流量报告
6) Uninstall                           卸载
0) Exit (or just press Enter)          退出
```

#### 步骤 1: 更新配置（选项 2）

需要提供以下信息：

1. **服务器名称**: VPS 的友好名称（例如："生产服务器"）
2. **Telegram Bot Token**:
   - 在 Telegram 中找 [@BotFather](https://t.me/BotFather)
   - 发送 `/newbot` 并按指示操作
   - 复制提供的 bot token
3. **Telegram Chat ID**:
   - 在 Telegram 中找 [@userinfobot](https://t.me/userinfobot)
   - 复制你的 Chat ID
4. **流量重置日期**: 每月流量重置的日期（1-31）
5. **月流量限制**: 每月流量限制（GB），例如 500
6. **报告时间**: 发送每日报告的时间（HH:MM 格式，如 09:00）
7. **网络接口**: 通常自动检测（如 eth0, ens3）

#### 步骤 2: 测试通知（选项 4）

在设置定时任务之前，测试 Telegram 配置是否正常：
- 从菜单选择选项 4
- 检查 Telegram 是否收到测试消息

#### 步骤 3: 安装定时任务

更新配置后，会询问是否安装定时任务。选择"yes"以启用自动每日报告。

### 使用方法

#### 查看当前配置
```bash
./setup.sh
# 选择选项 1
```

#### 更新配置
```bash
./setup.sh
# 选择选项 2
```

#### 手动运行报告
```bash
./setup.sh
# 选择选项 5
```

或直接运行：
```bash
./scripts/traffic_monitor.sh daily
```

#### 更新脚本
```bash
./setup.sh
# 选择选项 3
```

### 报告格式

每日报告包含：

```
📊 Daily Traffic Report - 我的VPS

📅 Date: 2025-11-06
⏰ Time: 09:00:00

━━━━━━━━━━━━━━━━━━━━

📈 Today's Usage: 2.45 GB        今日使用

📊 Billing Cycle Stats:          账单周期统计
├ Used: 125.50 GB                已用
├ Limit: 500 GB                  限制
├ Remaining: 374.50 GB           剩余
└ Usage: 25.10% 🟢              使用率

████████░░░░░░░░░░░░ 25.10%

━━━━━━━━━━━━━━━━━━━━

🔄 Cycle Info:                   周期信息
├ Reset Day: 03 of each month    重置日期：每月3号
└ Days until reset: 27           距离重置：27天
```

### 配置文件

配置存储在 `config/config.conf`:

```bash
SERVER_NAME="MyVPS"
TELEGRAM_BOT_TOKEN="your_bot_token"
TELEGRAM_CHAT_ID="your_chat_id"
TRAFFIC_RESET_DAY=3
MONTHLY_TRAFFIC_LIMIT=500
REPORT_TIME="09:00"
NETWORK_INTERFACE="eth0"
CRON_INSTALLED="yes"
```

### 文件结构

```
server-traffic-reporter/
├── setup.sh                    # 主设置脚本
├── scripts/
│   ├── traffic_monitor.sh      # 流量监控脚本
│   └── telegram_notify.sh      # Telegram 通知处理
├── config/
│   └── config.conf             # 配置文件
├── data/
│   ├── traffic.db              # 流量数据库
│   └── cron.log                # 定时任务日志
└── README.md                   # 本文件
```

### 故障排除

#### 收不到通知

1. 检查 Telegram 配置:
   ```bash
   ./setup.sh
   # 选择选项 1 查看配置
   ```

2. 测试通知:
   ```bash
   ./setup.sh
   # 选择选项 4
   ```

3. 检查 curl 能否访问 Telegram:
   ```bash
   curl -I https://api.telegram.org
   ```

#### 流量统计不正确

1. 验证网络接口:
   ```bash
   ip link show
   ```

2. 检查接口是否有流量:
   ```bash
   cat /sys/class/net/你的接口名/statistics/rx_bytes
   cat /sys/class/net/你的接口名/statistics/tx_bytes
   ```

3. 查看流量数据库:
   ```bash
   cat data/traffic.db
   ```

#### 定时任务未运行

1. 检查 cron 服务:
   ```bash
   systemctl status cron  # 某些系统上是 'crond'
   ```

2. 查看定时任务:
   ```bash
   crontab -l
   ```

3. 检查日志:
   ```bash
   cat data/cron.log
   ```

### 卸载

卸载方法：

```bash
./setup.sh
# 选择选项 6
```

这将：
- 删除定时任务
- 可选择删除配置和数据文件

### 贡献

欢迎贡献！请随时提交 Pull Request。

### 许可证

本项目采用 MIT 许可证 - 详见 LICENSE 文件。

### 支持

如果遇到任何问题或有疑问：
- 在 [GitHub](https://github.com/uniquMonte/server-traffic-reporter/issues) 上提交 issue

---

Made with ❤️ by uniquMonte
