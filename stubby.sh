#!/bin/sh
set -eu

HOTPLUG_FILE="/etc/hotplug.d/iface/99-stubby-after-wan"

echo "=== STEP 1: creating hotplug script ==="

cat > "$HOTPLUG_FILE" <<'EOF'
#!/bin/sh

[ "${ACTION:-}" = "ifup" ] || exit 0
[ "${INTERFACE:-}" = "wan" ] || exit 0

LOGFILE="/tmp/stubby-fix.log"

log_msg() {
    MSG="$1"
    logger -t stubby-fix "$MSG"
    echo "$(date) - $MSG" >> "$LOGFILE"
}

port_5453_listening() {
    if command -v ss >/dev/null 2>&1; then
        ss -ln 2>/dev/null | grep -qE '127\.0\.0\.1:5453|:5453'
        return $?
    fi

    if command -v netstat >/dev/null 2>&1; then
        netstat -ln 2>/dev/null | grep -qE '127\.0\.0\.1:5453|:5453'
        return $?
    fi

    return 1
}

log_msg "WAN is up, waiting for internet connectivity"

for i in $(seq 1 30); do
    if ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
        log_msg "Internet connectivity detected"
        break
    fi

    if [ "$i" -eq 30 ]; then
        log_msg "WARNING: internet connectivity was not detected after 30 seconds"
    fi

    sleep 1
done

log_msg "Restarting stubby"
/etc/init.d/stubby restart || log_msg "ERROR: stubby restart command failed"

log_msg "Waiting for stubby listener on 5453"

for i in $(seq 1 15); do
    if port_5453_listening; then
        log_msg "Stubby is listening on port 5453"
        break
    fi

    if [ "$i" -eq 15 ]; then
        log_msg "ERROR: port 5453 is not listening after 15 seconds"
    fi

    sleep 1
done

if pgrep stubby >/dev/null 2>&1; then
    log_msg "Stubby process is running"
else
    log_msg "ERROR: stubby process not found"
fi

log_msg "Restarting dnsmasq"
/etc/init.d/dnsmasq restart || log_msg "ERROR: dnsmasq restart command failed"

sleep 2

log_msg "Checking DNS resolution through dnsmasq"

if nslookup google.com 127.0.0.1 >/dev/null 2>&1; then
    log_msg "google.com resolution via dnsmasq OK"
else
    log_msg "ERROR: google.com resolution via dnsmasq failed"
fi

if nslookup youtube.com 127.0.0.1 >/dev/null 2>&1; then
    log_msg "youtube.com resolution via dnsmasq OK"
else
    log_msg "ERROR: youtube.com resolution via dnsmasq failed"
fi

if [ -x /etc/init.d/getdomains ]; then
    log_msg "Restarting getdomains"
    /etc/init.d/getdomains restart || log_msg "ERROR: getdomains restart command failed"
else
    log_msg "getdomains init script not found, skipping"
fi

log_msg "DNS stack restart completed"
EOF

echo "=== STEP 2: making hotplug script executable ==="
chmod +x "$HOTPLUG_FILE"

echo "=== STEP 3: enabling stubby autostart ==="
if [ -x /etc/init.d/stubby ]; then
    /etc/init.d/stubby enable
else
    echo "WARNING: stubby init script not found"
fi

echo "=== STEP 4: verifying file ==="
ls -l "$HOTPLUG_FILE"

echo "=== STEP 5: done ==="
echo "Hotplug script installed."
echo "Logs after reboot will be here: /tmp/stubby-fix.log"
echo "You can also check them with: logread | grep stubby-fix"

echo "=== STEP 6: rebooting router ==="
reboot
