#!/usr/bin/env python3
"""Sign and verify backward-compatible Nabira update feeds.

Only Python's standard library and the system OpenSSL executable are required. The private key is
read from a file outside Git; it is never printed or copied into the resulting feed.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.parse import urlparse


ALGORITHM = "ecdsa-p256-sha256"
PLATFORM_PATHS = {
    "macos": {
        "stable": "/downloads/Nabira-macOS.dmg",
        "beta": "/downloads/beta/Nabira-macOS.dmg",
    },
    "windows": {
        "stable": "/downloads/Nabira-Windows-x64.exe",
        "beta": "/downloads/beta/Nabira-Windows-x64.exe",
    },
}
VERSION_PATTERNS = {
    "macos": re.compile(r"^[0-9]+(?:\.[0-9]+){1,3}[a-z]?$"),
    "windows": re.compile(r"^[0-9]+(?:\.[0-9]+){1,3}$"),
}
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")


def fail(message: str) -> None:
    raise ValueError(message)


def run_openssl(arguments: list[str], *, input_data: bytes | None = None) -> bytes:
    result = subprocess.run(
        ["openssl", *arguments], input=input_data, capture_output=True, check=False
    )
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"OpenSSL failed: {detail}")
    return result.stdout


def strict_base64(value: str, field: str) -> bytes:
    try:
        return base64.b64decode(value, validate=True)
    except (ValueError, base64.binascii.Error) as error:
        raise ValueError(f"invalid {field}") from error


def validate_payload(
    payload: object, expected_platform: str, expected_channel: str = "stable"
) -> dict[str, object]:
    if not isinstance(payload, dict):
        fail("signed payload must be a JSON object")
    expected_keys = {"schema", "platform", "version", "url", "notes", "sha256"}
    if set(payload) != expected_keys:
        fail("signed payload contains missing or unknown fields")
    if payload["schema"] != 1 or payload["platform"] != expected_platform:
        fail("signed payload schema or platform mismatch")

    version = payload["version"]
    url = payload["url"]
    notes = payload["notes"]
    sha256 = payload["sha256"]
    if not isinstance(version, str) or not VERSION_PATTERNS[expected_platform].fullmatch(version):
        fail("invalid update version")
    if not isinstance(notes, str) or len(notes) > 20_000:
        fail("invalid update notes")
    if not isinstance(sha256, str) or not SHA256_PATTERN.fullmatch(sha256):
        fail("invalid update SHA-256")
    if not isinstance(url, str):
        fail("invalid update URL")
    parsed = urlparse(url)
    if (
        parsed.scheme != "https"
        or parsed.hostname != "nabira.site"
        or parsed.username is not None
        or parsed.password is not None
        or parsed.port is not None
        or parsed.path != PLATFORM_PATHS[expected_platform][expected_channel]
        or parsed.fragment
    ):
        fail("update URL must use the official Nabira download endpoint")
    return payload


def compact_payload(feed: dict[str, object], platform: str, channel: str = "stable") -> bytes:
    payload = {
        "schema": 1,
        "platform": platform,
        "version": feed.get("version"),
        "url": feed.get("url"),
        "notes": feed.get("notes", ""),
        "sha256": feed.get("sha256"),
    }
    validate_payload(payload, platform, channel)
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def public_der(public_key: Path) -> bytes:
    return run_openssl(["pkey", "-pubin", "-in", str(public_key), "-outform", "DER"])


def key_id(public_key: Path) -> str:
    return hashlib.sha256(public_der(public_key)).hexdigest()[:16]


def verify_feed(
    feed_path: Path, platform: str, public_key: Path, channel: str = "stable"
) -> dict[str, object]:
    feed = json.loads(feed_path.read_text(encoding="utf-8"))
    if not isinstance(feed, dict):
        fail("feed must be a JSON object")
    if feed.get("signature_algorithm") != ALGORITHM:
        fail("unsupported signature algorithm")
    if feed.get("key_id") != key_id(public_key):
        fail("update signing key id mismatch")
    signed_payload = feed.get("signed_payload")
    signature = feed.get("signature")
    if not isinstance(signed_payload, str) or not isinstance(signature, str):
        fail("signed feed fields are missing")
    payload_bytes = strict_base64(signed_payload, "signed_payload")
    signature_bytes = strict_base64(signature, "signature")
    payload = validate_payload(json.loads(payload_bytes.decode("utf-8")), platform, channel)

    # NamedTemporaryFile stays exclusively open on Windows, so OpenSSL cannot reopen it by path.
    # A private temporary directory lets us close the file before launching the verifier.
    with tempfile.TemporaryDirectory() as directory:
        signature_path = Path(directory) / "signature.der"
        signature_path.write_bytes(signature_bytes)
        result = subprocess.run(
            [
                "openssl",
                "dgst",
                "-sha256",
                "-verify",
                str(public_key),
                "-signature",
                str(signature_path),
            ],
            input=payload_bytes,
            capture_output=True,
            check=False,
        )
    if result.returncode != 0:
        fail("update feed signature verification failed")

    for field in ("version", "url", "notes"):
        if feed.get(field) != payload[field]:
            fail(f"legacy field {field} differs from the signed payload")
    legacy_manual_install = (
        platform == "macos"
        and channel == "stable"
        and feed.get("legacy_manual_install") is True
        and "sha256" not in feed
    )
    if not legacy_manual_install and feed.get("sha256") != payload["sha256"]:
        fail("legacy field sha256 differs from the signed payload")
    return payload


def sign_feed(
    feed_path: Path,
    output_path: Path,
    platform: str,
    private_key: Path,
    channel: str = "stable",
) -> None:
    mode = private_key.stat().st_mode & 0o777
    # Windows does not expose POSIX ownership bits and commonly reports 0666 for a private temp
    # file. The GitHub runner deletes that file in a finally block; enforce 0600 where permissions
    # are meaningful instead of making the Windows release job impossible.
    if os.name != "nt" and mode & 0o077:
        fail("private key permissions must be 0600 or stricter")
    feed = json.loads(feed_path.read_text(encoding="utf-8"))
    if not isinstance(feed, dict):
        fail("feed must be a JSON object")
    payload_bytes = compact_payload(feed, platform, channel)
    signature = run_openssl(
        ["dgst", "-sha256", "-sign", str(private_key)], input_data=payload_bytes
    )

    with tempfile.TemporaryDirectory() as directory:
        public_key = Path(directory) / "public.pem"
        public_key.write_bytes(
            run_openssl(["pkey", "-in", str(private_key), "-pubout"])
        )
        feed.update(
            {
                "signed_payload": base64.b64encode(payload_bytes).decode("ascii"),
                "signature": base64.b64encode(signature).decode("ascii"),
                "signature_algorithm": ALGORITHM,
                "key_id": key_id(public_key),
            }
        )
        # Nabira 3.3.1 still requires Apple Developer ID for in-place installation.
        # The independent release signature was introduced in the next client, so that
        # legacy version must make one manual browser-assisted transition. Omitting only
        # the unsigned legacy hash triggers its existing safe browser fallback. New
        # clients ignore these top-level compatibility fields and use signed_payload.
        if platform == "macos" and channel == "stable":
            feed["legacy_manual_install"] = True
            feed.pop("sha256", None)
        else:
            feed.pop("legacy_manual_install", None)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        temporary = output_path.with_name(f".{output_path.name}.{os.getpid()}.tmp")
        temporary.write_text(
            json.dumps(feed, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        os.replace(temporary, output_path)
        verify_feed(output_path, platform, public_key, channel)


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    subcommands = result.add_subparsers(dest="command", required=True)

    sign = subcommands.add_parser("sign")
    sign.add_argument("--platform", choices=PLATFORM_PATHS, required=True)
    sign.add_argument("--channel", choices=("stable", "beta"), default="stable")
    sign.add_argument("--key", type=Path, required=True)
    sign.add_argument("--feed", type=Path, required=True)
    sign.add_argument("--output", type=Path)

    verify = subcommands.add_parser("verify")
    verify.add_argument("--platform", choices=PLATFORM_PATHS, required=True)
    verify.add_argument("--channel", choices=("stable", "beta"), default="stable")
    verify.add_argument("--public-key", type=Path, required=True)
    verify.add_argument("--feed", type=Path, required=True)
    return result


def main() -> int:
    args = parser().parse_args()
    try:
        if args.command == "sign":
            sign_feed(
                args.feed,
                args.output or args.feed,
                args.platform,
                args.key,
                args.channel,
            )
            print(f"signed {args.platform}/{args.channel} feed: {args.output or args.feed}")
        else:
            payload = verify_feed(args.feed, args.platform, args.public_key, args.channel)
            print(f"verified {args.platform}/{args.channel} feed version {payload['version']}")
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError, UnicodeDecodeError) as error:
        print(f"update feed error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
