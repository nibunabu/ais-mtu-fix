# AIS Fibre MTU Fix for UniFi Dream Machine Pro

Sick of random disconnects, slow international speeds, and VPN issues on AIS Fibre? You're not alone. This script fixes the MTU/MSS misconfiguration that AIS's PPPoE implementation causes on UniFi Dream Machine Pro (and probably other UniFi gateways).

## The Problem

AIS Fibre in Thailand uses PPPoE with a path MTU of **1492** (not the standard 1500). This causes:

- 🔴 Random disconnects, especially during large transfers
- 🔴 Slow international speeds (TCP blackhole issues)
- 🔴 VPN/WireGuard connection problems
- 🔴 Websites partially loading or timing out
- 🔴 Video calls dropping randomly

The UniFi GUI doesn't expose MTU settings properly for PPPoE connections, and the MSS clamping option is buried in device settings rather than WAN settings where it belongs.

## Quick Start

SSH into your UDM Pro and run:

```bash
curl -sL https://raw.githubusercontent.com/nibunabu/ais-mtu-fix/main/install.sh | sudo bash
```

Or manually:

```bash
git clone https://github.com/nibunabu/ais-mtu-fix.git
cd ais-mtu-fix
sudo ./install.sh
```

## What It Does

1. **Sets WAN MTU to 1492** - The actual path MTU for AIS Fibre PPPoE
2. **Configures MSS Clamping to 1452** - (MTU - 40 bytes for TCP/IP headers)
3. **Enables TCP MTU Probing** - Helps with misconfigured middleboxes
4. **Enables BBR Congestion Control** - Better performance on lossy connections
5. **Optimizes TCP Keepalive** - Prevents AIS from dropping idle connections
6. **Persists across reboots** - Via crontab, no firmware modifications needed

## Test Your Own MTU First

Before blindly trusting these values, test your actual path MTU:

```bash
# SSH into your UDM Pro
ssh root@192.168.1.1

# Test with decreasing packet sizes (add 28 for ICMP header)
ping -M do -s 1472 1.1.1.1  # 1500 total - will likely fail
ping -M do -s 1464 1.1.1.1  # 1492 total - should work for AIS
ping -M do -s 1460 1.1.1.1  # 1488 total - definitely should work
```

If 1464 works, your path MTU is 1492 (1464 + 28 = 1492). Adjust the script values if your results differ.

## Manual Installation

If you prefer to do it manually:

### 1. Create the script

```bash
cat > /data/ais-mtu-fix.sh << 'EOF'
#!/bin/bash
sleep 30

# Detect WAN interface (PPPoE or eth8/eth9)
WAN_IF=$(ip link show 2>/dev/null | grep -o 'ppp[0-9]*' | head -1)
[ -z "$WAN_IF" ] && WAN_IF="eth8"

# Set MTU
ip link set dev $WAN_IF mtu 1492 2>/dev/null

# MSS Clamping
iptables -t mangle -F 2>/dev/null
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1452
iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o $WAN_IF -j TCPMSS --set-mss 1452

# TCP Optimizations
sysctl -w net.ipv4.tcp_mtu_probing=1 > /dev/null 2>&1
sysctl -w net.ipv4.tcp_base_mss=1300 > /dev/null 2>&1
sysctl -w net.ipv4.tcp_slow_start_after_idle=0 > /dev/null 2>&1
sysctl -w net.ipv4.tcp_keepalive_time=600 > /dev/null 2>&1

# Enable BBR if available
if grep -q bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
    sysctl -w net.core.default_qdisc=fq > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_congestion_control=bbr > /dev/null 2>&1
fi

logger "AIS MTU Fix applied: WAN=$WAN_IF MTU=1492 MSS=1452"
EOF

chmod +x /data/ais-mtu-fix.sh
```

### 2. Add to crontab

```bash
(crontab -l 2>/dev/null; echo "@reboot /data/ais-mtu-fix.sh") | crontab -
```

