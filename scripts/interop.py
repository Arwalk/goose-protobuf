#!/usr/bin/env python3
"""Cross-implementation round trips: generated Goose against protoc and Python.

Driven by scripts/interop.sh, which sets up the environment. The corpus is
every <case>.txtpb of tests/roundtrip/<name>/, with the message schema in its
`# proto-message:` line. A `# interop-decode-as: pkg.Msg` line makes Goose read
the bytes as another message, so that what it does not know passes as unknown
fields.

A small Goose echo program (stdin, decode, encode, stdout) is generated for
each <name>. Each case then checks, with P the bytes protoc encodes:

  protoc->goose->protoc  protoc --decode of echo(P) is the text of P.
  goose->protoc->goose   that text, encoded by protoc and echoed again, reads
                         the same. Maps print sorted, so this is order-free.
  python->goose->python  Python parses P and serialises it deterministically,
                         giving Y; Python's reading of echo(Y) serialises to Y.
  goose canonical        echo(Y) == Y byte for byte, unless the case has an
                         interop-decode-as line: Goose keeps fields in number
                         order and maps in the order it read them.

A failure prints the bytes on each side as a hex diff. Exit 1 if any case fails.
"""
import difflib
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from google.protobuf import descriptor_pb2, descriptor_pool, message_factory

ROOT = Path(__file__).resolve().parent.parent
PROTOC = os.environ.get("PROTOC", "protoc")
GOOSE = os.environ.get("GOOSE", "goose")
PLUGIN = os.environ["PLUGIN"]
PROTO_DIR = Path(os.environ.get("PROTO_DIR", ROOT / "tests/protos"))
CASE_DIR = Path(os.environ.get("ROUNDTRIP_DIR", ROOT / "tests/roundtrip"))
# A command put in front of the echo program; the self-test breaks echoes with it.
WRAPPER = os.environ.get("INTEROP_ECHO_WRAPPER")
LIMIT = int(os.environ.get("TEST_TIMEOUT", "120"))


class Mismatch(Exception):
    pass


def run(cmd, data=None, cwd=None):
    """The command's stdout; a failure raises Mismatch with its stderr."""
    try:
        p = subprocess.run(cmd, input=data, cwd=cwd, capture_output=True, timeout=LIMIT)
    except subprocess.TimeoutExpired:
        raise Mismatch(f"timed out: {' '.join(map(str, cmd))}") from None
    if p.returncode != 0:
        err = (p.stderr or p.stdout).decode(errors="replace").strip()
        raise Mismatch(f"exit {p.returncode}: {' '.join(map(str, cmd))}\n{err}")
    return p.stdout


def hex_lines(data):
    return [f"{i:06x}  {data[i:i + 16].hex(' ')}" for i in range(0, len(data), 16)] or ["(empty)"]


