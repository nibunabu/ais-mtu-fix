#!/bin/bash
# AIS Fibre MTU Fix Uninstaller

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Uninstalling AIS MTU Fix...${NC}"

# Remove from crontab
if crontab -l 2>/dev/null | grep -q "ais-mtu-fix"; then
    crontab -l 2>/dev/null | grep -v "ais-mtu-fix" | crontab -
    echo -e "${GREEN}✓ Removed from crontab${NC}"
else
    echo -e "${YELLOW}• Not found in crontab${NC}"
fi

# Remove script
if [ -f "/data/ais-mtu-fix.sh" ]; then
    rm -f /data/ais-mtu-fix.sh
    echo -e "${GREEN}✓ Removed /data/ais-mtu-fix.sh${NC}"
else
    echo -e "${YELLOW}• Script file not found${NC}"
fi

# Remove log file
if [ -f "/var/log/ais-mtu-fix.log" ]; then
    rm -f /var/log/ais-mtu-fix.log
    echo -e "${GREEN}✓ Removed log file${NC}"
fi

# Clear mangle rules
iptables -t mangle -F 2>/dev/null && echo -e "${GREEN}✓ Cleared iptables mangle rules${NC}"

echo ""
echo -e "${GREEN}Uninstall complete.${NC}"
echo -e "${YELLOW}Reboot to restore default network settings.${NC}"
echo ""
