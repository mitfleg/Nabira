#!/usr/bin/env python3
"""Разовый пост произвольного текста в Telegram-канал владельца.

Читает файл MESSAGE_FILE и постит его содержимое через настроенного бота
(секрет TELEGRAM_BOT_TOKEN). Канал задаётся секретом TELEGRAM_CHANNEL.
Токен живёт только в секретах GitHub — локально/в переписке не светится.
"""
import os
import urllib.parse
import urllib.request

TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
CHANNEL = os.environ.get("TELEGRAM_CHANNEL", "")
MSG_FILE = os.environ.get("MESSAGE_FILE", "telegram/welcome.md")


def main() -> int:
    if not TOKEN or not CHANNEL:
        print("TELEGRAM_BOT_TOKEN or TELEGRAM_CHANNEL not set — aborting")
        return 1
    try:
        text = open(MSG_FILE, encoding="utf-8").read().strip()
    except OSError as e:
        print("cannot read message file:", e)
        return 1
    if not text:
        print("message file empty — aborting")
        return 1
    data = urllib.parse.urlencode({
        "chat_id": CHANNEL,
        "text": text,
        "disable_web_page_preview": "true",
    }).encode()
    req = urllib.request.Request(f"https://api.telegram.org/bot{TOKEN}/sendMessage", data=data)
    try:
        with urllib.request.urlopen(req) as r:
            print("posted to", CHANNEL, "status", r.status)
        return 0
    except Exception as e:  # noqa: BLE001
        print("post failed:", e)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
