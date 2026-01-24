#!/usr/bin/env python3.15
import os
import json
import socket
import shutil
import subprocess
from email import message_from_string
from email.header import decode_header, make_header
from pathlib import Path


# Paths and icons
ACCOUNTS_CONF = Path.home() / ".config/aerc/accounts.conf"
STATE_FILE = Path(f"/tmp/mail-status-{os.getenv('USER', 'user')}.state")
ICON_OPEN = "\U000f06ee "   # Open envelope (no unread)
ICON_CLOSED = "\U000f0d8d "  # Closed envelope (has unread)


def ensure_dbus():
    if "DBUS_SESSION_BUS_ADDRESS" in os.environ:
        return
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    if runtime_dir:
        os.environ["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path={runtime_dir}/bus"


def send_notification(summary: str, body: str) -> None:
    if not shutil.which("notify-send"):
        return
    ensure_dbus()
    try:
        subprocess.run(
            [
                "notify-send",
                "-u",
                "normal",
                "-i",
                "mail-unread",
                "-a",
                "mail-notification",
                summary,
                body,
            ],
            timeout=3,
            check=False,
        )
    except Exception:
        pass


def load_previous_state() -> dict:
    state = {}
    if STATE_FILE.exists():
        for line in STATE_FILE.read_text().splitlines():
            if "=" in line:
                account, uids = line.split("=", 1)
                state[account] = set(filter(None, uids.split(",")))
    return state


def save_state(current_uids_map: dict) -> None:
    lines = []
    for account, uids in current_uids_map.items():
        lines.append(f"{account}={','.join(uids)}")
    STATE_FILE.write_text("\n".join(lines))


def parse_accounts_conf():
    accounts = {}
    if not ACCOUNTS_CONF.exists():
        return accounts

    current = None
    with ACCOUNTS_CONF.open() as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            if line.startswith("[") and line.endswith("]"):
                current = line[1:-1]
                accounts[current] = {"source": "", "source_cred_cmd": "", "from": ""}
                continue
            if current is None:
                continue
            if "=" not in line:
                continue
            key, value = line.split("=", 1)
            if key in ("source", "source-cred-cmd", "from"):
                accounts[current][key.replace("-", "_")] = value.strip()
    return accounts


def run_cred_cmd(cmd: str) -> str:
    if not cmd:
        return ""
    expanded = os.path.expanduser(cmd)
    try:
        result = subprocess.run(
            expanded,
            shell=True,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=5,
        )
        return result.stdout.strip()
    except Exception:
        return ""


def parse_source_url(source: str):
    if not source.startswith("imaps://"):
        return None
    stripped = source[len("imaps://") :]
    # Format: user@domain@server:port
    if "@" not in stripped:
        return None
    user_part = stripped.split("@", 1)[0]
    rest = stripped.split("@", 1)[1]
    if "@" not in rest:
        return None
    domain = rest.split("@", 1)[0]
    server_port = rest.split("@", 1)[1]
    server, sep, port = server_port.partition(":")
    if not port:
        port = "993"
    return f"{user_part}@{domain}", server, int(port)


def imap_connect(server: str, port: int, user: str, password: str):
    import imaplib

    socket.setdefaulttimeout(10)
    client = imaplib.IMAP4_SSL(server, port)
    client.login(user, password)
    return client


def fetch_unseen_uids(client) -> list:
    typ, _ = client.select("INBOX")
    if typ != "OK":
        return []
    typ, data = client.uid("SEARCH", None, "UNSEEN")
    if typ != "OK" or not data:
        return []
    raw = data[0].decode().strip()
    return [uid for uid in raw.split() if uid]


def fetch_headers(client, uid: str) -> str:
    # Include extra headers useful for forwarded messages
    typ, data = client.uid(
        "FETCH",
        uid,
        "(BODY.PEEK[HEADER.FIELDS (SUBJECT RESENT-SUBJECT THREAD-TOPIC FROM SENDER REPLY-TO RESENT-FROM X-ORIGINAL-FROM X-FORWARDED-FOR TO DELIVERED-TO DATE)])",
    )
    if typ != "OK" or not data:
        return ""
    # data can contain multiple parts; find the bytes payload
    for part in data:
        if isinstance(part, tuple) and len(part) > 1 and isinstance(part[1], (bytes, bytearray)):
            return part[1].decode(errors="replace")
    return ""


def parse_email_info(headers: str):
    msg = message_from_string(headers)

    def decode_val(val: str) -> str:
        if not val:
            return ""
        try:
            return str(make_header(decode_header(val)))
        except Exception:
            return val

    def first_nonempty(keys):
        for key in keys:
            for val in msg.get_all(key, []) or []:
                decoded = decode_val(val).replace("\n", " ").strip()
                if decoded:
                    return decoded
        return ""

    subject = first_nonempty(["Subject", "Resent-Subject", "Thread-Topic"])
    sender = first_nonempty([
        "Reply-To",
        "X-Original-From",
        "X-Forwarded-For",
        "Resent-From",
        "From",
        "Sender",
    ])
    recipient = first_nonempty(["To", "Delivered-To"])
    date = first_nonempty(["Date"])
    return subject, sender, recipient, date


def main():
    import shutil

    previous = load_previous_state()
    accounts = parse_accounts_conf()

    total_unread = 0
    accounts_with_unread = []
    current_uids_map = {}

    for account_name, cfg in accounts.items():
        source = cfg.get("source", "")
        cred_cmd = cfg.get("source_cred_cmd", "")
        from_addr = cfg.get("from", account_name)

        parsed = parse_source_url(source)
        if not parsed:
            current_uids_map[account_name] = []
            continue
        imap_user, server, port = parsed

        password = run_cred_cmd(cred_cmd)
        if not password:
            current_uids_map[account_name] = []
            continue

        try:
            client = imap_connect(server, port, imap_user, password)
        except Exception:
            current_uids_map[account_name] = []
            continue

        try:
            uids = fetch_unseen_uids(client)
        except Exception:
            uids = []
        current_uids_map[account_name] = uids

        unread = len(uids)
        if unread > 0:
            accounts_with_unread.append(f"{from_addr} ({unread})")
            total_unread += unread

        prev_uids = previous.get(account_name, set())
        current_set = set(uids)
        new_uids = current_set if not prev_uids else current_set - prev_uids

        if new_uids:
            for uid in sorted(new_uids):
                headers = ""
                try:
                    headers = fetch_headers(client, uid)
                except Exception:
                    headers = ""

                subject, sender, recipient, date = parse_email_info(headers)
                subject = subject or "No Subject"
                sender = sender or "Unknown Sender"
                recipient = recipient or from_addr

                body_lines = [f"From: {sender}"]
                if date:
                    body_lines.append(f"Date: {date}")
                body_lines.append(f"To: {recipient}")
                body = "\n".join(body_lines)

                send_notification(subject, body)

        try:
            client.logout()
        except Exception:
            pass

    save_state({k: v for k, v in current_uids_map.items()})

    if total_unread > 0:
        tooltip = "\n".join(accounts_with_unread)
        payload = {
            "text": f"{ICON_CLOSED} {total_unread} ",
            "tooltip": tooltip,
            "class": "mail-status",
        }
    else:
        payload = {
            "text": f"{ICON_OPEN} ",
            "tooltip": "No unread emails",
            "class": "mail-status",
        }

    print(json.dumps(payload))


if __name__ == "__main__":
    main()
