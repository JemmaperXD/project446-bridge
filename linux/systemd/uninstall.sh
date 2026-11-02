#!/bin/sh
# Удаление Project 446 bridge из systemd.
#   sudo ./uninstall.sh            — удалить программу и сервис, оставить пул/логи
#   sudo ./uninstall.sh --purge    — удалить также пул, логи и пользователя
set -eu

SVC=project446-bridge
INSTALL_DIR=/opt/project446-bridge
STATE_DIR=/var/lib/project446-bridge
RUN_USER=project446
PURGE=0

[ "${1:-}" = "--purge" ] && PURGE=1
[ "$(id -u)" -eq 0 ] || { echo "нужен root: sudo $0" >&2; exit 1; }

if command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now "$SVC" 2>/dev/null || true
fi

rm -f "/etc/systemd/system/$SVC.service"
command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload || true
rm -rf "$INSTALL_DIR"

# Убираем только нашу строку hosts (и маркер).
if grep -qE '^127\.0\.0\.1[[:space:]]+gc\.project446\.com$' /etc/hosts 2>/dev/null; then
    [ -f /etc/hosts.project446.bak ] || cp -a /etc/hosts /etc/hosts.project446.bak
    sed -i.tmp -e '/^# project446-bridge$/d' \
        -e '/^127\.0\.0\.1[[:space:]]\{1,\}gc\.project446\.com$/d' /etc/hosts
    rm -f /etc/hosts.tmp
    echo "[hosts] запись удалена (бэкап: /etc/hosts.project446.bak)"
fi

if [ "$PURGE" -eq 1 ]; then
    rm -rf "$STATE_DIR"
    userdel "$RUN_USER" 2>/dev/null || true
    groupdel "$RUN_USER" 2>/dev/null || true
    echo "Пул, логи и пользователь $RUN_USER удалены."
else
    echo "Пул и логи оставлены в $STATE_DIR (удалить: --purge)."
fi
