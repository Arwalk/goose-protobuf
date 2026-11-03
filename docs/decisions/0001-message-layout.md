# 0001: message storage layout

- Status: final (reviewed by the project owner against the context-pool
  alternative, 2026-11-03)
- Date: 2026-11-03
- Bead: gpb-wof.1 (blocks gpb-8qn.1, decode context and pool storage)
- Toolchain: Goose v2026.3 (`goose runtime 4d3da949e563`), gcc 15.2.0,
  linux-x64
- Builds on: [0004](0004-decode-errors.md) (decode errors)

## Question

Goose has no heap. Memory is data stacks, plus `reusable` pools with a
freelist (`alloc_index`, `alloc_ref`, `free`) and `reusable[]` slice pools
(`alloc_slice`, `realloc_slice`, `free_slice`). A struct holds at most one
resizable field, and it must be the last. A protobuf message has
variable-size parts: bytes and strings, repeated fields, maps, nested and
recursive sub-messages, and unknown fields. Where do they live, and what
does a user write to build, read, encode and decode a message?

## Prototype

`tests/spikes/layout/layout.goose` is hand-written stand-in output for

```proto
message Node {
  bytes name = 1;
  repeated Node children = 2;
  map<string, bytes> attrs = 3;
}
```

The runtime pieces it would take from pb_wire are inlined.
`tests/spikes/layout/main.goose` builds a 3-level message (root, children,
grandchildren, with map entries at two levels), then checks:

- encode and `size_of` agree;
- decode, then re-encode, gives identical bytes;
- a message can be decoded into a local and into an element of the
  caller's own array;
- a child reference survives 100 appended siblings;
- on a duplicate map key, the last value wins;
- truncated input fails, and the partial message clears;
- clearing every message and rebuilding reuses every pool slot.

It passes under `goose run --debug` and `goose build --debug`.

## Decision

**Fixed-size records, with every variable part in a global reusable
pool.** A record reaches its parts through 8-byte spans (runs) and 4-byte
pool-relative links.

```goose
// pb_wire
struct pb_Span { at: u32, len: u32 }          // elements [at, at + len) of a pool
reusable[] var pb_bytes: u8[>..] = [];        // contents of every string/bytes field
fn pb_run<T>(pool: T[>..]&, s: pb_Span) -> T[:]
fn pb_resize<T>(pool: T[>..]&, s: pb_Span, n: i64) -> pb_Span   // alloc / realloc / free a run

// generated, per message M
struct M_Ref { m: M&<u32 in M_pool>? }        // a link, wrapped (see below)
struct M { <fields> }                         // fixed-size record
reusable var M_pool: M[>..] = [];             // one slot per sub-message
reusable[] var M_links: M_Ref[>..] = [];      // runs of links: repeated M fields
```

| Field kind | In the record | Contents |
|---|---|---|
| scalar, enum (`i32`) | inline | |
| presence (proto3 `optional`, proto2) | has-bit words, inline | |
| string, bytes | `pb_Span` | run in `pb_bytes` |
| repeated scalar | `pb_Span` | run in a pb_wire pool per element type (`pb_i32s`, `pb_u64s`, `pb_f64s`, ...) |
| repeated string/bytes | `pb_Span` | run of `pb_Span` in `pb_spans` |
| singular message | `Sub_Ref` (optional link) | slot in `Sub_pool` |
| repeated message | `pb_Span` | run of `Sub_Ref` in `Sub_links`; one slot per element |
| map | `pb_Span` | run of entry records in `Entry_pool` (a `reusable[]` pool) |
| oneof | fixed-mode ADT, inline (gpb-gp4.3) | payloads as above |
| unknown fields | `pb_Span` | run in `pb_bytes`, raw wire bytes |

A top-level message is any `M` value the caller owns: a local, a global,
or an element of the caller's array. The pools hold only what it owns.

### User-facing API

```goose
var root = Node { .. };                          // construct: an empty message
Node_set_name(root, "root");                     // setters copy into the pools
let c .= Node_add_children(root);                // a new child; valid until root is cleared
Node_set_name(c, "c0");
Node_attrs_put(root, "k", "v");

let name = Node_name(root);                      // read: u8[:] into pb_bytes
for i in Node_children(root).len { use(Node_children_at(root, i)); }
let v, found = Node_attrs_get(root, "k");

var out: u8[>..] = [];
Node_encode(root, out);                          // append; Node_size_of(root) bytes
var back = Node { .. };
let err = Node_decode(out, back);                // merge; 0 or PB_ERR_* (0004)
Node_clear(root);                                // free everything it owns
Node_clear(back);
```

Scalar fields are read and written directly (`m.id = 5`). Everything
that lives in a pool goes through an accessor. Naming (prefix versus
namespace, how packages map to names) belongs to the emitter task
(gpb-41j.3).

