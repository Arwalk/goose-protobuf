# 0010: maps get no index

- Status: accepted. A workload that needs one reopens it.
- Date: 2026-11-04
- Bead: gpb-dx9.9
- Toolchain: Goose v2026.3, gcc 15.2.0, linux-x64
- Builds on: [0008](0008-map-decode.md), which made one decode near-linear

## Question

`get`, `put` and `remove` scan the map, so building n entries with `put` is
quadratic. Many `M_decode` calls into one message each fold the whole run, which
is quadratic too. Both are the caller's code, not one input. Is a per-map index
worth having?

## Measurements

`scripts/bench_maps.sh`, build at -O2, one run each, in seconds. `put` is building
the map one `_put` at a time, and `get` is one `_get` of every key after that.

| Entries | `put_int` put | `put_int` get | `put_str` put | `put_str` get |
|---:|---:|---:|---:|---:|
| 10 | 0.000002 | 0.0000002 | 0.000009 | 0.0000007 |
| 100 | 0.000006 | 0.000003 | 0.00002 | 0.00001 |
| 1,000 | 0.00023 | 0.00022 | 0.0010 | 0.00096 |
| 10,000 | 0.022 | 0.022 | 0.099 | 0.097 |
| 40,000 | 0.37 | 0.36 | 1.6 | 1.6 |
| 160,000 | 6.0 | 6.0 | 26 | 26 |

`int_merge`, 100 entries per `M_decode` call: 10,000 takes 0.013, 160,000 takes
3.7, and 640,000 takes 65. Decoding all of 1,000,000 in one call takes 0.066
(decision 0008).

So a map of 1,000 entries costs about 0.2 µs per lookup with int keys and 1 µs with
short strings, and a map of 10,000 about 2 µs and 10 µs.

## Decision

**No index.** The scan stays, and the guide states the limit and the way around it.

- **The cost lands on what is already fine.** An index needs a span in the record
  of every message with a map, 8 bytes per map field, set or not, and code to keep
  it right on every change. The maps that gain are those past about 10,000 entries
  built or searched from code, and nothing here asks for those.
- **A sorted index does not fix `put`.** It makes `get` and finding a key in `put`
  logarithmic, but each new key still shifts half of the index on average. That is
  cheaper than a scan by a constant, and still quadratic. This is reasoned, not
  measured, as no index was built.
- **A hash index needs a seed.** Decision 0008 turned one down for decode: the
  stdlib's `hash` takes no seed, so crafted keys can collide. The same holds for
  keys a program takes from its input and passes to `put`.
- **The view gets in the way.** `M_<f>(m)` hands out the entries, and an entry's
  key has a setter. A program may change a key through it, and an index would then
  be wrong with nothing to notice it, whereas a scan cannot be.
- **`M_decode` in a loop has a way out.** Concatenated encodings are a merge of
  the messages they encode, so joining the buffers and decoding once gives the same
  message in linear time.

## Consequences

- `docs/usage.md` states the limit, with these figures, and both ways around it:
  decode once rather than calling `_put` or `M_decode` in a loop, or keep your own
  index beside the map.
- gpb-811 looks at this again once the rest of the backlog is done, starting with a
  bulk append that decision did not weigh.
- A workload with larger maps built from code reopens this sooner, with its figures. It
  would likely want a seeded hash, built lazily on the first lookup, so that the
  decode path and small maps pay nothing but the span.