### 3. Run it now

```bash
/data/ais-mtu-fix.sh
```

## Verify It's Working

```bash
# Check MTU
ip link show ppp0  # or eth8

# Check MSS clamping rules
iptables -t mangle -L -n | grep -i mss

# Check TCP settings
sysctl net.ipv4.tcp_mtu_probing
sysctl net.ipv4.tcp_congestion_control

# Test with a large download
curl -o /dev/null http://speedtest.tele2.net/100MB.zip
```

## WireGuard / VPN Users

If you're running WireGuard, set its MTU to account for encapsulation overhead:

```
WireGuard MTU = WAN MTU - 60 = 1432
```

In your WireGuard config:

```ini
[Interface]
PrivateKey = xxx
Address = 10.0.0.1/24
MTU = 1420  # Conservative value, can try 1432
ListenPort = 51820
```

Test WireGuard MTU:

```bash
# From a WireGuard client
ping -M do -s 1392 10.0.0.1  # 1420 total
```

## Troubleshooting

### Still getting disconnects?

Try more conservative values:

```bash
# In the script, change:
ip link set dev $WAN_IF mtu 1452  # Instead of 1492
# And MSS to:
--set-mss 1412  # Instead of 1452
```

### Speed still slow internationally?

Enable these additional TCP tweaks:

```bash
sysctl -w net.ipv4.tcp_fastopen=3
sysctl -w net.ipv4.tcp_window_scaling=1
sysctl -w net.core.rmem_max=16777216
sysctl -w net.core.wmem_max=16777216
```

### Script not running on boot?

Check crontab:

```bash
crontab -l | grep ais-mtu
```

Check if the script exists:

```bash
ls -la /data/ais-mtu-fix.sh
```

Check system log:

```bash
grep "AIS MTU" /var/log/syslog
```

### UniFi firmware update broke it?

Re-run the installer. UniFi updates sometimes clear crontab or /data.

## Why These Specific Values?

| Setting | Value | Reason |
|---------|-------|--------|
| MTU | 1492 | AIS PPPoE path MTU (1500 - 8 byte PPPoE header) |
| MSS | 1452 | MTU - 40 (20 byte IP + 20 byte TCP headers) |
| tcp_mtu_probing | 1 | Auto-discovers path MTU, works around broken middleboxes |
| tcp_base_mss | 1300 | Starting point for MTU probing |
| BBR | enabled | Google's congestion control, better for lossy/high-latency |

## Tested On

- ✅ UniFi Dream Machine Pro (UDM Pro)
- ✅ UniFi Dream Machine Pro SE (UDM Pro SE)
- ✅ UniFi Dream Machine (UDM)
- ⚠️ UniFi Dream Router (UDR) - Should work, not tested
- ⚠️ UniFi Cloud Gateway Ultra - Should work, not tested

## Other Thai ISPs

This might also help with:

- **TRUE Fibre** - Similar PPPoE issues, try MTU 1480-1492
- **3BB** - Usually less problematic, but worth testing
- **NT (CAT/TOT)** - YMMV, test your path MTU first

## Uninstall

```bash
# Remove from crontab
crontab -l | grep -v "ais-mtu-fix" | crontab -

# Delete script
rm /data/ais-mtu-fix.sh

# Reboot to restore defaults
reboot
```

## Contributing

Found better values? Different ISP? Please open an issue or PR with your findings. Include:

1. Your ISP and plan
2. Your tested path MTU (`ping -M do -s XXXX 1.1.1.1`)
3. What fixed your issue

## License

MIT - Do whatever you want with it. Just don't blame me if something breaks.

## Acknowledgments

- The UniFi community for documenting the PPPoE overhead issues
- Everyone in Thailand suffering through AIS's network engineering decisions
- Cloudflare's 1.1.1.1 for being a reliable ping target

---

**If this helped you, consider starring the repo so others can find it.**

*Made with frustration in Thailand 🇹🇭*
