#!/usr/bin/env python3
"""Анонс нового релиза Nabira в Telegram-канал владельца.

Вызывается из GitHub Actions при публикации СТАБИЛЬНОГО релиза (беты пропускаем — см.
workflow). Постит заголовок + заметки релиза + ссылку через настроенного бота
(секрет TELEGRAM_BOT_TOKEN). Канал задаётся секретом TELEGRAM_CHANNEL.
Бот должен быть АДМИНОМ канала с правом публикации.
"""
import os
import urllib.parse
import urllib.request

TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
CHANNEL = os.environ.get("TELEGRAM_CHANNEL", "")
NAME = os.environ.get("RELEASE_NAME", "").strip()
TAG = os.environ.get("RELEASE_TAG", "").strip()
BODY = os.environ.get("RELEASE_BODY", "").strip()
URL = os.environ.get("RELEASE_URL", "").strip()

TG_LIMIT = 4096


def main() -> int:
    if not TOKEN or not CHANNEL:
        print("TELEGRAM_BOT_TOKEN or TELEGRAM_CHANNEL not set — skipping")
        return 0
    title = NAME or TAG or "Nabira"
    header = f"🎉 {title}\n\n"
    footer = f"\n\n⬇️ {URL}" if URL else ""
    room = TG_LIMIT - len(header) - len(footer) - 16
    body = BODY
    if len(body) > room:
        body = body[: max(0, room - 1)].rstrip() + "…"
    text = header + body + footer

    data = urllib.parse.urlencode({
        "chat_id": CHANNEL,
        "text": text,
        "disable_web_page_preview": "false",
    }).encode()
    req = urllib.request.Request(f"https://api.telegram.org/bot{TOKEN}/sendMessage", data=data)
    try:
        with urllib.request.urlopen(req) as r:
            print("telegram announce sent:", r.status)
        return 0
    except Exception as e:  # noqa: BLE001
        print("telegram announce failed:", e)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
