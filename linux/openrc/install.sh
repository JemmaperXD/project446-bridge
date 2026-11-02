#!/bin/sh
# Установка Project 446 bridge как сервиса OpenRC.
# Запуск:  sudo ./install.sh
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
SVC=project446-bridge
INSTALL_DIR=/opt/project446-bridge
STATE_DIR=/var/lib/project446-bridge

[ "$(id -u)" -eq 0 ] || { echo "нужен root: sudo $0" >&2; exit 1; }
command -v rc-service >/dev/null 2>&1 || {
    echo "OpenRC не найден. Для systemd используйте linux/systemd/install.sh" >&2
    exit 1
}

install -d -m 0755 "$INSTALL_DIR"
install -m 0644 "$ROOT/bridge.py" "$INSTALL_DIR/bridge.py"
install -d -m 0750 "$STATE_DIR"
install -m 0755 "$HERE/$SVC" "/etc/init.d/$SVC"

if ! grep -qE '^[^#]*[[:space:]]gc\.project446\.com([[:space:]]|$)' /etc/hosts; then
    [ -f /etc/hosts.project446.bak ] || cp -a /etc/hosts /etc/hosts.project446.bak
    printf '\n# project446-bridge\n127.0.0.1 gc.project446.com\n' >> /etc/hosts
    echo "[hosts] добавлено: 127.0.0.1 gc.project446.com"
else
    echo "[hosts] запись уже есть"
fi

rc-update add "$SVC" default >/dev/null 2>&1 || true
rc-service "$SVC" restart 2>/dev/null || rc-service "$SVC" start
sleep 2
rc-service "$SVC" status || true
echo
echo "Готово."
echo "  логи:  tail -f $STATE_DIR/bridge.log"
echo "  стоп:  sudo rc-service $SVC stop"
echo "  удалить: sudo $HERE/uninstall.sh"
