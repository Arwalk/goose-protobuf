# Benchmarks

How fast generated code decodes and encodes, next to protobuf C++ on the same bytes.

| Message | Bytes | Decode: Goose | C++ | Encode: Goose | C++ |
|---|---:|---:|---:|---:|---:|
| Small | 36 | 0.12 µs (300 MB/s) | 0.07 µs (480 MB/s) | 0.03 µs (1,200 MB/s) | 0.05 µs (750 MB/s) |
| Record | 186 | 0.56 µs (330 MB/s) | 0.22 µs (849 MB/s) | 0.10 µs (1,938 MB/s) | 0.13 µs (1,442 MB/s) |
| Batch | 187,837 | 550.37 µs (341 MB/s) | 235.99 µs (796 MB/s) | 115.51 µs (1,626 MB/s) | 153.29 µs (1,225 MB/s) |
| Ints | 31,806 | 91.53 µs (347 MB/s) | 69.93 µs (455 MB/s) | 109.56 µs (290 MB/s) | 69.00 µs (461 MB/s) |
| Strings | 19,510 | 59.30 µs (329 MB/s) | 26.54 µs (735 MB/s) | 3.90 µs (5,004 MB/s) | 17.80 µs (1,096 MB/s) |
| Blob | 1,048,580 | 400.47 µs (2,618 MB/s) | 47.69 µs (21,989 MB/s) | 30.24 µs (34,674 MB/s) | 48.32 µs (21,701 MB/s) |
| Table | 18,233 | 78.40 µs (233 MB/s) | 73.81 µs (247 MB/s) | 10.88 µs (1,675 MB/s) | 26.88 µs (678 MB/s) |

In short, on these messages:

- **Decoding** takes 1.1 to 2.5 times as long as C++, and 8 times as long for a large
  `bytes` value, which is copied a byte at a time.
- **Encoding** is faster than C++, except for packed integers, which take 1.6 times as long.

Use these as a rough guide. Your messages, compiler and machine will differ.

## The messages

[`codec.proto`](../tests/bench/codec/codec.proto) has them, and
[`scripts/bench_codec.py`](../scripts/bench_codec.py) makes their values, always the same:

| Message | What it holds |
|---|---|
| Small | A small record of two strings, an integer and a bool |
| Record | A log line with a few of every kind of field |
| Batch | 1,000 Records |
| Ints | 10,000 packed `int64` values of mixed sizes |
| Strings | 1,000 short strings |
| Blob | 1 MiB of `bytes` |
| Table | A map of 1,000 strings to integers |

## How they were measured

Each figure is the fastest of 5 rounds of 1 second, in one thread. A decode is
`M_decode` and then `M_clear`, or `ParseFromArray` and then `Clear`, each on one message
kept for the run. An encode writes into one buffer kept for the run. C++ uses no arena,
which can make it faster.

| | |
|---|---|
| Machine | Intel Core i9-9900K at 3.60 GHz, 16 GB, x86_64, Linux 7.0 |
| Goose | v2026.3, with `goose build`'s defaults, using gcc 15.2.0 |
| C++ | protobuf 36.2, built as `Release` (`-O3`), with code compiled by gcc 15.2.0 at `-O2` |

To run them yourself, with the protobuf submodule checked out:

```sh
scripts/build_runner.sh
scripts/bench_codec.py
```