def hex_diff(a_name, a, b_name, b):
    first = next((i for i, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
    head = f"{a_name}: {len(a)} bytes; {b_name}: {len(b)} bytes; first difference at offset {first}"
    body = difflib.unified_diff(hex_lines(a), hex_lines(b), a_name, b_name, lineterm="", n=2)
    return "\n".join([head, *body])


def text_diff(a_name, a, b_name, b):
    return "\n".join(difflib.unified_diff(
        a.decode(errors="replace").splitlines(), b.decode(errors="replace").splitlines(),
        a_name, b_name, lineterm="", n=2))


def mangle(segment):
    """A file path segment as decision 0006 names it."""
    s = re.sub(r"\W", "_", segment, flags=re.ASCII)
    return "_" + s if s[0].isdigit() else s


def import_path(proto_file, work):
    """The generated file's import, found on disk: the plugin may have escaped its name."""
    stem = proto_file[:-len(".proto")]
    if proto_file.startswith("google/protobuf/"):
        parts = ["pb_wire", "wkt", stem.split("/")[-1]]
    else:
        parts = [mangle(s) for s in stem.split("/")]
    base = work.joinpath(*parts)
    if not base.with_name(parts[-1] + ".goose").exists():
        parts[-1] += "_"
    return ".".join(parts)


def goose_names(file_set):
    """Maps each message's full name to (its .proto, its Goose name)."""
    names = {}
    def walk(file, prefix, goose, messages):
        for m in messages:
            names[prefix + m.name] = (file, goose + m.name)
            walk(file, prefix + m.name + ".", goose + m.name + "_", m.nested_type)
    for f in file_set.file:
        ns = f.package.replace(".", "_") + "::" if f.package else ""
        walk(f.name, f.package + "." if f.package else "", ns, f.message_type)
    return names


def echo_source(messages, names, work):
    """A program: argv[1] is an index into messages; stdin is decoded and re-encoded."""
    out = ["import os;", "import pb_wire;"]
    out += [f"import {i};" for i in sorted({import_path(names[m][0], work) for m in messages})]
    for i, m in enumerate(messages):
        g = names[m][1]
        out.append(f"""
fn echo{i}(input: const u8[:], out: u8[>..]&) -> i32 {{
    var m = {g} {{ .. }};
    let err = {g}_decode(input, m);
    if err == PB_OK {{ {g}_encode(m, out); }}
    return err;
}}""")
    out.append("""
fn main() {
    var input: u8[>..] = [];
    read_stdin(input);
    var out: u8[>..] = [];
    var which = 0;
    for c in args()[1] { which = which * 10 + (c - '0') as i64; }
    var err = PB_OK;""")
    for i in range(len(messages)):
        out.append(f"    if which == {i} {{ err = echo{i}(input, out); }}")
    out.append("""    if err != PB_OK {
        write_stderr(str("decode error ", err, "\\n"));
        exit(2);
    }
    write_stdout(out);
    flush_stdout();
}""")
    return "\n".join(out) + "\n"


class Interop:
    def __init__(self, name, work):
        self.name = name
        self.work = work
        self.proto = PROTO_DIR / f"{name}.proto"
        self.cases = sorted((CASE_DIR / name).glob("*.txtpb"))
        desc = work / "set"
        run([PROTOC, "--include_imports", f"--descriptor_set_out={desc}",
             f"-I{PROTO_DIR}", self.proto])
        self.file_set = descriptor_pb2.FileDescriptorSet.FromString(desc.read_bytes())
        self.names = goose_names(self.file_set)
        pool = descriptor_pool.DescriptorPool()
        for f in self.file_set.file:
            pool.Add(f)
        self.pool = pool
        self.messages = []

    def header(self, text, key):
        m = re.search(rf"^# {key}: *(\S+)", text, re.M)
        return m.group(1) if m else None

    def build_echo(self):
        for case in self.cases:
            text = case.read_text()
            msg = self.header(text, "proto-message")
            if msg is None:
                raise Mismatch(f"{case.name} has no '# proto-message:' line")
            for m in (msg, self.header(text, "interop-decode-as") or msg):
                if m not in self.names:
                    raise Mismatch(f"{case.name}: no message {m}")
                if m not in self.messages:
                    self.messages.append(m)
        run([PROTOC, f"--plugin=protoc-gen-goose={PLUGIN}", f"--goose_out={self.work}",
             f"-I{PROTO_DIR}", *[f.name for f in self.file_set.file]])
        run([ROOT / "scripts/vendor_runtime.sh", self.work])
        (self.work / "interop_echo.goose").write_text(echo_source(self.messages, self.names, self.work))
        run([GOOSE, "build", "interop_echo.goose", "--debug", "-o", self.work / "echo"], cwd=self.work)

    def echo(self, msg, data):
        cmd = [self.work / "echo", str(self.messages.index(msg))]
        if WRAPPER:
            cmd = [WRAPPER, *cmd]
        return run(cmd, data)

    def decode_text(self, msg, data):
        return run([PROTOC, f"--decode={msg}", f"-I{PROTO_DIR}", self.proto], data)

    def encode_text(self, msg, text):
        return run([PROTOC, f"--encode={msg}", f"-I{PROTO_DIR}", self.proto], text)

    def py_canon(self, msg, data):
        cls = message_factory.GetMessageClass(self.pool.FindMessageTypeByName(msg))
        parsed = cls()
        parsed.ParseFromString(data)
        return parsed.SerializeToString(deterministic=True)

    def check_case(self, case):
        source = case.read_text()
        msg = self.header(source, "proto-message")
        as_msg = self.header(source, "interop-decode-as")
        reader = as_msg or msg

        p = self.encode_text(msg, source.encode())
        text = self.decode_text(msg, p)

        g1 = self.echo(reader, p)
        try:
            text1 = self.decode_text(msg, g1)
        except Mismatch as e:
            raise Mismatch(f"protoc->goose->protoc: protoc cannot read Goose's bytes\n{e}\n"
                           + hex_diff("protoc", p, "goose", g1)) from None
        if text1 != text:
            raise Mismatch("protoc->goose->protoc\n" + text_diff("protoc", text, "goose", text1)
                           + "\n" + hex_diff("protoc", p, "goose", g1))

        p2 = self.encode_text(msg, text1)
        g2 = self.echo(reader, p2)
        text2 = self.decode_text(msg, g2)
        if text2 != text1:
            raise Mismatch("goose->protoc->goose\n" + text_diff("first", text1, "second", text2)
                           + "\n" + hex_diff("protoc", p2, "goose", g2))

        y = self.py_canon(msg, p)
        g3 = self.echo(reader, y)
        try:
            y3 = self.py_canon(msg, g3)
        except Exception as e:
            raise Mismatch(f"python->goose->python: Python cannot read Goose's bytes: {e}\n"
                           + hex_diff("python", y, "goose", g3)) from None
        if y3 != y:
            raise Mismatch("python->goose->python\n" + hex_diff("python", y, "goose", y3))
        if as_msg is None and g3 != y:
            raise Mismatch("goose canonical\n" + hex_diff("python", y, "goose", g3))


def main():
    names = sys.argv[1:] or sorted(d.name for d in CASE_DIR.iterdir() if d.is_dir())
    failed, cases_ok = [], 0
    with tempfile.TemporaryDirectory() as tmp:
        for name in names:
            work = Path(tmp) / name
            work.mkdir()
            try:
                if not (CASE_DIR / name).is_dir():
                    raise Mismatch(f"no directory {CASE_DIR / name}")
                if not (PROTO_DIR / f"{name}.proto").is_file():
                    raise Mismatch(f"no {PROTO_DIR / name}.proto")
                it = Interop(name, work)
                if not it.cases:
                    print(f"skip {name}: no cases")
                    continue
                it.build_echo()
            except Mismatch as e:
                print(f"FAIL {name}: {e}")
                failed.append(name)
                continue
            ok = True
            for case in it.cases:
                try:
                    it.check_case(case)
                    cases_ok += 1
                except Mismatch as e:
                    print(f"FAIL {name}/{case.stem}: {e}")
                    ok = False
            if ok:
                print(f"ok   {name} ({len(it.cases)})")
            else:
                failed.append(name)
    if failed:
        print(f"interop: {len(failed)} failed: {' '.join(failed)}")
        return 1
    print(f"interop: {cases_ok} cases ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
