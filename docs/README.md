# Documentation map

Every document here is written for one reader, and every fact has one home. Find
your reader below. If you are adding to the docs, the second table says where the
text goes. A document marked *planned* does not exist yet.

## Who reads what

### Using the plugin

| Document | Read it to |
|---|---|
| [README](../README.md) | Decide whether this project fits: what it does, its scope, a short sample |
| [docs/install.md](install.md) | Install the tools and the plugin, and get the runtime |
| [docs/quickstart.md](quickstart.md) | Get from an empty directory to a round trip in five minutes |
| [docs/usage.md](usage.md) | Learn the whole path on a real message: build, encode, decode, read |
| [docs/generated-code.md](generated-code.md) | Look up an accessor, a naming rule or a view's lifetime |
| [docs/limitations.md](limitations.md) | Check what is unsupported or slow, and the workaround |
| [docs/troubleshooting.md](troubleshooting.md) | Fix a compiler or `protoc` error you have in front of you |
| `docs/build-systems.md` *(planned)* | Regenerate code from Make or buf |
| `docs/benchmarks.md` *(planned)* | See how fast encoding and decoding are |
| [examples/](../examples/) | Start from a complete program |
| `CHANGELOG.md` *(planned)* | See what changed between versions |
| `SECURITY.md` *(planned)* | Report a problem, or decode untrusted input safely |

### Working on the project

| Document | Read it to |
|---|---|
| [CONTRIBUTING.md](../CONTRIBUTING.md) | Build and test the project, find your way around it, and commit |
| [TOOLCHAIN.md](../TOOLCHAIN.md) | See which version of each tool is pinned, why, and how to change a pin |
| [docs/decisions/](decisions/) | Understand why a design is the way it is |
| `RELEASING.md` *(planned)* | Cut a release (project owner) |

### Agents

| Document | Read it to |
|---|---|
| [AGENTS.md](../AGENTS.md) | Follow the rules that apply only to agents, such as the beads workflow |
| [CLAUDE.md](../CLAUDE.md) | Nothing of its own: it points to AGENTS.md |

## Where each fact lives

| Fact | Home |
|---|---|
| What the project is and why | README |
| Scope, as a summary (formats, syntaxes) | README |
| Tested tool versions for users, platforms, C compiler | `docs/install.md` |
| Installing the plugin; the three ways to get the runtime | `docs/install.md` |
| Importing and using generated code, step by step | `docs/usage.md` |
| Accessors, naming rules, pools, view lifetimes | `docs/generated-code.md` |
| Each limitation, its cost and workaround | `docs/limitations.md` |
| Error messages and their fixes, including `=` against `.=` | `docs/troubleshooting.md` |
| Generator and runtime versions of each release | `CHANGELOG.md` |
| What is public, and the version rules | [Decision 0012](decisions/0012-public-api.md) |
| Reporting a vulnerability; depth and memory limits | `SECURITY.md` |
| Measured performance | `docs/benchmarks.md` |
| Build, test, golden, round-trip, interop, conformance and fuzz commands | `CONTRIBUTING.md` |
| Repository layout, the protobuf submodule | `CONTRIBUTING.md` |
| Commit format and the rules on test-first fixes, failure lists and regenerating bindings | `CONTRIBUTING.md` |
| Goose pitfalls when writing the generator or runtime | `CONTRIBUTING.md` |
| Pinned versions and checksums, how to change one, what the conformance runner needs | `TOOLCHAIN.md` (checksums in `scripts/install_toolchain.sh`) |
| Why a design was chosen | `docs/decisions/` |
| The release procedure | `RELEASING.md` |
| Beads workflow; who handles the remote, pushes and tags | `AGENTS.md` |

## Rules for writing here

- **One home.** Another document may quote a fact in a sentence, such as a version
  number, and link its home. It does not explain it again. A pin change updates
  the quotes too.
- **Users' documents speak to users.** They carry no bead ids, project phases or
  conformance details, and they do not assume a checkout's internal layout beyond
  the commands they give.
- **What a guide says runs.** A guide with commands is run by
  `scripts/check_docs.py` in CI, so its output is what you would see.
- **Decisions are history.** A record is not rewritten when it stops holding. It
  is marked as superseded, and the current fact lives in its home above.
- **A new document goes in this map** in the commit that adds it, and a planned
  entry becomes a link in the same way.
