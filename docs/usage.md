# Using protoc-gen-goose

`protoc-gen-goose` is a `protoc` plugin. It turns `.proto` files into Goose code
that reads and writes the protobuf binary wire format. This guide takes one
message from a `.proto` file to a running program.

`scripts/check_docs.py` runs this guide: it builds the program below from the
blocks in this file, runs the commands, and compares the output, so what you
read here works. CI does this on every push.

## What you need

- Goose v2026.3 and protoc 36.2. Other versions are untested.
- A C compiler, which `goose build` uses, as for any Goose program.
- A checkout of this repository. The examples expect it next to your project,
  as `../goose-protobuf`.

`scripts/install_toolchain.sh` installs the pinned protoc and Goose into
`.tools/`. [TOOLCHAIN.md](../TOOLCHAIN.md) has the details.

Build the plugin from your project's directory:

```sh run
../goose-protobuf/scripts/build_plugin.sh
```

## Write a proto

```proto file=people.proto
syntax = "proto3";

package people;

import "google/protobuf/duration.proto";

enum Role {
  ROLE_UNSPECIFIED = 0;
  ROLE_ADMIN = 1;
}

message Address {
  string city = 1;
}

message Person {
  string name = 1;
  int32 age = 2;
  optional int32 height = 3;
  Role role = 4;
  Address home = 5;
  repeated string emails = 6;
  repeated int32 scores = 7;
  map<string, int32> counts = 8;
  oneof contact {
    string phone = 9;
    Address office = 10;
  }
  google.protobuf.Duration tenure = 11;
}
```

## Generate the code

```sh run
protoc --plugin=protoc-gen-goose=../goose-protobuf/build/protoc-gen-goose \
       --goose_out=. -I . people.proto
```

This writes `people.goose`. Output your generated files next to your program's
root file: Goose resolves imports from there, including the ones between
generated files.

## Import the runtime

Generated code uses a small runtime package, `pb_wire`. Only the root file of a
program declares where it comes from. Here it is a checkout:

```goose file=app.goose
import pb_wire from "../goose-protobuf";
import people;
```

There are two other ways to provide it:

- A git source: `import pb_wire from "owner/repo@vX.Y.Z";`. Pin a commit if the
  build must be reproducible, since a tag can move.
- A copy next to your root file: run `scripts/vendor_runtime.sh <dir>` from this
  repository and leave out the `from` line, writing `import pb_wire;`.

**Keep the plugin and the runtime on the same version.** Nothing checks this. A
mismatch is a compile error if a `pb_` name changed, and otherwise goes unnoticed.

### Well-known types

The well-known types come with `pb_wire`, already generated, and need no protoc
step: `any`, `duration`, `empty`, `field_mask`, `struct`, `timestamp` and
`wrappers`. The generated `people.goose` imports `pb_wire.wkt.duration` for you.
A file with no such field that uses a well-known type itself imports it the same
way, with `struct.proto` as `pb_wire.wkt.struct_`. Their types are in the namespace
`google_protobuf`, as `google_protobuf::Duration`.

## Build a message

A package becomes a namespace, with dots turned into underscores, so
`foo.bar` is `foo_bar::`. A nested message `Outer.Inner` is `Outer_Inner`. Enum
values are `i32` constants named after the enum and the value. Functions are
named `<Message>_<operation>`.

Messages are records whose variable-size contents live in shared pools, so make
one with `{ .. }` and clear it when you are done:

```goose file=app.goose
fn build(p: people::Person&) {
    people::Person_set_name(p, "Ada");       // strings and bytes have setters
    p.age = 36;                              // plain scalars are record fields
    p.role = people::Role_ROLE_ADMIN;

    people::Person_set_height(p, 170);       // `optional` has set_, has_, clear_

    let home .= people::Person_mutable_home(p);  // creates the sub-message
    people::Address_set_city(home, "London");

    people::Person_add_emails(p, "ada@example.org");
    people::Person_add_scores(p, 10);
    people::Person_add_scores(p, 20);

    people::Person_counts_put(p, "visits", 3);

    people::Person_set_phone(p, "555-0100");     // sets this member of the oneof

    let tenure .= people::Person_mutable_tenure(p);
    tenure.seconds = 60;
}
```

