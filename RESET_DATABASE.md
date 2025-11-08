# 重置流量数据库指南 / Database Reset Guide

## 快速重置 / Quick Reset

在您的VPS上运行此命令以安全地重置数据库到新的详细格式：

**一键重置命令：**
```bash
sudo bash /opt/vps-traffic-reporter/reset_database.sh
```

---

## 该脚本会做什么 / What This Script Does

1. ✅ 备份现有数据库（如果存在）
2. ✅ 临时禁用cron定时任务
3. ✅ 删除旧数据库
4. ✅ 初始化新的详细格式数据库
5. ✅ 验证新格式正确
6. ✅ 重新启用cron任务

---

## 手动操作步骤 / Manual Steps

如果您想手动操作，请按以下步骤：

### 1. 停止定时任务
```bash
# 查看当前cron配置
sudo crontab -l

# 编辑cron（注释掉traffic_monitor.sh相关行）
sudo crontab -e
```

### 2. 备份并删除旧数据库
```bash
# 备份
sudo cp /opt/vps-traffic-reporter/data/traffic.db \
       /opt/vps-traffic-reporter/data/traffic.db.backup

# 删除
sudo rm /opt/vps-traffic-reporter/data/traffic.db
```

### 3. 初始化新数据库
```bash
sudo /opt/vps-traffic-reporter/traffic_monitor.sh
```

### 4. 验证新格式
```bash
cat /opt/vps-traffic-reporter/data/traffic.db
```

您应该看到类似这样的格式：
```
# Traffic monitoring data
2025-11-08|1234567890|1234567890|123456789|987654321|123456789|987654321|baseline_rx=1234567890|baseline_tx=987654321
```

### 5. 重新启用定时任务
```bash
sudo crontab -e
# 取消注释traffic_monitor.sh相关行
```

---

## 新功能特性 / New Features

重置后，您的流量报告将包含：

- **📊 详细的上传/下载分解**
  - ⬇️ 下载流量单独显示
  - ⬆️ 上传流量单独显示

- **🔄 自动适配流量方向**
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
sudo cp /opt/vps-traffic-reporter/data/traffic.db.backup.* \
       /opt/vps-traffic-reporter/data/traffic.db
```

---

## 支持 / Support

如有问题，请检查：
1. `/opt/vps-traffic-reporter/traffic_monitor.sh` 是否存在且可执行
2. 配置文件是否正确设置了BOT_TOKEN和CHAT_ID
3. 查看系统日志：`sudo journalctl -xe`
