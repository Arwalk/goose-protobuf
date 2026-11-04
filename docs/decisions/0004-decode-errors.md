# 0004: decode errors use a sticky code in the reader

- Status: accepted
- Date: 2026-11-03
- Bead: gpb-wof.4 (blocks gpb-41j.1 pb_wire scalars, gpb-41j.4 proto3 scalars)
- Toolchain: Goose v2026.3 (`goose runtime 4d3da949e563`), gcc 15.2.0,
  linux-x64

## Question

Decoding fails on truncated input, a malformed varint or tag, a length
that overruns its window, and nesting beyond a depth limit. Decode is
recursive: a message's decoder calls its sub-messages' decoders. Goose
puts these constraints on such a cycle (reference §19):

- the entry is a `recursive fn`, and every function in the cycle has an
  explicit signature;
- no non-fixed local may be live across a recursive call, and non-fixed
  parameters are references or slices;
- `exception::try` cannot be re-entered inside the cycle, and a
  long-distance return (`return E from f`) may carry only owned values or
  references to globals.

How does an error get from the primitive that sees it (a varint read, say)
to the caller of the generated `decode`, and what do the generated
`decode`, `encode` and `size_of` signatures look like?

## Candidates

| Idiom | How it works |
|---|---|
| **S: sticky code** | `Reader { buf, pos, end, err, depth }` is passed by reference. A failing primitive records the first error and sets `pos = end`, so every field loop (`while r.pos < r.end`) stops. Values read after a failure are 0 and are thrown away. Callers check `r.err` only after a nested message decode, because the parent restores its own `end` and would otherwise keep reading. |
| **T: throw** | Primitives call `exception::throw(code)`. The non-recursive entry wraps the recursive decoder in `exception::try<i32>`. Decoders never check. |
| **E: explicit** | Every primitive returns `(value, ok)` or `(value, next_pos)` with -1 meaning error, and every call site checks it. This is the style of the hand-written testee's `read_varint`. |
| **R: `return … from`** | This is T without the library. pb_wire's primitives cannot name each message's entry function, so it needs a shared entry and adds nothing over T. |

## Prototype

`tests/spikes/decode_errors/` has two prototypes. `sticky.goose` is S and
`throw.goose` is T. Both decode
`message Node { int32 id = 1; repeated Node children = 2; bytes name = 3; }`
into a `Node[>..]` pool passed by reference through the recursive
decoder. `bench.goose` is shared between them. Both pass `goose check` and
`goose run --debug`:

| Input | S | T |
|---|---|---|
| 3-level message | ok, 3 nodes, deepest id 3 | same |
| the same, cut 2 bytes short | truncated | truncated |
| 5 levels (limit 3) | depth | depth |
| 11-byte varint | malformed | not run |
| child length larger than its parent's window, buffer long enough | truncated | not run |

Benchmark (`goose build` at -O2, `<variant> bench`): a root message with
200,000 children, decoded 20 times (52 MB):

| | run 1 | run 2 | run 3 |
|---|---|---|---|
| S | 0.087 s | 0.087 s | 0.090 s |
| T | 0.129 s | 0.107 s | 0.103 s |

T is about 15–50% slower. A long-distance return is a hidden discriminant that
every frame on the path checks after each call (reference §20), so each
primitive call in T carries a check that S does only after a nested
message.

## Decision

**S, a sticky error code in the reader.** pb_wire (gpb-41j.1) provides:

```goose
struct pb_Reader { buf: const u8[:], pos: i64, end: i64, err: i32, depth: i32 }

let PB_OK = 0;
let PB_ERR_TRUNCATED = 1;   // input ends inside a value, or a length overruns its window
let PB_ERR_MALFORMED = 2;   // varint over 10 bytes, bad wire type, field number 0, ...
let PB_ERR_DEPTH = 3;       // nesting beyond PB_MAX_DEPTH
let PB_ERR_UTF8 = 4;        // a proto3 string that is not valid UTF-8 (gpb-8qn.4)
let PB_ERR_REQUIRED = 5;    // decoded whole, but a required proto2 field is unset (gpb-6xy.4)
let PB_MAX_DEPTH = 100;     // protobuf's default recursion limit

fn pb_fail(r: pb_Reader&, code: i32)   // keeps the first code; pos = end
fn pb_read_varint(r: pb_Reader&) -> u64 // 0 after a failure; likewise every reader
```

The primitives never abort on bad input: `as!` for wrapping casts, and
bounds checked before every index.

For each message `M` the generator emits the following. The storage
layout comes from [0001](0001-message-layout.md), and names are fixed by
the emitter task:

```goose
// Entry: non-recursive. Merges buf into m. 0 on success, else a PB_ERR_*
// code; m then holds a partial message, which the caller clears (M_clear).
fn M_decode(buf: const u8[:], m: M&) -> i32

// Merges fields from r's window into m, setting r.err on failure.
// `recursive fn` only when M is in a recursive cycle.
recursive fn M_decode_from(r: pb_Reader&, m: M&)

fn M_encode(m: M&, out: u8[>..]&)  // appends; cannot fail
fn M_size_of(m: M&) -> i64         // cannot fail
```

The code generated for a sub-message field is:

```goose
let n = pb_read_len(r);                  // fails if n > r.end - r.pos
if r.depth >= PB_MAX_DEPTH { pb_fail(r, PB_ERR_DEPTH); return; }
let outer = r.end;
r.end = r.pos + n; r.depth++;
Sub_decode_from(r, ..., child);
if r.err != PB_OK { return; }
r.depth--; r.end = outer;
```

Depth lives in the reader, not in a parameter, so every `decode_from` has
the same shape. Encoding cannot fail: it appends to a builder, and the
sizes come from `size_of`. A message over 2 GiB is the caller's problem,
as in protobuf.

## Rejected

- **T (throw).** It is slower, and any call of a throwing primitive outside
  a `try` is a compile error ("every throw must have a handler on every
  compile-time call path"). That would make the pb_wire primitives
  unusable on their own, for example in the hand-written testee and in
  unit tests. It also does nothing to stop the restore-`end` hazard,
  since a throw skips those lines, which is harmless only because the
  whole decode is abandoned.
- **E (explicit).** It has the same performance profile as S but needs a
  check at every primitive call. Generated code would grow by about one
  `guard` per field read, with no benefit, because S's "read 0 and stop
  the loop" is already safe.
- **R (`return … from`).** See T.

`PB_ERR_REQUIRED` is the one code not set in the reader: `M_decode` returns it
after a decode with no other error, from `M_is_initialized(m)`, which walks the
whole message. Checking each occurrence of a sub-message would be wrong, since a
later one that merges into it may set what an earlier one lacks. That function
exists only for a message that can reach a required field, so proto3-only code
pays nothing. A required enum whose value the enum does not
declare stays unset, so it fails.

## Consequences

- A generated decoder must check `r.err` after every nested
  `*_decode_from` call, and before any action that is unsafe on zero
  values. Today nothing else is: pool pushes of zeroed records are
  harmless. Golden tests show the check, and the round-trip tests
  (gpb-41j) cover truncation inside nested messages.
- On failure, storage holds a partial message. `M_decode` documents this,
  and the testee answers `parse_error` without reading it.