**Bind a sub-message with `.=`, not `=`.** `let home = ...` makes a copy of the
record. Goose accepts it without a warning, and what you set on the copy never
reaches the message.

## Encode

```goose file=app.goose
fn encode(p: people::Person&) -> u8[>..] {
    var out: u8[>..] = [];
    people::Person_encode(p, out);           // appends to out
    return out;
}
```

`Person_size_of(p)` gives the encoded size without encoding.

## Decode

`Person_decode(bytes, m)` merges the bytes into `m`, as protobuf's merge does, and
returns `PB_OK` or an error code. After an error `m` holds part of a message, so
clear it.

| Code | Meaning |
|---|---|
| `PB_ERR_TRUNCATED` | the input ends inside a value, or a length overruns it |
| `PB_ERR_MALFORMED` | a bad varint, wire type or field number |
| `PB_ERR_DEPTH` | messages nested deeper than `PB_MAX_DEPTH` (100) |
| `PB_ERR_UTF8` | a string field that must be UTF-8 and is not |
| `PB_ERR_REQUIRED` | a proto2 required field is unset |

The input must not be a view of a message's contents, as decoding allocates in
the pool that holds them. Copy such bytes into a buffer of their own first.

## Read a message

```goose file=app.goose
fn show(p: people::Person&) {
    print(people::Person_name(p), " is ", p.age);

    // Fields that track presence.
    if people::Person_has_height(p) { print("height ", p.height); }
    let home .= people::Person_home(p);      // null if there is none
    guard home else { return; }
    print("city ", people::Address_city(home));

    // Repeated fields: _at reads one, and the plain getter is a view of all.
    print("email ", people::Person_emails_at(p, 0));
    var total = 0;
    for s in people::Person_scores(p) { total += s; }
    print("total ", total);

    // Maps: _get gives the value and whether it was found. Entries keep their
    // insertion order; the same key on the wire keeps the place of the first
    // and the value of the last.
    let visits, found = people::Person_counts_get(p, "visits");
    if found { print("visits ", visits); }

    // A oneof is an ADT in the record field of its name.
    match p.contact {
        phone => { print("phone ", people::Person_phone(p)); },
        office => { print("has an office"); },
        pb_none => { print("no contact"); },
    }
}
```

A view such as `Person_name(p)` is valid until the next change to any message:
changes may move the pool under it. Copy what you want to keep with `str(...)` or
into your own buffer.

An unset field reads as its default. A field the message does not know is kept
and written back by `encode`, after the known fields.

## Put it together

```goose file=app.goose
fn main() {
    var p = people::Person { .. };
    build(p);
    let bytes = encode(p);
    print(bytes.len == people::Person_size_of(p));
    people::Person_clear(p);                 // frees what the message holds

    var q = people::Person { .. };
    let err = people::Person_decode(bytes, q);
    if err != PB_OK {
        people::Person_clear(q);
        abort(str("decode error ", err));
    }
    show(q);

    // A deep copy. Assigning a record would share its contents.
    var r = people::Person { .. };
    people::Person_copy(r, q);
    people::Person_clear(q);
    print(people::Person_name(r));
    people::Person_clear(r);

    let cut = bytes[0..bytes.len - 1];
    var t = people::Person { .. };
    print(people::Person_decode(cut, t) == PB_ERR_TRUNCATED);
    people::Person_clear(t);
}
```

```sh run
goose build app.goose -o app
./app
```

prints:

```text output
true
Ada is 36
height 170
city London
email ada@example.org
total 30
visits 3
phone 555-0100
Ada
true
```

## Limitations

- Binary wire format only. There is no JSON or text format, no reflection, and
  no services or RPC.
- proto2, proto3 and editions up to 2023.
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
- One run of values is limited to 2^32 elements.

## Working on this repository

The protobuf submodule, which only the conformance tests use, is left out of a
plain `git submodule update --init`, so that package users do not fetch it. Use
`git submodule update --init --checkout`. [AGENTS.md](../AGENTS.md) lists the
build and test commands. Design decisions are in [docs/decisions/](decisions/).
