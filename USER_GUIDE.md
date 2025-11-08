# 流量监控 - 使用指南 / Traffic Monitor - User Guide

## 🎯 交互式菜单 / Interactive Menu

直接运行脚本即可进入交互式菜单（无需参数）：

```bash
sudo /opt/vps-traffic-reporter/traffic_monitor.sh
```

### 菜单选项 / Menu Options

```
==========================================
   📊 Traffic Monitor - Control Panel
==========================================

1) 📈 Send Daily Report (Normal Run)
2) 🔄 Manual Reset Database
3) 📊 View Current Statistics
4) 📁 Show Database Content
5) 🔍 Test Configuration
0) ❌ Exit

==========================================
```

---

## 🔄 重置数据库 / Reset Database

### 方法一：使用交互式菜单（推荐）/ Method 1: Interactive Menu (Recommended)

1. 运行脚本进入菜单：
```bash
sudo /opt/vps-traffic-reporter/traffic_monitor.sh
```

2. 选择选项 `2) 🔄 Manual Reset Database`

3. 确认重置（输入 `yes`）

脚本会自动：
- ✅ 备份现有数据库
- ✅ 删除旧数据
- ✅ 初始化新的详细格式数据库
- ✅ 发送Telegram通知

### 方法二：手动操作 / Method 2: Manual Steps

如果您想手动操作，请按以下步骤：

#### 1. 备份并删除旧数据库
```bash
# 备份
sudo cp /opt/vps-traffic-reporter/data/traffic.db \
       /opt/vps-traffic-reporter/data/traffic.db.backup

# 删除
sudo rm /opt/vps-traffic-reporter/data/traffic.db
```

#### 2. 初始化新数据库
```bash
sudo /opt/vps-traffic-reporter/traffic_monitor.sh daily
```

#### 3. 验证新格式
```bash
cat /opt/vps-traffic-reporter/data/traffic.db
```

您应该看到类似这样的格式：
```
# Traffic Database
# Format: DATE|DAILY_BYTES|CUMULATIVE_BYTES|DAILY_RX|DAILY_TX|CUMULATIVE_RX|CUMULATIVE_TX|baseline_rx=RX|baseline_tx=TX
RESET|2025-11-08|0|2025-11
2025-11-08|0|0|0|0|0|0|baseline_rx=1234567890|baseline_tx=987654321
```

---

## 📊 查看统计信息 / View Statistics

使用菜单选项 `3) 📊 View Current Statistics` 可以实时查看：
- 今日流量使用（总计、下载、上传）
- 当前计费周期使用情况
- 使用百分比和进度条

---

## 🔍 测试配置 / Test Configuration

使用菜单选项 `5) 🔍 Test Configuration` 可以检查：
- ✅ 服务器配置（名称、网络接口、流量方向）
- ✅ 网络接口状态和当前流量
- ✅ Telegram Bot配置
- ✅ 数据库格式（新/旧）

---

## 📁 查看数据库 / View Database

使用菜单选项 `4) 📁 Show Database Content` 可以：
- 查看数据库文件路径和大小
- 查看最近10条记录
- 验证数据格式

---

## 🤖 Cron自动运行 / Cron Automatic Execution

Cron定时任务会自动调用脚本发送每日报告，无需交互：

```bash
# Cron配置示例
0 20 * * * /opt/vps-traffic-reporter/traffic_monitor.sh daily
```

**重要：** Cron调用时需要使用 `daily` 或 `auto` 参数，这样脚本会跳过交互式菜单，直接执行日报任务。

---

## 新功能特性 / New Features

### 📊 详细的上传/下载分解
- ⬇️ 下载流量单独显示
- ⬆️ 上传流量单独显示
- 支持今日使用和计费周期两个维度

### 🎯 交互式管理面板
- 一键发送报告
- 安全的数据库重置（带确认）
- 实时统计查看
- 配置测试工具
- 数据库内容查看

### 🔄 自动适配流量方向
- 根据TRAFFIC_DIRECTION配置自动调整显示
- 支持双向(1)、仅上传(2)、仅下载(3)模式

---

## 故障排查 / Troubleshooting

### 问题：脚本提示权限错误
**解决：** 使用 `sudo` 运行脚本

### 问题：找不到数据库文件
**解决：** 检查安装路径是否为 `/opt/vps-traffic-reporter/`

### 问题：想恢复旧数据
**解决：**
```bash
# 查看可用的备份
ls -la /opt/vps-traffic-reporter/data/traffic.db.backup.*

# 恢复特定备份
sudo cp /opt/vps-traffic-reporter/data/traffic.db.backup.20251108_120000 \
       /opt/vps-traffic-reporter/data/traffic.db
```

### 问题：菜单显示异常
**解决：** 确保终端支持UTF-8编码，或者使用 `export LANG=en_US.UTF-8`

### 问题：Cron不发送报告
**解决：**
1. 检查cron配置是否正确：`sudo crontab -l`
2. 确保使用 `daily` 参数：`/path/to/traffic_monitor.sh daily`
3. 查看cron日志：`grep CRON /var/log/syslog`

---

## 支持 / Support

如有问题，请检查：
1. `/opt/vps-traffic-reporter/traffic_monitor.sh` 是否存在且可执行
2. 配置文件是否正确设置了BOT_TOKEN和CHAT_ID
3. 网络接口名称是否正确（可通过菜单选项5测试）
4. 查看系统日志：`sudo journalctl -xe`
