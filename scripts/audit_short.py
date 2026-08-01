# Данные корпуса (top-N частот) не в репо. Перед запуском:
#   B=https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018
#   curl -sL "$B/en/en_50k.txt" -o en_raw.txt
#   curl -sL "$B/ru/ru_full.txt" -o ru_raw.txt
# Держать в синхроне со списками в macos/Sources/RuSwitcher/ShortWords.swift
#!/usr/bin/env python3
"""Collision audit for the short-word (2-letter) frequency signal.

Rule in the app: for a 2-letter typed word W (lang=cur), convert to its image C
(lang=oth) ONLY IF  C in SHORT[oth]  AND  W not in SHORT[cur].
So the ONLY unsafe case is: a REAL common word W the user types in cur, where
W is NOT in SHORT[cur] but image(W) IS in SHORT[oth] -> wrongful convert.

This audits my curated SHORT lists against the FULL set of real common 2-letter
words (top-N by frequency), flagging any such false-convert risk.
"""
import re

# QWERTY(lower) -> ЙЦУКЕН. Letters only; punct-mapped RU letters (х ъ ж э б ю ё)
# come from QWERTY punctuation keys, so a letters-only EN word never maps to them.
EN2RU = dict(zip("qwertyuiopasdfghjklzxcvbnm",
                 "йцукенгшщзфывапролдячсмить"))
RU2EN = {v: k for k, v in EN2RU.items()}

def img_en_to_ru(w):
    return "".join(EN2RU.get(c, "?") for c in w)
def img_ru_to_en(w):
    return "".join(RU2EN.get(c, "?") for c in w)

# ---- curated lists (candidates to validate) ----
SHORT_RU = set("не ты на он мы вы да но за бы же из ну по то от их ее её со ли ни об ей во им ко те та уж ок эй".split())
SHORT_EN = set("to it of is in we me he my on do no be so go if up at as an us or by am ok hi oh ah um mr ya".split())

# ---- real common 2-letter words (top-N by frequency) as "what users type" ----
def top2(path, rx, n=80):
    out, seen = [], set()
    for line in open(path, encoding="utf-8"):
        p = line.split()
        if p:
            w = p[0].lower()
            if rx.match(w) and w not in seen:
                seen.add(w); out.append(w)
        if len(out) >= n: break
    return out

REAL_RU = top2("ru_raw.txt", re.compile(r"^[а-яё]{2}$"))
REAL_EN = top2("en_raw.txt", re.compile(r"^[a-z]{2}$"))
SET_RU, SET_EN = set(REAL_RU), set(REAL_EN)

print("=== RISK: typing a real RU word gets wrongly converted to EN ===")
risk = 0
for w in REAL_RU:
    c = img_ru_to_en(w)
    if "?" in c:  # image has punctuation -> typed-as-letters can't reach convert
        continue
    if c in SHORT_EN and w not in SHORT_RU:
        print(f"  RU «{w}» -> EN '{c}' (in EN list, «{w}» NOT in RU list) — WOULD CONVERT")
        risk += 1
print(f"  risks: {risk}")

print("=== RISK: typing a real EN word gets wrongly converted to RU ===")
risk2 = 0
for w in REAL_EN:
    c = img_en_to_ru(w)
    if c in SHORT_RU and w not in SHORT_EN:
        print(f"  EN '{w}' -> RU «{c}» (in RU list, '{w}' NOT in EN list) — WOULD CONVERT")
        risk2 += 1
print(f"  risks: {risk2}")

print("=== ambiguous pairs (both in lists) — safely declined by symmetric guard ===")
for w in SHORT_RU:
    c = img_ru_to_en(w)
    if c in SHORT_EN:
        print(f"  RU «{w}» <-> EN '{c}' (both listed -> .keep, never auto-converted)")

# sanity: does the #22 word convert?
print("=== sanity: #22 «Не» ===")
w = "yt"  # typed in EN layout, meaning не
print(f"  typed EN 'yt' -> RU image «{img_en_to_ru('yt')}» in RU list? {img_en_to_ru('yt') in SHORT_RU}")