### Why these choices

- **Spans, not slices, in records.** The first version stored slices
  (`name: u8[:]`, `children: Node[:]`). A slice loaded from a record field
  is rooted at the record, not at the pool, and Goose requires every
  recursive call to keep the root the cycle was entered with. The
  recursive decode, encode and clear functions were all rejected
  ("recursive call passes m rooted outside Node_pool", §3.9). A span is
  plain data, and its accessor slices the global pool directly, so the
  root is exact. Records also stay fixed-size and copyable.
- **One slot per sub-message, plus a run of links.** The second version
  stored repeated messages inline, as one run of `Node` records. Appending
  a sibling can move the run (`realloc_slice`), and a reference from
  `Node_add_children` then points at a freed slot. The prototype showed a
  write through such a reference silently vanishing. That slot can later
  be reused by another message, which would then be corrupted. This is
  memory-safe but a real bug. With a slot per message, a `Node&` stays
  valid until its parent is cleared, as in protobuf C++. Measured at -O2
  on 200,000 children, decode plus clear, 20 times over 28 MB: links
  0.16–0.18 s, inline runs 0.17–0.18 s. Encode: 0.06 s for both. The
  extra indirection costs nothing measurable.
- **Wrapped, optional links.** A slice pool fills new elements with a
  default value, and a non-optional link has none. Hence `M&<u32 in
  M_pool>?`. The generated `M_<field>_at(m, i)` narrows the link with
  `assert`. `index_of` cannot name the slot of a bare link element (it
  dereferences the link), so `pb_resize` needs the link wrapped in a
  one-field struct.
- **Doubling while decoding.** Repeated runs grow by doubling during
  decode, with the used length in a fixed local, which recursion permits.
  They are trimmed when the message ends, on error too, so `M_clear`
  frees exact runs. Without doubling, appending to a run that is not at
  the pool's end moves it every time, which is quadratic.
- **Maps as entry runs, last key wins.** Entries are inline records
  (`key`, `value` spans). Nobody holds references to entries, so the run
  may move. Decode replaces the value of an existing key. Lookup is
  linear, and a hash index can come later if a benchmark asks for one.

## Consequences and limits

- **One message universe per program.** The pools are globals, so every
  message of a type shares them, and a program cannot run two independent
  arenas. Goose threads share only flat values, so messages are
  single-threaded. A thread-safe or multi-arena mode would need the
  context-passing layout below.
- **Lifetime is manual.** `M_clear` frees what a message owns. A
  forgotten clear leaks pool slots until exit, though never memory
  outside the pools. A reference into a cleared message reads whatever
  reuses the slot: a logic bug, never memory corruption (reference §14).
- Records hold spans, links and has-bits, so they copy cheaply. A copy
  shares the pool contents and is **not** a deep copy: clearing one copy
  invalidates the other. The generator should emit `M_copy(dst, src)` for
  a deep copy.
- Encode calls `size_of` per nested message, which is O(n · depth). If
  that shows up in profiles, protobuf C++'s fix applies: a cached size in
  the record, set by `size_of`.

## Review

The owner reviewed this layout (A) against the context of locally owned
pools (B) and confirmed A as final on 2026-11-03. What tipped it:

- A is the only option fully prototyped in Goose.
- It has the simplest API: no context parameter on any call.
- Several `.proto` files compose with no extra design, whereas B has an
  open problem: a context type covering the pools of imported files.

Accepted with A, and not to be relitigated without a new requirement:

- one message universe per program;
- likely single-threaded use;
- manual `M_clear`;
- pools that never shrink.

A requirement for threads or per-request arenas is what would reopen
this. Records are spans, links and scalars in both A and B, so a later
move to B changes signatures and user code, not the data layout.

## Rejected

- **Context of locally owned pools**: a struct of references to pools
  owned by the caller, passed to every accessor. This is what Goose
  suggests for recursion over several tables. It allows several arenas and
  threads, but:
  - every accessor, setter and codec call takes the context;
  - `in pool` links need a global pool, so links would become
    self-relative (one root array) or indices;
  - a `.proto` that imports another needs a combined context type over
    both files' pools.

  Spans are indices, so moving to this later only changes the accessors
  and signatures, not the records.
- **Slices in records**: recursion root check, see above.
- **Inline runs for repeated messages**: unstable references, see above.
- **One byte arena per message, FlatBuffers-style**: compact and good to
  read, but every mutation rebuilds, and a decoded message cannot be
  edited in place.
- **Zero-copy views into the input buffer**: string and bytes fields
  would point into the caller's buffer, which then has to outlive the
  message. Copying into `pb_bytes` costs one `memcpy`-like pass and keeps
  lifetimes simple. This could come back as an opt-in decode mode.
