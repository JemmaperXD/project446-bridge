#!/bin/sh
# Установка Project 446 bridge как systemd-сервиса.
# Запуск:  sudo ./install.sh
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
SVC=project446-bridge
INSTALL_DIR=/opt/project446-bridge
STATE_DIR=/var/lib/project446-bridge
RUN_USER=project446

[ "$(id -u)" -eq 0 ] || { echo "нужен root: sudo $0" >&2; exit 1; }
command -v systemctl >/dev/null 2>&1 || {
    echo "systemctl не найден. Для OpenRC используйте linux/openrc/install.sh" >&2
    exit 1
}

if ! getent group "$RUN_USER" >/dev/null 2>&1; then
    groupadd --system "$RUN_USER"
fi
if ! getent passwd "$RUN_USER" >/dev/null 2>&1; then
    useradd --system --gid "$RUN_USER" --home-dir "$STATE_DIR" \
        --no-create-home --shell /usr/sbin/nologin "$RUN_USER"
fi

install -d -m 0755 "$INSTALL_DIR"
install -m 0644 "$ROOT/bridge.py" "$INSTALL_DIR/bridge.py"
install -d -m 0750 -o "$RUN_USER" -g "$RUN_USER" "$STATE_DIR"
install -m 0644 "$HERE/$SVC.service" "/etc/systemd/system/$SVC.service"

# /etc/hosts: gc.project446.com -> локальный мост
if ! grep -qE '^[^#]*[[:space:]]gc\.project446\.com([[:space:]]|$)' /etc/hosts; then
    [ -f /etc/hosts.project446.bak ] || cp -a /etc/hosts /etc/hosts.project446.bak
    printf '\n# project446-bridge\n127.0.0.1 gc.project446.com\n' >> /etc/hosts
    echo "[hosts] добавлено: 127.0.0.1 gc.project446.com"
else
    echo "[hosts] запись уже есть"
fi

systemctl daemon-reload
systemctl enable --now "$SVC"
sleep 2
systemctl --no-pager --full status "$SVC" | head -20 || true
echo
echo "Готово."
echo "  логи:      journalctl -u $SVC -f"
echo "  файл лога: $STATE_DIR/bridge.log"
echo "  стоп:      sudo systemctl stop $SVC"
echo "  удалить:   sudo $HERE/uninstall.sh"
