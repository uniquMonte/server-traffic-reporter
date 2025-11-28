# 流量统计显示为 0 的调试指南

## 快速诊断

如果你的流量报告一直显示 0 GB,请立即运行诊断脚本:

```bash
cd /path/to/server-traffic-reporter
sudo ./scripts/debug_traffic.sh
```

## 诊断脚本会检查什么?

1. ✅ 配置文件是否存在
2. ✅ 网络接口配置是否正确
3. ✅ 能否读取流量统计文件
4. ✅ 当前各接口的流量数据
5. ✅ 数据库状态和基准值
6. ✅ 推荐最佳网络接口

## 最常见的问题

### 🔴 问题: 网络接口配置错误

**现象**: 诊断脚本显示:
```
✗ Interface 'eth1' does not exist!
Available network interfaces:
  - eth0
  - docker0
```

或者:
```
✗ WARNING: Total traffic is 0!
This interface may not be the one carrying your traffic.

Checking all interfaces:
  eth0: 45.32 GB ✓
  eth1: 0.00 GB
```

**解决方法**:

1. 记下有流量的接口名称(比如上面的 `eth0`)

2. 编辑配置文件:
```bash
nano config/config.conf
```

3. 找到这一行:
```bash
NETWORK_INTERFACE="eth1"  # 旧的错误配置
```

4. 改成有流量的接口:
```bash
NETWORK_INTERFACE="eth0"  # 新的正确配置
```

5. 保存退出 (Ctrl+X, Y, Enter)

6. 重置数据库以清除旧数据:
```bash
./scripts/traffic_monitor.sh
# 选择 2 (Manual Reset Database)
# 输入 yes 确认
```

7. 测试:
```bash
./scripts/traffic_monitor.sh
# 选择 3 (View Current Statistics)
```

### 🟡 问题: 基准值等于当前值

**现象**: 诊断脚本显示:
```
Traffic since last baseline:
RX: 0 bytes (0.00 GB)
TX: 0 bytes (0.00 GB)
Total: 0 bytes (0.00 GB)

✗ No traffic detected since last measurement!
```

但当前流量不为 0:
```
Current traffic statistics:
RX (Download): 5234567890 bytes (4.87 GB)
TX (Upload):   1234567890 bytes (1.15 GB)
```

**原因**: 数据库中保存的基准值和当前值相同,这通常发生在:
- 刚初始化数据库
- 刚重置数据库
- 服务器刚重启且脚本立即运行

**解决方法**:

等待一段时间(至少几分钟),让服务器产生一些网络流量,然后:

```bash
# 产生一些流量(可选)
ping -c 10 google.com
curl -I https://www.baidu.com

# 再次检查
./scripts/traffic_monitor.sh
# 选择 3 (View Current Statistics)
```

如果还是 0,可能接口配置错误,回到上一个问题的解决方法。

### 🟢 问题: 权限不足

**现象**:
```
✗ Cannot read /sys/class/net/eth0/statistics/rx_bytes
Permission issue - try running with sudo
```

**解决方法**:

使用 sudo 运行:
```bash
sudo ./scripts/debug_traffic.sh
```

确保 cron 任务使用 root 权限:
```bash
sudo crontab -e
```

### 📋 如何找到正确的网络接口?

运行以下命令查看所有接口及其流量:

```bash
for iface in /sys/class/net/*; do
    name=$(basename $iface)
    if [ "$name" != "lo" ]; then
        rx=$(cat $iface/statistics/rx_bytes 2>/dev/null || echo 0)
        tx=$(cat $iface/statistics/tx_bytes 2>/dev/null || echo 0)
        total=$((rx + tx))
        gb=$(echo "scale=2; $total/1073741824" | bc)
        echo "$name: $gb GB"
    fi
done
```

选择流量最大的接口(通常是 `eth0`, `ens3`, `venet0` 等)。

**注意**:
- ❌ 不要使用 `lo` (本地回环,不统计外网流量)
- ❌ 不要使用 `docker0` (Docker 内部网络)
- ✅ 使用 `eth0`, `eth1`, `ens3`, `venet0` 等主网络接口

## 完整测试流程

### 1. 运行诊断
```bash
sudo ./scripts/debug_traffic.sh
```

### 2. 根据诊断结果修复配置
如果推荐使用其他接口,修改配置文件。

### 3. 重置数据库
```bash
./scripts/traffic_monitor.sh
# 选择 2: Manual Reset Database
# 输入 yes
```

### 4. 等待几分钟产生流量

### 5. 手动发送测试报告
```bash
./scripts/traffic_monitor.sh
# 选择 1: Send Daily Report
```

### 6. 查看 Telegram 收到的报告
应该能看到非零的流量数据。

## 仍然无法解决?

运行以下命令收集调试信息:

```bash
echo "=== System Info ==="
uname -a
cat /etc/os-release | head -5

echo -e "\n=== Network Interfaces ==="
ip addr

echo -e "\n=== Current Traffic ==="
for iface in /sys/class/net/*; do
    name=$(basename $iface)
    if [ "$name" != "lo" ]; then
        rx=$(cat $iface/statistics/rx_bytes 2>/dev/null || echo 0)
        tx=$(cat $iface/statistics/tx_bytes 2>/dev/null || echo 0)
        echo "$name: RX=$rx TX=$tx"
    fi
done

echo -e "\n=== Config ==="
cat config/config.conf | grep -v "BOT_TOKEN" | grep -v "CHAT_ID"

echo -e "\n=== Database Last Lines ==="
tail -10 data/traffic.db

echo -e "\n=== Cron Jobs ==="
crontab -l | grep traffic
```

将输出发送到 GitHub Issues 寻求帮助: https://github.com/uniquMonte/server-traffic-reporter/issues

## 验证接口的小技巧

在终端运行这个命令,然后在浏览器访问你的 VPS 或下载文件:

```bash
INTERFACE="eth0"  # 替换为你的接口
while true; do
    rx=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes)
    tx=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes)
    echo "RX: $rx bytes | TX: $tx bytes"
    sleep 2
done
```

按 Ctrl+C 停止。如果数字在变化,说明这是正确的接口。
