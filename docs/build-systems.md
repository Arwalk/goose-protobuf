# Build systems

Goose has no `protoc` step of its own, so something has to regenerate your code when a
`.proto` file changes. Here is how to do that from Make or from buf, and whether to
commit what they generate.

Both start from a directory of protos and a program, with the plugin installed:

```sh run
../goose-protobuf/scripts/install_plugin.sh
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

```goose file=library.goose
import pb_wire from "../goose-protobuf";
import acme.library.book;

fn main() {
    var book = acme_library::Book { .. };
    acme_library::Book_set_title(book, "Emma");
    print(acme_library::Book_title(book));
    acme_library::Book_clear(book);
}
```

## Make

Generate every file together, since a file's generated code depends on those it imports.
A stamp file records when that last happened:

```make file=Makefile
PROTOS := $(shell find proto -name '*.proto')

library: library.goose generated.stamp
	goose build library.goose -o library

generated.stamp: $(PROTOS)
	protoc -I proto --goose_out=. $(PROTOS:proto/%=%)
	touch generated.stamp

clean:
	rm -rf acme generated.stamp library

.PHONY: clean
```

```sh run
make
./library
```

```text output
Emma
```

Changing a `.proto` file regenerates and rebuilds, and otherwise nothing happens:

```sh run
make -q && echo "nothing to do"
touch proto/acme/library/author.proto
make -q || echo "out of date"
```

```text output
nothing to do
out of date
```

Make cannot see that the plugin changed. After upgrading it, run `make clean` and then
`make`.

## buf

[buf](https://buf.build) compiles protos with its own compiler, so it needs no `protoc`,
and runs the plugin from your `PATH`. The generated files are the same, byte for byte.
Name the proto directory in `buf.yaml`, and the plugin in `buf.gen.yaml`:

```yaml file=buf.yaml
version: v2
modules:
  - path: proto
```

```yaml file=buf.gen.yaml
version: v2
plugins:
  - local: protoc-gen-goose
    out: .
```

```sh run
make clean
buf generate
goose build library.goose -o library
./library
```

```text output
Emma
```

`buf generate` has no record of what changed, so it regenerates everything each time.
To use it from Make, put it in place of the `protoc` line above. `local` runs the plugin
on your machine, which is the only way to run it, as it is not on the Buf Schema
Registry.

## Should you commit generated code?

**Usually not.** Add the generated files to `.gitignore`, and generate them in your
build and CI. Your repository then has one source for each message, and nobody reviews
generated changes. It takes `protoc` and the plugin wherever you build, and they have to
be [the same version as your runtime](versions.md#one-version-for-everything).

**Commit them if whoever builds your program should not need those tools.** The output
is the same bytes for the same input and plugin, so you can check it in CI: regenerate,
then fail on `git diff --exit-code`. Upgrading the plugin then changes every generated
file, in one commit.

**A library is better off shipping its `.proto` files**, and letting each program
generate them, as a program that generates another library's proto as well gets its
types twice.
