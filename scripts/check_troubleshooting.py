#!/usr/bin/env python3
"""Reproduces what docs/troubleshooting.md lists, so its messages are real.

Each case makes the mistake in a new directory, and must print its message. A message
that the page shows must be on the page, word for word. Paths differ between machines,
so each is the part of the message that does not hold one.

Usage: scripts/check_troubleshooting.py [page]
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RUNTIME = f'import pb_wire from "{ROOT}";\n'
PROTO = """syntax = "proto3";
package p;
message Sub { string city = 1; int32 zip = 2; }
message P {
  string name = 1;
  Sub home = 2;
  repeated string tags = 3;
  repeated Sub subs = 4;
  map<string, int32> counts = 5;
  oneof o { string a = 6; int32 b = 7; }
}
"""
A_IMPORTS_B = 'syntax = "proto3";\nimport "b.proto";\nmessage A { B b = 1; }\n'
B = 'syntax = "proto3";\nmessage B {}\n'
PROGRAM = RUNTIME + "import p;\n"

# name, program, message. A program builds in a directory that holds p.proto's code.
PROGRAMS = [
    ("a sub-message bound with =", PROGRAM + """
fn main() {
    var m = p::P { .. };
    let h = p::P_mutable_home(m);
    p::Sub_set_city(h, "x");
    h.zip = 3;
    let r .= p::P_mutable_home(m);
    print("city=[", p::Sub_city(r), "] zip=", r.zip);
}
""", "city=[] zip=0"),
    ("a repeated message bound with =", PROGRAM + """
fn main() {
    var m = p::P { .. };
    let s = p::P_add_subs(m);
    p::Sub_set_city(s, "x");
    s.zip = 3;
    let r .= p::P_subs_at(m, 0);
    print("city=[", p::Sub_city(r), "] zip=", r.zip);
}
""", "city=[] zip=0"),
    ("printing a string's record field", PROGRAM + """
fn main() { var m = p::P { .. }; p::P_set_name(m, "x"); print(m.name); }
""", "pb_Span { 0, 1 }"),
    ("no runtime", "import p;\nfn main() {}\n", "error: cannot find the module pb_wire, looked for"),
    ("a vendored runtime and a package", PROGRAM + "fn main() {}\n",
     "error: pb_wire is both a file of this package (pb_wire.goose) and the declared package pb_wire's module"),
    ("a loop over a repeated string", PROGRAM + """
fn main() { var m = p::P { .. }; for s in p::P_tags(m) { print(s); } }
""", "error: unknown function: p::P_tags"),
    ("a string set as a record field", PROGRAM + """
fn main() { var m = p::P { .. }; m.name = "x"; }
""", "error: expected a value of type pb_Span, got const u8[:]"),
    ("a getter's null not checked", PROGRAM + """
fn main() { var m = p::P { .. }; print(p::Sub_city(p::P_home(m))); }
""", "cannot pass p::Sub? as p::Sub&"),
    ("a type without its namespace", PROGRAM + """
fn main() { var m = P { .. }; }
""", "error: cannot construct a value of type P with a literal"),
    ("a match with no pb_none", PROGRAM + """
fn main() { var m = p::P { .. }; match m.o { a => { print(1); }, b => { print(2); }, } }
""", "error: match does not cover variant P_o.pb_none"),
]
# Not quoted on the page, which describes them: name, program, what it prints.
BEHAVIOUR = [
    ("decoding merges", PROGRAM + """
fn main() {
    var m = p::P { .. };
    p::P_add_tags(m, "x");
    var out: u8[>..] = [];
    p::P_encode(m, out);
    print(p::P_decode(out, m) == PB_OK, " ", p::P_tags_len(m));
}
""", "true 2"),
    ("a record copy shares contents", PROGRAM + """
fn main() {
    var a = p::P { .. };
    p::P_set_name(a, "x");
    let b = a;
    p::P_clear(a);
    p::P_set_name(a, "y");
    print(p::P_name(b));
}
""", "y"),
    ("append leaves repeated keys until fold_maps", PROGRAM + """
