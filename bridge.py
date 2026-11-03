#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Project 446 bridge.

Локальный TCP-мост:  127.0.0.1:443  ->  gc.project446.com:443
Трафик идёт через пул публичных HTTP-CONNECT-прокси, TLS остаётся
сквозным (end-to-end): мост не расшифровывает и не подменяет трафик.

Зачем: если провайдер не даёт подключиться к IP игрового координатора,
игра ходит на 127.0.0.1:443 (через /etc/hosts или hosts Windows),
а мост находит рабочий прокси и проксирует TCP как есть.

Особенности:
  * пул прокси проверяется в фоне и сохраняется в good_proxies.json;
  * проверка прокси идёт с ПРОВЕРКОЙ сертификата (MITM-прокси вроде
    Zscaler отсеиваются и не попадают в пул);
  * один «залипший» прокси используется первым, чтобы внешний IP не
    менялся на каждом соединении (важно для reservation cookie);
  * мёртвые прокси уходят в карантин;
  * TCP keepalive, ротация лога, отдельные пулы потоков для проверок.

Настройки через переменные окружения:
  BRIDGE_LISTEN_HOST   (по умолчанию 127.0.0.1)
  BRIDGE_LISTEN_PORT   (по умолчанию 443; аргумент командной строки важнее)
  BRIDGE_TARGET_IP     (по умолчанию 213.152.43.203)
  BRIDGE_TARGET_PORT   (по умолчанию 443)
  BRIDGE_TARGET_SNI    (по умолчанию gc.project446.com)
  BRIDGE_STATE_DIR     (по умолчанию папка со скриптом)
  BRIDGE_STICKY_FIRST  (1/0, по умолчанию 1)
  BRIDGE_CONSOLE       (0/1/auto, по умолчанию auto) — вывод в stdout;
                       auto = только если stdout является терминалом
