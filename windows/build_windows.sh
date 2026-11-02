#!/bin/sh
# Сборка Project446-Windows.zip:
#   windows/ + bridge.py + официальный embeddable Python.
#
# Запуск (на Linux/macOS):  ./windows/build_windows.sh
# Результат:                dist/Project446-Windows.zip
#
# Python НЕ коммитится в git: он скачивается при сборке и кладётся
# в release asset.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
OUT_DIR=${OUT_DIR:-$ROOT/dist}
CACHE_DIR=${CACHE_DIR:-$ROOT/.cache}
PY_VER=${PY_VER:-3.12.10}
PY_URL="https://www.python.org/ftp/python/${PY_VER}/python-${PY_VER}-embed-amd64.zip"
PY_ZIP="$CACHE_DIR/python-${PY_VER}-embed-amd64.zip"
STAGE="$OUT_DIR/Project446-Windows"
ZIP="$OUT_DIR/Project446-Windows.zip"

VERSION=$(sed -n 's/^VERSION = "\(.*\)"$/\1/p' "$ROOT/bridge.py" | head -1)
[ -n "$VERSION" ] || { echo "не смог определить VERSION из bridge.py" >&2; exit 1; }

mkdir -p "$CACHE_DIR" "$OUT_DIR"

if [ ! -f "$PY_ZIP" ]; then
    echo "[build] скачиваю Python ${PY_VER} embeddable..."
    curl -fL --retry 3 --retry-delay 2 -o "$PY_ZIP.part" "$PY_URL"
    mv "$PY_ZIP.part" "$PY_ZIP"
fi

echo "[build] версия моста: $VERSION"
rm -rf "$STAGE" "$ZIP"
mkdir -p "$STAGE/python"

cp "$ROOT/bridge.py" "$STAGE/"
cp "$HERE/README.md" "$HERE/1_SETUP.bat" "$HERE/start_bridge.bat" "$STAGE/"

if command -v unzip >/dev/null 2>&1; then
    unzip -q "$PY_ZIP" -d "$STAGE/python"
else
    python3 - "$PY_ZIP" "$STAGE/python" <<'PYEOF'
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
PYEOF
fi

# .bat должны быть в CRLF (иначе cmd может ругаться на склейку строк).
python3 - "$STAGE/1_SETUP.bat" "$STAGE/start_bridge.bat" <<'PYEOF'
import sys
for path in sys.argv[1:]:
    with open(path, "rb") as f:
        data = f.read()
    data = data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    with open(path, "wb") as f:
        f.write(data.replace(b"\n", b"\r\n"))
PYEOF

# Проверка, что в архиве есть всё критичное.
for f in bridge.py start_bridge.bat 1_SETUP.bat README.md \
         python/pythonw.exe python/python312.dll; do
    [ -e "$STAGE/$f" ] || { echo "[build] ОШИБКА: нет $f" >&2; exit 1; }
done

# Убираем возможный мусор из embeddable-архива.
rm -rf "$STAGE/python/__pycache__"

( cd "$STAGE" && zip -qr "$ZIP" . )
ln -sf "$(basename "$ZIP")" "$OUT_DIR/Project446-Windows-latest.zip" 2>/dev/null || true

echo "[build] готово: $ZIP ($(du -h "$ZIP" | cut -f1))"
