# Security

## Reporting a problem

Please report a vulnerability privately, through
[a security advisory](https://github.com/Arwalk/goose-protobuf/security/advisories/new),
and not in a public issue. Say which version you use and give an input that shows the
problem, if you have one.

This project is before version 1.0, so only the latest version is fixed.

## Decoding untrusted bytes

Generated decoders are meant to take bytes from anyone. Malformed input gives an error
code, and a decoder does not read outside its buffer. So does input that asks for too
much memory, up to a limit, but **what your program already holds counts as well**.

### The decode limit

A small input can ask for far more memory than its own size, as each element costs a
whole record. Measured with Goose v2026.3 on Linux x64, with a sub-message of eight
`int64` fields and a string:

| Input of only | Peak memory for each input byte |
|---|---|
| Empty entries of a repeated message field | 45 |
| Empty entries of a map | 23 |
| Packed one-byte `int64` values | 8 |

So one decode may allocate `PB_DEFAULT_DECODE_LIMIT`, 512 MiB, and input that needs more
gets `PB_ERR_TOO_LARGE`. The count is close but not exact, and a field takes up to twice
its size in memory while it grows. `pb_set_decode_limit(bytes)` changes the limit for
every decode after it. Lower it to what your messages need, which also keeps the memory
a stranger can make you use to about twice that.

### What can still end your program

Goose keeps a program's data on stacks of 2 GB of reserved address space. Past that,
**the program ends with `data stack overflow`, which it cannot catch**. The default limit
stays under it when nothing else is in the pools, but it applies to each decode alone,
and the pools hold every message you have not cleared.

So:

- Call `M_clear` on a message when you are done with it, and also after a failed decode,
  since the pools are global and nothing else frees what it holds.
- Keep few decoded messages at once, or lower the limit so that they cannot add up to 2 GB.
- Raising the limit past about 1 GiB brings the abort back within reach of one message.
- If input must not be able to end your service, decode in a process you can restart.

### Do not raise the reservation for untrusted input

`goose build --stack-reserve` raises the limit above. Do not use it to decode untrusted
input: positions in the pools are 32 bits, and **past 4 GiB in one pool a decoder
returns `PB_OK` with wrong data**, as a new value overwrites an old one. The default
reservation ends the program long before that.

### Other limits

- **Depth.** Messages and groups nest up to `PB_MAX_DEPTH` (100), and more gives
  `PB_ERR_DEPTH`, so input cannot overflow the C stack through a decoder.
- **Time.** We know of no input that makes decoding slow: 16 MB of nested unknown groups
  and 12 MB of distinct map keys each took about 0.1 s. Reading a map is slower, and
  [the limitations](docs/limitations.md) give the cost of `_get` on a large one.
- **Text.** `PB_ERR_UTF8` covers proto3 strings. A proto2 string may hold any bytes, so
  check it yourself if you need valid UTF-8.
- **Unknown fields** are kept, so they cost memory and are written back when you encode.
  Do not forward a decoded message and assume it holds only the fields you declared.
- **Required fields.** `PB_ERR_REQUIRED` means the message decoded whole but lacks one.
  Your own checks on values are still yours to make.

## What fuzzing covers

Generated decoders are fuzzed with libFuzzer and AddressSanitizer, on a schedule in CI.
Each input is decoded, encoded, decoded and encoded again. A crash, a failed check of
Goose's debug build, or two encodings that differ all count as failures.

The fuzzer runs on protobuf's own test messages, which hold every kind of field, and
not on yours. It keeps inputs to a few kilobytes, so it does not reach the memory limits
above. It does not run on Windows. It does not cover the plugin
either: `.proto` files and the plugin's input are trusted, like your source code.