fn main() {
    var m = p::P { .. };
    p::P_counts_append(m, "k", 1);
    p::P_counts_append(m, "k", 2);
    print(p::P_counts_len(m));
    p::P_fold_maps(m);
    print(p::P_counts_len(m), " ", p::P_counts_value_at(m, 0));
}
""", "2\n1 2"),
]
# name, files, protoc arguments, message.
PROTOC = [
    ("an output directory that does not exist", {"p.proto": PROTO}, ["--goose_out=gen", "p.proto"],
     "gen/: No such file or directory"),
    ("an import not found", {"i.proto": 'syntax = "proto3";\nimport "missing.proto";\n'}, ["--goose_out=.", "i.proto"],
     "missing.proto: File not found."),
    ("edition 2026", {"e.proto": 'edition = "2026";\nmessage E {}\n'}, ["--goose_out=.", "e.proto"],
     "is a file using edition 2026, which isn't supported by code generator protoc-gen-goose."),
    ("two names that map to one", {"c.proto": 'syntax = "proto3";\nmessage A { message B {} }\nmessage A_B {}\n'},
     ["--goose_out=.", "c.proto"], "both map to the Goose name A_B"),
    ("an unknown parameter", {"p.proto": PROTO}, ["--goose_out=foo:.", "p.proto"], "--goose_out: unknown parameter: foo"),
]


def run(args, cwd, env):
    p = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True, timeout=300)
    return p.returncode, p.stdout + p.stderr


class Checker:
    def __init__(self, page, tmp, env):
        self.page, self.tmp, self.env = page, Path(tmp), env
        self.problems = []
        self.count = 0

    def new_dir(self, files):
        self.count += 1
        d = self.tmp / f"case{self.count}"
        d.mkdir()
        for name, text in files.items():
            (d / name).write_text(text)
        return d

    def expect(self, name, output, message, quoted=True):
        if message not in output:
            self.problems.append(f"{name}: no longer prints '{message}':\n{output}")
        if quoted and message not in self.page:
            self.problems.append(f"{name}: the page does not show '{message}'")

    def build(self, program):
        """Builds program next to the code of PROTO. Its directory, and the output of the build and program."""
        d = self.new_dir({"p.proto": PROTO, "t.goose": program})
        code, out = run(["protoc", "--goose_out=.", "p.proto"], d, self.env)
        if code != 0:
            self.problems.append(f"protoc failed: {out}")
        return d, *self.build_in(d)

    def build_in(self, d):
        code, out = run(["goose", "build", "t.goose", "-o", "t"], d, self.env)
        if code == 0:
            _, printed = run(["./t"], d, self.env)
            out += printed
        return code, out

    def programs(self):
        for name, program, message in PROGRAMS:
            if "vendored" in name:
                vendor = self.new_dir({})
                run([str(ROOT / "scripts/vendor_runtime.sh"), str(vendor)], ROOT, self.env)
                d, _, _ = self.build(program)
                shutil.copytree(vendor, d, dirs_exist_ok=True)
                _, out = self.build_in(d)
            else:
                _, _, out = self.build(program)
            self.expect(name, out, message)
        for name, program, printed in BEHAVIOUR:
            _, _, out = self.build(program)
            self.expect(name, out, printed + "\n", quoted=False)

    def generated_import(self):
        d = self.new_dir({"a.proto": A_IMPORTS_B, "b.proto": B})
        (d / "gen").mkdir()
        run(["protoc", "--goose_out=gen", "a.proto", "b.proto"], d, self.env)
        (d / "t.goose").write_text(RUNTIME + "import gen.a;\nfn main() {}\n")
        _, out = self.build_in(d)
        self.expect("generated files in a directory of their own", out, "error: cannot find the module b, looked for")

    def version_mismatch(self):
        d, _, _ = self.build(PROGRAM + "fn main() {}\n")
        generated = d / "p.goose"
        text = generated.read_text()
        name = "pb_plugin_and_runtime_versions_differ_abi_"
        if name not in text:
            self.problems.append("generated code no longer has the version check")
        generated.write_text(text.replace(name, name + "0"))
        _, out = self.build_in(d)
        self.expect("a plugin of another version", out, "error: unknown identifier: " + name)

    def no_plugin(self):
        env = dict(self.env)
        env["PATH"] = os.pathsep.join(p for p in env["PATH"].split(os.pathsep) if p != self.env["PLUGIN_DIR"])
        _, out = run(["protoc", "--goose_out=.", "p.proto"], self.new_dir({"p.proto": PROTO}), env)
        self.expect("no plugin on the PATH", out, "protoc-gen-goose: program not found or is not executable")

    def protoc(self):
        for name, files, args, message in PROTOC:
            _, out = run(["protoc", *args], self.new_dir(files), self.env)
            self.expect(name, out, message)


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs/troubleshooting.md"
    subprocess.run([str(ROOT / "scripts/build_plugin.sh")], check=True, capture_output=True)
    with tempfile.TemporaryDirectory() as tmp:
        plugin_dir = Path(tmp) / "plugin"
        plugin_dir.mkdir()
        shutil.copy(ROOT / "build/protoc-gen-goose", plugin_dir)
        env = dict(os.environ)
        # Only the copy above: a plugin the user installed must not hide a mistake.
        path_dirs = [d for d in env["PATH"].split(os.pathsep) if not (Path(d) / "protoc-gen-goose").exists()]
        tools = ROOT / ".tools/bin"
        env["PATH"] = os.pathsep.join([*([str(tools)] if tools.is_dir() else []), str(plugin_dir), *path_dirs])
        env["PLUGIN_DIR"] = str(plugin_dir)
        env["HOME"] = tmp
        env.pop("GOOSE_HOME", None)
        checker = Checker(path.read_text(), tmp, env)
        checker.programs()
        checker.generated_import()
        checker.version_mismatch()
        checker.no_plugin()
        checker.protoc()
    for problem in checker.problems:
        print(f"FAIL {problem}")
    if checker.problems:
        return 1
    print(f"ok   {path.name}: {checker.count} cases")
    return 0


if __name__ == "__main__":
    sys.exit(main())
