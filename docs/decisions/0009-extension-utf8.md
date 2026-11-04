# 0009: the UTF-8 of a string extension is not validated

- Status: accepted, confirmed by the project owner. Nothing else depends on it.
- Date: 2026-11-04
- Bead: gpb-dx9.10
- Toolchain: protobuf v36.2 conformance suite

## Question

With `--enforce_recommended`, one binary test fails:
`Recommended.Editions.ProtobufInput.RejectInvalidUtf8.String.Extension`. Invalid
UTF-8 in a string extension of `TestAllTypesEdition2023` must not parse. Here it
does, as extensions are kept as unknown bytes (gpb-6xy.6). Should decoding look
at them?

## Decision

**No. The test stays failing**, listed in
`conformance/failure_list_recommended.txt`.

- **Extensions have no typed form here, by design.** They have no accessors, and
  pass through as the bytes they came as. Nothing in a Goose program can read one
  as a string, so no program can be handed the invalid text this check guards
  against. A program that takes the bytes out and treats them as text has to
  check them, as it would with any bytes.
- **A decoder cannot know them all.** An extension may be declared in a file that
  the target's file does not import, so generated code for the target cannot see
  it. Validating would cover the extensions that happen to be in view, and the
  same bytes would be accepted or rejected depending on what is generated. Full
  coverage needs a registry at decode time, which is the reflection-like machinery
  the project's scope leaves out.
- **The failure is small.** It is one recommended test, not a required one, and
  every other recommended binary test passes.

## Known gap

We expect protobuf's own runtimes to treat an extension they have not been told
about as unknown, without looking inside, as this one does. That comes from general
knowledge of them, and was not tested or checked against their source, so this
decision does not rest on it. If they turn out to reject such bytes anyway, this
runtime is the odd one out, and the choice is worth weighing again.

## Consequences

- Invalid UTF-8 in a string extension decodes and re-encodes unchanged, so a program
  that forwards messages can pass it to a stricter peer, which may reject them.
- `docs/usage.md` lists this under its limitations.
- If extensions ever get accessors, that work decides this again: an accessor that
  returns text must validate.