"""

import asyncio
import json
import os
import random
import socket
import ssl
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

VERSION = "2.1.2"


def _env(name, default):
    v = os.environ.get(name)
    return v if v not in (None, "") else default


LISTEN_HOST = _env("BRIDGE_LISTEN_HOST", "127.0.0.1")
LISTEN_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else int(
    _env("BRIDGE_LISTEN_PORT", "443"))
TARGET_IP = _env("BRIDGE_TARGET_IP", "213.152.43.203")
TARGET_PORT = int(_env("BRIDGE_TARGET_PORT", "443"))
TARGET_SNI = _env("BRIDGE_TARGET_SNI", "gc.project446.com")
STICKY_FIRST = _env("BRIDGE_STICKY_FIRST", "1") != "0"
CONSOLE = _env("BRIDGE_CONSOLE", "auto").lower()


def _console_on():
    """auto: печатаем только в терминал, чтобы сервис не дублировал лог."""
    if CONSOLE == "0":
        return False
    if CONSOLE == "1":
        return True
    try:
        return bool(sys.stdout is not None and sys.stdout.isatty())
    except Exception:
        return False


CONSOLE_ON = _console_on()

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
STATE_DIR = _env("BRIDGE_STATE_DIR", BASE_DIR)
LOG_PATH = os.path.join(STATE_DIR, "bridge.log")
POOL_FILE = os.path.join(STATE_DIR, "good_proxies.json")

LISTS = [
    "https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/http.txt",
    "https://raw.githubusercontent.com/monosans/proxy-list/main/proxies/http.txt",
    "https://raw.githubusercontent.com/clarketm/proxy-list/master/proxy-list-raw.txt",
    "https://raw.githubusercontent.com/proxifly/free-proxy-list/main/proxies/protocols/http/data.txt",
    "https://raw.githubusercontent.com/roosterkid/openproxylist/main/HTTPS_RAW.txt",
]

# Небольшой набор «запасных» адресов. Они тоже проверяются с проверкой
# сертификата и попадают в пул только если реально работают.
SEEDS = [
    "194.67.120.148:10808",
    "134.185.85.16:3128",
    "191.195.51.243:8080",
    "186.167.53.178:8282",
]

POOL = {}            # proxy -> latency_ms
BAD_UNTIL = {}       # proxy -> unix time, до которого не трогаем
STICKY = None        # последний удачный прокси
POOL_LOCK = asyncio.Lock()

TARGET_POOL = 12
PROBE_TIMEOUT = 4.0
CONNECT_TIMEOUT = 2.5
STICKY_TIMEOUT = 1.8
HEADER_TIMEOUT = 3.0
MAX_CANDIDATES = 16
ATTEMPTS = 3                # сколько раз пробуем найти туннель под клиента
BAD_COOLDOWN = 300          # 5 минут карантина
KEEPALIVE_EVERY = 60
REFRESH_MIN = 60            # не чаще одного обновления списков в минуту

CANDIDATES = []             # очередь кандидатов из списков
LISTS_TS = 0.0
SEEN = {}                   # proxy -> время последней выдачи
SEEN_TTL = 900              # 15 минут: потом адрес можно проверить снова

CONNECT_REQ = (
    "CONNECT %s:%d HTTP/1.1\r\nHost: %s:%d\r\n\r\n"
    % (TARGET_IP, TARGET_PORT, TARGET_IP, TARGET_PORT)
).encode()

# Отдельные пулы потоков: проверки прокси не должны забивать общий executor,
# иначе connect() к прокси и резолв начинают ждать в очереди по 30+ секунд.
PROBE_EXECUTOR = ThreadPoolExecutor(max_workers=32,
                                    thread_name_prefix="probe")
FETCH_EXECUTOR = ThreadPoolExecutor(max_workers=2,
                                    thread_name_prefix="fetch")


def log(*a):
    msg = time.strftime("[%H:%M:%S]") + " " + " ".join(str(x) for x in a)
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as f:
            f.write(msg + "\n")
    except Exception:
        pass
    try:
        if CONSOLE_ON and sys.stdout is not None:
            print(msg, flush=True)
    except Exception:
        pass


def load_pool():
    try:
        with open(POOL_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        for p, ms in data.items():
            if isinstance(p, str) and ":" in p:
                POOL[p] = float(ms)
        log("загружен сохранённый пул:", len(POOL))
    except Exception:
        pass


def save_pool():
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        tmp = POOL_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(POOL, f)
        os.replace(tmp, POOL_FILE)
    except Exception:
        pass


def rotate_log():
    try:
        if os.path.getsize(LOG_PATH) > 5 * 1024 * 1024:
            os.replace(LOG_PATH, LOG_PATH + ".1")
    except Exception:
        pass


# ---------------------------------------------------------------- проверки

def _probe_blocking(p, timeout=PROBE_TIMEOUT):
    """CONNECT + TLS-хендшейк с ПРОВЕРКОЙ сертификата.

    Возвращает задержку в мс, None (прокси не работает) или -1, если прокси
    подменяет сертификат (корпоративный SSL-инспектор вроде Zscaler).
    """
    t0 = time.time()
    host, port = p.rsplit(":", 1)
    s = None
    try:
        s = socket.create_connection((host, int(port)), timeout)
        s.settimeout(timeout)
        s.sendall(CONNECT_REQ)
        buf = b""
        while b"\r\n\r\n" not in buf:
            c = s.recv(1)
            if not c:
                return None
            buf += c
            if len(buf) > 512:
                return None
        if b" 200" not in buf.split(b"\r\n")[0]:
            return None
        ctx = ssl.create_default_context()
        t = ctx.wrap_socket(s, server_hostname=TARGET_SNI)
        s = None
        t.close()
        return int((time.time() - t0) * 1000)
    except ssl.SSLCertVerificationError:
        return -1
    except Exception:
        return None
    finally:
        if s is not None:
            try:
                s.close()
            except Exception:
                pass


async def probe(p):
    loop = asyncio.get_running_loop()
    try:
        return await asyncio.wait_for(
            loop.run_in_executor(PROBE_EXECUTOR, _probe_blocking, p,
                                 PROBE_TIMEOUT),
            PROBE_TIMEOUT + 2,
        )
    except Exception:
        return None


async def probe_many(cands, sem_limit=32):
    sem = asyncio.Semaphore(sem_limit)
    out = {}
    mitm = []

    async def one(p):
        async with sem:
            ms = await probe(p)
            if ms is not None and ms >= 0:
                out[p] = ms
            elif ms == -1:
                mitm.append(p)

    await asyncio.gather(*[one(p) for p in cands])
    if mitm:
        log("отсеяно прокси с подменой сертификата:", len(mitm))
    return out


# ---------------------------------------------------------------- пул

async def http_get(url, timeout=20):
    def _f():
        req = urllib.request.Request(url, headers={"User-Agent": "curl/8"})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.read().decode("utf-8", "replace")

    return await asyncio.get_running_loop().run_in_executor(FETCH_EXECUTOR, _f)


def parse_list(text):
    out = []
    for line in text.splitlines():
        line = line.strip().replace("http://", "").replace("https://", "")
        parts = line.split(":")
        if len(parts) == 2 and parts[1].isdigit() and parts[0].count(".") == 3:
            out.append(line)
    return out


async def refresh_candidates():
    global LISTS_TS, CANDIDATES
    text = ""
    for u in LISTS:
        try:
            text += await http_get(u) + "\n"
        except Exception as e:
            log("не смог скачать список:", type(e).__name__)

    cands = list(dict.fromkeys(parse_list(text)))
    random.shuffle(cands)
    now = time.time()

    # Бесплатные прокси оживают и умирают, поэтому старые отметки
    # «уже проверяли» забываем. Иначе через несколько обновлений все
    # адреса считаются проверенными и пул перестаёт пополняться.
    for p, ts in list(SEEN.items()):
        if now - ts > SEEN_TTL:
            del SEEN[p]

    def fresh():
        return [p for p in cands
                if p not in POOL and p not in SEEN
                and BAD_UNTIL.get(p, 0) < now]

    CANDIDATES = fresh()
    if not CANDIDATES and cands:
        # Все адреса недавно выдавали — перепроверяем по кругу.
        SEEN.clear()
        CANDIDATES = fresh()

    LISTS_TS = now
    log("кандидатов из списков:", len(CANDIDATES))


async def take_candidates(n):
    global CANDIDATES
    # Не дёргаем списки чаще, чем раз в минуту, даже если очередь пуста.
    if not CANDIDATES and time.time() - LISTS_TS > REFRESH_MIN:
        await refresh_candidates()
    got = CANDIDATES[:n]
    del CANDIDATES[:n]
    now = time.time()
    for p in got:
        SEEN[p] = now
    return got


def add_to_pool(found):
    """Добавляет лучшие найденные прокси, не раздувая пул выше TARGET_POOL."""
    for p, ms in sorted(found.items(), key=lambda x: x[1]):
        if len(POOL) >= TARGET_POOL:
            break
        POOL[p] = ms
        BAD_UNTIL.pop(p, None)


async def keeper():
    global STICKY
    while True:
        try:
            rotate_log()
            now = time.time()
            for p, until in list(BAD_UNTIL.items()):
                if until < now:
                    del BAD_UNTIL[p]
            async with POOL_LOCK:
                current = list(POOL)

            if current:
                good = await probe_many(current, sem_limit=24)
                async with POOL_LOCK:
                    for p in current:
                        if p in good:
                            POOL[p] = good[p]
                        else:
                            POOL.pop(p, None)
                            BAD_UNTIL[p] = time.time() + BAD_COOLDOWN

            if len(POOL) < 3:
                seed_good = await probe_many(SEEDS, sem_limit=8)
                async with POOL_LOCK:
                    add_to_pool(seed_good)

            need = TARGET_POOL - len(POOL)
            if need > 0:
                batch = await take_candidates(max(need * 30, 120))
                found = await probe_many(batch, sem_limit=32)
                async with POOL_LOCK:
                    add_to_pool(found)

            async with POOL_LOCK:
                if STICKY not in POOL:
                    STICKY = min(POOL, key=POOL.get) if POOL else None
                alive = len(POOL)
                best = min(POOL.values()) if POOL else 0
            save_pool()
            log("пул: живых %d (лучший %d мс)" % (alive, best))
        except Exception as e:
            log("keeper error:", type(e).__name__, e)
        await asyncio.sleep(KEEPALIVE_EVERY)


async def bootstrap():
    """Заполняем пул ДО начала приёма соединений.

    Важно: в пул попадают только прокси, прошедшие проверку сертификата,
    поэтому игра никогда не получит подменённый (Zscaler) сертификат.
    """
    global STICKY
    t0 = time.time()
    async with POOL_LOCK:
        current = list(POOL)

    if current:
        good = await probe_many(current, sem_limit=32)
        async with POOL_LOCK:
            for p in current:
                if p in good:
                    POOL[p] = good[p]
                else:
                    POOL.pop(p, None)
                    BAD_UNTIL[p] = time.time() + BAD_COOLDOWN

    if len(POOL) < 4:
        seed_good = await probe_many(SEEDS, sem_limit=8)
        async with POOL_LOCK:
            add_to_pool(seed_good)

    if len(POOL) < 4:
        batch = await take_candidates(128)
        found = await probe_many(batch, sem_limit=48)
        async with POOL_LOCK:
            add_to_pool(found)

    async with POOL_LOCK:
        if STICKY not in POOL:
            STICKY = min(POOL, key=POOL.get) if POOL else None
        alive = len(POOL)
        best = min(POOL.values()) if POOL else 0

    save_pool()
    log("старт: пул готов за %.1f c, живых %d (лучший %d мс)"
        % (time.time() - t0, alive, best))


async def pick_candidates():
    now = time.time()
    async with POOL_LOCK:
        pool_items = [(p, ms) for p, ms in POOL.items()
                      if BAD_UNTIL.get(p, 0) < now]
        sticky = STICKY
    pool_items.sort(key=lambda x: x[1])

    out = []
    if sticky:
        for p, _ in pool_items:
            if p == sticky:
                out.append(p)
                break
    for p, _ in pool_items:
        if p not in out:
            out.append(p)
    return out[:MAX_CANDIDATES]


EMERGENCY_LOCK = asyncio.Lock()


async def emergency_fill():
    """Пул опустел — срочно проверяем сиды и пачку кандидатов."""
    async with EMERGENCY_LOCK:
        async with POOL_LOCK:
            if POOL:
                return
        log("пул пуст — аварийное заполнение")
        found = await probe_many(list(SEEDS), sem_limit=8)
        if len(found) < 2:
            cands = await take_candidates(96)
            found.update(await probe_many(cands, sem_limit=48))
        async with POOL_LOCK:
            add_to_pool(found)
            alive = len(POOL)
        save_pool()
        log("аварийное заполнение: живых", alive)


# ---------------------------------------------------------------- соединения

def set_keepalive(writer):
    try:
        sock = writer.get_extra_info("socket")
        if sock is not None:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            if hasattr(socket, "TCP_KEEPIDLE"):
                sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPIDLE, 30)
                sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPINTVL, 10)
                sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPCNT, 3)
    except Exception:
        pass


async def open_tcp(host, port, timeout=CONNECT_TIMEOUT):
    """TCP-коннект без getaddrinfo/executor — только неблокирующий sock_connect."""
    loop = asyncio.get_running_loop()
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setblocking(False)
    try:
        await asyncio.wait_for(loop.sock_connect(sock, (host, int(port))),
                               timeout)
    except BaseException:
        try:
            sock.close()
        except Exception:
            pass
        raise
    return await asyncio.open_connection(sock=sock)


async def try_proxy(p, timeout=CONNECT_TIMEOUT):
    host, port = p.rsplit(":", 1)
    w = None
    try:
        r, w = await open_tcp(host, port, timeout)
        w.write(CONNECT_REQ)
        await w.drain()
        line = await asyncio.wait_for(r.readline(), timeout)
        if b" 200" not in line:
            w.close()
            return None
        while True:
            h = await asyncio.wait_for(r.readline(), timeout)
            if h in (b"\r\n", b"\n", b""):
                break
        set_keepalive(w)
        return r, w
    except asyncio.CancelledError:
        if w is not None:
            try:
                w.close()
            except Exception:
                pass
        raise
    except Exception:
        if w is not None:
            try:
                w.close()
            except Exception:
                pass
        return None


async def _race(cands):
    """Гонка прокси: кто первый ответил 200 — того и тапки."""
    task_map = {asyncio.create_task(try_proxy(p)): p for p in cands}
    pending = set(task_map)
    winner = None
    while pending and winner is None:
        done, pending = await asyncio.wait(
            pending, return_when=asyncio.FIRST_COMPLETED
        )
        for t in done:
            try:
                res = t.result()
            except Exception:
                res = None
            if res:
                winner = (task_map[t], res)
                break
    for t in pending:
        t.cancel()
    if pending:
        await asyncio.gather(*pending, return_exceptions=True)
    return winner


async def get_upstream():
    global STICKY
    cands = await pick_candidates()
    if not cands:
        await emergency_fill()
        cands = await pick_candidates()
    if not cands:
        log("гонка: кандидатов 0")
        return None, None, None

    winner = None

    # 1. Сначала пробуем «залипший» прокси ОДИН. Это важно: пока он жив,
    #    внешний IP не меняется, и backend не перерегистрирует reservation.
    if STICKY_FIRST and STICKY in cands:
        res = await try_proxy(STICKY, timeout=STICKY_TIMEOUT)
        if res:
            winner = (STICKY, res)
        else:
            log("залипший прокси не ответил, переключаюсь:", STICKY)
            async with POOL_LOCK:
                BAD_UNTIL[STICKY] = time.time() + BAD_COOLDOWN
                POOL.pop(STICKY, None)
            cands = [p for p in cands if p != STICKY]

    # 2. Если залипший не сработал — гонка остальных.
    if winner is None and cands:
        log("гонка: кандидатов", len(cands))
        winner = await _race(cands)

    if winner:
        p, (r, w) = winner
        set_keepalive(w)
        async with POOL_LOCK:
            STICKY = p
        log("туннель через", p)
        return r, w, p

    async with POOL_LOCK:
        for p in cands:
            BAD_UNTIL[p] = time.time() + BAD_COOLDOWN
            POOL.pop(p, None)
    return None, None, None


async def pump(r, w):
    try:
        while True:
            data = await r.read(65536)
            if not data:
                break
            w.write(data)
            await w.drain()
    except Exception:
        pass
    finally:
        try:
            w.close()
        except Exception:
            pass


async def relay(cr, cw, ur, uw):
    t1 = asyncio.create_task(pump(cr, uw))
    t2 = asyncio.create_task(pump(ur, cw))
    _done, pending = await asyncio.wait(
        {t1, t2}, return_when=asyncio.FIRST_COMPLETED
    )
    for t in pending:
        t.cancel()
    for s in (cw, uw):
        try:
            s.close()
        except Exception:
            pass
    if pending:
        await asyncio.gather(*pending, return_exceptions=True)


async def handle(cr, cw):
    t0 = time.time()
    log("входящее соединение")
    try:
        for attempt in range(ATTEMPTS):
            ur, uw, used = await get_upstream()
            if ur is not None:
                await relay(cr, cw, ur, uw)
                log("соединение закрыто (%s, %.1f c)" % (used or "?",
                                                          time.time() - t0))
                return
            log("попытка %d: туннеля нет (%.1f c)" % (attempt + 1,
                                                      time.time() - t0))
            if attempt < ATTEMPTS - 1:
                await asyncio.sleep(1.0)
        log("нет доступного туннеля — рву соединение")
        cw.close()
    except Exception as e:
        log("handle error:", type(e).__name__, e)
        try:
            cw.close()
        except Exception:
            pass


async def main():
    os.makedirs(STATE_DIR, exist_ok=True)
    rotate_log()
    load_pool()

    def exc_handler(loop, context):
        log("loop error:", context.get("message"),
            repr(context.get("exception")))

    asyncio.get_running_loop().set_exception_handler(exc_handler)

    # Сначала занимаем порт (клиенты встают в очередь), но принимаем
    # соединения только после того, как пул проверен и в нём нет MITM.
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((LISTEN_HOST, LISTEN_PORT))
    sock.listen(128)
    sock.setblocking(False)
    log("v%s: порт %d занят, проверяю пул..." % (VERSION, LISTEN_PORT))

    await bootstrap()

    srv = await asyncio.start_server(handle, sock=sock)
    log("v%s: слушаю %s:%d -> %s:%d (SNI %s)"
        % (VERSION, LISTEN_HOST, LISTEN_PORT, TARGET_IP, TARGET_PORT,
           TARGET_SNI))
    asyncio.create_task(keeper())
    async with srv:
        await srv.serve_forever()


if __name__ == "__main__":
    if os.name == "nt":
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
