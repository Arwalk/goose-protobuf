# 0002: float/double to and from bits in pure Goose

- Status: accepted
- Date: 2026-11-03
- Bead: gpb-wof.2 (blocks gpb-41j.1, pb_wire scalar primitives)
- Toolchain: Goose v2026.3 (`goose runtime 4d3da949e563`), gcc 15.2.0,
  linux-x64

## Question

protobuf `float` and `double` are fixed32 and fixed64 bit patterns on the
wire. pb_wire needs exact `f32 <-> u32` and `f64 <-> u64` conversions in
both directions, and they must keep -0.0, infinities, subnormals and NaN
payloads, signalling NaNs included. Goose has no bit-cast builtin. `x as
u32` on a float truncates the value (NaN gives 0), and the stdlib `binary`
module has no float readers. Can this be done without a C shim?

## Options tried

Both options are in `tests/spikes/float_bits/`.

1. **Pure Goose** (`pure.goose`)
   - float to bits: wrap the value in a one-element array and read it with
     `bytes_of(a)`, a read-only `u8[:]` view of the element region, then
     assemble the bytes little-endian with shifts.
   - bits to float: build a `from_bytes` image by hand in a fixed `u8[5]`
     or `u8[9]`. The image is `uleb128(byte count)` followed by the
     little-endian payload (`docs/design/serialization.md` §3 in the Goose
     release). `from_bytes<f32[>..]>` / `from_bytes<f64[>..]>` then returns
     the one-element array. For a flat scalar element type, the verifier
     only checks framing: the length must be a multiple of `sizeof(T)`, and
     it does not inspect float values.
2. **C shim** (`shim.goose` + `shim.build` + `float_bits.c`): four
   `extern fn`s that do the cast with `memcpy`.

## Results

Both programs check the same 26 vectors, 13 for f32 and 13 for f64:

- +0.0, -0.0, 1.0 and -2.5
- +inf and -inf
- a quiet NaN with payload 1, a negative quiet NaN with payload 0xBEEF
- a signalling NaN with payload 1, a signalling NaN with the maximum payload
- the smallest and largest subnormals, and the largest finite value

Each vector is checked against the known bits and as a bits → float → bits
round trip.

| Run | pure | shim |
|---|---|---|
| `goose x.goose` (in-process, -O1) | 26/26 PASS | 26/26 PASS |
| `goose x.goose --debug` | 26/26 PASS | 26/26 PASS |
| `goose build` (gcc -O2) | 26/26 PASS | 26/26 PASS |
| `goose build --debug` | 26/26 PASS | 26/26 PASS |
| 20M f64 and f32 round trips (gcc -O2) | 0.089 s | 0.076 s |

- Signalling NaNs come through unchanged, because neither route does float
  arithmetic. As a control, `sNaN + 0.0` comes back quieted (0x7FC00001).
- No `as` cast aborts under `--debug`. Narrowing uses `as!`.
- Changing one expected value makes the program print `FAIL` and exit 1.
- A first pure version built the image in a growable `u8[>..]` and took
  0.349 s. The fixed-size array removes almost all of that cost, so pure
  Goose is within about 15% of the C call.

## Decision

**Use pure Goose.** pb_wire gets `f32_to_bits`, `f64_to_bits`,
`f32_from_bits` and `f64_from_bits` written as in `pure.goose`, and has no
C sidecar.

Reasons:

- It is exact on every vector the task requires, on every build mode.
- It costs about the same as the shim.
- A C shim would make pb_wire a package with native parts. That means a
  `.build` sidecar, the C compiler at every build, and packaging work in
  gpb-wof.5, all for four one-line functions.

## Consequences and risks

- **Little-endian only.** That is no new limit: the Goose C backend targets
  64-bit little-endian hosts, and `bytes_of` and `from_bytes` abort with
  `GS_E_ENDIAN` on a big-endian host rather than return wrong bytes.
  Assembling the bytes with explicit shifts keeps the code correct if Goose
  ever adds a byte-swapping variant.
- **Dependence on the image format.** The `from_bytes` image layout is a
  documented contract (serialization.md §3), not an implementation detail.
  If a later Goose release changes it, the spike vectors will catch it.
  gpb-41j.1's unit tests should keep these vectors.
- `f32_from_bits` and `f64_from_bits` call `abort` on a rejected image.
  That can't happen for a 5- or 9-byte image with a correct prefix, so it
  marks a broken invariant, not a decode error.
- If a Goose release adds a bit-cast builtin, replace these four functions
  with it.
