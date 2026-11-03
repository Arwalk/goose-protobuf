#!/usr/bin/env python3
"""Spike gpb-wof.3: drive the echo program the way conformance_test_runner
drives a testee: write one length-prefixed frame, read the reply, then write
the next, never closing stdin between frames.

Usage: python3 tests/spikes/stdio/driver.py <command...>
  e.g. driver.py goose tests/spikes/stdio/echo.goose --debug
       driver.py ./echo
Exits 0 if every check passes. Each read has a timeout, so a testee that
waits for EOF fails instead of hanging.
"""
import os
import select
import struct
import subprocess
import sys
import time

TIMEOUT = 30.0  # seconds; generous, `goose run` compiles first
failures = 0


def check(name, ok, detail=""):
    global failures
    if not ok:
        failures += 1
    print(("PASS " if ok else "FAIL ") + name + (" " + detail if detail else ""))


def start(cmd):
    return subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, bufsize=0)


def read_exact(fd, n):
    """n bytes from fd, or None on timeout/EOF."""
    buf = b""
    deadline = time.monotonic() + TIMEOUT
    while len(buf) < n:
        left = deadline - time.monotonic()
        if left <= 0 or not select.select([fd], [], [], left)[0]:
            return None
        chunk = os.read(fd, n - len(buf))
        if not chunk:
            return None
        buf += chunk
    return buf


def wait_exit(p):
    try:
        return p.wait(TIMEOUT)
    except subprocess.TimeoutExpired:
        p.kill()
        p.wait()
        return "timeout"


def interactive(cmd):
    p = start(cmd)
    out = p.stdout.fileno()
    sizes = [0, 1, 4, 1000, 70000, 3]
    for i, n in enumerate(sizes):
        payload = bytes((i * 31 + k) % 256 for k in range(n))
        frame = struct.pack("<I", n) + payload
        if i == len(sizes) - 1:
            # Split mid-prefix with a pause: the testee must keep reading.
            p.stdin.write(frame[:2]); p.stdin.flush()
            time.sleep(0.3)
            p.stdin.write(frame[2:]); p.stdin.flush()
        else:
            p.stdin.write(frame); p.stdin.flush()
        got = read_exact(out, len(frame))
        check(f"frame {i} ({n} bytes) echoed with stdin open",
              got == frame, "" if got == frame else f"got {None if got is None else len(got)} bytes")
        if got is None:
            p.kill(); p.wait()
            return
    p.stdin.close()
    rc = wait_exit(p)
    check("clean EOF after frames exits 0", rc == 0, f"rc={rc}")


def ends(cmd, name, data, want_zero):
    p = start(cmd)
    p.stdin.write(data)
    p.stdin.close()
    rc = wait_exit(p)
    ok = rc == 0 if want_zero else (rc != 0 and rc != "timeout")
    check(name, ok, f"rc={rc}")


def main():
    cmd = sys.argv[1:]
    if not cmd:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    interactive(cmd)
    ends(cmd, "EOF with no input exits 0", b"", True)
    ends(cmd, "EOF inside the length prefix exits nonzero", b"\x05\x00", False)
    ends(cmd, "EOF inside the payload exits nonzero", struct.pack("<I", 10) + b"abc", False)
    print(f"{failures} failures")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
