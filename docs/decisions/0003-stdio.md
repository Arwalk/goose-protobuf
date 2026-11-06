# 0003: exact-length stdin reads and stdout flush

- Status: accepted
- Date: 2026-11-03
- Bead: gpb-wof.3 (blocks gpb-iip.4, hand-written Goose testee)
- Toolchain: Goose v2026.3 (`goose runtime 4d3da949e563`), gcc 15.2.0,
  Python 3.14.4, linux-x64

## Question

conformance_test_runner talks to the testee over pipes. It writes a 4-byte
little-endian length and a ConformanceRequest, waits for the testee's
length-prefixed ConformanceResponse, then sends the next request. stdin
stays open until the last test. The testee must therefore read exactly N
bytes, write its reply, make sure the reply leaves the process, and tell a
clean EOF between frames from a truncated frame.

Goose's `os` module (`stdlib/os.goose`, runtime `runtime_os.h`) offers:

- `read_stdin(out)`: `fread` in a loop until EOF. It returns only when the
  runner closes stdin, so the testee would deadlock on the first request.
- `read_line(out)`: `fgetc` up to `\n`, and it strips a trailing `\r`.
  That is useless for binary frames.
- `write_stdout(s)`: `fwrite(stdout)`. `flush_stdout()`: `fflush(stdout)`.

Goose has no other way to read stdin.

## Mechanism

A C shim with one function, linked by a sidecar. The shim and the spike
are in `tests/spikes/stdio/`:

```goose
// echo.build: c_sources = ["stdio.c"];
extern "pbio_read_exact" fn read_exact(out: u8[>..]&, n: i64) -> i32;
```

`pbio_read_exact` loops `read(0, ...)` in chunks of up to 64 KiB, retries
on `EINTR`, and appends each chunk to the builder with `gs_bld_append`
(`goose.h`, which the compiler puts on every native part's include path).
It returns:

| Result | Meaning |
|---|---|
| 0 | all `n` bytes appended |
| 1 | EOF before the first byte, a clean end between frames |
| -1 | EOF partway through (short read), a read error, or `n < 0` |

It uses `read(2)` rather than `fread`, so no stdio buffer sits in front of
fd 0. The testee must therefore never call `read_stdin` or `read_line`,
which use the `stdin` FILE.

**Output needs no shim.** The runtime's init calls
`setvbuf(stdout, NULL, _IONBF, 0)`, so every `write_stdout` is one
unbuffered write. The testee builds the 4-byte prefix and the payload in a
single buffer, so each reply is one `write_stdout`, then calls
`flush_stdout()`. The flush does nothing today, but it costs nothing and
keeps the testee correct if the runtime ever buffers stdout.

The frame loop (`echo.goose`) reads 4 bytes. A result of 1 means exit 0,
and -1 means exit 1. It then decodes the length in `u64`, reads the payload
with `read_exact(frame, len as! i64)` (-1 means exit 1), writes the frame
and flushes.

## Results

`driver.py` plays the runner. It writes one frame, reads the echo with a
30 s timeout, and only then writes the next, never closing stdin. The
frames are 0, 1, 4, 1000, 70000 (more than one 64 KiB pipe buffer) and 3
bytes, and the last one is written in two parts, split inside the length
prefix, with a 0.3 s pause. Then it checks the ends of the stream: closing
stdin after the frames, and with no input at all, must exit 0, while EOF
inside the prefix and EOF inside the payload must exit nonzero.

| Run | Result |
|---|---|
| `goose echo.goose` (in-process, -O1) | 10/10 PASS |
| `goose echo.goose --debug` | 10/10 PASS |
| `goose build` (gcc -O2) | 10/10 PASS |
| `goose build --debug` | 10/10 PASS |
| 20,000 round trips of 64-byte frames (gcc -O2, Python driver) | 1.03 s, about 52 µs each |

Controls:

- A testee using `read_stdin` fails frame 0 on the 30 s timeout. That is
  the deadlock this spike exists to avoid, and the driver catches it.
- The echo without `flush_stdout()` still passes, which confirms that
  stdout is unbuffered.

## Decision

**Use the `pbio_read_exact` C shim for stdin and the stock `write_stdout`
plus `flush_stdout` for stdout.** gpb-iip.4 copies `stdio.c` to
`conformance/io.c` with a `conformance/testee.build` sidecar
(`c_sources = ["io.c"];`) and uses the frame loop from `echo.goose`.

Reasons:

- Goose has no other way to read part of stdin, and the shim is 20 lines
  of plain POSIX.
- The shim belongs to the testee, not to pb_wire. Generated code and the
  runtime library never touch stdio, so decision 0002's no-C rule for
  pb_wire still holds.

## Consequences and risks

- **POSIX only.** `read(2)` and `<unistd.h>` won't build on Windows. That
  is no new limit, because the conformance suite doesn't support Windows
  and CI runs on Linux and macOS (TOOLCHAIN.md). macOS has not been run
  yet. The same code should work there, and the CI bead should run the
  driver on macOS. (Since superseded: CI runs the stdio check on macOS, and the owner
  reported its first run green on 2026-11-06.)
- **No stdio for stdin.** Mixing `read_stdin` or `read_line` with the shim
  would lose bytes into the FILE buffer. Only the shim reads stdin in the
  testee.
- **Don't print to stdout.** `print` writes to stdout and would corrupt the
  framing. Diagnostics go to `write_stderr`.
- **Length limit.** The prefix is a u32, so `len as! i64` can't overflow.
  The testee allocates whatever length the runner sends. That is fine for a
  trusted runner, but it is not a defence against hostile input.
- If a Goose release adds an exact-length or partial read to `os`, replace
  the shim with it.
