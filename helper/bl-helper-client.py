#!/usr/bin/env python3
"""bl-helper-client — talk to the bl-helper daemon over its Unix socket.

Usage:
  ./bl-helper-client.py detect
  ./bl-helper-client.py unlock /dev/disk4s1
  ./bl-helper-client.py mount  /dev/disk4s1 [--rw]
  ./bl-helper-client.py eject  /tmp/bl/mnt
"""
import getpass
import json
import re
import socket
import sys

SOCK = "/usr/local/var/run/bl-helper.sock"
RECOVERY = re.compile(r"^\d{6}(-\d{6}){7}$")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    op = sys.argv[1]
    req = {"op": op}
    secret = b""

    if op in ("unlock", "mount"):
        req["device"] = sys.argv[2]
        if op == "mount" and "--rw" in sys.argv[3:]:
            req["rw"] = True
        pw = getpass.getpass("BitLocker password (or 48-digit recovery key): ")
        secret = pw.encode("utf-8")
        req["secretType"] = "recovery" if RECOVERY.match(pw) else "password"
        req["secretLen"] = len(secret)
    elif op == "probe":
        req["device"] = sys.argv[2]
    elif op == "eject":
        req["mount"] = sys.argv[2]
    elif op == "cleanup":
        req["image"] = sys.argv[2]

    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.connect(SOCK)
    except OSError as e:
        print(f"cannot connect to helper at {SOCK}: {e}", file=sys.stderr)
        print("Is the helper installed and loaded? See helper/install-helper.sh",
              file=sys.stderr)
        return 1
    s.sendall((json.dumps(req) + "\n").encode("utf-8"))
    if secret:
        s.sendall(secret)
    f = s.makefile("rb")
    rc = 0
    for line in f:
        text = line.decode("utf-8", "replace").rstrip()
        print(text)
        if '"error"' in text:
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
