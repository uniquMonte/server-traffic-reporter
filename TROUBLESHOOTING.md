# 故障排除指南 (Troubleshooting Guide)

## 问题: 流量统计一直显示为 0

如果你的流量报告一直显示 0 GB,请按照以下步骤排查问题。

### 步骤 1: 运行诊断脚本

我们提供了一个诊断脚本来帮助你找出问题所在:

```bash
cd /path/to/server-traffic-reporter
./scripts/debug_traffic.sh
```

如果遇到权限问题,使用 sudo:

```bash
sudo ./scripts/debug_traffic.sh
```

### 步骤 2: 常见问题和解决方案

#### 问题 1: 网络接口配置错误

**症状**: 诊断脚本显示当前接口流量为 0,但其他接口有流量

**原因**: 配置文件中的 `NETWORK_INTERFACE` 设置不正确

**解决方案**:

1. 运行诊断脚本查看所有网络接口:
```bash
./scripts/debug_traffic.sh
```

2. 诊断脚本会推荐流量最大的接口

3. 编辑配置文件:
```bash
nano config/config.conf
```

4. 修改 `NETWORK_INTERFACE` 为正确的接口名称:
```bash
NETWORK_INTERFACE="eth0"  # 替换为你的实际接口
```

常见的网络接口名称:
- `eth0`, `eth1` - 传统以太网接口
- `ens3`, `ens5`, `ens33` - 新版 systemd 命名
- `eno1`, `eno2` - 板载网卡
- `enp0s3`, `enp3s0` - PCI 网卡
- `venet0`, `venet0:0` - OpenVZ 虚拟化
- `wlan0` - 无线接口 (通常不用于VPS)

#### 问题 2: 基准值设置问题

**症状**: 接口有流量,但计算出的增量为 0

**原因**: 数据库基准值与当前值相同

**解决方案**:

1. 查看当前统计:
```bash
./scripts/traffic_monitor.sh
# 选择选项 3: View Current Statistics
```

2. 如果确认有问题,手动重置数据库:
```bash
./scripts/traffic_monitor.sh
# 选择选项 2: Manual Reset Database
# 输入 'yes' 确认
```

3. 等待一段时间产生一些流量后,再次检查

#### 问题 3: 权限问题

**症状**: 无法读取 `/sys/class/net/` 下的统计文件

**解决方案**:

确保 cron 任务或脚本以 root 权限运行:

```bash
sudo crontab -e
```

检查 cron 任务是否存在并正确配置。

#### 问题 4: 服务器刚启动

**症状**: 刚部署或重启服务器后,流量为 0

**原因**: 这是正常的,需要等待一段时间积累流量

**解决方案**:

1. 产生一些流量(浏览网页、下载文件等)
2. 等待几分钟
3. 手动运行一次监控脚本:
```bash
./scripts/traffic_monitor.sh
# 选择选项 1: Send Daily Report
```

### 步骤 3: 手动测试流量统计

你可以手动测试当前接口的流量:

```bash
# 查看当前流量
INTERFACE="eth0"  # 替换为你的接口
echo "RX: $(cat /sys/class/net/$INTERFACE/statistics/rx_bytes) bytes"
echo "TX: $(cat /sys/class/net/$INTERFACE/statistics/tx_bytes) bytes"

# 等待几秒,产生一些流量
sleep 5

# 再次查看
echo "RX: $(cat /sys/class/net/$INTERFACE/statistics/rx_bytes) bytes"
echo "TX: $(cat /sys/class/net/$INTERFACE/statistics/tx_bytes) bytes"
```

如果两次读数相同,说明这个接口没有流量,需要换一个接口。

### 步骤 4: 检查所有接口的流量

```bash
# 列出所有网络接口及其流量
for iface in /sys/class/net/*; do
    name=$(basename $iface)
    if [ "$name" != "lo" ]; then
        rx=$(cat $iface/statistics/rx_bytes 2>/dev/null || echo 0)
        tx=$(cat $iface/statistics/tx_bytes 2>/dev/null || echo 0)
        total=$((rx + tx))
        echo "$name: $total bytes"
    fi
done
```

选择流量最大的接口更新到配置文件中。

### 步骤 5: 验证配置

运行测试配置功能:

```bash
./scripts/traffic_monitor.sh
# 选择选项 5: Test Configuration
```

这会显示:
- 当前配置
- 网络接口状态
- Telegram 配置
- 数据库状态

### 步骤 6: 强制刷新

如果以上步骤都没有解决问题:

1. 备份当前数据库:
```bash
cp data/traffic.db data/traffic.db.backup
```

2. 手动重置:
```bash
./scripts/traffic_monitor.sh
# 选择选项 2: Manual Reset Database
```

3. 等待几分钟产生流量

4. 手动发送报告:
```bash
./scripts/traffic_monitor.sh
# 选择选项 1: Send Daily Report
```

### 调试日志

如果问题仍然存在,可以启用详细日志:

```bash
# 手动运行脚本并查看输出
bash -x ./scripts/traffic_monitor.sh daily
```

这会显示详细的执行过程,帮助定位问题。

### 需要帮助?

如果以上步骤都无法解决问题,请在 GitHub Issues 中提供以下信息:

1. 运行 `./scripts/debug_traffic.sh` 的完整输出
2. 运行 `cat config/config.conf` 的输出 (隐藏敏感信息如 BOT_TOKEN)
3. 运行 `tail -20 data/traffic.db` 的输出
4. VPS 提供商和操作系统版本
5. 网络接口信息: `ip addr` 或 `ifconfig`

## 常见问题 FAQ

### Q: 为什么推荐使用 eth0 而不是 lo?

A: `lo` 是本地回环接口,只统计本机进程间通信的流量,不包括外网流量。你需要使用实际的网络接口如 `eth0`, `ens3` 等。

### Q: 我的接口名称很奇怪,是正常的吗?

A: 是的。现代 Linux 系统使用"可预测的网络接口名称"(Predictable Network Interface Names),所以你可能看到 `ens3`, `enp0s3` 这样的名称,这是正常的。

### Q: 流量统计会在服务器重启后丢失吗?

A: 不会。`/sys/class/net/` 下的计数器会在重启后归零,但脚本会检测到这种情况并从数据库的累计值继续计算。

### Q: 我可以在多个接口上统计流量吗?

A: 目前脚本只支持单个接口。如果你需要统计多个接口,可以修改脚本或运行多个实例。

### Q: 流量统计准确吗?

A: 统计来自 Linux 内核的网络接口计数器,是非常准确的。但注意这包括所有网络层的开销(TCP/IP头部、重传等),实际应用层数据会略少。
