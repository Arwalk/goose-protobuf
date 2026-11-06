# Limitations

What `protoc-gen-goose` does not do, or does slowly, and what to do about it.

- Binary wire format only. There is no JSON or text format, no reflection, and
  no services or RPC.
- proto2, proto3 and editions up to 2026.
- Messages are single-threaded: they live in global pools, and Goose threads
  share only flat values.
- Extensions are kept as unknown fields, with no accessors. A string extension's
  UTF-8 is therefore not checked.
- Unknown fields stay in the order they were read, so they do not keep their
  place between known fields.
- Map `_get`, `_put` and `_remove` scan the map: about 2 µs per int key and 10 µs
  per short string at 10,000 entries, in proportion to the size. Building a map with
  `_put` is therefore quadratic, and so is calling `M_decode` in a loop to add a few
  entries to a large map. To build one, call `M_f_append` for each entry and
  `M_fold_maps(m)` once, before reading it: 160,000 entries take 7 ms, not 6 s. To
  add to one by decoding, concatenated encodings decode as a merge, so join the
  buffers and decode once. For many `_get` on a large map, keep your own index beside
  it ([decision 0010](decisions/0010-no-map-index.md)).
- One run of values is limited to 2^32 elements, and one pool to 4 GiB.
- One decode may allocate 512 MiB unless you
  [raise the limit](../SECURITY.md#the-decode-limit), and a program's messages are limited
  to about 2 GB in each pool together.
