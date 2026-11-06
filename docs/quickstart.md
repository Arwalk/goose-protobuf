# Quickstart

Go from an empty directory to a program that encodes and decodes a protobuf
message. This takes about five minutes, most of it installing tools.

## Set up

You need Goose and `protoc`, at the versions in [the install guide](install.md), and
a C compiler, which `goose build` uses.

Clone [this repository](https://github.com/Arwalk/goose-protobuf), then make an empty directory for your project next to it,
as `../goose-protobuf`. If you do not have the tools, run
`scripts/install_toolchain.sh` in the clone, and put its `.tools/bin` on your `PATH`.

From your project's directory, install the plugin:

```sh run
../goose-protobuf/scripts/install_plugin.sh
```

This copies `protoc-gen-goose` to `~/.local/bin`, where `protoc` finds it. If it
tells you that directory is not on your `PATH`, add it. To put the plugin
somewhere else, give the script a prefix: `install_plugin.sh /usr/local`.

## Write a message

```proto file=hello.proto
syntax = "proto3";
package hello;

message Greeting {
  string text = 1;
  int32 count = 2;
}
```

## Generate the code

```sh run
protoc --goose_out=. hello.proto
```

This writes `hello.goose`, next to where your program goes.

## Write a program

```goose file=app.goose
import pb_wire from "../goose-protobuf";
import hello;

fn main() {
    var greeting = hello::Greeting { .. };
    hello::Greeting_set_text(greeting, "hi");
    greeting.count = 3;

    var bytes: u8[>..] = [];
    hello::Greeting_encode(greeting, bytes);
    hello::Greeting_clear(greeting);

    var back = hello::Greeting { .. };
    let err = hello::Greeting_decode(bytes, back);
    if err != PB_OK { abort(str("decode failed: ", pb_error_text(err))); }
    print(hello::Greeting_text(back), " x ", back.count, " in ", bytes.len, " bytes");
    hello::Greeting_clear(back);
}
```

Strings and bytes live in shared pools, so they have setters and getters, and
plain numbers are record fields. `clear` frees what a message holds.

## Build and run

```sh run
goose build app.goose -o app
./app
```

prints:

```text output
hi x 3 in 6 bytes
```

`goose build` also prints lines of its own progress, such as `parsed ok`, `typechecked ok`,
`bce:` and `wrote`. They are normal, and these guides leave them out.

## Three ways to get the runtime

Generated code imports a small runtime package, `pb_wire`, and only your program's
root file says where it comes from. The first line of `app.goose` is the only thing
that changes.

**A checkout**, as above, is the quickest way to start:
`import pb_wire from "../goose-protobuf";`.

**A git source** has Goose fetch the runtime for you. You still need a checkout at the
same version to get the plugin. The [install guide](install.md#a-git-source) has the
lines to write.

**A copy** next to your program needs no network and no other directory. Copy the
package in, and name it with no source:

```sh run
../goose-protobuf/scripts/vendor_runtime.sh .
sed 's/^import pb_wire from .*/import pb_wire;/' app.goose > app.new
mv app.new app.goose
goose build app.goose -o app
./app
```

prints the same:

```text output
hi x 3 in 6 bytes
```

Whichever you choose, **use one version of the plugin and the runtime**: build the
plugin from the release or commit you import. Otherwise your program will not build,
with an error naming `pb_plugin_and_runtime_versions_differ`.

## Next

[The usage guide](usage.md) takes a full message through every kind of proto3 field:
optional fields, sub-messages, repeated fields, maps, oneofs and decode errors.
[The documentation map](README.md) lists everything else.
