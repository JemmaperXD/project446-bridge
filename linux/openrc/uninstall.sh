#!/bin/sh
# Удаление Project 446 bridge из OpenRC.
#   sudo ./uninstall.sh            — оставить пул/логи
#   sudo ./uninstall.sh --purge    — удалить и их
set -eu

SVC=project446-bridge
INSTALL_DIR=/opt/project446-bridge
STATE_DIR=/var/lib/project446-bridge
PURGE=0

[ "${1:-}" = "--purge" ] && PURGE=1
[ "$(id -u)" -eq 0 ] || { echo "нужен root: sudo $0" >&2; exit 1; }

rc-service "$SVC" stop 2>/dev/null || true
rc-update del "$SVC" default 2>/dev/null || true
rm -f "/etc/init.d/$SVC"
rm -rf "$INSTALL_DIR"

if grep -qE '^127\.0\.0\.1[[:space:]]+gc\.project446\.com$' /etc/hosts 2>/dev/null; then
    [ -f /etc/hosts.project446.bak ] || cp -a /etc/hosts /etc/hosts.project446.bak
    sed -i.tmp -e '/^# project446-bridge$/d' \
        -e '/^127\.0\.0\.1[[:space:]]\{1,\}gc\.project446\.com$/d' /etc/hosts
    rm -f /etc/hosts.tmp
    echo "[hosts] запись удалена (бэкап: /etc/hosts.project446.bak)"
fi

if [ "$PURGE" -eq 1 ]; then
    rm -rf "$STATE_DIR"
    echo "Пул и логи удалены."
else
    echo "Пул и логи оставлены в $STATE_DIR (удалить: --purge)."
fi
