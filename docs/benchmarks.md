# Benchmarks

How fast generated code decodes and encodes, next to protobuf C++ on the same bytes.

| Message | Bytes | Decode: Goose | C++ | Encode: Goose | C++ |
|---|---:|---:|---:|---:|---:|
| Small | 36 | 0.12 µs (288 MB/s) | 0.07 µs (493 MB/s) | 0.03 µs (1,200 MB/s) | 0.05 µs (766 MB/s) |
| Record | 186 | 0.55 µs (341 MB/s) | 0.22 µs (845 MB/s) | 0.09 µs (2,044 MB/s) | 0.13 µs (1,420 MB/s) |
| Batch | 187,837 | 534.82 µs (351 MB/s) | 233.39 µs (805 MB/s) | 114.36 µs (1,642 MB/s) | 152.22 µs (1,234 MB/s) |
| Ints | 31,806 | 90.73 µs (351 MB/s) | 69.36 µs (459 MB/s) | 108.78 µs (292 MB/s) | 68.73 µs (463 MB/s) |
| Strings | 19,510 | 57.27 µs (341 MB/s) | 26.74 µs (730 MB/s) | 3.91 µs (4,992 MB/s) | 17.61 µs (1,108 MB/s) |
| Blob | 1,048,580 | 64.59 µs (16,235 MB/s) | 47.47 µs (22,090 MB/s) | 29.93 µs (35,036 MB/s) | 47.59 µs (22,036 MB/s) |
| Table | 18,233 | 77.54 µs (235 MB/s) | 72.98 µs (250 MB/s) | 10.79 µs (1,689 MB/s) | 26.73 µs (682 MB/s) |

In short, on these messages:

- **Decoding** takes 1.1 to 2.5 times as long as C++.
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
