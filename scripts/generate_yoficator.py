#!/usr/bin/env python3
"""Generate Nabira's conservative е→ё dictionary from OpenCorpora data.

The runtime application does not depend on Python or pymorphy3.  This script is
only needed when refreshing the bundled dictionary.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = (
    REPO_ROOT
    / "macos"
    / "Sources"
    / "Nabira"
    / "Resources"
    / "yoficator.tsv"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    try:
        import pymorphy3
    except ImportError as error:
        raise SystemExit(
            "Install build-time dependencies first: "
            "python3 -m pip install pymorphy3 pymorphy3-dicts-ru"
        ) from error

    morph = pymorphy3.MorphAnalyzer(lang="ru")
    words = morph.dictionary.words
    variants: dict[str, set[str]] = defaultdict(set)

    for raw_word in words.iterkeys():
        word = raw_word.lower()
        if "ё" in word:
            variants[word.replace("ё", "е")].add(word)

    replacements: dict[str, str] = {}
    skipped_existing = 0
    skipped_multiple = 0
    for source, targets in variants.items():
        # Several ё placements for one spelling cannot be resolved without context.
        if len(targets) != 1:
            skipped_multiple += 1
            continue
        target = next(iter(targets))
        # If the е spelling is itself a dictionary word (все/всё, осел/осёл),
        # changing it without context can alter meaning, so keep it untouched.
        if words.get(source):
            skipped_existing += 1
            continue
        replacements[source] = target

    meta = morph.dictionary.meta
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8", newline="\n") as output:
        output.write("# Nabira yoficator dictionary\n")
        output.write("# Derived from OpenCorpora via pymorphy3-dicts-ru\n")
        output.write(f"# source_revision={meta.get('source_revision', 'unknown')}\n")
        output.write(f"# corpus_revision={meta.get('corpus_revision', 'unknown')}\n")
        output.write("# License: CC BY-SA 3.0\n")
        for source, target in sorted(replacements.items()):
            output.write(f"{source}\t{target}\n")

    print(
        f"wrote {len(replacements)} replacements to {args.output} "
        f"(skipped {skipped_existing} existing е-forms and "
        f"{skipped_multiple} multi-variant forms)"
    )


if __name__ == "__main__":
    main()
