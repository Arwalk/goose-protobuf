# Using protoc-gen-goose

`protoc-gen-goose` is a `protoc` plugin. It turns `.proto` files into Goose code
that reads and writes the protobuf binary wire format. This guide takes one
message from a `.proto` file to a running program.

## What you need

- Goose v2026.3 and protoc 27.0 to 36.2. Other versions are untested.
- A C compiler, which `goose build` uses, as for any Goose program.
- A checkout of this repository. The examples expect it next to your project,
  as `../goose-protobuf`.

`scripts/install_toolchain.sh` installs the pinned protoc and Goose into
`.tools/`. [The install guide](install.md) has the details.

Install the plugin from your project's directory. This copies it to `~/.local/bin`,
which must be on your `PATH`:

```sh run
../goose-protobuf/scripts/install_plugin.sh
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
  bytes avatar = 12;
  repeated Address moves = 13;
  map<string, Address> places = 14;
}
```

## Generate the code

```sh run
protoc --goose_out=. people.proto
```

This writes `people.goose`. Output your generated files next to your program's
root file: Goose resolves imports from there, including the ones between
generated files.

[Several proto files](#several-proto-files) shows a directory of protos, and how to
keep generated files in a directory of their own.

## Import the runtime

Generated code uses a small runtime package, `pb_wire`. Only the root file of a
program declares where it comes from. Here it is a checkout:

```goose file=app.goose
import pb_wire from "../goose-protobuf";
import people;
```

There are two other ways to provide it:

- A git source, with the line to write in the
  [install guide](install.md#get-the-runtime).
- A copy next to your root file: run `scripts/vendor_runtime.sh <dir>` from this
  repository and leave out the `from` line, writing `import pb_wire;`.

**Use one version of the plugin and the runtime.** Generated code will not build
against a runtime of another version, and the error names the problem:
`unknown identifier: pb_plugin_and_runtime_versions_differ_abi_1`. Generate again
with the plugin that matches the runtime you import.

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
    people::Person_set_avatar(p, "\x89PNG");

    let home .= people::Person_mutable_home(p);  // creates the sub-message
    people::Address_set_city(home, "London");

    people::Person_add_emails(p, "ada@example.org");
    people::Person_add_scores(p, 10);
    people::Person_add_scores(p, 20);

    let paris .= people::Person_add_moves(p);    // adds a message and returns it
    people::Address_set_city(paris, "Paris");
    let rome .= people::Person_add_moves(p);
    people::Address_set_city(rome, "Rome");

    people::Person_counts_put(p, "visits", 3);

    let work .= people::Person_places_put(p, "work");  // the value, added empty if new
    people::Address_set_city(work, "Oslo");

    people::Person_set_phone(p, "555-0100");     // sets this member of the oneof

    let tenure .= people::Person_mutable_tenure(p);
    tenure.seconds = 60;
}
```

**Bind a message with `.=`, not `=`.** This goes for whatever returns one to fill
in: `_mutable_`, `_add_` of a repeated message and `_put` of a map with message
values, and also for `_at`, `_value_at` and the getter if you will change what they
return. `let paris = ...` makes a copy of the record. Goose accepts it without a
warning, and what you set on the copy never reaches the message.

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

`pb_error_text(err)` gives the meaning of a code as text, for a message to a person.

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

    // Repeated fields: _len counts them and _at reads one. Numbers, bools and
    // enums also have a plain getter, a view of all; strings, bytes and messages
    // do not.
    for i in people::Person_emails_len(p) { print("email ", people::Person_emails_at(p, i)); }
    var total = 0;
    for s in people::Person_scores(p) { total += s; }
    print("total ", total);

    // Repeated messages: _at gives a message, which you read like any other.
    for i in people::Person_moves_len(p) {
        print("moved to ", people::Address_city(people::Person_moves_at(p, i)));
    }

    // Maps: _get gives the value and whether it was found. Entries keep their
    // insertion order; the same key on the wire keeps the place of the first
    // and the value of the last. _len, _key_at and _value_at go through them.
    let visits, found = people::Person_counts_get(p, "visits");
    if found { print("visits ", visits); }
    for i in people::Person_counts_len(p) {
        print(people::Person_counts_key_at(p, i), " = ", people::Person_counts_value_at(p, i));
    }
    for i in people::Person_places_len(p) {
        let place .= people::Person_places_value_at(p, i);
        print(people::Person_places_key_at(p, i), " is in ", people::Address_city(place));
    }

    // A oneof is an ADT in the record field of its name.
    match p.contact {
        phone => { print("phone ", people::Person_phone(p)); },
        office => { print("has an office"); },
        pb_none => { print("no contact"); },
    }
}
```

A view such as `Person_name(p)` is valid until the next change to any message, so
copy what you want to keep with `str(...)` or into your own buffer.
[The generated code reference](generated-code.md) lists every function by kind of
field, and how long what each returns stays valid.

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
        abort(str("decode failed: ", pb_error_text(err)));
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
moved to Paris
moved to Rome
visits 3
visits = 3
work is in Oslo
phone 555-0100
Ada
true
```

This guide uses every kind of field proto3 has. proto2 and editions add `required`,
which `M_is_initialized(m)` checks, `[default]` and groups, all read in the same way.

## Several proto files

A real project has a directory of protos that import each other. Here two files are
under `proto/`, and one imports the other by its path from there:

```sh run
mkdir -p proto/acme/library
```

```proto file=proto/acme/library/author.proto
syntax = "proto3";
package acme.library;

message Author {
  string name = 1;
}
```

```proto file=proto/acme/library/book.proto
syntax = "proto3";
package acme.library;

import "acme/library/author.proto";

message Book {
  string title = 1;
  Author author = 2;
}
```

`-I` names the directory that import paths start from, and each file you pass is named
from there. Pass every file your program needs, including the ones that are only
imported, since `protoc` generates only what you name:

```sh run
protoc -I proto --goose_out=. acme/library/author.proto acme/library/book.proto
```

This writes `acme/library/author.goose` and `acme/library/book.goose`, which must stay
at those paths next to your root file, as `book.goose` says `import acme.library.author;`
and Goose resolves that from the root. Your root file imports what it uses by the same
path. The proto package `acme.library` is the namespace `acme_library`:

```goose file=library.goose
import pb_wire from "../goose-protobuf";
import acme.library.book;

fn main() {
    var book = acme_library::Book { .. };
    acme_library::Book_set_title(book, "Emma");
    acme_library::Author_set_name(acme_library::Book_mutable_author(book), "Jane");
    print(acme_library::Book_title(book));
    acme_library::Book_clear(book);
}
```

```sh run
goose build library.goose -o library
./library
```

```text output
Emma
```

### Generated code in a directory of its own

Passing `--goose_out=gen` and then writing `import gen.acme.library.book;` does not
work: the file's own `import acme.library.author;` would still start from your root
file. Make the directory a package instead, whose imports start from its own root. It
needs an entry file named after it, which imports what your program uses:

```sh run
mkdir gen
protoc -I proto --goose_out=gen acme/library/author.proto acme/library/book.proto
echo 'import .acme.library.book;' > gen/gen.goose
```

Your root file then declares that package, and uses the same namespace as before:

```goose file=library_gen.goose
import pb_wire from "../goose-protobuf";
import gen from "./gen";

fn main() {
    var book = acme_library::Book { .. };
    acme_library::Book_set_title(book, "Persuasion");
    print(acme_library::Book_title(book));
    acme_library::Book_clear(book);
}
```

```sh run
goose build library_gen.goose -o library_gen
./library_gen
```

```text output
Persuasion
```

[The multi-file example](../examples/multi_file/) is a complete program with two proto
packages.

## Next

- [The generated code reference](generated-code.md) lists every function.
- [The examples](../examples/) are complete programs to copy.
- [Troubleshooting](troubleshooting.md) lists error messages and silent mistakes,
  with their fixes.
- [Limitations](limitations.md) lists what is unsupported or slow, and the workarounds.
- [The documentation map](README.md) lists everything else.
