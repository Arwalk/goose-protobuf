# Releasing

How the project owner cuts version `X.Y.Z`. Only the owner tags and pushes. To decide
which number comes next, see the bump table in
[decision 0012](docs/decisions/0012-public-api.md).

One tag, `vX.Y.Z`, names the plugin, the runtime and the well-known types.

## Prepare

Start from `main`, with `PREV` set to the last tag (skip the steps that compare with
it on the first release).

1. **Fuzz.** CI does not run the fuzzer, so run it by hand:

   ```sh
   scripts/fuzz.sh 3600
   ```

2. **Bump the version check if needed.** See what changed since the last release:

   ```sh
   git diff --stat "$PREV"..HEAD -- runtime/ tests/golden/
   ```

   If this lists anything, the runtime or the generated code changed, so follow
   [Changing the plugin and runtime version
   check](CONTRIBUTING.md#changing-the-plugin-and-runtime-version-check).

3. **Set the version.** In `generator-goose/main.goose`, set `plugin_version` to
   `X.Y.Z`, with no `-dev`.

4. **Finish the changelog.** In [CHANGELOG.md](CHANGELOG.md), turn the top heading into
   `## X.Y.Z (YYYY-MM-DD)`. Check that it lists every breaking change since `PREV`, and
   that its tool and `abi` versions are still right:

   ```sh
   scripts/build_plugin.sh && build/protoc-gen-goose --version
   ```

5. **Name it in the guide.** In [docs/install.md](docs/install.md), the "A git source"
   row and section name the latest release. Set them to `vX.Y.Z`.

6. **Commit and push**, as `chore: Release vX.Y.Z`, and wait for CI to go green on that
   commit, in both the build and the conformance jobs.

## Tag

```sh
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
```

A tag can move, so do not move this one: a mistake found now is fixed by a new patch
release.

## Check the pushed tag

Build a program against the tag from outside the repository, in a clean Goose home:

```sh
cd "$(mktemp -d)"
export GOOSE_HOME="$PWD/goose_home"
git clone --quiet --branch vX.Y.Z --depth 1 https://github.com/Arwalk/goose-protobuf plugin
plugin/scripts/install_plugin.sh "$PWD/prefix"
export PATH="$PWD/prefix/bin:$PATH"
protoc-gen-goose --version
cat > item.proto <<'PROTO'
syntax = "proto3";
message Item { string name = 1; }
PROTO
protoc --goose_out=. item.proto
cat > app.goose <<'APP'
import pb_wire from "Arwalk/goose-protobuf@vX.Y.Z";
import item;

fn main() {
    var a = Item { .. };
    Item_set_name(a, "tea");
    var bytes: u8[>..] = [];
    Item_encode(a, bytes);
    var b = Item { .. };
    if Item_decode(bytes, b) != PB_OK { abort("decode"); }
    print(Item_name(b));
}
APP
goose build app.goose -o app
./app
```

`--version` should print `X.Y.Z`, and the program `tea`.

## Open the next version

1. In `generator-goose/main.goose`, set `plugin_version` to the next version with
   `-dev`, such as `X.Y.(Z+1)-dev`.
2. In [CHANGELOG.md](CHANGELOG.md), add a new top heading for it, marked `(unreleased)`.
3. Commit and push, as `chore: Open version X.Y.(Z+1)`.

The version in the heading can change as the work does: a breaking change or a new
public name raises it, by decision 0012's table.
