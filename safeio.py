#!/usr/bin/env python3
"""Bounded, symlink-refusing file I/O for the color history.

The state files sit at predictable paths, and a shell that stays up for days
reads them on every change. Anything can be at such a path by the time it is
opened: a symlink aimed at another of the user's files, a FIFO that never
returns and takes the whole shell down with it, or something far larger than a
list of colors has any business being. So every open here refuses on its own
terms instead of trusting the name:

  O_NOFOLLOW   the final component must not be a symlink
  O_NONBLOCK   opening a FIFO cannot park the caller forever
  S_ISREG      whatever was opened must be an ordinary file
  ceiling      and no larger than a real history could plausibly get

O_NOFOLLOW covers the final component only. A symlink in a parent directory is
still followed, which is the same trust already placed in $HOME.

Exit codes: 0 ok, 2 nothing there (a normal first run), 1 refused.
"""

import base64
import binascii
import os
import stat
import sys

CEILING = 4 * 1024 * 1024


def open_regular(path, flags, mode=0o600):
    try:
        fd = os.open(path, flags | os.O_NOFOLLOW | os.O_NONBLOCK, mode)
    except FileNotFoundError:
        raise SystemExit(2)
    except OSError:
        # ELOOP (a symlink), ENXIO (a FIFO with no reader), anything else.
        raise SystemExit(1)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise SystemExit(1)
    except SystemExit:
        os.close(fd)
        raise
    except OSError:
        os.close(fd)
        raise SystemExit(1)
    return fd


def read(path):
    fd = open_regular(path, os.O_RDONLY)
    with os.fdopen(fd, "rb") as handle:
        raw = handle.read(CEILING + 1)
    if len(raw) > CEILING:
        raise SystemExit(1)
    sys.stdout.buffer.write(raw)


def ensure_directory(path):
    directory = os.path.dirname(path)
    if directory:
        try:
            os.makedirs(directory, exist_ok=True)
        except OSError:
            raise SystemExit(1)


def append(path, line):
    ensure_directory(path)
    fd = open_regular(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT)
    with os.fdopen(fd, "wb") as handle:
        handle.write(line.encode("utf-8") + b"\n")


def write(path):
    """Replace path with the content on stdin, atomically and never through a link.

    stdin carries one base64 line rather than raw bytes, so the read ends at the
    newline instead of at EOF. The caller is a long-lived shell whose Process
    keeps the pipe open, and waiting for an EOF that never comes would hang it.

    The decoded content goes to a fresh file in the same directory and is
    renamed over the target, so a symlink planted at the path is replaced rather
    than followed, and a reader never catches a half-written history.
    """
    encoded = sys.stdin.buffer.readline()
    if len(encoded) > CEILING:
        raise SystemExit(1)
    try:
        raw = base64.b64decode(encoded.strip(), validate=True)
    except (ValueError, binascii.Error):
        raise SystemExit(1)
    if len(raw) > CEILING:
        raise SystemExit(1)

    ensure_directory(path)
    directory = os.path.dirname(path) or "."
    tmp = os.path.join(directory, ".%s.tmp.%d" % (os.path.basename(path), os.getpid()))
    try:
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    except OSError:
        raise SystemExit(1)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(raw)
        os.replace(tmp, path)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise SystemExit(1)


def main(argv):
    if len(argv) < 3:
        raise SystemExit(64)
    command, path = argv[1], argv[2]
    if command == "read":
        read(path)
    elif command == "append":
        if len(argv) < 4:
            raise SystemExit(64)
        append(path, argv[3])
    elif command == "write":
        write(path)
    else:
        raise SystemExit(64)


if __name__ == "__main__":
    main(sys.argv)
