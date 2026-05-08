#!/usr/bin/env python3
import os
import fcntl
import json
import shutil
import subprocess
from pathlib import Path


ACCOUNTS_CONF = Path.home() / ".config/aerc/accounts.conf"
STATE_FILE = Path(f"/tmp/mail-status-{os.getenv('USER', 'user')}.state")
LOCK_FILE = Path(f"/tmp/mail-status-{os.getenv('USER', 'user')}.lock")
# Per-account branded icons live in ../icons/ relative to this script.
# Path(__file__).resolve() walks the symlink (~/.config/waybar → ~/.stubbe/...)
# so the resulting absolute path is the dotfiles checkout, not a dangling
# /home path that notify-send can't read.
ICONS_DIR = Path(__file__).resolve().parent.parent / "icons"
ACCOUNT_ICONS = {
    "gmail": ICONS_DIR / "gmail.svg",
    "kontainer": ICONS_DIR / "exchange.svg",
}
DEFAULT_NOTIFICATION_ICON = "mail-unread"
ICON_OPEN = "\U000f06ee "
ICON_CLOSED = "\U000f0d8d "


def ensure_dbus():
    if "DBUS_SESSION_BUS_ADDRESS" in os.environ:
        return
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    if runtime_dir:
        os.environ["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path={runtime_dir}/bus"


def account_icon(account: str) -> str:
    candidate = ACCOUNT_ICONS.get(account)
    if candidate and candidate.exists():
        return str(candidate)
    return DEFAULT_NOTIFICATION_ICON


def send_notification(summary: str, body: str, account: str) -> None:
    """Fire a clickable notification.

    notify-send -w blocks until the user dismisses or actions the
    notification, then prints the action ID. We spawn it detached in a
    subshell that runs `mail-open` when the default action fires (any
    click on the notification body in swaync). The Python script returns
    immediately so waybar's 5s tick isn't blocked by 100s-of-seconds of
    notification dwell time.
    """
    if not shutil.which("notify-send"):
        return
    ensure_dbus()

    notify_cmd = [
        "notify-send",
        "-u", "normal",
        "-w",
        "-A", "default=Open",
        "-a", "mail-notification",
        "-i", account_icon(account),
        "--",
        summary,
        body,
    ]

    # Quote each arg for the inner sh -c. shlex.quote handles spaces and
    # special characters (subjects routinely contain quotes, brackets, $).
    import shlex
    quoted = " ".join(shlex.quote(a) for a in notify_cmd)
    routing = f'[ "$({quoted})" = "default" ] && exec mail-open'

    try:
        subprocess.Popen(
            ["sh", "-c", routing],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except Exception:
        pass


def load_previous_state() -> dict:
    state = {}
    if STATE_FILE.exists():
        for line in STATE_FILE.read_text().splitlines():
            if "=" in line:
                account, ids = line.split("=", 1)
                state[account] = set(filter(None, ids.split("\t")))
    return state


def save_state(current: dict) -> None:
    lines = []
    for account, ids in current.items():
        lines.append(f"{account}={chr(9).join(sorted(ids))}")
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
                accounts[current] = {"source": "", "from": ""}
                continue
            if current is None or "=" not in line:
                continue
            key, value = line.split("=", 1)
            if key in ("source", "from"):
                accounts[current][key] = value.strip()
    return accounts


def notmuch_message_ids(query: str) -> list:
    try:
        result = subprocess.run(
            ["notmuch", "search", "--output=messages", "--", query],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
            text=True,
            timeout=10,
        )
    except Exception:
        return []
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def notmuch_headers(message_id: str):
    try:
        result = subprocess.run(
            [
                "notmuch",
                "show",
                "--format=json",
                "--body=false",
                "--",
                message_id,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
            text=True,
            timeout=10,
        )
        data = json.loads(result.stdout) if result.stdout else []
    except Exception:
        return {}
    # `notmuch show --format=json` returns a nested list of threads.
    # Walk it until we find a dict with "headers".
    stack = [data]
    while stack:
        node = stack.pop()
        if isinstance(node, dict) and "headers" in node:
            return node["headers"]
        if isinstance(node, list):
            stack.extend(node)
    return {}


def main():
    previous = load_previous_state()
    accounts = parse_accounts_conf()

    total_unread = 0
    accounts_with_unread = []
    current_ids_map = {}

    for account_name, cfg in accounts.items():
        if not cfg.get("source", "").startswith("notmuch://"):
            continue

        from_addr = cfg.get("from") or account_name
        query = (
            f"tag:{account_name} and tag:unread "
            f"and folder:{account_name}/INBOX"
        )
        ids = notmuch_message_ids(query)
        current_ids_map[account_name] = set(ids)

        unread = len(ids)
        if unread > 0:
            accounts_with_unread.append(f"{from_addr} ({unread})")
            total_unread += unread

        prev_ids = previous.get(account_name, set())
        # On first run the state file is missing; don't notify for the
        # whole existing inbox.
        new_ids = (
            current_ids_map[account_name] - prev_ids
            if account_name in previous
            else set()
        )

        for mid in sorted(new_ids):
            headers = notmuch_headers(mid)
            subject = headers.get("Subject") or "No Subject"
            sender = headers.get("From") or "Unknown Sender"
            # Keep the body minimal: just the sender. swaync already
            # shows its own arrival timestamp so Date is redundant, and
            # the recipient is always us. Cuts down on noisy headers
            # (e.g. quoted copyright strings inside Date / Reply-To
            # that some senders inject) leaking into the popup.
            send_notification(subject, sender, account_name)

    save_state(current_ids_map)

    if total_unread > 0:
        payload = {
            "text": f"{ICON_CLOSED} {total_unread} ",
            "tooltip": "\n".join(accounts_with_unread),
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
    with LOCK_FILE.open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        main()
