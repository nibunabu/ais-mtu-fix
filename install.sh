#!/bin/bash
# AIS Fibre MTU Fix Installer for UniFi Dream Machine Pro
# https://github.com/nibunabu/ais-mtu-fix

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_PATH="/data/ais-mtu-fix.sh"

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         AIS Fibre MTU Fix for UniFi Dream Machine         ║"
echo "║                    v1.0.0                                 ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Please run as root (sudo)${NC}"
    exit 1
fi

# Check if this looks like a UniFi device
if [ ! -d "/data" ]; then
    echo -e "${YELLOW}Warning: /data directory not found. Creating it...${NC}"
    mkdir -p /data
fi

echo -e "${GREEN}[1/4]${NC} Creating MTU fix script..."

cat > "$SCRIPT_PATH" << 'SCRIPT'
#!/bin/bash
# AIS Fibre MTU Fix - Runs on boot
# Settings: MTU=1492, MSS=1452 (tested for AIS Fibre Thailand)

# Wait for network stack to be ready
sleep 30

# Log function
log() {
    logger -t "ais-mtu-fix" "$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> /var/log/ais-mtu-fix.log
}

log "Starting AIS MTU fix..."

# Detect PPPoE interface, fallback to eth8/eth9
WAN_IF=$(ip link show 2>/dev/null | grep -oE 'ppp[0-9]+' | head -1)
if [ -z "$WAN_IF" ]; then
    for iface in eth8 eth9 eth4; do
        if ip link show "$iface" 2>/dev/null | grep -q "state UP"; then
            WAN_IF="$iface"
            break
        fi
    done
fi

if [ -z "$WAN_IF" ]; then
    log "ERROR: Could not detect WAN interface"
    exit 1
fi

log "Detected WAN interface: $WAN_IF"

# Set MTU (1492 = standard PPPoE max for AIS)
if ip link set dev "$WAN_IF" mtu 1492 2>/dev/null; then
    log "Set MTU to 1492 on $WAN_IF"
else
    log "Warning: Could not set MTU on $WAN_IF"
fi

# Clear existing mangle rules and set MSS clamping
# MSS = MTU - 40 (20 IP + 20 TCP headers)
iptables -t mangle -F 2>/dev/null || true
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1452
iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o "$WAN_IF" -j TCPMSS --set-mss 1452
log "MSS clamping set to 1452"

# TCP Optimizations
sysctl -w net.ipv4.tcp_mtu_probing=1 > /dev/null 2>&1
sysctl -w net.ipv4.tcp_base_mss=1300 > /dev/null 2>&1
sysctl -w net.ipv4.tcp_slow_start_after_idle=0 > /dev/null 2>&1
sysctl -w net.ipv4.tcp_keepalive_time=600 > /dev/null 2>&1
sysctl -w net.ipv4.tcp_keepalive_intvl=60 > /dev/null 2>&1
sysctl -w net.ipv4.tcp_keepalive_probes=5 > /dev/null 2>&1
log "TCP optimizations applied"

# Enable BBR congestion control if available
if grep -q bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
    sysctl -w net.core.default_qdisc=fq > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_congestion_control=bbr > /dev/null 2>&1
    log "BBR congestion control enabled"
fi

log "AIS MTU fix completed successfully"
SCRIPT

chmod +x "$SCRIPT_PATH"
echo -e "${GREEN}   ✓ Created $SCRIPT_PATH${NC}"

echo -e "${GREEN}[2/4]${NC} Setting up boot persistence..."

# Remove any existing entry first, then add new one
CRON_CMD="@reboot $SCRIPT_PATH"
(crontab -l 2>/dev/null | grep -v "ais-mtu-fix"; echo "$CRON_CMD") | crontab -
echo -e "${GREEN}   ✓ Added to crontab${NC}"

echo -e "${GREEN}[3/4]${NC} Applying settings now..."

# Run in background so we don't wait for the sleep
nohup bash -c "sleep 2 && $SCRIPT_PATH" > /dev/null 2>&1 &
echo -e "${GREEN}   ✓ Script running in background${NC}"

echo -e "${GREEN}[4/4]${NC} Verifying installation..."
sleep 3

# Quick verification
echo ""
echo -e "${BLUE}Current Configuration:${NC}"
echo "─────────────────────────────────────"

WAN_IF=$(ip link show 2>/dev/null | grep -oE 'ppp[0-9]+' | head -1)
[ -z "$WAN_IF" ] && WAN_IF="eth8"

printf "  WAN Interface:      %s\n" "$WAN_IF"
printf "  Current MTU:        %s\n" "$(ip link show $WAN_IF 2>/dev/null | grep -o 'mtu [0-9]*' | awk '{print $2}' || echo 'checking...')"
printf "  TCP MTU Probing:    %s\n" "$(sysctl -n net.ipv4.tcp_mtu_probing 2>/dev/null || echo 'N/A')"
printf "  Congestion Control: %s\n" "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 'N/A')"

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            Installation Complete! 🎉                      ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "The fix will automatically apply on every reboot."
echo ""
echo -e "Log file: ${YELLOW}/var/log/ais-mtu-fix.log${NC}"
echo -e "To uninstall: ${YELLOW}curl -sL https://raw.githubusercontent.com/nibunabu/ais-mtu-fix/main/uninstall.sh | sudo bash${NC}"
echo ""
