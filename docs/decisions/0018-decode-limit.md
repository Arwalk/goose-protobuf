# 0018: a decode has a memory budget

- Status: accepted
- Date: 2026-11-06
- Bead: gpb-ky7.21
- Toolchain: Goose v2026.3, protoc 36.2, linux-x64
- Builds on: [0004](0004-decode-errors.md) (decode errors), [0012](0012-public-api.md)
  (public API)

## Question

Malformed input gives an error code, but input that is merely large did not: 256 MB of
empty entries of a repeated message field ended the program with `data stack overflow`,
and Goose cannot catch that. How can a decoder fail with an error code instead?

## Options

- **Tell users to check the size of the input.** The cost per input byte depends on the
  schema, and on a large record it is high, so the right size is hard to work out.
- **Check how full each pool is.** This is the actual limit, but Goose does not tell a
  program its reservation, and generated pools have no shared code to put the check in.
- **Count what a decode allocates.** One number, for every schema, at a cost of one
  subtraction per element.

## Decision

Count. `pb_Reader` gets a budget from `pb_decode_limit`, and generated code and the
runtime call `pb_charge(r, n)` before each allocation that input can ask for: an element
of a repeated field, a record, a map entry, string and bytes values, and unknown fields.
Past the budget it fails with `PB_ERR_TOO_LARGE`, through `pb_fail`, so it stops the
loops as every other error does. `pb_append` and `pb_reserve` stay as they were, and the
one element allocated after a failed charge does no harm.

The charge is close, and need not be exact. Goose has no `sizeof`, so a record counts 32
bytes and 8 per field. This matched the measured 88 bytes of a record of nine fields.

The default is 512 MiB. A run takes up to twice its size as it grows, so that stays under
the 2 GB of a data stack. It was measured on input of 1 GiB or more of each kind, and each
gave the error, peaking at about 1 GiB beyond the input's own size.

The limit is a global that each decode reads when it starts, for each decode alone, which
a user sets with `pb_set_decode_limit`. It is not an argument to `M_decode`: that would
change every call, for what most programs set once. Messages are single-threaded anyway.

`PB_ERR_TOO_LARGE`, `PB_DEFAULT_DECODE_LIMIT` and `pb_set_decode_limit` are public, and
`tests/runtime/pb_wire_public_test.goose` holds them.

## Consequences

- Decoding packed one-byte `int64` values, where the charge costs the most, takes about
  2% longer (320 million values: 0.92 s before and 0.94 s after).
- A message that needs more than 512 MiB no longer decodes until its program raises the
  limit. It worked before, up to about 2 GB.
- Messages the program still holds add up, and past 2 GB the abort remains. Tracking what
  is live would need a charge on every free too. [SECURITY.md](../../SECURITY.md) says so.
- A pool past 2^32 elements, which only a raised `--stack-reserve` allows, is a separate
  problem: `pb_resize` ends the program there, as a position would wrap.
