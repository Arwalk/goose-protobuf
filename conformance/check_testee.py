#!/usr/bin/env python3
"""Drive a conformance testee the way conformance_test_runner does, with
hand-encoded ConformanceRequests, and check its replies byte for byte.

Usage: python3 conformance/check_testee.py <command...>
  e.g. check_testee.py build/testee
       check_testee.py goose conformance/testee.goose --debug
Exits 0 if every check passes. Each read has a timeout, so a testee that
waits for EOF fails instead of hanging.

Contract (gpb-41j.7): the FailureSet request gets an empty FailureSet; a
binary TestAllTypesProto3 or TestAllTypesProto2 request with binary output
gets its payload decoded and re-encoded in protobuf_payload, or a parse_error
if it does not decode; every other request gets `skipped`.
"""
import os
import select
import struct
import subprocess
import sys
import time

TIMEOUT = 30.0  # seconds; generous, `goose run` compiles first
failures = 0

# conformance.proto
PROTOBUF, JSON = 1, 2
FAILURE_SET_REPLY = b"\x1a\x00"  # protobuf_payload (3) = empty FailureSet
SKIPPED_TAG = 0x2A               # skipped (5), length-delimited
PARSE_ERROR_TAG = 0x0A           # parse_error (1), length-delimited


def check(name, ok, detail=""):
    global failures
    if not ok:
        failures += 1
    print(("PASS " if ok else "FAIL ") + name + (" " + detail if detail else ""))


def varint(v):
    out = bytearray()
    while True:
        b = v & 0x7F
        v >>= 7
        if v:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def field_len(num, data):
    return varint(num << 3 | 2) + varint(len(data)) + data


def field_varint(num, v):
    return varint(num << 3) + varint(v)


def request(message_type, payload_field=1, payload=b"", out_format=PROTOBUF,
            extra=b""):
    return (field_len(payload_field, payload)
            + field_varint(3, out_format)
            + field_len(4, message_type.encode())
            + extra)


def frame(msg):
    return struct.pack("<I", len(msg)) + msg


def is_one_field(reply, tag):
    """True if reply is exactly one `tag` field with a non-empty text."""
    if not reply or reply[0] != tag:
        return False
    n, shift, i = 0, 0, 1
    while i < len(reply):
        b = reply[i]; i += 1
        n |= (b & 0x7F) << shift; shift += 7
        if not b & 0x80:
            return n > 0 and i + n == len(reply)
    return False


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


def read_reply(fd):
    head = read_exact(fd, 4)
    if head is None:
        return None
    return read_exact(fd, struct.unpack("<I", head)[0])


def wait_exit(p):
    try:
        return p.wait(TIMEOUT)
    except subprocess.TimeoutExpired:
        p.kill()
        p.wait()
        return "timeout"


T3 = "protobuf_test_messages.proto3.TestAllTypesProto3"
T2 = "protobuf_test_messages.proto2.TestAllTypesProto2"
UNKNOWN_999 = varint(999 << 3) + varint(5)   # a field TestAllTypesProto3 lacks
CASES = [
    # (name, request bytes, expectation: "failureset", "skipped",
    #  "parse_error", or the bytes of the expected protobuf_payload)
    ("FailureSet request gets an empty FailureSet",
     request("conformance.FailureSet"), "failureset"),
    ("binary in, binary out round-trips",
     request(T3, payload=b"\x08\x96\x01"), b"\x08\x96\x01"),
    ("binary in, empty payload gives an empty payload",
     request(T3), b""),
    ("unknown fields are kept",
     request(T3, payload=b"\x08\x01" + UNKNOWN_999), b"\x08\x01" + UNKNOWN_999),
    ("a truncated payload is a parse_error",
     request(T3, payload=b"\x08"), "parse_error"),
    ("a payload after a parse_error still round-trips",
     request(T3, payload=b"\x10\x02"), b"\x10\x02"),
    ("proto2 round-trips",
     request(T2, payload=b"\x08\x96\x01"), b"\x08\x96\x01"),
    ("a truncated proto2 payload is a parse_error",
     request(T2, payload=b"\x08"), "parse_error"),
    ("another message is skipped",
     request("protobuf_test_messages.editions.TestAllTypesEdition2023", payload=b"\x08\x01"), "skipped"),
    ("JSON in is skipped",
     request(T3, payload_field=2, payload=b"{}"), "skipped"),
    ("JSON out is skipped",
     request(T3, payload=b"\x08\x01", out_format=JSON), "skipped"),
    ("text in is skipped",
     request(T3, payload_field=8, payload=b"optional_int32: 1"), "skipped"),
    ("unknown and unhandled request fields are skipped over",
     request(T3, payload=b"\x08\x01",
             extra=field_varint(5, 1) + field_len(6, b"\x08\x01")
             + field_varint(9, 1) + b"\x55\x01\x02\x03\x04"   # field 10, fixed32
             + b"\x59" + bytes(8)),                           # field 11, fixed64
     b"\x08\x01"),
    ("FailureSet request split mid-prefix gets an empty FailureSet",
     request("conformance.FailureSet"), "failureset"),
]


def interactive(cmd):
    p = start(cmd)
    out = p.stdout.fileno()
    for i, (name, msg, want) in enumerate(CASES):
        data = frame(msg)
        if i == len(CASES) - 1:
            # Split inside the length prefix with a pause, stdin kept open.
            p.stdin.write(data[:2]); p.stdin.flush()
            time.sleep(0.3)
            p.stdin.write(data[2:]); p.stdin.flush()
        else:
            p.stdin.write(data); p.stdin.flush()
        got = read_reply(out)
        if want == "failureset":
            ok = got == FAILURE_SET_REPLY
        elif want == "skipped":
            ok = got is not None and is_one_field(got, SKIPPED_TAG)
        elif want == "parse_error":
            ok = got is not None and is_one_field(got, PARSE_ERROR_TAG)
        else:
            ok = got == field_len(3, want)
        check(name, ok, "" if ok else f"got {got!r}")
        if got is None:
            p.kill(); p.wait()
            return
    p.stdin.close()
    rc = wait_exit(p)
    check("clean EOF after requests exits 0", rc == 0, f"rc={rc}")


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
    ends(cmd, "EOF inside the payload exits nonzero",
         struct.pack("<I", 10) + b"abc", False)
    ends(cmd, "malformed request (wire type 7) exits nonzero",
         frame(b"\x0f"), False)
    print(f"{failures} failures")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
