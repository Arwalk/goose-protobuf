# goose-protobuf

Read and write [Protocol Buffers](https://protobuf.dev) from
[Goose](https://aardappel.github.io/goose/). `protoc-gen-goose` is a `protoc` plugin
that turns your `.proto` files into Goose code for the protobuf binary wire format, so
a Goose program can exchange messages with services and files written in any other
language.

- **Correct.** The generated code passes every required binary test of protobuf's
  official conformance suite, and is checked against `protoc` and Python protobuf.
- **Plain Goose.** You get records and functions you can read, with one small runtime
  package underneath, and no reflection or descriptors at run time.
- **Safe on bad input.** Malformed input, or input that asks for too much memory, gives
  an error code. The decoders are fuzzed, and [SECURITY.md](SECURITY.md) has the limits.
- **Goose all the way.** The plugin is itself written in Goose, so building it takes
  nothing beyond what your Goose programs already need.

## A short example

Given a message:

```proto file=person.proto
syntax = "proto3";
package demo;

message Person {
  string name = 1;
  int32 age = 2;
  repeated string emails = 3;
}
```

you encode and decode it like this:

```goose file=app.goose
import pb_wire from "../goose-protobuf";
import person;

fn main() {
    var p = demo::Person { .. };
    demo::Person_set_name(p, "Ada");
    p.age = 36;
    demo::Person_add_emails(p, "ada@example.org");

    var bytes: u8[>..] = [];
    demo::Person_encode(p, bytes);
    demo::Person_clear(p);

    var q = demo::Person { .. };
    let err = demo::Person_decode(bytes, q);
    if err != PB_OK { abort(str("decode failed: ", pb_error_text(err))); }
    print(demo::Person_name(q), ", ", q.age, ", ", demo::Person_emails_at(q, 0));
    demo::Person_clear(q);
}
```

```sh run
../goose-protobuf/scripts/install_plugin.sh
protoc --goose_out=. person.proto
goose build app.goose -o app
./app
```

```text output
Ada, 36, ada@example.org
```

## What it covers

| | |
|---|---|
| Syntax | proto2, proto3, and editions up to 2026 |
| Fields | Scalars, enums, strings, bytes, sub-messages, repeated fields (packed or not), maps, oneofs, groups |
| Presence | `optional` and `required`, and defaults for unset fields |
| Well-known types | `Any`, `Duration`, `Empty`, `FieldMask`, `Struct`, `Timestamp` and the wrappers, ready to import |
| Unknown fields | Kept when decoding, and written back when encoding |
| Extensions | Kept as unknown fields, with no accessors, and none are planned for now |
| Not planned for now | JSON and text formats, reflection, services and RPC |

Messages live in global pools, so they are single-threaded. The
[limitations](docs/limitations.md) list the rest, with their workarounds.

This project is before version 1.0. Its
[version rules](docs/versions.md) say what you can rely on.

## Get started

1. [Install](docs/install.md) the tools and the plugin.
2. Follow the [quickstart](docs/quickstart.md), from an empty directory to a round trip.
3. Read the [usage guide](docs/usage.md) for every kind of proto3 field.

The [documentation map](docs/README.md) lists everything else. To work on the project
itself, see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT, see [LICENSE](LICENSE).
