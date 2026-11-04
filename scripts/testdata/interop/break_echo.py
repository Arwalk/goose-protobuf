#!/usr/bin/env python3
"""Runs the echo in argv[1:], and spoils its output as INTEROP_BREAK says."""
import os
import subprocess
import sys

out = subprocess.run(sys.argv[1:], stdout=subprocess.PIPE, check=True).stdout
mode = os.environ["INTEROP_BREAK"]
if mode == "flip":        # another value: every reader sees it
    out = out[:-1] + bytes([out[-1] ^ 1])
elif mode == "truncate":  # no message: protoc cannot read it
    out = out[:-1]
elif mode == "double":    # the same value twice: only a byte comparison sees it
    out = out + out
sys.stdout.buffer.write(out)
