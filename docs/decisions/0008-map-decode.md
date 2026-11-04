# 0008: decoding a map folds repeated keys once, after the input

- Status: accepted
- Date: 2026-11-04
- Bead: gpb-dx9.7
- Toolchain: Goose v2026.3, gcc 15.2.0, linux-x64
- Amends: [0001](0001-message-layout.md), on how decode handles a repeated key

## Question

Decision 0001 looked up each map entry on decode, in a linear scan, and left a
hash index for "if a benchmark asks". Decode takes untrusted input, and a
benchmark asked: 160,000 entries (2 MB) took 6 s, 16 times more for each 4
times the input. How does one input stay near-linear?

## Decision

`decode_from` only appends entries. `M_decode` then runs `M_fold_maps(m)` once,
when all the input is read and before the required-field check. It walks the
message top-down, and for each map `<Entry>_fold` sorts `(key, position)`
records with `sort`, walks the groups of equal keys, keeps the last value in the
place of the first occurrence, and closes the gaps. What a client sees does not
change: the last value wins, in insertion order, and values of two entries do
not merge. `M_fold_maps` exists only for a message that can reach a map.

`pb_reserve` now doubles what this decode loop added, not the run.

### Why these choices

- **Sort, not a hash.** `sort` documents an O(n log n) worst case for any input.
  The stdlib's `hash` takes no seed, so crafted keys could be made to collide and
  bring the quadratic cost back, and a seeded hash needs a random source. A comparison of
  long keys costs their length, which the input has paid for: `str_long` below.
- **Once per `M_decode`, not when each message ends.** The first version folded
  in `decode_from`. A singular sub-message may repeat on the wire, each occurrence
  merging into the last, and each one sorted the whole run: `wrap_map` took 21 s
  at 40,000, against 0.6 s before it. All the tests passed; only the benchmark
  showed it. `tests/roundtrip/maps/maps_scale_merge_roundtrip.goose` guards this.
- **Doubling what the loop added.** Growing a run writes a default in every new
  slot, even in place, and the trim at the end of the loop gave it back. Doubling
  the whole run cost its full length per occurrence: alternating grow and trim
  took 0.92 s for 160,000 rounds, against 0.0004 s growing by one. This fixed
  repeated fields too (`wrap_list`).

## Measurements

`scripts/bench_maps.sh`, build at -O2, time of the decode call only, in seconds,
a process per run, one run each, except as noted. Old is commit `c1272bd`. A run
was cut off at 120 s.

| Shape | Entries | Input | Old | New |
|---|---|---|---:|---:|
| `int_random`, unique int32 keys | 160,000 | 2.0 MB | 5.95 | 0.010 |
| | 1,000,000 | 12.4 MB | >120 | 0.066 |
| `str_random`, unique short strings | 160,000 | 2.5 MB | 28.6 | 0.036 |
| | 1,000,000 | 15.7 MB | >120 | 0.344 |
| `str_prefix`, strings with a 64-byte prefix | 160,000 | 12.8 MB | 68.7 | 0.214 |
| | 1,000,000 | 79.7 MB | >120 | 1.79 |
| `str_long`, strings with a 64 KiB prefix | 2,000 | 131 MB | 4.76 | 1.18 |
| `int_half`, each key twice | 1,000,000 | 12.4 MB | >120 | 0.097 |
| `wrap_map`, one entry per sub-message occurrence | 1,000,000 | 14.4 MB | >120 | 0.083 |
| `two_maps`, the same, alternating two sub-messages | 1,000,000 | 14.4 MB | >120 | 0.086 |
| `wrap_list`, one repeated element per occurrence | 1,000,000 | 4.0 MB | 35.6 | 0.020 |
| `two_lists`, the same, alternating two sub-messages | 1,000,000 | 4.0 MB | 17.7 | 0.025 |

gpb-dx9.8 did the same for unknown fields, which grew by doubling the whole run in
`pb_unknown_grow`, from commit `e18c46f`:

| Shape | Occurrences | Input | Old | New |
|---|---|---|---:|---:|
| `wrap_unknown`, one unknown field per sub-message occurrence | 160,000 | 0.64 MB | 0.44 | 0.005 |
| | 1,000,000 | 4 MB | 18 | 0.033 |
| | 4,000,000 | 16 MB | >120 | 0.130 |
| `wrap_mixed`, the same with a bytes field between them | 4,000,000 | 36 MB | not run | 0.265 |
| `two_unknown`, alternating two sub-messages | 4,000,000 | 16 MB | not run | 0.152 |

New from 10,000 to 1,000,000 entries, 100 times the input: `int_random` takes 111
times as long, `str_random` 191 and `str_prefix` 201.

What got slower, median of 7 alternating runs (min to max):

| Shape | Size | Old | New |
|---|---|---:|---:|
| `small_maps`, 1,000,000 maps of 4 entries | 52 MB | 0.189 (0.187 to 0.222) | 0.205 (0.199 to 0.242) |
| `int_dup`, 1,000,000 entries of one key | 6 MB | 0.023 (0.023 to 0.024) | 0.034 (0.033 to 0.035) |

The first is about 16 ns per map, the cost of the common case. It is accepted, as
a size threshold with a second code path is not worth it at this figure.

## Limits

- `get`, `put` and `remove` are still linear per call, so building n entries with
  `put` is quadratic. Many `M_decode` calls into one message each fold the whole
  run: `int_merge`, 100 entries per call, took 3.6 s at 160,000 (old 6.0 s), and
  is still quadratic. Both are the caller's code rather than one input, and
  [decision 0010](0010-no-map-index.md) leaves them so.
- A failed decode does not fold, so a partial message may hold repeated keys
  until it is cleared, or a later decode into it succeeds.
- `two_maps` is linear although its two runs share a pool, which goes against the
  expectation that they keep moving. The merged free spans of `reusable[]` may be
  why; that was not looked into, and only this pattern was measured.
