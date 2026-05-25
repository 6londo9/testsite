#!/bin/sh
set -eu

HOTPLUG_FILE="/etc/hotplug.d/iface/99-stubby-after-wan"

echo "=== STEP 1: creating hotplug script ==="

cat > "$HOTPLUG_FILE" <<'EOF'
#!/bin/sh

[ "$ACTION" = "ifup" ] || exit 0
[ "$INTERFACE" = "wan" ] || exit 0

logger -t stubby-fix "WAN is up, waiting before restarting DNS stack"

sleep 15

/etc/init.d/stubby restart
sleep 2
/etc/init.d/dnsmasq restart

if [ -x /etc/init.d/getdomains ]; then
    /etc/init.d/getdomains restart
fi

logger -t stubby-fix "DNS stack restarted successfully"
EOF

echo "=== STEP 2: making script executable ==="
chmod +x "$HOTPLUG_FILE"

echo "=== STEP 3: enabling stubby autostart ==="
if [ -x /etc/init.d/stubby ]; then
    /etc/init.d/stubby enable
else
    echo "WARNING: stubby init script not found"
fi

echo "=== STEP 4: verifying file ==="
ls -l "$HOTPLUG_FILE"

echo "=== STEP 5: rebooting router ==="
reboot
