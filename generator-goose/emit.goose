// Goose emitter: turns one FileDescriptorProto into one .goose file.
//
// Port of generator/src/emit.zig, function for function and with its names, which
// is what makes a diff between the two easy to reason about. A field `f` of a
// message comes in as a reference, an optional as a null, and an optional string
// as an empty one; each of those is said where it is declared. The name rules are
// final, docs/decisions/0006-naming.md; user code depends on them:
//   - package `a.b`        -> `namespace a_b;` (no package: global namespace)
//   - message `Outer.Inner` -> struct `Outer_Inner`
//   - enum value `RED` of enum `Outer.Color` -> `let Outer_Color_RED: i32`
//     (Goose enums have no discriminants, so protobuf enums are i32
//     constants; aliases are separate constants with the same value)
//   - generated functions and globals are `<path>_<op>`, built from the
//     unescaped path (`Node_decode`, `Node_set_name`, `Node_pool`)
//   - a final name on the reserved list (keyword, builtin, `pb_`/`PB_`
//     prefix) gets a trailing `_` (`message type` -> `type_`;
//     `struct.self` -> `struct_self`; `message pb_x` -> `pb_x_`)
//   - a nested type or enum constant whose name is a generated name gets
//     a trailing `_` (`Outer.decode` -> `Outer_decode_`)
// Every generated name is claimed before any type or constant. Two
// declarations that still end up with the same name are an error,
// reported through CodeGeneratorResponse.error.
//
// Output order follows the descriptor (protoc's declaration order), so the
// same request always yields the same bytes.

import std;
import pb_wire;
import google.protobuf.compiler.plugin;
import google.protobuf.descriptor;
import features;
import support;
import float_text;

type Request = google_protobuf_compiler::CodeGeneratorRequest;

// The request, a global as its record is large. It does not change once it is
// decoded, so the views and references taken from it stay valid.
var request = Request { .. };

// What holds for the whole request, whichever file is being generated, so that a
// file and what it imports are each worked out once. See indexRequest.
var request_indexed = false;
// Full name of a message -> the index of its file in proto_file.
var message_files: u32 = 0;
// Full name of an enum -> its index in enum_infos.
var enum_index: u32 = 0;
// Proto name of a file whose names are claimed -> its index in file_emitters.
var claimed_files: u32 = 0;
// Full name of a message -> what holdsRequired and holdsMaps have found.
var required_answers: u32 = 0;
var maps_answers: u32 = 0;

// The text of the files generated so far: `w` of the Zig emitter. The response
// keeps a copy of each, so the plugin holds its output twice. It cannot shrink, as
// a global may hold a reference into a grow-only array.
var w: u8[>..] = [];

// Goose keywords and contextual keywords (Goose reference, Appendix A).
const goose_keywords = [
    "import", "namespace", "struct", "enum", "type", "fn", "thread_fn",
    "export", "simd", "recursive", "let", "var", "extern", "const",
    "pad", "reusable", "if", "else", "while", "for", "in",
    "loop", "block", "guard", "match", "return", "break", "continue",
    "as", "true", "false", "null", "self", "bool", "varint",
    "i8", "i16", "i32", "i64", "u8", "u16", "u32",
    "u64", "f32", "f64", "from", "upto", "inline", "checkfree",
    "fields", "types",
];

fn isGooseKeyword(name: const u8[:]) -> bool {
    for k in goose_keywords {
        if k == name { return true; }
    }
    return false;
}

// Goose builtins (Goose reference, section 25).
const goose_builtins = [
    "print", "str", "format", "assert",
    "abort", "exit", "copy", "default",
    "hardware_threads", "thread_spawn", "thread_spawn_contained", "thread_wait",
    "qput", "qget", "qpoll", "qlimit",
    "to_bytes", "bytes_of", "from_bytes", "embed_file",
    "embed_shader",
];

fn startsWith(s: const u8[:], prefix: const u8[:]) -> bool {
    return s.len >= prefix.len && s[..prefix.len] == prefix;
}

fn endsWith(s: const u8[:], suffix: const u8[:]) -> bool {
    return s.len >= suffix.len && s[s.len - suffix.len..] == suffix;
}

// True for names a generated declaration may not take as they are:
// Goose keywords and builtins, and the `pb_`/`PB_` prefixes of the
// pb_wire runtime (`pb_Span`, `PB_ERR_TRUNCATED`).
fn isReserved(name: const u8[:]) -> bool {
    if isGooseKeyword(name) { return true; }
    for b in goose_builtins {
        if b == name { return true; }
    }
    return startsWith(name, "pb_") || startsWith(name, "PB_");
}

// `name`, with a trailing `_` if it is reserved.
fn ident(name: const u8[:]) -> const u8[:] {
    if isReserved(name) { return keep(str(name, "_")); }
    return name;
}

// `a.b.c` -> `a_b_c`, escaped if the result is a keyword.
fn namespaceName(package: const u8[:]) -> const u8[:] {
    var t: u8[>..] = [];
    for c in package { t.push(if c == '.' { '_' } else { c }); }
    return ident(keep(t));
}

// The unescaped path of a nested declaration: `prefix_name`, or `name` at
// the top level. Its Goose name is ident() of it.
fn nestedPath(prefix: const u8[:], name: const u8[:]) -> const u8[:] {
    if prefix.len == 0 { return name; }
    return keep(str(prefix, "_", name));
}

// Operations and globals generated for every message, as `<path>_<op>`
// (decisions 0001 and 0004: codecs, `M_copy`, the `M_Ref` link, the pools).
const message_ops = [
    "decode", "decode_from", "encode", "size_of", "clear", "copy", "is_initialized", "fold_maps", "Ref", "pool", "links",
];

// What a map entry message has besides: its pool of runs (decision 0001) and
// the helpers of the map field that uses it.
const map_entry_ops = ["entries", "find", "slot", "place", "fold"];

// How a field is stored, which decides its accessors.
let KIND_SCALAR = 0;
let KIND_ONEOF_SCALAR = 1;
let KIND_STRING = 2;
let KIND_MESSAGE = 3;
let KIND_REPEATED = 4;
let KIND_REPEATED_MESSAGE = 5;
let KIND_MAP = 6;

// One accessor of a field: `<path>_<prefix><field><suffix>`.
struct Accessor { prefix: const u8[:], suffix: const u8[:] }

const get_acc = Accessor { prefix: "", suffix: "" };
const set_acc = Accessor { prefix: "set_", suffix: "" };
const has_acc = Accessor { prefix: "has_", suffix: "" };
const clear_acc = Accessor { prefix: "clear_", suffix: "" };
const mutable_acc = Accessor { prefix: "mutable_", suffix: "" };
const at_acc = Accessor { prefix: "", suffix: "_at" };
const add_acc = Accessor { prefix: "add_", suffix: "" };
const map_get_acc = Accessor { prefix: "", suffix: "_get" };
const map_put_acc = Accessor { prefix: "", suffix: "_put" };
const map_remove_acc = Accessor { prefix: "", suffix: "_remove" };
// The global holding a string or bytes field's [default], which is not empty.
const default_acc = Accessor { prefix: "", suffix: "_default" };

const accessors_scalar_presence: Accessor[3] = [set_acc, has_acc, clear_acc];
const accessors_oneof_scalar: Accessor[4] = [get_acc, set_acc, has_acc, clear_acc];
const accessors_string: Accessor[2] = [get_acc, set_acc];
const accessors_message: Accessor[4] = [get_acc, mutable_acc, has_acc, clear_acc];
const accessors_repeated: Accessor[5] = [get_acc, at_acc, add_acc, set_acc, clear_acc];
const accessors_repeated_message: Accessor[4] = [get_acc, at_acc, add_acc, clear_acc];
const accessors_map: Accessor[5] = [get_acc, map_get_acc, map_put_acc, map_remove_acc, clear_acc];

// The accessors generated for a field. This table is the one source of
// truth for accessor names: the emitters of each field kind use it, and
// the collision check claims every name in it. Scalars are read
// directly (`m.id`); without presence they are also written directly
// (`m.id = 5`), so they have none. A scalar with presence is written
// with `set_`, which also sets its has-bit.
fn fieldAccessors(kind: i64, presence: bool) -> const Accessor[:] {
    return match kind {
        KIND_SCALAR => if presence { accessors_scalar_presence[..] } else { accessors_scalar_presence[..0] },
        KIND_ONEOF_SCALAR => accessors_oneof_scalar[..],
        KIND_STRING => if presence { accessors_oneof_scalar[..] } else { accessors_string[..] },
        KIND_MESSAGE => accessors_message[..],
        KIND_REPEATED => accessors_repeated[..],
        KIND_REPEATED_MESSAGE => accessors_repeated_message[..],
        _ => accessors_map[..],
    };
}

// The Goose name of a generated function or global of the message at
// `path` (unescaped): `<path>_<op>`, escaped if reserved.
fn generatedName(path: const u8[:], op: const u8[:]) -> const u8[:] {
    return ident(keep(str(path, "_", op)));
}

// The Goose name of accessor `acc` of field `field` of the message at
// `path` (unescaped).
fn accessorName(path: const u8[:], field: const u8[:], acc: Accessor) -> const u8[:] {
    return ident(keep(str(path, "_", acc.prefix, field, acc.suffix)));
}

fn isAlpha(c: u8) -> bool { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
fn isDigit(c: u8) -> bool { return c >= '0' && c <= '9'; }

// The output file of a .proto, which `import a.b.c;` loads as a/b/c.goose:
// `api/foo.v1.proto` -> `api/foo_v1.goose`. In each path segment, whatever
// an identifier cannot hold becomes `_`, a leading digit gets a `_` before
// it, and a reserved result is escaped.
fn outputName(proto_name: const u8[:]) -> const u8[:] {
    let stem = if endsWith(proto_name, ".proto") { proto_name[..proto_name.len - 6] } else { proto_name };
    var out: u8[>..] = [];
    var start = 0;
    loop {
        var end = start;
        while end < stem.len && stem[end] != '/' { end += 1; }
        var mangled: u8[>..] = [];
        for c in stem[start..end] {
            mangled.push(if isAlpha(c) || isDigit(c) || c == '_' { c } else { '_' });
        }
        if mangled.len > 0 && isDigit(mangled[0]) { out.push('_'); }
        out.append(ident(keep(mangled)));
        if end == stem.len { break; }
        out.push('/');
        start = end + 1;
    }
    out.append(".goose");
    return keep(out);
}

// The well-known types with special semantics, such as a JSON form of their
// own. Their bindings ship in the pb_wire package, under wkt/, so that one
// copy exists to attach those semantics to (decision 0007). Other files of
// google/protobuf/ are ordinary protos.
const well_known_files = [
    "google/protobuf/any.proto",
    "google/protobuf/duration.proto",
    "google/protobuf/empty.proto",
    "google/protobuf/field_mask.proto",
    "google/protobuf/struct.proto",
    "google/protobuf/timestamp.proto",
    "google/protobuf/wrappers.proto",
];

fn isWellKnown(file: FileDesc&) -> bool {
    if filePackage(file) != "google.protobuf" { return false; }
    for name in well_known_files {
        if fileName(file) == name { return true; }
    }
    return false;
}

// A well-known type's file in this repository, which `import pb_wire.wkt.x;`
// loads: `google/protobuf/any.proto` -> `wkt/any.goose`.
fn wellKnownOutputName(proto_name: const u8[:]) -> const u8[:] {
    var base = 0;
    for i in proto_name.len {
        if proto_name[i] == '/' { base = i + 1; }
    }
    return keep(str("wkt/", outputName(proto_name[base..])));
}

// How a generated file imports the file generated from `file`. Goose resolves
// it from the root file's directory, or for pb_wire from the package.
fn importPath(file: FileDesc&) -> const u8[:] {
    let proto_name = fileName(file);
    let well_known = isWellKnown(file);
    let out = if well_known { wellKnownOutputName(proto_name) } else { outputName(proto_name) };
    var path: u8[>..] = [];
    if well_known { path.append("pb_wire."); }
    for c in out[..out.len - 6] { path.push(if c == '/' { '.' } else { c }); }
    return keep(path);
}

// A message: stored fields hold it by reference.
struct MessageInfo {
    desc: MessageDesc&,
    // The unescaped path generated names are built from.
    path: const u8[:],
    // Its Goose name, as the file being generated writes it.
    goose_name: const u8[:],
    // What its names are written with: `ns::`, or nothing in its own namespace.
    ns: const u8[:],
    // How the file being generated imports it, if it is in another file.
    import_path: const u8[:],
    // The file that declares it.
    file: FileDesc&,
    // What its fields and nested types inherit.
    features: Features,
}

// Message infos, which maps refer to by index.
var message_infos: MessageInfo[>..] = [];

fn infoOf(e: MapEntry&) -> MessageInfo& { return message_infos[e.index]; }

// An enum, and whether its features close it.
struct EnumInfo {
    desc: EnumDesc&,
    closed: bool,
}

var enum_infos: EnumInfo[>..] = [];

// The size class of a scalar: `size: union(enum)` of the Zig emitter.
let SZ_VARINT = 0;
let SZ_FIXED = 1;
let SZ_BYTES = 2;
let SZ_MESSAGE = 3;

// How one scalar type is stored, read, written and sized. In the
// templates, `$` stands for the value (`m.<field>`).
struct Scalar {
    goose: const u8[:],
    wire: i64,
    // Statement resetting the value to the default, freeing what it owns.
    clear: const u8[:],
    // Decode expression, reading from `r` (`$` is the old value).
    read: const u8[:],
    // Encode statement, writing the value (tag already written) to `out`.
    write: const u8[:],
    // True if the value is not the default (implicit presence: only then
    // is it encoded). Floats compare bits, so -0.0 is encoded.
    nonzero: const u8[:],
    size: i64,
    // Its size, when size is SZ_FIXED.
    fixed: i64 = 0,
    // For varints: the u64 written, whose pb_varint_size is the size.
    write_value: const u8[:] = "",
    // The parameter type of set_, and its statement storing `v`.
    set_type: const u8[:] = "",
    set: const u8[:] = "$ = v",
}

// The default value of a numeric or bool type.
fn sc_zero(sc: Scalar&) -> const u8[:] {
    if sc.goose == "bool" { return "false"; }
    if sc.goose[0] == 'f' { return "0.0"; }
    return "0";
}

fn sc_setType(sc: Scalar&) -> const u8[:] {
    return if sc.set_type.len > 0 { sc.set_type } else { sc.goose };
}

// The pb_wire pool of a repeated field of this type (decision 0001).
fn sc_pool(sc: Scalar&) -> const u8[:] {
    if sc.goose == "i32" { return "pb_i32s"; }
    if sc.goose == "i64" { return "pb_i64s"; }
    if sc.goose == "u32" { return "pb_u32s"; }
    if sc.goose == "u64" { return "pb_u64s"; }
    if sc.goose == "f32" { return "pb_f32s"; }
    if sc.goose == "f64" { return "pb_f64s"; }
    if sc.goose == "bool" { return "pb_bools"; }
    if sc.goose == "pb_Span" { return "pb_spans"; }
    abort(str("no pool for ", sc.goose));
}

fn varintScalar(goose: const u8[:], read: const u8[:], write: const u8[:], value: const u8[:]) -> Scalar {
    return Scalar { goose: goose, wire: 0, clear: "$ = 0", read: read, write: write, nonzero: "$ != 0", size: SZ_VARINT, write_value: value };
}

let sc_int32 = varintScalar("i32", "pb_u64_to_int32(pb_read_varint(r))", "pb_write_varint(out, pb_int32_to_u64($))", "pb_int32_to_u64($)");
let sc_int64 = varintScalar("i64", "pb_u64_to_int64(pb_read_varint(r))", "pb_write_varint(out, pb_int64_to_u64($))", "pb_int64_to_u64($)");
let sc_uint32 = varintScalar("u32", "pb_read_varint(r) as! u32", "pb_write_varint(out, $)", "$");
let sc_uint64 = varintScalar("u64", "pb_read_varint(r)", "pb_write_varint(out, $)", "$");
let sc_sint32 = varintScalar("i32", "pb_unzigzag32(pb_read_varint(r) as! u32)", "pb_write_varint(out, pb_zigzag32($))", "pb_zigzag32($)");
let sc_sint64 = varintScalar("i64", "pb_unzigzag64(pb_read_varint(r))", "pb_write_varint(out, pb_zigzag64($))", "pb_zigzag64($)");
let sc_bool = Scalar { goose: "bool", wire: 0, clear: "$ = false", read: "pb_read_varint(r) != 0", write: "pb_write_varint(out, pb_bool_to_u64($))", nonzero: "$", size: SZ_FIXED, fixed: 1 };
let sc_fixed32 = Scalar { goose: "u32", wire: 5, clear: "$ = 0", read: "pb_read_fixed32(r)", write: "pb_write_fixed32(out, $)", nonzero: "$ != 0", size: SZ_FIXED, fixed: 4 };
let sc_sfixed32 = Scalar { goose: "i32", wire: 5, clear: "$ = 0", read: "pb_read_fixed32(r) as! i32", write: "pb_write_fixed32(out, $ as! u32)", nonzero: "$ != 0", size: SZ_FIXED, fixed: 4 };
let sc_float = Scalar { goose: "f32", wire: 5, clear: "$ = 0.0", read: "pb_read_float(r)", write: "pb_write_float(out, $)", nonzero: "pb_f32_to_bits($) != 0", size: SZ_FIXED, fixed: 4 };
let sc_fixed64 = Scalar { goose: "u64", wire: 1, clear: "$ = 0", read: "pb_read_fixed64(r)", write: "pb_write_fixed64(out, $)", nonzero: "$ != 0", size: SZ_FIXED, fixed: 8 };
let sc_sfixed64 = Scalar { goose: "i64", wire: 1, clear: "$ = 0", read: "pb_read_fixed64(r) as! i64", write: "pb_write_fixed64(out, $ as! u64)", nonzero: "$ != 0", size: SZ_FIXED, fixed: 8 };
let sc_double = Scalar { goose: "f64", wire: 1, clear: "$ = 0.0", read: "pb_read_double(r)", write: "pb_write_double(out, $)", nonzero: "pb_f64_to_bits($) != 0", size: SZ_FIXED, fixed: 8 };
let sc_bytes = Scalar { goose: "pb_Span", wire: 2, clear: "$ = pb_bytes_free($)", read: "pb_read_bytes(r, $)", write: "pb_write_bytes(out, $)", nonzero: "$.len > 0", size: SZ_BYTES, set_type: "const u8[:]", set: "$ = pb_bytes_set($, v)" };
// The storage of a map field: a span. Its emitters handle the rest.
let sc_map = Scalar { goose: "pb_Span", wire: 2, clear: "", read: "", write: "", nonzero: "", size: SZ_MESSAGE };
// proto3 strings must be valid UTF-8 (validated on decode).
let sc_string = Scalar { goose: "pb_Span", wire: 2, clear: "$ = pb_bytes_free($)", read: "pb_read_string(r, $)", write: "pb_write_bytes(out, $)", nonzero: "$.len > 0", size: SZ_BYTES, set_type: "const u8[:]", set: "$ = pb_bytes_set($, v)" };

// The storage of sub-message fields, made as they are met.
var ref_scalars: Scalar[>..] = [];

// A real oneof: a fixed-mode ADT in the record, with a variant per member.
struct Oneof {
    // The record field name, escaped.
    name: const u8[:],
    type_name: const u8[:],
    // The name of its clear_ accessor.
    clear: const u8[:],
}

var oneof_pool: Oneof[>..] = [];

// A field stored in the record. An optional string is empty when it is not set.
struct Field {
    fd: FieldDesc&,
    sc: Scalar&,
    // The record field name, escaped.
    name: const u8[:],
    // The has-bit of a field with presence: bit bit % 32 of pb_has<bit / 32>,
    // or -1.
    bit: i64 = -1,
    // The message of a sub-message field, whose presence is its link.
    sub: MessageInfo?,
    // A repeated field, whose record field is a span of a run: of `sub`'s
    // links, of pb_spans for strings and bytes, else of the pool of `sc`'s
    // type. Its tag() is that of a value on its own.
    repeated: bool = false,
    // The oneof it is a member of. Its value is the payload of a variant
    // named `name` of the oneof's ADT, and that it is set is its presence.
    oneof: Oneof?,
    // The entry message of a map field, whose record field is a span of a
    // run of entries.
    map: MessageInfo?,
    // A field of a map entry: encoded even at its default, as protobuf does.
    always: bool = false,
    // An enum field of a closed enum: the condition on pb_v that a value is
    // declared. Any other value is kept as an unknown field. For a map field,
    // this is about its values.
    closed: const u8[:] = "",
    // A repeated scalar that encodes as one packed run.
    packs: bool = true,
    // A field that must be set, in the record or in what holds it.
    required: bool = false,
    // A sub-message that encodes between tags, like a group, not with a length.
    delimited: bool = false,
    // The expression of its default, if it is not the one of its type: its
    // record field starts there. A string or bytes default is a global instead.
    dflt: const u8[:] = "",
    // Statement resetting the value, with `$` for it: to `dflt`, or as
    // its type does.
    clear: const u8[:] = "",
}

// Every message's stored fields, a run per message and one sorted by number.
var field_pool: Field[>..] = [];

fn fieldSub(f: Field&) -> MessageInfo& {
    let s = f.sub;
    assert(s);
    return s;
}

fn fieldMap(f: Field&) -> MessageInfo& {
    let s = f.map;
    assert(s);
    return s;
}

fn fieldOneof(f: Field&) -> Oneof& {
    let s = f.oneof;
    assert(s);
    return s;
}

fn fieldExpr(f: Field&) -> const u8[:] { return keep(str("m.", f.name)); }

fn f_number(f: Field&) -> i64 { return f.fd.number; }
fn f_tag(f: Field&) -> i64 { return (f_number(f) << 3) | f.sc.wire; }
fn f_packedTag(f: Field&) -> i64 { return (f_number(f) << 3) | 2; }

// In decode_from, where a sub-message begins: its length, or for a group
// the scan to its end tag, which checks that it matches and leaves r after.
fn f_subOpen(f: Field&) -> const u8[:] {
    if f.delimited {
        return "            let pb_body = r.pos;\n            let pb_stop = pb_skip_group(r, tag);\n            if r.err != PB_OK { break; }\n            let pb_after = r.pos;\n";
    }
    return "            let pb_n = pb_read_len(r);\n            if r.err != PB_OK { break; }\n            if r.depth >= PB_MAX_DEPTH { pb_fail(r, PB_ERR_DEPTH); break; }\n";
}

// Narrows r to the sub-message's window.
fn f_subWindow(f: Field&) -> const u8[:] {
    if f.delimited {
        return "            let pb_outer = r.end;\n            r.pos = pb_body;\n            r.end = pb_stop;\n            r.depth++;\n";
    }
    return "            let pb_outer = r.end;\n            r.end = r.pos + pb_n;\n            r.depth++;\n";
}

// Restores r after the sub-message's window.
fn f_subClose(f: Field&) -> const u8[:] {
    if f.delimited {
        return "            r.depth--;\n            r.end = pb_outer;\n            r.pos = pb_after;\n";
    }
    return "            r.depth--;\n            r.end = pb_outer;\n";
}

// A span that owns nothing, for reading a value into a new run.
const empty_span = "pb_Span { at: 0, len: 0 }";

fn bitMask(b: i64) -> u32 {
    let one: u32 = 1;
    return one << (b % 32);
}

fn varintSize(v: i64) -> i64 {
    var n = 1;
    var x = v;
    while x >= 0x80 {
        x = x >> 7;
        n += 1;
    }
    return n;
}

// Template `t` with every `$` replaced by `x`.
fn subst(t: const u8[:], x: const u8[:]) -> const u8[:] {
    var out: u8[>..] = [];
    for c in t {
        if c == '$' { out.append(x); } else { out.push(c); }
    }
    return keep(out);
}

// The encode condition of a field: its has-bit if it has presence, else a
// value other than the default.
fn isSet(f: Field&, x: const u8[:]) -> const u8[:] {
    if f.bit >= 0 { return keep(str("(m.pb_has", f.bit / 32, " & 0x", hex8(bitMask(f.bit)), ") != 0")); }
    return subst(f.sc.nonzero, x);
}

// The statements writing sub-message `l` of field `f`: length-delimited,
// or between the tags of a group.
fn subWrite(f: Field&, indent: const u8[:], l: const u8[:], size_of: const u8[:], encode: const u8[:]) -> const u8[:] {
    if f.delimited {
        return keep(str(indent, "pb_write_varint(out, ", f_tag(f), ");\n",
            indent, encode, "(", l, ", out);\n",
            indent, "pb_write_varint(out, ", f_tag(f) + 1, ");"));
    }
    return keep(str(indent, "pb_write_varint(out, ", f_tag(f), ");\n",
        indent, "pb_write_varint(out, ", size_of, "(", l, ") as! u64);\n",
        indent, encode, "(", l, ", out);"));
}

// The size of sub-message `l` of field `f`, with its tags.
fn subSize(f: Field&, size_of: const u8[:], l: const u8[:]) -> const u8[:] {
    let ts = varintSize(f_tag(f));
    if f.delimited { return keep(str(2 * ts, " + ", size_of, "(", l, ")")); }
    return keep(str(ts, " + pb_len_size(", size_of, "(", l, "))"));
}

// The full name of the message type of `fd`, singular or repeated, if it has
// one, else "". A map field has its entry's.
fn messageTypeOf(fd: FieldDesc&) -> const u8[:] {
    let t = fieldType(fd);
    if t != TYPE_MESSAGE && t != TYPE_GROUP { return ""; }
    let tn = google_protobuf::FieldDescriptorProto_type_name(fd);
    return if startsWith(tn, ".") { tn[1..] } else { tn };
}

// What <entry>_fold sorts the key of entry pb_r[pb_i] by. Only grouping
// matters, so a signed key is simply widened, which keeps keys distinct.
fn foldKey(sc: Scalar&) -> const u8[:] {
    if sc.size == SZ_BYTES { return "pb_r[pb_i].key"; }
    if sc.goose == "bool" { return "pb_bool_to_u64(pb_r[pb_i].key)"; }
    if sc.goose[0] == 'u' { return "pb_r[pb_i].key"; }
    return "pb_r[pb_i].key as! u64";
}

// The field numbered `number` of a map entry.
fn mapField(fields: const Field[:], number: i64) -> Field& {
    for &f in fields {
        if f_number(f) == number { return f; }
    }
    abort("a map entry without its field");
}

// The features of field `fd` of message `m` of `file`, where `m` has `own`.
fn fieldFeatures(file: FileDesc&, own: Features, m: MessageDesc&, fd: FieldDesc&) -> Features {
    if isRealOneofMember(fd) {
        let parent = featuresOfOneof(own, google_protobuf::DescriptorProto_oneof_decl_at(m, fd.oneof_index));
        return featuresOfField(file, parent, fd);
    }
    return featuresOfField(file, own, fd);
}

// True if `fd` is in a real oneof. A proto3 optional is in a synthetic one,
// which is not an ADT: its field is stored like any other.
fn isRealOneofMember(fd: FieldDesc&) -> bool {
    return google_protobuf::FieldDescriptorProto_has_oneof_index(fd) && !fd.proto3_optional;
}

// Runs of realOneofSlots, in a global pool as a local array could not stay in scope
// across the recursion of the messages.
var oneof_slots: i64[>..] = [];

// Adds a run to oneof_slots and returns where it starts: for each oneof of `m` in
// order, its place among the real ones, or -1 for a synthetic one, which holds only
// a proto3 optional.
fn realOneofSlots(m: MessageDesc&) -> i64 {
    let at = oneof_slots.len;
    let count = google_protobuf::DescriptorProto_oneof_decl(m).len;
    for i in count { oneof_slots.push(-1); }
    for k in google_protobuf::DescriptorProto_field(m).len {
        let fd .= google_protobuf::DescriptorProto_field_at(m, k);
        if isRealOneofMember(fd) && fd.oneof_index >= 0 && fd.oneof_index < count { oneof_slots[at + fd.oneof_index] = 0; }
    }
    var next = 0;
    for i in count {
        if oneof_slots[at + i] >= 0 {
            oneof_slots[at + i] = next;
            next += 1;
        }
    }
    return at;
}

// The scalar storage of singular field `fd`, which has features `ff`, or null
// if it is a message. A string is validated only if its features say so.
fn scalarOf(ff: Features, fd: FieldDesc&) -> Scalar? {
    if fieldIsRepeated(fd) { return null; }
    if !ff.verify_utf8 && fieldType(fd) == TYPE_STRING { return sc_bytes; }
    return scalarOfType(fd);
}

// The element storage of repeated non-message field `fd`, as for scalarOf.
fn repeatedScalarOf(ff: Features, fd: FieldDesc&) -> Scalar? {
    if !fieldIsRepeated(fd) { return null; }
    if !ff.verify_utf8 && fieldType(fd) == TYPE_STRING { return sc_bytes; }
    return scalarOfType(fd);
}

// The value field of the map entry `entry`.
fn mapValueOf(entry: MessageDesc&) -> FieldDesc& {
    for k in google_protobuf::DescriptorProto_field(entry).len {
        let e .= google_protobuf::DescriptorProto_field_at(entry, k);
        if e.number == 2 { return e; }
    }
    abort("a map entry without a value");
}

// The key field of the map entry `entry`.
fn mapKeyOf(entry: MessageDesc&) -> FieldDesc& {
    for k in google_protobuf::DescriptorProto_field(entry).len {
        let e .= google_protobuf::DescriptorProto_field_at(entry, k);
        if e.number == 1 { return e; }
    }
    abort("a map entry without a key");
}

// The number of the value of `e` that the [default] of `fd` names, else of its
// first.
fn enumDefault(e: EnumDesc&, fd: FieldDesc&) -> i32 {
    let values = google_protobuf::EnumDescriptorProto_value(e).len;
    if google_protobuf::FieldDescriptorProto_has_default_value(fd) {
        let name = google_protobuf::FieldDescriptorProto_default_value(fd);
        for i in values {
            let v .= google_protobuf::EnumDescriptorProto_value_at(e, i);
            if google_protobuf::EnumValueDescriptorProto_name(v) == name { return v.number; }
        }
    }
    if values == 0 { return 0; }
    return google_protobuf::EnumDescriptorProto_value_at(e, 0).number;
}

// True if the [default] of a string or bytes field `fd` is there and not empty.
fn hasDefaultBytes(fd: FieldDesc&) -> bool {
    if !google_protobuf::FieldDescriptorProto_has_default_value(fd) { return false; }
    if google_protobuf::FieldDescriptorProto_default_value(fd).len == 0 { return false; }
    let t = fieldType(fd);
    return t == TYPE_STRING || t == TYPE_BYTES;
}

// The contents of the [default] of a string or bytes field, if hasDefaultBytes.
// protoc writes a bytes default C-escaped, a string one as it is.
fn defaultBytes(fd: FieldDesc&) -> const u8[:] {
    let text = google_protobuf::FieldDescriptorProto_default_value(fd);
    return if fieldType(fd) == TYPE_BYTES { cUnescape(text) } else { text };
}

fn hexDigit(c: u8) -> i64 {
    if c >= '0' && c <= '9' { return c - '0'; }
    if c >= 'a' && c <= 'f' { return c - 'a' + 10; }
    if c >= 'A' && c <= 'F' { return c - 'A' + 10; }
    return -1;
}

fn cUnescape(text: const u8[:]) -> const u8[:] {
    var out: u8[>..] = [];
    var i = 0;
    while i < text.len {
        let c = text[i];
        i += 1;
        if c != '\\' || i == text.len {
            out.push(c);
            continue;
        }
        let e = text[i];
        i += 1;
        if e == 'a' { out.push(7); }
        else if e == 'b' { out.push(8); }
        else if e == 'f' { out.push(12); }
        else if e == 'n' { out.push('\n'); }
        else if e == 'r' { out.push('\r'); }
        else if e == 't' { out.push('\t'); }
        else if e == 'v' { out.push(11); }
        else if e >= '0' && e <= '7' {
            var v: i64 = e - '0';
            var n = 1;
            while n < 3 && i < text.len && text[i] >= '0' && text[i] <= '7' {
                v = v * 8 + (text[i] - '0');
                i += 1;
                n += 1;
            }
            out.push(v as! u8);
        } else if e == 'x' {
            var v: u32 = 0;
            while i < text.len && hexDigit(text[i]) >= 0 {
                v = v * 16 + (hexDigit(text[i]) as! u32);
                i += 1;
            }
            out.push(v as! u8);
        } else {
            out.push(e);
        }
    }
    return keep(out);
}

// The condition on pb_v that it is a value of `e`, as sorted runs of values.
fn knownValues(e: EnumDesc&) -> const u8[:] {
    var values: i64[>..] = [];
    for i in google_protobuf::EnumDescriptorProto_value(e).len {
        values.push(google_protobuf::EnumDescriptorProto_value_at(e, i).number);
    }
    sort(values);
    var out: u8[>..] = [];
    var i = 0;
    while i < values.len {
        var j = i;
        while j + 1 < values.len && values[j + 1] <= values[j] + 1 { j += 1; }
        if out.len > 0 { out.append(" || "); }
        if values[i] == values[j] {
            format(out, "pb_v == ", values[i]);
        } else {
            format(out, "(pb_v >= ", values[i], " && pb_v <= ", values[j], ")");
        }
        i = j + 1;
    }
    return keep(out);
}

// True if `m` is the synthetic entry of a map field.
fn isMapEntryDesc(m: MessageDesc&) -> bool {
    let opts = google_protobuf::DescriptorProto_options(m);
    guard opts else { return false; }
    return google_protobuf::MessageOptions_has_map_entry(opts) && opts.map_entry;
}

fn isMapEntryType(info: MessageInfo&) -> bool { return isMapEntryDesc(info.desc); }

fn scalarOfType(fd: FieldDesc&) -> Scalar? {
    let t = fieldType(fd);
    if t == TYPE_INT32 || t == TYPE_ENUM { return sc_int32; }
    if t == TYPE_INT64 { return sc_int64; }
    if t == TYPE_UINT32 { return sc_uint32; }
    if t == TYPE_UINT64 { return sc_uint64; }
    if t == TYPE_SINT32 { return sc_sint32; }
    if t == TYPE_SINT64 { return sc_sint64; }
    if t == TYPE_BOOL { return sc_bool; }
    if t == TYPE_FIXED32 { return sc_fixed32; }
    if t == TYPE_SFIXED32 { return sc_sfixed32; }
    if t == TYPE_FLOAT { return sc_float; }
    if t == TYPE_FIXED64 { return sc_fixed64; }
    if t == TYPE_SFIXED64 { return sc_sfixed64; }
    if t == TYPE_DOUBLE { return sc_double; }
    if t == TYPE_STRING { return sc_string; }
    if t == TYPE_BYTES { return sc_bytes; }
    return null;
}

// scalarOfType(fd), of a field known to be a scalar.
fn scalarOfTypeReq(fd: FieldDesc&) -> Scalar& {
    let sc = scalarOfType(fd);
    assert(sc);
    return sc;
}

// The storage kind of field `fd` of message `m`, whose full name is `full`.
fn fieldKind(m: MessageDesc&, full: const u8[:], fd: FieldDesc&) -> i64 {
    let t = if google_protobuf::FieldDescriptorProto_has_type(fd) { fd.type_ } else { TYPE_INT32 };
    let is_msg = t == TYPE_MESSAGE || t == TYPE_GROUP;
    if fieldIsRepeated(fd) {
        if is_msg && isMapEntry(m, full, google_protobuf::FieldDescriptorProto_type_name(fd)) { return KIND_MAP; }
        return if is_msg { KIND_REPEATED_MESSAGE } else { KIND_REPEATED };
    }
    if is_msg { return KIND_MESSAGE; }
    if t == TYPE_STRING || t == TYPE_BYTES { return KIND_STRING; }
    return if isRealOneofMember(fd) { KIND_ONEOF_SCALAR } else { KIND_SCALAR };
}

// True if `type_name` (`.pkg.M.XEntry`) names a map entry nested in `m`.
fn isMapEntry(m: MessageDesc&, full: const u8[:], type_name: const u8[:]) -> bool {
    let tn = if startsWith(type_name, ".") { type_name[1..] } else { type_name };
    if !startsWith(tn, full) || tn.len <= full.len + 1 || tn[full.len] != '.' { return false; }
    let local = tn[full.len + 1..];
    for k in google_protobuf::DescriptorProto_nested_type(m).len {
        let n .= google_protobuf::DescriptorProto_nested_type_at(m, k);
        if messageName(n) == local { return isMapEntryDesc(n); }
    }
    return false;
}

// True if singular field `fd`, with features `ff`, tracks presence: a message, a
// oneof member (a proto3 `optional` is one), or as its features say.
fn hasPresence(ff: Features, fd: FieldDesc&) -> bool {
    if fieldIsRepeated(fd) { return false; }
    let t = if google_protobuf::FieldDescriptorProto_has_type(fd) { fd.type_ } else { TYPE_INT32 };
    if t == TYPE_MESSAGE || t == TYPE_GROUP { return true; }
    if google_protobuf::FieldDescriptorProto_has_oneof_index(fd) || fd.proto3_optional { return true; }
    return ff.presence != PRESENCE_IMPLICIT;
}

// The message for CodeGeneratorResponse.error of a name collision.
var diag: const u8[:] = "";

// What the Zig emitter carries in its hash maps, each here a number in support's
// global table.
struct FileEmitter {
    file: FileDesc&,
    // Goose name -> what claimed it (text), and whether a generated function or
    // global did (flag), which a nested declaration yields to.
    names: u32,
    // Unescaped message path -> full name. Two messages with one path
    // also share every generated name; this reports the types instead.
    message_paths: u32,
    // Full name of a type or enum value in this file -> its Goose name.
    decls: u32,
    // Full name of a message in this file -> the message.
    messages: u32,
    // Full name of a message of another file whose names are claimed ->
    // the message, its names qualified from this file.
    foreign: u32,
    // Import paths of the files that the stored fields need.
    imports: u32,
    // How the codec functions of the current message are declared.
    fn_kw: const u8[:] = "fn",
    // True once findCycles has been through the messages of this file.
    cycles_found: bool = false,
}

// The emitters of this run: one for each file generated, and one for each file
// whose names one of those claims.
var file_emitters: FileEmitter[>..] = [];

fn newFileEmitter(file: FileDesc&) -> FileEmitter& {
    let fe .= file_emitters.push(FileEmitter {
        file: file, names: newMap(), message_paths: newMap(), decls: newMap(), messages: newMap(),
        foreign: newMap(), imports: newMap(),
    });
    mapPut(claimed_files, fileName(file)).index = file_emitters.len - 1;
    return fe;
}

// Forgets what is known of the request, for a test that makes another.
fn forgetRequest() {
    request_indexed = false;
}

// Indexes the messages and enums of every file of the request by full name.
fn indexRequest() {
    if request_indexed { return; }
    request_indexed = true;
    message_files = newMap();
    enum_index = newMap();
    claimed_files = newMap();
    required_answers = newMap();
    maps_answers = newMap();
    for i in google_protobuf_compiler::CodeGeneratorRequest_proto_file(request).len {
        let file .= google_protobuf_compiler::CodeGeneratorRequest_proto_file_at(request, i);
        let inherited = featuresOfFile(file);
        let package = filePackage(file);
        for k in google_protobuf::FileDescriptorProto_enum_type(file).len {
            indexEnum(google_protobuf::FileDescriptorProto_enum_type_at(file, k), package, inherited);
        }
        for k in google_protobuf::FileDescriptorProto_message_type(file).len {
            indexMessage(google_protobuf::FileDescriptorProto_message_type_at(file, k), package, inherited, i);
        }
    }
}

fn indexEnum(e: EnumDesc&, scope: const u8[:], parent: Features) {
    enum_infos.push(EnumInfo { desc: e, closed: featuresOfEnum(parent, e).closed_enum });
    mapPut(enum_index, fullName(scope, enumName(e))).index = enum_infos.len - 1;
}

recursive fn indexMessage(m: MessageDesc&, scope: const u8[:], parent: Features, file_at: i64) {
    let full = fullName(scope, messageName(m));
    mapPut(message_files, full).index = file_at;
    let inherited = featuresOfMessage(parent, m);
    for i in google_protobuf::DescriptorProto_enum_type(m).len {
        indexEnum(google_protobuf::DescriptorProto_enum_type_at(m, i), full, inherited);
    }
    for i in google_protobuf::DescriptorProto_nested_type(m).len {
        indexMessage(google_protobuf::DescriptorProto_nested_type_at(m, i), full, inherited, file_at);
    }
}

fn emit(fe: FileEmitter&) {
    let f .= fe.file;
    let proto_name = fileName(f);
    format(w, "// Code generated by protoc-gen-goose. DO NOT EDIT.\n// source: ", proto_name, "\n\n");
    w.append(api_comment);
    let package = filePackage(f);
    if package.len > 0 {
        format(w, "namespace ", namespaceName(package), ";\n\n");
    }
    w.append("import pb_wire;\n");

    claimAll(fe);
    for i in google_protobuf::FileDescriptorProto_message_type(f).len {
        collectImports(fe, google_protobuf::FileDescriptorProto_message_type_at(f, i));
    }
    var imports: const u8[:][>..] = [];
    var at = map_firsts[fe.imports];
    while at != 0 {
        let e .= map_entries[at - 1];
        imports.push(e.key);
        at = e.next_of_map;
    }
    sort(imports) { a, b => compare(a, b) < 0 };
    for i in imports { format(w, "import ", i, ";\n"); }

    for i in google_protobuf::FileDescriptorProto_enum_type(f).len {
        emitEnum(fe, google_protobuf::FileDescriptorProto_enum_type_at(f, i), package);
    }
    for i in google_protobuf::FileDescriptorProto_message_type(f).len {
        emitMessage(fe, google_protobuf::FileDescriptorProto_message_type_at(f, i), "", package);
    }
}

// Claims every name of the file, in the order the declarations are
// emitted, so that generated names come first.
fn claimAll(fe: FileEmitter&) {
    let f .= fe.file;
    let package = filePackage(f);
    let inherited = featuresOfFile(f);
    let messages = google_protobuf::FileDescriptorProto_message_type(f).len;
    for i in messages { claimGenerated(fe, google_protobuf::FileDescriptorProto_message_type_at(f, i), "", package, inherited); }
    for i in google_protobuf::FileDescriptorProto_enum_type(f).len { claimEnum(fe, google_protobuf::FileDescriptorProto_enum_type_at(f, i), "", package); }
    for i in messages { claimMessage(fe, google_protobuf::FileDescriptorProto_message_type_at(f, i), "", package, inherited); }
}

// Records the files the stored fields of `m` and its nested messages
// need. Importing only those lets a file build without the others.
recursive fn collectImports(fe: FileEmitter&, m: MessageDesc&) {
    for i in google_protobuf::DescriptorProto_field(m).len {
        subMessageOf(fe, google_protobuf::DescriptorProto_field_at(m, i));
    }
    for i in google_protobuf::DescriptorProto_nested_type(m).len {
        collectImports(fe, google_protobuf::DescriptorProto_nested_type_at(m, i));
    }
}

fn fullName(scope: const u8[:], name: const u8[:]) -> const u8[:] {
    if scope.len == 0 { return name; }
    return keep(str(scope, ".", name));
}

// Fails generating the file: the first error goes in CodeGeneratorResponse.error,
// and generateFile reports it when it is done. The Zig emitter stops here, but a
// long-distance return cannot leave the recursion of emitMessage, and what runs
// after a collision can only add names no one will read.
fn collide(message: const u8[:]) {
    if diag.len == 0 { diag = message; }
}

fn claim(fe: FileEmitter&, goose_name: const u8[:], what: const u8[:], generated: bool) {
    let found = mapGet(fe.names, goose_name);
    if found {
        collide(keep(str(fileName(fe.file), ": ", found.text, " and ", what, " both map to the Goose name ", goose_name)));
        return;
    }
    let e .= mapPut(fe.names, goose_name);
    e.text = what;
    e.flag = generated;
}

// Claims the Goose name of a type or enum constant at `path` and
// returns it. A nested declaration whose name is a generated name
// gets a trailing `_`; a top-level one is a collision.
fn claimDecl(fe: FileEmitter&, path: const u8[:], full: const u8[:], nested: bool) -> const u8[:] {
    var goose_name = ident(path);
    if nested {
        let owner = mapGet(fe.names, goose_name);
        if owner {
            if owner.flag { goose_name = keep(str(goose_name, "_")); }
        }
    }
    claim(fe, goose_name, full, false);
    return goose_name;
}

// Claims every function and global generated for `m` and its nested
// messages, so that types and constants claimed later yield to them.
recursive fn claimGenerated(fe: FileEmitter&, m: MessageDesc&, prefix: const u8[:], scope: const u8[:], inherited: Features) {
    let name = messageName(m);
    let path = nestedPath(prefix, name);
    let full = fullName(scope, name);
    let own = featuresOfMessage(inherited, m);
    let found = mapGet(fe.message_paths, path);
    if found {
        collide(keep(str(fileName(fe.file), ": ", found.text, " and ", full, " both map to the Goose name ", ident(path))));
    }
    mapPut(fe.message_paths, path).text = full;
    for op in message_ops {
        claim(fe, generatedName(path, op), keep(str("generated ", op, " of ", full)), true);
    }
    if isMapEntryDesc(m) {
        for op in map_entry_ops {
            claim(fe, generatedName(path, op), keep(str("generated ", op, " of ", full)), true);
        }
    }
    for k in google_protobuf::DescriptorProto_field(m).len {
        let fd .= google_protobuf::DescriptorProto_field_at(m, k);
        let fname = fieldName(fd);
        let kind = fieldKind(m, full, fd);
        // A map entry's fields have no presence, whatever the syntax.
        for &acc in fieldAccessors(kind, hasPresence(fieldFeatures(fe.file, own, m, fd), fd) && !isMapEntryDesc(m)) {
            claim(fe, accessorName(path, fname, acc), keep(str("accessor ", acc.prefix, fname, acc.suffix, " of ", full)), true);
        }
        if hasDefaultBytes(fd) {
            claim(fe, accessorName(path, fname, default_acc), keep(str("default of ", fname, " of ", full)), true);
        }
    }
    // A oneof's type and its clear_. A field cannot have its name.
    let slots_at = realOneofSlots(m);
    for i in google_protobuf::DescriptorProto_oneof_decl(m).len {
        if oneof_slots[slots_at + i] < 0 { continue; }
        let oname = google_protobuf::OneofDescriptorProto_name(google_protobuf::DescriptorProto_oneof_decl_at(m, i));
        claim(fe, generatedName(path, oname), keep(str("oneof ", oname, " of ", full)), true);
        claim(fe, accessorName(path, oname, clear_acc), keep(str("accessor clear_", oname, " of ", full)), true);
    }
    for k in google_protobuf::DescriptorProto_nested_type(m).len {
        claimGenerated(fe, google_protobuf::DescriptorProto_nested_type_at(m, k), path, full, own);
    }
}

// Claims the names of an enum and its values, in the order they are
// emitted.
fn claimEnum(fe: FileEmitter&, e: EnumDesc&, prefix: const u8[:], scope: const u8[:]) {
    let name = enumName(e);
    let path = nestedPath(prefix, name);
    let full = fullName(scope, name);
    let goose_name = claimDecl(fe, path, full, prefix.len > 0);
    mapPut(fe.decls, full).text = goose_name;
    for i in google_protobuf::EnumDescriptorProto_value(e).len {
        let vname = google_protobuf::EnumValueDescriptorProto_name(google_protobuf::EnumDescriptorProto_value_at(e, i));
        let vfull = fullName(full, vname);
        let const_name = claimDecl(fe, nestedPath(path, vname), vfull, true);
        mapPut(fe.decls, vfull).text = const_name;
    }
}

// Claims the names of a message and what is nested in it, in the
// order they are emitted. Fields name their types through this, and
// a type may be declared after the field that uses it.
recursive fn claimMessage(fe: FileEmitter&, m: MessageDesc&, prefix: const u8[:], scope: const u8[:], inherited: Features) {
    let name = messageName(m);
    let path = nestedPath(prefix, name);
    let full = fullName(scope, name);
    let own = featuresOfMessage(inherited, m);
    let goose_name = claimDecl(fe, path, full, prefix.len > 0);
    mapPut(fe.decls, full).text = goose_name;
    message_infos.push(MessageInfo { desc: m, path: path, goose_name: goose_name, ns: "", import_path: "", file: fe.file, features: own });
    mapPut(fe.messages, full).index = message_infos.len - 1;
    for i in google_protobuf::DescriptorProto_enum_type(m).len {
        claimEnum(fe, google_protobuf::DescriptorProto_enum_type_at(m, i), path, full);
    }
    for i in google_protobuf::DescriptorProto_nested_type(m).len {
        claimMessage(fe, google_protobuf::DescriptorProto_nested_type_at(m, i), path, full, own);
    }
}

// The message that field `fd` stores as a sub-message, or null if it
// is not stored.
fn subMessageOf(fe: FileEmitter&, fd: FieldDesc&) -> MessageInfo? {
    let t = messageTypeOf(fd);
    if t.len == 0 { return null; }
    let own = mapGet(fe.messages, t);
    if own {
        let info .= infoOf(own);
        if isMapEntryType(info) { return null; }
        return info;
    }
    return foreignMessage(fe, t);
}

// The entry message of `fd`, if it is a map field this generator stores.
fn mapEntryOf(fe: FileEmitter&, fd: FieldDesc&) -> MessageInfo? {
    if !fieldIsRepeated(fd) { return null; }
    let t = messageTypeOf(fd);
    if t.len == 0 { return null; }
    let own = mapGet(fe.messages, t);
    guard own else { return null; }
    let info .= infoOf(own);
    return if isMapEntryType(info) { info } else { null };
}

// The message of type `t`, in any file, with no qualifier: what it holds, not how
// a file writes it. Claims the names of its file the first time, as generating that
// file does, or null if no file declares it.
fn claimedMessage(t: const u8[:]) -> MessageInfo? {
    let home = mapGet(message_files, t);
    guard home else { return null; }
    let file .= google_protobuf_compiler::CodeGeneratorRequest_proto_file_at(request, home.index);
    var claimed = mapGet(claimed_files, fileName(file));
    if claimed == null {
        claimAll(newFileEmitter(file));
        claimed .= mapGet(claimed_files, fileName(file));
    }
    assert(claimed);
    let found = mapGet(file_emitters[claimed.index].messages, t);
    guard found else { return null; }
    return infoOf(found);
}

// What a search has found about a message, in MapEntry.index of an answers map.
let ANSWER_UNKNOWN = 0;
let ANSWER_YES = 1;
let ANSWER_NO = 2;
// Being searched, or found to have nothing but what is being searched: it may yet
// turn out to reach what its ancestors reach.
let ANSWER_OPEN = 3;

// True if a message of type `t` can reach a required field that is stored, itself
// or in what it holds, in any file: it then has is_initialized.
fn holdsRequired(t: const u8[:]) -> bool {
    return answerFor(t, required_answers, false);
}

// True if a message of type `t` can reach a map field that is stored: it then has
// fold_maps. An entry counts what its value holds, not itself.
fn holdsMaps(t: const u8[:]) -> bool {
    return answerFor(t, maps_answers, true);
}

// The answer for `t`. A search stops at what it looks for, so it claims no more
// files than it needs. Finding nothing settles every message it went through, as
// they have seen all they can reach. Finding something settles only those on the
// way to it: another may have stopped short at a message being searched.
fn answerFor(t: const u8[:], answers: u32, maps: bool) -> bool {
    let found = searchAnswer(t, answers, maps);
    while open_answers.len > 0 {
        let e .= map_entries[open_answers.pop()];
        if e.index == ANSWER_OPEN { e.index = if found { ANSWER_UNKNOWN } else { ANSWER_NO }; }
    }
    return found;
}

// The map entries a search has gone through, by index in map_entries.
var open_answers: i64[>..<] = [];

recursive fn searchAnswer(t: const u8[:], answers: u32, maps: bool) -> bool {
    let answer_at = mapPutIndex(answers, t);
    let answer .= map_entries[answer_at];
    if answer.index != ANSWER_UNKNOWN { return answer.index == ANSWER_YES; }
    answer.index = ANSWER_OPEN;
    open_answers.push(answer_at);
    let info = claimedMessage(t);
    guard info else { return false; }
    for k in google_protobuf::DescriptorProto_field(info.desc).len {
        let fd .= google_protobuf::DescriptorProto_field_at(info.desc, k);
        if !maps && fieldFeatures(info.file, info.features, info.desc, fd).presence == PRESENCE_REQUIRED {
            answer.index = ANSWER_YES;
            return true;
        }
        let s = messageTypeOf(fd);
        if s.len == 0 { continue; }
        if maps {
            let sub = claimedMessage(s);
            guard sub else { continue; }
            if isMapEntryType(sub) {
                answer.index = ANSWER_YES;
                return true;
            }
        }
        if searchAnswer(s, answers, maps) {
            answer.index = ANSWER_YES;
            return true;
        }
    }
    return false;
}

// True if the message that stored field `f` holds has fold_maps.
fn fieldHoldsMaps(f: Field&) -> bool {
    let t = messageTypeOf(f.fd);
    if t.len == 0 { return false; }
    return holdsMaps(t);
}

// True if the message that stored field `f` holds has is_initialized.
fn fieldHoldsRequired(f: Field&) -> bool {
    let t = messageTypeOf(f.fd);
    if t.len == 0 { return false; }
    return holdsRequired(t);
}

// Message `t` of another file, as this file writes it, which it marks for import.
fn foreignMessage(fe: FileEmitter&, t: const u8[:]) -> MessageInfo? {
    let known = mapGet(fe.foreign, t);
    if known { return infoOf(known); }
    let info = claimedMessage(t);
    guard info else { return null; }
    let ns = qualifier(fe, filePackage(info.file));
    let import_path = importPath(info.file);
    message_infos.push(MessageInfo {
        desc: info.desc, path: info.path, goose_name: keep(str(ns, info.goose_name)),
        ns: ns, import_path: import_path, file: info.file, features: info.features,
    });
    mapPut(fe.foreign, t).index = message_infos.len - 1;
    mapPut(fe.imports, import_path);
    return message_infos[message_infos.len - 1];
}

// What names in the namespace of `package` are written with from
// this file.
fn qualifier(fe: FileEmitter&, package: const u8[:]) -> const u8[:] {
    if package == filePackage(fe.file) { return ""; }
    if package.len == 0 { return "::"; }
    return keep(str(namespaceName(package), "::"));
}

// The name of generated function or global `op` of `sub`, as this file
// writes it.
fn subName(fe: FileEmitter&, sub: MessageInfo&, op: const u8[:]) -> const u8[:] {
    return keep(str(sub.ns, generatedName(sub.path, op)));
}

// True if a message of type `full` can hold another of its type: its
// codec functions are in a cycle, so they are `recursive fn`.
fn isRecursive(fe: FileEmitter&, full: const u8[:]) -> bool {
    let own = mapGet(fe.messages, full);
    guard own else { return false; }
    if !fe.cycles_found {
        fe.cycles_found = true;
        while cycle_nodes.len < message_infos.len { cycle_nodes.push(CycleNode { .. }); }
        var at = map_firsts[fe.messages];
        while at != 0 {
            let e .= map_entries[at - 1];
            if cycle_nodes[e.index].order == 0 { findCycles(fe, e.index); }
            at = e.next_of_map;
        }
    }
    return cycle_nodes[own.index].in_cycle;
}

// The full name of the message in this file that `fd` holds, if it
// is a field kind this generator stores, else "". A map field holds its entries.
fn sameFileMessageType(fe: FileEmitter&, fd: FieldDesc&) -> const u8[:] {
    let t = messageTypeOf(fd);
    if t.len == 0 { return ""; }
    return if mapContains(fe.messages, t) { t } else { "" };
}

// A message of the file being generated, in Tarjan's search for strongly connected
// components, by its index in message_infos. `order` is 0 until it is reached.
struct CycleNode {
    order: i64,
    low: i64,
    on_stack: bool,
    in_cycle: bool,
}

var cycle_nodes: CycleNode[>..] = [];
var cycle_stack: i64[>..<] = [];
var cycle_order: i64 = 0;

// Finds the cycles through what the message at `at` of message_infos can reach, in
// this file: a component of several messages, or one that holds itself, is a cycle.
recursive fn findCycles(fe: FileEmitter&, at: i64) {
    let node .= cycle_nodes[at];
    cycle_order += 1;
    node.order = cycle_order;
    node.low = cycle_order;
    node.on_stack = true;
    cycle_stack.push(at);
    let desc .= message_infos[at].desc;
    for k in google_protobuf::DescriptorProto_field(desc).len {
        let t = sameFileMessageType(fe, google_protobuf::DescriptorProto_field_at(desc, k));
        if t.len == 0 { continue; }
        let held = mapGet(fe.messages, t);
        assert(held);
        if held.index == at { node.in_cycle = true; }
        let next .= cycle_nodes[held.index];
        if next.order == 0 {
            findCycles(fe, held.index);
            if next.low < node.low { node.low = next.low; }
        } else if next.on_stack {
            if next.order < node.low { node.low = next.order; }
        }
    }
    if node.low != node.order { return; }
    let several = cycle_stack[cycle_stack.len - 1] != at;
    loop {
        let member = cycle_stack.pop();
        cycle_nodes[member].on_stack = false;
        if several { cycle_nodes[member].in_cycle = true; }
        if member == at { break; }
    }
}

fn emitEnum(fe: FileEmitter&, e: EnumDesc&, scope: const u8[:]) {
    let full = fullName(scope, enumName(e));
    format(w, "\n// enum ", full, "\n");
    for i in google_protobuf::EnumDescriptorProto_value(e).len {
        let v .= google_protobuf::EnumDescriptorProto_value_at(e, i);
        let const_name = mapGet(fe.decls, fullName(full, google_protobuf::EnumValueDescriptorProto_name(v)));
        assert(const_name);
        format(w, "let ", const_name.text, ": i32 = ", v.number, ";\n");
    }
}

recursive fn emitMessage(fe: FileEmitter&, m: MessageDesc&, prefix: const u8[:], scope: const u8[:]) {
    let name = messageName(m);
    let path = nestedPath(prefix, name);
    let full = fullName(scope, name);
    let decl = mapGet(fe.decls, full);
    assert(decl);
    let goose_name = decl.text;
    format(w, "\n// message ", full, "\n");

    // In a map entry, whose fields are encoded even at their defaults.
    let is_entry = isMapEntryDesc(m);
    let own_info = mapGet(fe.messages, full);
    assert(own_info);
    let own = infoOf(own_info).features;
    // The fields this generator stores; every other field is kept as an
    // unknown field. They and the oneofs are a run in a global pool, as a local
    // array could not stay in scope across the recursion at the end.
    let fields_at = field_pool.len;
    let record_names = newMap();
    var bits = 0;
    // The real oneofs of a stored message, in the order of oneof_decl.
    let oneofs_at = oneof_pool.len;
    let slots_at = realOneofSlots(m);
    for i in google_protobuf::DescriptorProto_oneof_decl(m).len {
        if oneof_slots[slots_at + i] < 0 { continue; }
        let oname = google_protobuf::OneofDescriptorProto_name(google_protobuf::DescriptorProto_oneof_decl_at(m, i));
        let o .= oneof_pool.push(Oneof {
            name: ident(oname),
            type_name: generatedName(path, oname),
            clear: accessorName(path, oname, clear_acc),
        });
        claimRecordField(fe, record_names, o.name, full);
    }
    for k in google_protobuf::DescriptorProto_field(m).len {
        let fd .= google_protobuf::DescriptorProto_field_at(m, k);
        let sub = subMessageOf(fe, fd);
        let entry = mapEntryOf(fe, fd);
        let ff = fieldFeatures(fe.file, own, m, fd);
        // A map's entries and what is in them are never delimited.
        let delimited = sub != null && !is_entry && ff.delimited;
        var sc_opt: Scalar? = null;
        if entry {
            sc_opt .= sc_map;
        } else if sub {
            sc_opt .= refStorage(fe, sub, delimited);
        } else {
            sc_opt .= repeatedScalarOf(ff, fd);
            if sc_opt == null { sc_opt .= scalarOf(ff, fd); }
        }
        guard sc_opt else { continue; }
        let repeated = fieldIsRepeated(fd) && entry == null;
        let rname = ident(fieldName(fd));
        claimRecordField(fe, record_names, rname, full);
        var oneof: Oneof? = null;
        if isRealOneofMember(fd) { oneof .= oneof_pool[oneofs_at + oneof_slots[slots_at + fd.oneof_index]]; }
        var bit = -1;
        if sub == null && !repeated && oneof == null && !is_entry && hasPresence(ff, fd) {
            bit = bits;
            bits += 1;
        }
        let dflt = if is_entry || repeated || sub != null || entry != null { "" } else { defaultLiteral(fd) };
        var closed = "";
        if !is_entry {
            closed = if entry { closedCheck(mapValueOf(entry.desc)) } else { closedCheck(fd) };
        }
        field_pool.push(Field {
            fd: fd, sc: sc_opt, name: rname, bit: bit, sub: sub, repeated: repeated, oneof: oneof, map: entry, always: is_entry, closed: closed, packs: ff.packed_repeated, required: ff.presence == PRESENCE_REQUIRED, delimited: delimited,
            dflt: dflt,
            clear: if dflt.len > 0 { keep(str("$ = ", dflt)) } else { sc_opt.clear },
        });
    }
    let has_words = (bits + 31) / 32;
    let fields = field_pool[fields_at..];
    let oneofs = oneof_pool[oneofs_at..];
    let by_number_at = field_pool.len;
    for &f in fields { field_pool.push(f); }
    let by_number = field_pool[by_number_at..];
    sort(by_number) { a, b => f_number(a) < f_number(b) };
    fe.fn_kw = if isRecursive(fe, full) { "recursive fn" } else { "fn" };
    let checked = holdsRequired(full);
    let folded = holdsMaps(full);

    emitOneofTypes(fe, oneofs, fields);
    emitRecord(fe, goose_name, fields, oneofs, has_words);
    emitPools(fe, goose_name, path);
    emitDecode(fe, goose_name, path, fields, checked, folded);
    emitEncode(fe, goose_name, path, by_number);
    emitSizeOf(fe, goose_name, path, by_number);
    emitClear(fe, goose_name, path, fields, oneofs, has_words);
    emitCopy(fe, goose_name, path, fields, oneofs, has_words);
    if checked { emitIsInitialized(fe, goose_name, path, fields, has_words); }
    if folded { emitFoldMaps(fe, goose_name, path, fields); }
    for &o in oneofs { emitOneofClear(fe, goose_name, o, fields); }
    for &f in fields { emitAccessors(fe, goose_name, path, f); }
    if is_entry { emitMapEntryHelpers(fe, goose_name, path, fields); }

    for i in google_protobuf::DescriptorProto_enum_type(m).len {
        emitEnum(fe, google_protobuf::DescriptorProto_enum_type_at(m, i), full);
    }
    for i in google_protobuf::DescriptorProto_nested_type(m).len {
        emitMessage(fe, google_protobuf::DescriptorProto_nested_type_at(m, i), path, full);
    }
}

// Claims a record field name of the message `full`.
fn claimRecordField(fe: FileEmitter&, names: u32, rname: const u8[:], full: const u8[:]) {
    if !mapContains(names, rname) {
        mapPut(names, rname);
        return;
    }
    collide(keep(str(fileName(fe.file), ": two fields of ", full, " map to the Goose record field ", rname)));
}

// The condition on pb_v that a value of enum field `fd` is declared, if
// its enum is closed, else "". The enum's own features decide that: a proto3 enum
// stays open in a proto2 field. Written out, the check needs nothing of its file.
fn closedCheck(fd: FieldDesc&) -> const u8[:] {
    let found = enumOf(fd);
    guard found else { return ""; }
    if !found.closed { return ""; }
    return knownValues(found.desc);
}

// The enum of field `fd`, in any file.
fn enumOf(fd: FieldDesc&) -> EnumInfo? {
    if fieldType(fd) != TYPE_ENUM { return null; }
    if !google_protobuf::FieldDescriptorProto_has_type_name(fd) { return null; }
    let tn = google_protobuf::FieldDescriptorProto_type_name(fd);
    let found = mapGet(enum_index, if startsWith(tn, ".") { tn[1..] } else { tn });
    guard found else { return null; }
    return enum_infos[found.index];
}

// The Goose expression of the default of singular field `fd`, if it is a
// number, bool or enum whose default is not the one of its type, else "". An enum
// with no [default] has its first value, which an open enum requires to be 0.
fn defaultLiteral(fd: FieldDesc&) -> const u8[:] {
    if !google_protobuf::FieldDescriptorProto_has_type(fd) { return ""; }
    let t = fd.type_;
    if t == TYPE_ENUM {
        let found = enumOf(fd);
        guard found else { return ""; }
        let number = enumDefault(found.desc, fd);
        if number == 0 { return ""; }
        return keep(str(number));
    }
    if !google_protobuf::FieldDescriptorProto_has_default_value(fd) { return ""; }
    let text = google_protobuf::FieldDescriptorProto_default_value(fd);
    if t == TYPE_STRING || t == TYPE_BYTES || t == TYPE_MESSAGE || t == TYPE_GROUP { return ""; }
    if t == TYPE_BOOL { return if text == "true" { "true" } else { "" }; }
    if t == TYPE_FLOAT { return floatLiteral(true, text); }
    if t == TYPE_DOUBLE { return floatLiteral(false, text); }
    return if text == "0" { "" } else { text };
}

// The global of a string or bytes field's [default], which reads as it
// while the field is not set.
fn emitDefaultBytes(fe: FileEmitter&, name: const u8[:], value: const u8[:]) {
    format(w, "\nlet ", name, ": u8[", value.len, "] = [");
    for i in value.len {
        if i > 0 { w.append(", "); }
        format(w, value[i]);
    }
    w.append("];\n");
}

// The storage of a sub-message field: a link, whose presence is the
// field's. Only its type and wire type apply: the emitters handle
// the rest of a field with `sub` set themselves.
fn refStorage(fe: FileEmitter&, sub: MessageInfo&, delimited: bool) -> Scalar& {
    return ref_scalars.push(Scalar {
        goose: subName(fe, sub, "Ref"),
        wire: if delimited { 3 } else { 2 },
        clear: "", read: "", write: "", nonzero: "", size: SZ_MESSAGE,
    });
}

// The pool that holds the run of repeated or map field `f`.
fn runPool(fe: FileEmitter&, f: Field&) -> const u8[:] {
    if f.map != null { return subName(fe, fieldMap(f), "entries"); }
    if f.sub != null { return subName(fe, fieldSub(f), "links"); }
    return sc_pool(f.sc);
}

// The ADT of each oneof: a variant per member, its name the member's
// record field name, and pb_none, which no field name can be.
fn emitOneofTypes(fe: FileEmitter&, oneofs: const Oneof[:], fields: const Field[:]) {
    for &o in oneofs {
        format(w,
            "enum ", o.type_name, " {\n",
            "    pb_none,\n");
        for &f in fields {
            if f.oneof .== o {
                format(w, "    ", f.name, " { v: ", f.sc.goose, " },\n");
            }
        }
        format(w,
            "}\n",
            "\n");
    }
}

fn emitRecord(fe: FileEmitter&, goose_name: const u8[:], fields: const Field[:], oneofs: const Oneof[:], has_words: i64) {
    format(w, "struct ", goose_name, " {\n");
    for &f in fields {
        if f.oneof != null {
            continue;
        }
        format(w, "    ", f.name, ": ", if f.repeated { "pb_Span" } else { f.sc.goose });
        if f.dflt.len > 0 {
            let d = f.dflt;
            format(w, " = ", d);
        }
        format(w, ",\n");
    }
    for &o in oneofs {
        format(w, "    ", o.name, ": ", o.type_name, " = ", o.type_name, ".pb_none,\n");
    }
    for i in has_words {
        format(w, "    pb_has", i, ": u32,   // has-bits of fields with presence\n");
    }
    format(w,
        "    pb_unknown: pb_Span,   // unknown fields: raw wire bytes in pb_bytes\n",
        "}\n");
}

// The link type and pools of decision 0001: sub-messages of this type
// live one per slot in M_pool, and repeated fields hold runs of links
// in M_links.
fn emitPools(fe: FileEmitter&, goose_name: const u8[:], path: const u8[:]) {
    let ref = generatedName(path, "Ref");
    let pool = generatedName(path, "pool");
    format(w,
        "\n",
        "// A link to a ", goose_name, " in ", pool, ", for sub-message fields.\n",
        "struct ", ref, " { m: ", goose_name, "&<u32 in ", pool, ">? }\n",
        "reusable var ", pool, ": ", goose_name, "[>..] = [];\n",
        "reusable[] var ", generatedName(path, "links"), ": ", ref, "[>..] = [];\n");
}

fn emitDecode(fe: FileEmitter&, goose_name: const u8[:], path: const u8[:], fields: const Field[:], checked: bool, folded: bool) {
    let decode = generatedName(path, "decode");
    let decode_from = generatedName(path, "decode_from");
    format(w,
        "\n",
        "// Merges the fields in r's window into m; on failure r.err is set.\n",
        "// Fields it does not know, or with another wire type, are kept as\n",
        "// unknown fields.\n",
        fe.fn_kw, " ", decode_from, "(r: pb_Reader&, m: ", goose_name, "&) {\n",
        "    var unknown_len: i64 = m.pb_unknown.len;\n",
        "    let unknown_had: i64 = unknown_len;\n");
    for &f in fields {
        if f.repeated || f.map != null {
            format(w,
                "    let pb_had", f_number(f), ": i64 = m.", f.name, ".len;\n",
                "    var pb_len", f_number(f), ": i64 = pb_had", f_number(f), ";\n");
        }
    }
    format(w,
        "    while r.pos < r.end {\n",
        "        let start = r.pos;\n",
        "        let tag = pb_read_tag(r);\n",
        "        if r.err != PB_OK { break; }\n");
    for i in fields.len {
        let f .= fields[i];
        format(w, "        ", if i == 0 { "" } else { "} else " }, "if tag == ", f_tag(f), " {\n");
        let x = fieldExpr(f);
        if f.repeated {
            emitDecodeRepeated(fe, f);
            continue;
        }
        if f.map != null {
            let entry .= fieldMap(f);
            emitDecodeMapEntry(fe, f, entry);
            continue;
        }
        if f.sub != null {
            let sub .= fieldSub(f);
            emitDecodeSubMessage(fe, path, f, sub);
            continue;
        }
        if f.oneof != null {
            let o .= fieldOneof(f);
            // Read first: a value that fails to read replaces nothing, nor
            // does one that a closed enum does not declare.
            format(w,
                "            let pb_v = ", subst(f.sc.read, empty_span), ";\n",
                "            if r.err != PB_OK { break; }\n");
            if f.closed.len > 0 {
                let known = f.closed;
                format(w,
                    "            if !(", known, ") {\n",
                    "                pb_unknown_keep(r, start, m.pb_unknown, unknown_len, unknown_had);\n",
                    "                continue;\n",
                    "            }\n");
            }
            format(w,
                "            ", o.clear, "(m);\n",
                "            m.", o.name, " = ", o.type_name, ".", f.name, " { v: pb_v };\n");
            continue;
        }
        if f.closed.len > 0 {
            let known = f.closed;
            // Its value, as it is on the wire, goes with the unknown fields.
            format(w,
                "            let pb_v = ", subst(f.sc.read, x), ";\n",
                "            if r.err != PB_OK { break; }\n",
                "            if ", known, " {\n",
                "                ", x, " = pb_v;\n",
                "                m.pb_has", f.bit / 32, " |= 0x", hex8(bitMask(f.bit)), ";\n",
                "            } else {\n",
                "                pb_unknown_keep(r, start, m.pb_unknown, unknown_len, unknown_had);\n",
                "            }\n");
            continue;
        }
        format(w, "            ", x, " = ", subst(f.sc.read, x), ";\n");
        if f.bit >= 0 {
            let b = f.bit;
            format(w, "            m.pb_has", b / 32, " |= 0x", hex8(bitMask(b)), ";\n");
        }
    }
    if fields.len == 0 {
        format(w, "        pb_unknown_append(r, start, tag, m.pb_unknown, unknown_len, unknown_had);\n");
    } else {
        format(w,
            "        } else {\n",
            "            pb_unknown_append(r, start, tag, m.pb_unknown, unknown_len, unknown_had);\n",
            "        }\n");
    }
    format(w, "    }\n");
    for &f in fields {
        if f.repeated || f.map != null {
            format(w, "    m.", f.name, " = pb_trim(", runPool(fe, f), ", m.", f.name, ", pb_len", f_number(f), ");\n");
        }
    }
    format(w,
        "    m.pb_unknown = pb_bytes_trim(m.pb_unknown, unknown_len);\n",
        "}\n",
        "\n",
        "// Merges buf into m. 0 on success, else a PB_ERR_* code; m then holds a\n",
        "// partial message, which the caller clears.\n",
        "fn ", decode, "(buf: const u8[:], m: ", goose_name, "&) -> i32 {\n",
        "    var r = pb_reader(buf);\n",
        "    ", decode_from, "(r, m);\n");
    if folded {
        format(w, "    if r.err == PB_OK { ", generatedName(path, "fold_maps"), "(m); }\n");
    }
    if checked {
        // On the whole message: a later occurrence may set what an
        // earlier one of a sub-message lacks.
        format(w, "    if r.err == PB_OK && !", generatedName(path, "is_initialized"), "(m) { return PB_ERR_REQUIRED; }\n");
    }
    format(w,
        "    return r.err;\n",
        "}\n");
}

// The two branches of decode_from for a repeated scalar, the value on
// its own and packed: either form is read, whichever the field declares.
// A packed run is a window of its own, so a value cannot read past its
// end. After a failure the caller stops on r.err, as for a sub-message.
fn emitDecodeRepeated(fe: FileEmitter&, f: Field&) {
    if f.sub != null {
        let sub .= fieldSub(f);
        let pool = subName(fe, sub, "pool");
        format(w, f_subOpen(f));
        format(w,
            "            pb_reserve(", runPool(fe, f), ", m.", f.name, ", pb_len", f_number(f), ", pb_had", f_number(f), ");\n",
            "            let pb_sub .= ", pool, ".alloc_ref(", sub.goose_name, " { .. });\n",
            "            pb_run(", runPool(fe, f), ", m.", f.name, ")[pb_len", f_number(f), "].m .= pb_sub;\n",
            "            pb_len", f_number(f), "++;\n",
            f_subWindow(f), "            ", subName(fe, sub, "decode_from"), "(r, pb_sub);\n",
            "            if r.err != PB_OK { break; }\n",
            f_subClose(f));
        return;
    }
    if f.sc.size == SZ_BYTES {
        format(w, "            pb_append(pb_spans, m.", f.name, ", pb_len", f_number(f), ", pb_had", f_number(f), ", ", subst(f.sc.read, empty_span), ");\n");
        return;
    }
    if f.closed.len > 0 {
        let known = f.closed;
        // An unknown element of a packed run leaves on its own, with the
        // tag of a value on its own.
        format(w,
            "            let pb_v = ", f.sc.read, ";\n",
            "            if r.err != PB_OK { break; }\n",
            "            if ", known, " {\n",
            "                pb_append(", sc_pool(f.sc), ", m.", f.name, ", pb_len", f_number(f), ", pb_had", f_number(f), ", pb_v);\n",
            "            } else {\n",
            "                pb_unknown_keep(r, start, m.pb_unknown, unknown_len, unknown_had);\n",
            "            }\n",
            "        } else if tag == ", f_packedTag(f), " {\n",
            "            let pb_n = pb_read_len(r);\n",
            "            if r.err != PB_OK { break; }\n",
            "            let pb_outer = r.end;\n",
            "            r.end = r.pos + pb_n;\n",
            "            while r.pos < r.end {\n",
            "                let pb_at = r.pos;\n",
            "                let pb_v = ", f.sc.read, ";\n",
            "                if r.err != PB_OK { break; }\n",
            "                if ", known, " {\n",
            "                    pb_append(", sc_pool(f.sc), ", m.", f.name, ", pb_len", f_number(f), ", pb_had", f_number(f), ", pb_v);\n",
            "                } else {\n",
            "                    pb_unknown_element(r, ", f_tag(f), ", pb_at, m.pb_unknown, unknown_len, unknown_had);\n",
            "                }\n",
            "            }\n",
            "            if r.err != PB_OK { break; }\n",
            "            r.end = pb_outer;\n");
        return;
    }
    format(w,
        "            pb_append(", sc_pool(f.sc), ", m.", f.name, ", pb_len", f_number(f), ", pb_had", f_number(f), ", ", f.sc.read, ");\n",
        "        } else if tag == ", f_packedTag(f), " {\n",
        "            let pb_n = pb_read_len(r);\n",
        "            if r.err != PB_OK { break; }\n",
        "            let pb_outer = r.end;\n",
        "            r.end = r.pos + pb_n;\n",
        "            while r.pos < r.end { pb_append(", sc_pool(f.sc), ", m.", f.name, ", pb_len", f_number(f), ", pb_had", f_number(f), ", ", f.sc.read, "); }\n",
        "            if r.err != PB_OK { break; }\n",
        "            r.end = pb_outer;\n");
}

// The branch of decode_from for a map entry. It decodes into the next
// slot of the run. Repeated keys are folded once, by M_decode (see
// emitFoldMaps), as looking each one up would be quadratic. A partial
// entry is freed: only whole ones are in the map.
fn emitDecodeMapEntry(fe: FileEmitter&, f: Field&, entry: MessageInfo&) {
    let pool = runPool(fe, f);
    format(w,
        "            let pb_n = pb_read_len(r);\n",
        "            if r.err != PB_OK { break; }\n",
        "            if r.depth >= PB_MAX_DEPTH { pb_fail(r, PB_ERR_DEPTH); break; }\n",
        "            pb_reserve(", pool, ", m.", f.name, ", pb_len", f_number(f), ", pb_had", f_number(f), ");\n",
        "            let pb_e .= pb_run(", pool, ", m.", f.name, ")[pb_len", f_number(f), "];\n",
        "            let pb_outer = r.end;\n",
        "            r.end = r.pos + pb_n;\n",
        "            r.depth++;\n",
        "            ", subName(fe, entry, "decode_from"), "(r, pb_e);\n",
        "            if r.err != PB_OK { ", subName(fe, entry, "clear"), "(pb_e); break; }\n",
        "            r.depth--;\n",
        "            r.end = pb_outer;\n");
    if f.closed.len > 0 {
        let known = f.closed;
        // An entry whose value a closed enum does not declare is not in the
        // map: its bytes go with the unknown fields.
        format(w,
            "            let pb_v = pb_e.value;\n",
            "            if !(", known, ") {\n",
            "                ", subName(fe, entry, "clear"), "(pb_e);\n",
            "                pb_unknown_keep(r, start, m.pb_unknown, unknown_len, unknown_had);\n",
            "                continue;\n",
            "            }\n");
    }
    format(w,
        "            ", subName(fe, entry, "place"), "(pb_e);\n",
        "            pb_len", f_number(f), "++;\n");
}

// The statements adding the payload size of packed field `f` up in a
// new local pb_n.
fn emitPackedSize(fe: FileEmitter&, f: Field&, indent: const u8[:]) {
    if f.sc.size == SZ_FIXED {
        format(w, indent, "let pb_n: i64 = ", f.sc.fixed, " * m.", f.name, ".len;\n");
    } else {
        format(w, indent, "var pb_n: i64 = 0;\n");
        format(w, indent, "for pb_v in pb_run(", sc_pool(f.sc), ", m.", f.name, ") { pb_n += pb_varint_size(", subst(f.sc.write_value, "pb_v"), "); }\n");
    }
}

// The branch of decode_from for a sub-message: an occurrence merges
// into the message already there (decision 0004). After a failure
// r.end is not restored: the caller stops on r.err too.
fn emitDecodeSubMessage(fe: FileEmitter&, path: const u8[:], f: Field&, sub: MessageInfo&) {
    format(w, f_subOpen(f));
    format(w,
        f_subWindow(f), "            ", subName(fe, sub, "decode_from"), "(r, ", accessorName(path, fieldName(f.fd), mutable_acc), "(m));\n",
        "            if r.err != PB_OK { break; }\n",
        f_subClose(f));
}

fn emitEncode(fe: FileEmitter&, goose_name: const u8[:], path: const u8[:], fields: const Field[:]) {
    format(w,
        "\n",
        "// Appends m's wire encoding, ", generatedName(path, "size_of"), "(m) bytes, to out.\n",
        fe.fn_kw, " ", generatedName(path, "encode"), "(m: ", goose_name, "&, out: u8[>..]&) {\n");
    for &f in fields {
        let x = fieldExpr(f);
        if f.map != null {
            let entry .= fieldMap(f);
            format(w,
                "    for pb_i in m.", f.name, ".len {\n",
                "        let pb_e .= pb_run(", runPool(fe, f), ", m.", f.name, ")[pb_i];\n",
                "        pb_write_varint(out, ", f_tag(f), ");\n",
                "        pb_write_varint(out, ", subName(fe, entry, "size_of"), "(pb_e) as! u64);\n",
                "        ", subName(fe, entry, "encode"), "(pb_e, out);\n",
                "    }\n");
            continue;
        }
        if f.oneof != null {
            let o .= fieldOneof(f);
            if f.sub != null {
                let sub .= fieldSub(f);
                format(w,
                    "    match m.", o.name, " {\n",
                    "        ", f.name, " pb_p => {\n",
                    "            let pb_l = pb_p.v.m;\n",
                    "            if pb_l {\n",
                    subWrite(f, "                ", "pb_l", subName(fe, sub, "size_of"), subName(fe, sub, "encode")), "\n",
                    "            }\n",
                    "        },\n",
                    "        _ => {},\n",
                    "    }\n");
            } else {
                format(w,
                    "    match m.", o.name, " {\n",
                    "        ", f.name, " pb_p => {\n",
                    "            pb_write_varint(out, ", f_tag(f), ");\n",
                    "            ", subst(f.sc.write, "pb_p.v"), ";\n",
                    "        },\n",
                    "        _ => {},\n",
                    "    }\n");
            }
            continue;
        }
        if f.repeated && f.sub != null {
            let sub .= fieldSub(f);
            format(w,
                "    for pb_ref in pb_run(", runPool(fe, f), ", m.", f.name, ") {\n",
                "        let pb_l = pb_ref.m;\n",
                "        guard pb_l else { continue; }\n",
                subWrite(f, "        ", "pb_l", subName(fe, sub, "size_of"), subName(fe, sub, "encode")), "\n",
                "    }\n");
            continue;
        }
        if f.repeated && f.sc.size == SZ_BYTES {
            format(w,
                "    for pb_v in pb_run(pb_spans, m.", f.name, ") {\n",
                "        pb_write_varint(out, ", f_tag(f), ");\n",
                "        pb_write_bytes(out, pb_v);\n",
                "    }\n");
            continue;
        }
        if f.repeated {
            format(w, "    if m.", f.name, ".len > 0 {\n");
            if f.packs {
                format(w, "        pb_write_varint(out, ", f_packedTag(f), ");\n");
                emitPackedSize(fe, f, "        ");
                format(w, "        pb_write_varint(out, pb_n as! u64);\n");
                format(w, "        for pb_v in pb_run(", sc_pool(f.sc), ", m.", f.name, ") { ", subst(f.sc.write, "pb_v"), "; }\n");
            } else {
                format(w, "        for pb_v in pb_run(", sc_pool(f.sc), ", m.", f.name, ") {\n");
                format(w, "            pb_write_varint(out, ", f_tag(f), ");\n");
                format(w,
                    "            ", subst(f.sc.write, "pb_v"), ";\n",
                    "        }\n");
            }
            format(w, "    }\n");
            continue;
        }
        if f.sub != null {
            let sub .= fieldSub(f);
            format(w,
                "    let pb_f", f_number(f), " = ", x, ".m;\n",
                "    if pb_f", f_number(f), " {\n",
                subWrite(f, "        ", keep(str("pb_f", f_number(f))), subName(fe, sub, "size_of"), subName(fe, sub, "encode")), "\n",
                "    }\n");
            continue;
        }
        if f.always {
            format(w, "    pb_write_varint(out, ", f_tag(f), ");\n");
            format(w, "    ", subst(f.sc.write, x), ";\n");
            continue;
        }
        format(w, "    if ", isSet(f, x), " {\n");
        format(w, "        pb_write_varint(out, ", f_tag(f), ");\n");
        format(w, "        ", subst(f.sc.write, x), ";\n");
        format(w, "    }\n");
    }
    format(w,
        "    out.append(pb_run(pb_bytes, m.pb_unknown));\n",
        "}\n");
}

fn emitSizeOf(fe: FileEmitter&, goose_name: const u8[:], path: const u8[:], fields: const Field[:]) {
    format(w,
        "\n",
        "// The size of m's wire encoding, in bytes.\n",
        fe.fn_kw, " ", generatedName(path, "size_of"), "(m: ", goose_name, "&) -> i64 {\n",
        "    var n: i64 = 0;\n");
    for &f in fields {
        let x = fieldExpr(f);
        let ts = varintSize(f_tag(f));
        if f.map != null {
            let entry .= fieldMap(f);
            format(w,
                "    for pb_i in m.", f.name, ".len {\n",
                "        n += ", ts, " + pb_len_size(", subName(fe, entry, "size_of"), "(pb_run(", runPool(fe, f), ", m.", f.name, ")[pb_i]));\n",
                "    }\n");
            continue;
        }
        if f.oneof != null {
            let o .= fieldOneof(f);
            format(w, "    match m.", o.name, " {\n");
            if f.sc.size == SZ_MESSAGE {
                format(w,
                    "        ", f.name, " pb_p => {\n",
                    "            let pb_l = pb_p.v.m;\n",
                    "            if pb_l { n += ", subSize(f, subName(fe, fieldSub(f), "size_of"), "pb_l"), "; }\n",
                    "        },\n");
            }
            if f.sc.size == SZ_VARINT {
                format(w, "        ", f.name, " pb_p => { n += ", ts, " + pb_varint_size(", subst(f.sc.write_value, "pb_p.v"), "); },\n");
            }
            if f.sc.size == SZ_FIXED {
                format(w, "        ", f.name, " => { n += ", ts + f.sc.fixed, "; },\n");
            }
            if f.sc.size == SZ_BYTES {
                format(w, "        ", f.name, " pb_p => { n += ", ts, " + pb_bytes_size(pb_p.v); },\n");
            }
            format(w,
                "        _ => {},\n",
                "    }\n");
            continue;
        }
        if f.repeated && f.sub != null {
            format(w,
                "    for pb_ref in pb_run(", runPool(fe, f), ", m.", f.name, ") {\n",
                "        let pb_l = pb_ref.m;\n",
                "        guard pb_l else { continue; }\n",
                "        n += ", subSize(f, subName(fe, fieldSub(f), "size_of"), "pb_l"), ";\n",
                "    }\n");
            continue;
        }
        if f.repeated && f.sc.size == SZ_BYTES {
            format(w, "    for pb_v in pb_run(pb_spans, m.", f.name, ") { n += ", ts, " + pb_bytes_size(pb_v); }\n");
            continue;
        }
        if f.repeated {
            format(w, "    if m.", f.name, ".len > 0 {\n");
            if f.packs {
                emitPackedSize(fe, f, "        ");
                format(w, "        n += ", varintSize(f_packedTag(f)), " + pb_len_size(pb_n);\n");
            } else {
                emitPackedSize(fe, f, "        ");
                format(w, "        n += ", ts, " * m.", f.name, ".len + pb_n;\n");
            }
            format(w, "    }\n");
            continue;
        }
        if f.sub != null {
            let sub .= fieldSub(f);
            format(w, "    let pb_f", f_number(f), " = ", x, ".m;\n");
            format(w, "    if pb_f", f_number(f), " { n += ", subSize(f, subName(fe, sub, "size_of"), keep(str("pb_f", f_number(f)))), "; }\n");
            continue;
        }
        if f.always {
            format(w, "    n += ");
        } else {
            format(w, "    if ", isSet(f, x), " { n += ");
        }
        if f.sc.size == SZ_VARINT {
            format(w, ts, " + pb_varint_size(", subst(f.sc.write_value, x), ");");
        }
        if f.sc.size == SZ_FIXED {
            format(w, ts + f.sc.fixed, ";");
        }
        if f.sc.size == SZ_BYTES {
            format(w, ts, " + pb_bytes_size(", x, ");");
        }
        format(w, if f.always { "\n" } else { " }\n" });
    }
    format(w,
        "    n += m.pb_unknown.len;\n",
        "    return n;\n",
        "}\n");
}

fn emitClear(fe: FileEmitter&, goose_name: const u8[:], path: const u8[:], fields: const Field[:], oneofs: const Oneof[:], has_words: i64) {
    format(w,
        "\n",
        "// Frees what m owns and resets it to the empty message.\n",
        fe.fn_kw, " ", generatedName(path, "clear"), "(m: ", goose_name, "&) {\n");
    for &f in fields {
        if f.oneof != null {
            continue;
        }
        let x = fieldExpr(f);
        if (f.repeated && f.sub != null) || f.map != null {
            format(w, "    ", accessorName(path, fieldName(f.fd), clear_acc), "(m);\n");
            continue;
        }
        if f.repeated && f.sc.size == SZ_BYTES {
            format(w, "    ", x, " = pb_spans_free(", x, ");\n");
            continue;
        }
        if f.repeated {
            format(w, "    ", x, " = pb_resize(", sc_pool(f.sc), ", ", x, ", 0);\n");
            continue;
        }
        if f.sub != null {
            format(w, "    ", accessorName(path, fieldName(f.fd), clear_acc), "(m);\n");
            continue;
        }
        format(w, "    ", subst(f.clear, x), ";\n");
    }
    for &o in oneofs {
        format(w, "    ", o.clear, "(m);\n");
    }
    for i in has_words {
        format(w, "    m.pb_has", i, " = 0;\n");
    }
    format(w,
        "    m.pb_unknown = pb_bytes_free(m.pb_unknown);\n",
        "}\n");
}

// fold_maps: folds repeated keys in every map of m and of what it holds.
// M_decode runs it once, when all the input is read. Doing it when each
// message ends would repeat it for a sub-message that repeats on the wire,
// and one input could then make it quadratic. Top-down, so an entry that
// is replaced is not folded first.
fn emitFoldMaps(fe: FileEmitter&, goose_name: const u8[:], path: const u8[:], fields: const Field[:]) {
    format(w,
        "\n",
        "// Folds repeated keys in the maps of m and of the messages it holds, which\n",
        "// decoding appends without looking them up: the last value wins, in the\n",
        "// place of the first occurrence.\n",
        fe.fn_kw, " ", generatedName(path, "fold_maps"), "(m: ", goose_name, "&) {\n");
    for &f in fields {
        if f.map != null {
            let entry .= fieldMap(f);
            format(w, "    m.", f.name, " = ", subName(fe, entry, "fold"), "(m.", f.name, ");\n");
        }
        if !fieldHoldsMaps(f) {
            continue;
        }
        if f.map != null {
            let entry .= fieldMap(f);
            format(w, "    for pb_i in m.", f.name, ".len { ", subName(fe, entry, "fold_maps"), "(pb_run(", runPool(fe, f), ", m.", f.name, ")[pb_i]); }\n");
            continue;
        }
        let fold = subName(fe, fieldSub(f), "fold_maps");
        if f.repeated {
            format(w,
                "    for pb_ref in pb_run(", runPool(fe, f), ", m.", f.name, ") {\n",
                "        let pb_l = pb_ref.m;\n",
                "        guard pb_l else { continue; }\n",
                "        ", fold, "(pb_l);\n",
                "    }\n");
        } else if f.oneof != null {
            let o .= fieldOneof(f);
            format(w,
                "    match m.", o.name, " {\n",
                "        ", f.name, " pb_p => {\n",
                "            let pb_l = pb_p.v.m;\n",
                "            if pb_l { ", fold, "(pb_l); }\n",
                "        },\n",
                "        _ => {},\n",
                "    }\n");
        } else {
            format(w,
                "    let pb_f", f_number(f), " = m.", f.name, ".m;\n",
                "    if pb_f", f_number(f), " { ", fold, "(pb_f", f_number(f), "); }\n");
        }
    }
    format(w, "}\n");
}

// is_initialized: every required field is set, in m and in what it holds.
fn emitIsInitialized(fe: FileEmitter&, goose_name: const u8[:], path: const u8[:], fields: const Field[:], has_words: i64) {
    format(w,
        "\n",
        "// True if every required field is set, in m and in the messages it holds.\n",
        fe.fn_kw, " ", generatedName(path, "is_initialized"), "(m: ", goose_name, "&) -> bool {\n");
    var masks: u32[>..] = [];
    for pb_mi in has_words { masks.push(0); }
    for &f in fields {
        if !f.required { continue; }
        if f.bit >= 0 { masks[f.bit / 32] |= bitMask(f.bit); }
    }
    for i in masks.len {
        let mask = masks[i];
        if mask != 0 {
            format(w, "    if (m.pb_has", i, " & 0x", hex8(mask), ") != 0x", hex8(mask), " { return false; }\n");
        }
    }
    for &f in fields {
        if f.required && f.sub != null {
            format(w, "    if m.", f.name, ".m == null { return false; }\n");
        }
        if !fieldHoldsRequired(f) {
            continue;
        }
        if f.map != null {
            let entry .= fieldMap(f);
            format(w,
                "    for pb_i in m.", f.name, ".len {\n",
                "        if !", subName(fe, entry, "is_initialized"), "(pb_run(", runPool(fe, f), ", m.", f.name, ")[pb_i]) { return false; }\n",
                "    }\n");
            continue;
        }
        let check = subName(fe, fieldSub(f), "is_initialized");
        if f.repeated {
            format(w,
                "    for pb_ref in pb_run(", runPool(fe, f), ", m.", f.name, ") {\n",
                "        let pb_l = pb_ref.m;\n",
                "        guard pb_l else { continue; }\n",
                "        if !", check, "(pb_l) { return false; }\n",
                "    }\n");
        } else if f.oneof != null {
            let o .= fieldOneof(f);
            format(w,
                "    match m.", o.name, " {\n",
                "        ", f.name, " pb_p => {\n",
                "            let pb_l = pb_p.v.m;\n",
                "            if pb_l { if !", check, "(pb_l) { return false; } }\n",
                "        },\n",
                "        _ => {},\n",
                "    }\n");
        } else {
            format(w,
                "    let pb_f", f_number(f), " = m.", f.name, ".m;\n",
                "    if pb_f", f_number(f), " { if !", check, "(pb_f", f_number(f), ") { return false; } }\n");
        }
    }
    format(w,
        "    return true;\n",
        "}\n");
}

// Decision 0001: copying a record shares what its spans and links
// reach, so M_copy duplicates that too.
fn emitCopy(fe: FileEmitter&, goose_name: const u8[:], path: const u8[:], fields: const Field[:], oneofs: const Oneof[:], has_words: i64) {
    format(w,
        "\n",
        "// Makes dst a deep copy of src, freeing what dst owned. The two share\n",
        "// nothing afterwards. Neither may be a sub-message of the other.\n",
        fe.fn_kw, " ", generatedName(path, "copy"), "(dst: ", goose_name, "&, src: ", goose_name, "&) {\n",
        "    if dst .== src { return; }\n",
        "    ", generatedName(path, "clear"), "(dst);\n");
    for &f in fields {
        if f.oneof != null {
            continue;
        }
        if f.map != null {
            let entry .= fieldMap(f);
            let pool = runPool(fe, f);
            format(w,
                "    dst.", f.name, " = pb_resize(", pool, ", dst.", f.name, ", src.", f.name, ".len);\n",
                "    for pb_i in src.", f.name, ".len {\n",
                "        ", subName(fe, entry, "copy"), "(pb_run(", pool, ", dst.", f.name, ")[pb_i], pb_run(", pool, ", src.", f.name, ")[pb_i]);\n",
                "    }\n");
        } else if f.repeated && f.sub != null {
            let sub .= fieldSub(f);
            let links = runPool(fe, f);
            let pool = subName(fe, sub, "pool");
            format(w,
                "    dst.", f.name, " = pb_resize(", links, ", dst.", f.name, ", src.", f.name, ".len);\n",
                "    for pb_i in src.", f.name, ".len {\n",
                "        let pb_l = pb_run(", links, ", src.", f.name, ")[pb_i].m;\n",
                "        guard pb_l else { continue; }\n",
                "        let pb_c .= ", pool, ".alloc_ref(", sub.goose_name, " { .. });\n",
                "        pb_run(", links, ", dst.", f.name, ")[pb_i].m .= pb_c;\n",
                "        ", subName(fe, sub, "copy"), "(pb_c, pb_l);\n",
                "    }\n");
        } else if f.repeated && f.sc.size == SZ_BYTES {
            format(w, "    dst.", f.name, " = pb_spans_copy(src.", f.name, ");\n");
        } else if f.repeated {
            format(w, "    dst.", f.name, " = pb_copy_run(", sc_pool(f.sc), ", src.", f.name, ");\n");
        } else if f.sub != null {
            let sub .= fieldSub(f);
            format(w,
                "    let pb_f", f_number(f), " = src.", f.name, ".m;\n",
                "    if pb_f", f_number(f), " { ", subName(fe, sub, "copy"), "(", accessorName(path, fieldName(f.fd), mutable_acc), "(dst), pb_f", f_number(f), "); }\n");
        } else if f.sc.size == SZ_BYTES {
            format(w, "    dst.", f.name, " = pb_bytes_copy(src.", f.name, ");\n");
        } else {
            format(w, "    dst.", f.name, " = src.", f.name, ";\n");
        }
    }
    for &o in oneofs {
        format(w, "    match src.", o.name, " {\n");
        for &f in fields {
            if f.oneof .!= o {
                continue;
            }
            if f.sub != null {
                let sub .= fieldSub(f);
                format(w,
                    "        ", f.name, " pb_p => {\n",
                    "            let pb_l = pb_p.v.m;\n",
                    "            if pb_l { ", subName(fe, sub, "copy"), "(", accessorName(path, fieldName(f.fd), mutable_acc), "(dst), pb_l); }\n",
                    "        },\n");
            } else if f.sc.size == SZ_BYTES {
                format(w, "        ", f.name, " pb_p => { dst.", o.name, " = ", o.type_name, ".", f.name, " { v: pb_bytes_copy(pb_p.v) }; },\n");
            } else {
                format(w, "        ", f.name, " pb_p => { dst.", o.name, " = ", o.type_name, ".", f.name, " { v: pb_p.v }; },\n");
            }
        }
        format(w,
            "        _ => {},\n",
            "    }\n");
    }
    for i in has_words {
        format(w, "    dst.pb_has", i, " = src.pb_has", i, ";\n");
    }
    format(w,
        "    dst.pb_unknown = pb_bytes_copy(src.pb_unknown);\n",
        "}\n");
}

// The accessors of a stored field, per fieldAccessors: the getter
// and set_ of strings and bytes, and set_, has_ and clear_ of fields
// with presence; a sub-message has its own (emitSubMessageAccessors).
fn emitAccessors(fe: FileEmitter&, goose_name: const u8[:], path: const u8[:], f: Field&) {
    if f.oneof != null {
        let o .= fieldOneof(f);
        emitOneofAccessors(fe, goose_name, path, f, o);
        return;
    }
    if f.map != null {
        let entry .= fieldMap(f);
        emitMapAccessors(fe, goose_name, path, f, entry);
        return;
    }
    if f.repeated {
        if f.sub != null {
            let sub .= fieldSub(f);
            emitRepeatedMessageAccessors(fe, goose_name, path, f, sub);
            return;
        }
        if f.sc.size == SZ_BYTES {
            emitRepeatedStringAccessors(fe, goose_name, path, f);
            return;
        }
        emitRepeatedAccessors(fe, goose_name, path, f);
        return;
    }
    if f.sub != null {
        let sub .= fieldSub(f);
        emitSubMessageAccessors(fe, goose_name, path, f, sub);
        return;
    }
    let fname = fieldName(f.fd);
    let x = fieldExpr(f);
    let is_bytes = f.sc.size == SZ_BYTES;
    if hasDefaultBytes(f.fd) {
        let value = defaultBytes(f.fd);
        let name = accessorName(path, fname, default_acc);
        let b = f.bit;
        emitDefaultBytes(fe, name, value);
        format(w,
            "\n",
            "// The contents of ", fname, ", in pb_bytes, or ", name, " if it is not set: valid\n",
            "// until it is next set or m is cleared.\n",
            "fn ", accessorName(path, fname, get_acc), "(m: ", goose_name, "&) -> const u8[:] {\n",
            "    if (m.pb_has", b / 32, " & 0x", hex8(bitMask(b)), ") == 0 { return ", name, "; }\n",
            "    return pb_run(pb_bytes, ", x, ");\n",
            "}\n");
    } else if is_bytes {
        format(w,
            "\n",
            "// The contents of ", fname, ", in pb_bytes: valid until it is next set or m\n",
            "// is cleared.\n",
            "fn ", accessorName(path, fname, get_acc), "(m: ", goose_name, "&) -> u8[:] { return pb_run(pb_bytes, ", x, "); }\n");
    }
    if !is_bytes && f.bit < 0 {
        return;
    }
    format(w,
        "\n",
        "// Sets ", fname);
    if is_bytes {
        format(w, " to a copy of v");
    }
    if f.bit >= 0 {
        format(w,
            " and marks it present:\n",
            "// it is encoded even when ", if is_bytes { "empty" } else { "0" });
    }
    format(w,
        ".\n",
        "fn ", accessorName(path, fname, set_acc), "(m: ", goose_name, "&, v: ", sc_setType(f.sc), ") {\n",
        "    ", subst(f.sc.set, x), ";\n");
    if f.bit < 0 {
        format(w, "}\n");
        return;
    }
    let b = f.bit;
    format(w,
        "    m.pb_has", b / 32, " |= 0x", hex8(bitMask(b)), ";\n",
        "}\n",
        "\n",
        "fn ", accessorName(path, fname, has_acc), "(m: ", goose_name, "&) -> bool { return (m.pb_has", b / 32, " & 0x", hex8(bitMask(b)), ") != 0; }\n",
        "\n",
        "fn ", accessorName(path, fname, clear_acc), "(m: ", goose_name, "&) {\n",
        "    ", subst(f.clear, x), ";\n",
        "    m.pb_has", b / 32, " &= 0x", hex8(~bitMask(b)), ";\n",
        "}\n");
}

// What a map entry has besides a message's functions. Lookup is linear
// (decision 0001).
fn emitMapEntryHelpers(fe: FileEmitter&, goose_name: const u8[:], path: const u8[:], fields: const Field[:]) {
    let key .= mapField(fields, 1);
    let value .= mapField(fields, 2);
    let entries = generatedName(path, "entries");
    let find = generatedName(path, "find");
    let key_is_bytes = key.sc.size == SZ_BYTES;
    format(w,
        "\n",
        "// Runs of entries: one per map field of this type.\n",
        "reusable[] var ", entries, ": ", goose_name, "[>..] = [];\n",
        "\n",
        "// The index of the entry with key k among the first `used` of run s, or -1.\n",
        "fn ", find, "(s: pb_Span, used: i64, k: ", sc_setType(key.sc), ") -> i64 {\n",
        "    let pb_run_s = pb_run(", entries, ", s);\n",
        "    for pb_i in used {\n");
    if key_is_bytes {
        format(w, "        if pb_run(pb_bytes, pb_run_s[pb_i].key) == k { return pb_i; }\n");
    } else {
        format(w, "        if pb_run_s[pb_i].key == k { return pb_i; }\n");
    }
    format(w,
        "    }\n",
        "    return -1;\n",
        "}\n",
        "\n",
        "// The entry with key k in run s, added with the default value if there is none.\n",
        "fn ", generatedName(path, "slot"), "(s: pb_Span&, k: ", sc_setType(key.sc), ") -> ", goose_name, "& {\n",
        "    var pb_i = ", find, "(s, s.len, k);\n",
        "    if pb_i < 0 {\n",
        "        pb_i = s.len;\n",
        "        s = pb_resize(", entries, ", s, pb_i + 1);\n");
    if key_is_bytes {
        format(w, "        ", accessorName(path, "key", set_acc), "(pb_run(", entries, ", s)[pb_i], k);\n");
    } else {
        format(w, "        pb_run(", entries, ", s)[pb_i].key = k;\n");
    }
    if value.sub != null {
        format(w, "        ", accessorName(path, "value", mutable_acc), "(pb_run(", entries, ", s)[pb_i]);\n");
    }
    format(w,
        "    }\n",
        "    return pb_run(", entries, ", s)[pb_i];\n",
        "}\n",
        "\n",
        "// Settles an entry just decoded: a missing message value is an empty one,\n",
        "// and unknown fields are dropped.\n",
        "fn ", generatedName(path, "place"), "(pb_e: ", goose_name, "&) {\n");
    if value.sub != null {
        format(w, "    ", accessorName(path, "value", mutable_acc), "(pb_e);\n");
    }
    format(w,
        "    pb_e.pb_unknown = pb_bytes_free(pb_e.pb_unknown);\n",
        "}\n",
        "\n",
        "// Run s with each repeated key folded: the last value wins, in the place of\n",
        "// the first occurrence, and what the others held is freed. O(n log n).\n",
        "// fold_maps calls it; decoding leaves repeated keys for it.\n",
        "fn ", generatedName(path, "fold"), "(s: pb_Span) -> pb_Span {\n",
        "    if s.len < 2 { return s; }\n",
        "    let pb_r = pb_run(", entries, ", s);\n",
        "    var pb_keys: ", if key_is_bytes { "pb_StrKey" } else { "pb_NumKey" }, "[>..] = [];\n",
        "    for pb_i in pb_r.len { pb_keys.push(", if key_is_bytes { "pb_StrKey" } else { "pb_NumKey" }, " { key: ", foldKey(key.sc), ", at: pb_i as! u32 }); }\n",
        "    ", if key_is_bytes { "pb_sort_str_keys" } else { "pb_sort_num_keys" }, "(pb_keys);\n",
        "    var pb_gone: bool[>..] = [];\n",
        "    var pb_i: i64 = 0;\n",
        "    while pb_i < pb_keys.len {\n",
        "        var pb_j = pb_i + 1;\n",
        "        while pb_j < pb_keys.len && ", if key_is_bytes { "pb_same_str_key" } else { "pb_same_num_key" }, "(pb_keys[pb_i], pb_keys[pb_j]) { pb_j++; }\n",
        "        if pb_j - pb_i > 1 {\n",
        "            if pb_gone.len == 0 { for pb_k in pb_r.len { pb_gone.push(false); } }\n",
        "            let pb_first: i64 = pb_keys[pb_i].at;\n",
        "            let pb_last: i64 = pb_keys[pb_j - 1].at;\n",
        "            for pb_k in pb_j - pb_i - 1 {\n",
        "                let pb_at: i64 = pb_keys[pb_i + pb_k].at;\n",
        "                ", generatedName(path, "clear"), "(pb_r[pb_at]);\n",
        "                pb_gone[pb_at] = true;\n",
        "            }\n",
        "            pb_gone[pb_first] = false;\n",
        "            pb_gone[pb_last] = true;\n",
        "            pb_r[pb_first] = pb_r[pb_last];\n",
        "            pb_r[pb_last] = ", goose_name, " { .. };\n",
        "        }\n",
        "        pb_i = pb_j;\n",
        "    }\n",
        "    if pb_gone.len == 0 { return s; }\n",
        "    var pb_kept: i64 = 0;\n",
        "    for pb_k in pb_r.len {\n",
        "        if pb_gone[pb_k] { continue; }\n",
        "        if pb_kept != pb_k { pb_r[pb_kept] = pb_r[pb_k]; pb_r[pb_k] = ", goose_name, " { .. }; }\n",
        "        pb_kept++;\n",
        "    }\n",
        "    return pb_resize(", entries, ", s, pb_kept);\n",
        "}\n");
}

// The accessors of a map field. Entries live in a run that may move, so
// a reference to one is good until the map next changes; a message value
// has a slot of its own, and outlives other changes.
fn emitMapAccessors(fe: FileEmitter&, goose_name: const u8[:], path: const u8[:], f: Field&, entry: MessageInfo&) {
    let fname = fieldName(f.fd);
    let pool = runPool(fe, f);
    let key_fd .= mapKeyOf(entry.desc);
    let value_fd .= mapValueOf(entry.desc);
    let key_type = sc_setType(scalarOfTypeReq(key_fd));
    let find = subName(fe, entry, "find");
    let slot = subName(fe, entry, "slot");
    format(w,
        "\n",
        "// The entries of ", fname, ", in insertion order: its .len is their number, and\n",
        "// each has .key and .value, or the entry type's accessors for what is in a\n",
        "// pool. Valid until the map next changes or m is cleared.\n",
        "fn ", accessorName(path, fname, get_acc), "(m: ", goose_name, "&) -> ", entry.goose_name, "[:] { return pb_run(", pool, ", m.", f.name, "); }\n");
    let get = accessorName(path, fname, map_get_acc);
    let put = accessorName(path, fname, map_put_acc);
    let sub_opt = subMessageOf(fe, value_fd);
    if sub_opt {
        let sub .= sub_opt;
        format(w,
            "\n",
            "// The value with key k, or null if there is none. Valid until its entry\n",
            "// is removed or m is cleared.\n",
            "fn ", get, "(m: ", goose_name, "&, k: ", key_type, ") -> ", sub.goose_name, "&? {\n",
            "    let pb_i = ", find, "(m.", f.name, ", m.", f.name, ".len, k);\n",
            "    if pb_i < 0 { return null; }\n",
            "    return pb_run(", pool, ", m.", f.name, ")[pb_i].value.m;\n",
            "}\n",
            "\n",
            "// The value with key k, added empty if there is none.\n",
            "fn ", put, "(m: ", goose_name, "&, k: ", key_type, ") -> ", sub.goose_name, "& {\n",
            "    return ", accessorName(entry.path, "value", mutable_acc), "(", slot, "(m.", f.name, ", k));\n",
            "}\n");
    } else {
        let value_sc .= scalarOfTypeReq(value_fd);
        let is_bytes = value_sc.size == SZ_BYTES;
        format(w,
            "\n",
            "// The value with key k and true, or the default and false.", if is_bytes { " Valid until the\n// map next changes or m is cleared." } else { "" }, "\n",
            "fn ", get, "(m: ", goose_name, "&, k: ", key_type, ") -> ", if is_bytes { "u8[:]" } else { value_sc.goose }, ", bool {\n",
            "    let pb_i = ", find, "(m.", f.name, ", m.", f.name, ".len, k);\n");
        if is_bytes {
            format(w,
                "    if pb_i < 0 { return pb_run(pb_bytes, ", empty_span, "), false; }\n",
                "    return pb_run(pb_bytes, pb_run(", pool, ", m.", f.name, ")[pb_i].value), true;\n");
        } else {
            format(w,
                "    if pb_i < 0 { return ", sc_zero(value_sc), ", false; }\n",
                "    return pb_run(", pool, ", m.", f.name, ")[pb_i].value, true;\n");
        }
        format(w,
            "}\n",
            "\n",
            "// Sets the value with key k", if is_bytes { " to a copy of v" } else { " to v" }, ", adding an entry if there is none.\n",
            "fn ", put, "(m: ", goose_name, "&, k: ", key_type, ", v: ", sc_setType(value_sc), ") {\n");
        if is_bytes {
            format(w, "    ", accessorName(entry.path, "value", set_acc), "(", slot, "(m.", f.name, ", k), v);\n");
        } else {
            format(w, "    ", slot, "(m.", f.name, ", k).value = v;\n");
        }
        format(w, "}\n");
    }
    let clear_entry = subName(fe, entry, "clear");
    format(w,
        "\n",
        "// Removes the entry with key k and frees what it owns. False if there is\n",
        "// none. Later entries keep their order.\n",
        "fn ", accessorName(path, fname, map_remove_acc), "(m: ", goose_name, "&, k: ", key_type, ") -> bool {\n",
        "    let pb_i = ", find, "(m.", f.name, ", m.", f.name, ".len, k);\n",
        "    if pb_i < 0 { return false; }\n",
        "    let pb_r = pb_run(", pool, ", m.", f.name, ");\n",
        "    ", clear_entry, "(pb_r[pb_i]);\n",
        "    var pb_j = pb_i;\n",
        "    while pb_j + 1 < pb_r.len { pb_r[pb_j] = pb_r[pb_j + 1]; pb_j++; }\n",
        "    pb_r[pb_j] = ", entry.goose_name, " { .. };\n",
        "    m.", f.name, " = pb_resize(", pool, ", m.", f.name, ", pb_j);\n",
        "    return true;\n",
        "}\n",
        "\n",
        "// Frees the entries of ", fname, " and everything they own.\n",
        fe.fn_kw, " ", accessorName(path, fname, clear_acc), "(m: ", goose_name, "&) {\n",
        "    for pb_i in m.", f.name, ".len { ", clear_entry, "(pb_run(", pool, ", m.", f.name, ")[pb_i]); }\n",
        "    m.", f.name, " = pb_resize(", pool, ", m.", f.name, ", 0);\n",
        "}\n");
}

// clear_<oneof>: frees what the member that is set owns. It is in the
// cycle of M_clear, and may be the first call into it, so it is declared
// as the codecs are.
fn emitOneofClear(fe: FileEmitter&, goose_name: const u8[:], o: Oneof&, fields: const Field[:]) {
    format(w,
        "\n",
        "// Frees what oneof ", o.name, " holds, and sets no member.\n",
        fe.fn_kw, " ", o.clear, "(m: ", goose_name, "&) {\n",
        "    match m.", o.name, " {\n");
    for &f in fields {
        if f.oneof .!= o {
            continue;
        }
        if f.sub != null {
            let sub .= fieldSub(f);
            let pool = subName(fe, sub, "pool");
            format(w,
                "        ", f.name, " pb_p => {\n",
                "            let pb_sub = pb_p.v.m;\n",
                "            if pb_sub {\n",
                "                ", subName(fe, sub, "clear"), "(pb_sub);\n",
                "                ", pool, ".free(", pool, ".index_of(pb_sub));\n",
                "            }\n",
                "        },\n");
        } else if f.sc.size == SZ_BYTES {
            format(w, "        ", f.name, " pb_p => { pb_bytes_free(pb_p.v); },\n");
        }
    }
    format(w,
        "        _ => {},\n",
        "    }\n",
        "    m.", o.name, " = ", o.type_name, ".pb_none;\n",
        "}\n");
}

// The accessors of a member of a oneof: has_, clear_ (of this member
// only if it is the one set), and those of its kind of storage, which
// read the default when another member is set.
fn emitOneofAccessors(fe: FileEmitter&, goose_name: const u8[:], path: const u8[:], f: Field&, o: Oneof&) {
    let fname = fieldName(f.fd);
    let get = accessorName(path, fname, get_acc);
    let set = accessorName(path, fname, set_acc);
    let has = accessorName(path, fname, has_acc);
    let clear = accessorName(path, fname, clear_acc);
    if f.sub != null {
        let sub .= fieldSub(f);
        format(w,
            "\n",
            "// The sub-message ", fname, ", or null if it is not the member set. Valid until\n",
            "// oneof ", o.name, " changes or m is cleared.\n",
            "fn ", get, "(m: ", goose_name, "&) -> ", sub.goose_name, "&? {\n",
            "    match m.", o.name, " {\n",
            "        ", f.name, " pb_p => { return pb_p.v.m; },\n",
            "        _ => {},\n",
            "    }\n",
            "    return null;\n",
            "}\n",
            "\n",
            "// The sub-message ", fname, ", first made the member set, and empty, if it is not.\n",
            "fn ", accessorName(path, fname, mutable_acc), "(m: ", goose_name, "&) -> ", sub.goose_name, "& {\n",
            "    match m.", o.name, " {\n",
            "        ", f.name, " pb_p => {\n",
            "            let pb_l = pb_p.v.m;\n",
            "            if pb_l { return pb_l; }\n",
            "        },\n",
            "        _ => {},\n",
            "    }\n",
            "    ", o.clear, "(m);\n",
            "    let pb_new .= ", subName(fe, sub, "pool"), ".alloc_ref(", sub.goose_name, " { .. });\n",
            "    m.", o.name, " = ", o.type_name, ".", f.name, " { v: ", f.sc.goose, " { m: pb_new } };\n",
            "    return pb_new;\n",
            "}\n");
    } else if f.sc.size == SZ_BYTES {
        if hasDefaultBytes(f.fd) {
            let value = defaultBytes(f.fd);
            let name = accessorName(path, fname, default_acc);
            emitDefaultBytes(fe, name, value);
            format(w,
                "\n",
                "// The contents of ", fname, " in pb_bytes, ", name, " if it is not the member set:\n",
                "// valid until oneof ", o.name, " changes or m is cleared.\n",
                "fn ", get, "(m: ", goose_name, "&) -> const u8[:] {\n",
                "    match m.", o.name, " {\n",
                "        ", f.name, " pb_p => { return pb_run(pb_bytes, pb_p.v); },\n",
                "        _ => {},\n",
                "    }\n",
                "    return ", name, ";\n",
                "}\n");
        } else {
            format(w,
                "\n",
                "// The contents of ", fname, " in pb_bytes, empty if it is not the member set: valid\n",
                "// until oneof ", o.name, " changes or m is cleared.\n",
                "fn ", get, "(m: ", goose_name, "&) -> u8[:] {\n",
                "    match m.", o.name, " {\n",
                "        ", f.name, " pb_p => { return pb_run(pb_bytes, pb_p.v); },\n",
                "        _ => {},\n",
                "    }\n",
                "    return pb_run(pb_bytes, ", empty_span, ");\n",
                "}\n");
        }
        format(w,
            "\n",
            "// Makes ", fname, " the member set, with a copy of v, which may be its own contents.\n",
            "fn ", set, "(m: ", goose_name, "&, v: const u8[:]) {\n",
            "    let pb_t = pb_bytes_set(", empty_span, ", v);\n",
            "    ", o.clear, "(m);\n",
            "    m.", o.name, " = ", o.type_name, ".", f.name, " { v: pb_t };\n",
            "}\n");
    } else {
        format(w,
            "\n",
            "// The value of ", fname, ", the default if it is not the member set.\n",
            "fn ", get, "(m: ", goose_name, "&) -> ", f.sc.goose, " {\n",
            "    match m.", o.name, " {\n",
            "        ", f.name, " pb_p => { return pb_p.v; },\n",
            "        _ => {},\n",
            "    }\n",
            "    return ", if f.dflt.len > 0 { f.dflt } else { sc_zero(f.sc) }, ";\n",
            "}\n",
            "\n",
            "// Makes ", fname, " the member set, with value v: it is encoded even when ", sc_zero(f.sc), ".\n",
            "fn ", set, "(m: ", goose_name, "&, v: ", f.sc.goose, ") {\n",
            "    ", o.clear, "(m);\n",
            "    m.", o.name, " = ", o.type_name, ".", f.name, " { v: v };\n",
            "}\n");
    }
    format(w,
        "\n",
        "fn ", has, "(m: ", goose_name, "&) -> bool { return match m.", o.name, " { ", f.name, " => true, _ => false }; }\n",
        "\n",
        "// Clears oneof ", o.name, " if ", fname, " is the member set.\n",
        "fn ", clear, "(m: ", goose_name, "&) { if ", has, "(m) { ", o.clear, "(m); } }\n");
}

// The accessors of a repeated string or bytes field.
fn emitRepeatedStringAccessors(fe: FileEmitter&, goose_name: const u8[:], path: const u8[:], f: Field&) {
    let fname = fieldName(f.fd);
    format(w,
        "\n",
        "// The spans of ", fname, ", in pb_spans: its .len is the number of values.\n",
        "fn ", accessorName(path, fname, get_acc), "(m: ", goose_name, "&) -> pb_Span[:] { return pb_run(pb_spans, m.", f.name, "); }\n",
        "\n",
        "// The contents of value i of ", fname, ", in pb_bytes: valid until it is next\n",
        "// set or m is cleared.\n",
        "fn ", accessorName(path, fname, at_acc), "(m: ", goose_name, "&, i: i64) -> u8[:] { return pb_run(pb_bytes, pb_run(pb_spans, m.", f.name, ")[i]); }\n",
        "\n",
        "// Adds a copy of v to ", fname, ".\n",
        "fn ", accessorName(path, fname, add_acc), "(m: ", goose_name, "&, v: const u8[:]) { m.", f.name, " = pb_spans_add(m.", f.name, ", v); }\n",
        "\n",
        "// Sets value i of ", fname, " to a copy of v.\n",
        "fn ", accessorName(path, fname, set_acc), "(m: ", goose_name, "&, i: i64, v: const u8[:]) { pb_spans_set(m.", f.name, ", i, v); }\n",
        "\n",
        "fn ", accessorName(path, fname, clear_acc), "(m: ", goose_name, "&) { m.", f.name, " = pb_spans_free(m.", f.name, "); }\n");
}

// The accessors of a repeated message field. Each element has a slot of
// its own in the pool, so a reference to it outlives adding others.
fn emitRepeatedMessageAccessors(fe: FileEmitter&, goose_name: const u8[:], path: const u8[:], f: Field&, sub: MessageInfo&) {
    let fname = fieldName(f.fd);
    let links = runPool(fe, f);
    let pool = subName(fe, sub, "pool");
    format(w,
        "\n",
        "// The links of ", fname, ", in ", links, ": its .len is the number of messages.\n",
        "fn ", accessorName(path, fname, get_acc), "(m: ", goose_name, "&) -> ", f.sc.goose, "[:] { return pb_run(", links, ", m.", f.name, "); }\n",
        "\n",
        "// Message i of ", fname, ". Valid until it or m is cleared.\n",
        "fn ", accessorName(path, fname, at_acc), "(m: ", goose_name, "&, i: i64) -> ", sub.goose_name, "& {\n",
        "    let pb_l = pb_run(", links, ", m.", f.name, ")[i].m;\n",
        "    assert(pb_l);\n",
        "    return pb_l;\n",
        "}\n");
    format(w,
        "\n",
        "// Adds an empty message to ", fname, " and returns it.\n",
        "fn ", accessorName(path, fname, add_acc), "(m: ", goose_name, "&) -> ", sub.goose_name, "& {\n",
        "    let pb_i: i64 = m.", f.name, ".len;\n",
        "    m.", f.name, " = pb_resize(", links, ", m.", f.name, ", pb_i + 1);\n",
        "    let pb_new .= ", pool, ".alloc_ref(", sub.goose_name, " { .. });\n",
        "    pb_run(", links, ", m.", f.name, ")[pb_i].m .= pb_new;\n",
        "    return pb_new;\n",
        "}\n",
        "\n",
        "// Frees the messages of ", fname, " and everything they own.\n",
        fe.fn_kw, " ", accessorName(path, fname, clear_acc), "(m: ", goose_name, "&) {\n",
        "    for pb_ref in pb_run(", links, ", m.", f.name, ") {\n",
        "        let pb_l = pb_ref.m;\n",
        "        guard pb_l else { continue; }\n",
        "        ", subName(fe, sub, "clear"), "(pb_l);\n",
        "        ", pool, ".free(", pool, ".index_of(pb_l));\n",
        "    }\n",
        "    m.", f.name, " = pb_resize(", links, ", m.", f.name, ", 0);\n",
        "}\n");
}

// The accessors of a repeated scalar.
fn emitRepeatedAccessors(fe: FileEmitter&, goose_name: const u8[:], path: const u8[:], f: Field&) {
    let fname = fieldName(f.fd);
    let pool = sc_pool(f.sc);
    format(w,
        "\n",
        "// The values of ", fname, ", in ", pool, ": valid until it is next changed or m is\n",
        "// cleared.\n",
        "fn ", accessorName(path, fname, get_acc), "(m: ", goose_name, "&) -> ", f.sc.goose, "[:] { return pb_run(", pool, ", m.", f.name, "); }\n",
        "\n",
        "fn ", accessorName(path, fname, at_acc), "(m: ", goose_name, "&, i: i64) -> ", f.sc.goose, " { return pb_run(", pool, ", m.", f.name, ")[i]; }\n",
        "\n",
        "// Adds a value to ", fname, ". This moves its values, so ", accessorName(path, fname, set_acc), " is better for many.\n",
        "fn ", accessorName(path, fname, add_acc), "(m: ", goose_name, "&, v: ", f.sc.goose, ") { m.", f.name, " = pb_add(", pool, ", m.", f.name, ", v); }\n",
        "\n",
        "// Sets ", fname, " to a copy of v.\n",
        "fn ", accessorName(path, fname, set_acc), "(m: ", goose_name, "&, v: const ", f.sc.goose, "[:]) { m.", f.name, " = pb_set_run(", pool, ", m.", f.name, ", v); }\n",
        "\n",
        "fn ", accessorName(path, fname, clear_acc), "(m: ", goose_name, "&) { m.", f.name, " = pb_resize(", pool, ", m.", f.name, ", 0); }\n");
}

// The getter, mutable_, has_ and clear_ of a sub-message. Its slot in
// the pool is the sub-message's own, so a reference to it stays valid
// until the field is cleared.
// clear_ is in the cycle of M_clear, and may be the first call into it,
// so it is declared as the codecs are; likewise for a repeated message.
fn emitSubMessageAccessors(fe: FileEmitter&, goose_name: const u8[:], path: const u8[:], f: Field&, sub: MessageInfo&) {
    let fname = fieldName(f.fd);
    let pool = subName(fe, sub, "pool");
    format(w,
        "\n",
        "// The sub-message ", fname, ", or null if it is not set. Valid until it or m is\n",
        "// cleared.\n",
        "fn ", accessorName(path, fname, get_acc), "(m: ", goose_name, "&) -> ", sub.goose_name, "&? { return m.", f.name, ".m; }\n",
        "\n",
        "// The sub-message ", fname, ", set to an empty one first if it is not set.\n",
        "fn ", accessorName(path, fname, mutable_acc), "(m: ", goose_name, "&) -> ", sub.goose_name, "& {\n",
        "    let pb_sub = m.", f.name, ".m;\n",
        "    if pb_sub { return pb_sub; }\n",
        "    let pb_new .= ", pool, ".alloc_ref(", sub.goose_name, " { .. });\n",
        "    m.", f.name, ".m .= pb_new;\n",
        "    return pb_new;\n",
        "}\n",
        "\n",
        "fn ", accessorName(path, fname, has_acc), "(m: ", goose_name, "&) -> bool { return m.", f.name, ".m != null; }\n",
        "\n",
        "// Frees the sub-message ", fname, " and everything it owns.\n",
        fe.fn_kw, " ", accessorName(path, fname, clear_acc), "(m: ", goose_name, "&) {\n",
        "    let pb_sub = m.", f.name, ".m;\n",
        "    guard pb_sub else { return; }\n",
        "    ", subName(fe, sub, "clear"), "(pb_sub);\n",
        "    ", pool, ".free(", pool, ".index_of(pb_sub));\n",
        "    m.", f.name, ".m .= null;\n",
        "}\n");
}

// Generates the .goose source for `file` into `w`. False on a name collision,
// and `diag` holds the message.
fn generateFile(file: FileDesc&) -> bool {
    indexRequest();
    let fe .= newFileEmitter(file);
    emit(fe);
    return diag.len == 0;
}

// The header comment of every generated file: the user-facing API
// (decisions 0001, 0004, 0006).
const api_comment = """
    // API, for each message M (Outer.Inner is Outer_Inner):
    //   var m = M { .. };            an empty message: any local, global or
    //                                array element the caller owns
    //   m.f, m.f = v                 scalar fields without presence
    //   M_set_f(m, v), M_has_f(m),   scalar fields with presence (optional
    //   M_clear_f(m)                 or explicit); m.f reads them, and
    //                                an unset one reads as its default
    //   M_f(m) -> u8[:]              string and bytes fields: a view into
    //   M_set_f(m, v)                pb_bytes, and a copying setter; with a
    //                                [default], M_f(m) -> const u8[:]
    //                                reads global M_f_default while unset
    //   M_f(m) -> S&?                sub-message fields: null if not set;
    //   M_mutable_f(m) -> S&         mutable_ first sets an empty one
    //   M_has_f(m), M_clear_f(m)
    //   M_f(m) -> T[:], M_f_at(m, i) repeated numeric, bool and enum fields:
    //   M_add_f(m, v), M_set_f(m, vs), a view into a pool, and writers
    //   M_clear_f(m)
    //   M_f(m).len, M_f_at(m, i),    repeated string, bytes and message
    //   M_add_f(m...), M_clear_f(m)  fields; M_set_f(m, i, v) for strings;
    //                                add_ of a message returns it
    //   M_f(m), M_set_f(m, v),       members of a oneof o: M_f reads the
    //   M_has_f(m), M_clear_f(m)     default if another member is set;
    //   M_mutable_f(m) -> S&         messages have mutable_, not set_.
    //   M_clear_o(m)                 m.o is an ADT M_o to match on: pb_none,
    //                                or a variant f { v } per member
    //   M_f_get(m, k), M_f_put(m...) map fields: get gives the value and
    //   M_f_remove(m, k), M_f(m),    whether it was found (a message value:
    //   M_clear_f(m)                 S&?), put of a message returns it
    //   M_encode(m, out)             appends M_size_of(m) bytes to out
    //   M_decode(buf, m) -> i32      merges buf into m: PB_OK, or a
    //                                PB_ERR_* code and a partial m
    //                                (PB_ERR_UTF8: a string that is checked;
    //                                PB_ERR_REQUIRED: a required field is
    //                                unset, which M_is_initialized(m) checks
    //                                in a message that can hold one)
    //   M_clear(m)                   frees what m owns, empties it
    //   M_copy(dst, src)             makes dst a deep copy of src
    // Enum values are i32 constants E_VALUE. Decoding keeps a value that a
    // closed enum does not declare as an unknown field: the field stays as
    // it was. Variable-size parts (unknown fields, strings and
    // bytes, sub-messages, repeated fields)
    // live in global pools (pb_bytes, M_pool, M_links): clear a message
    // to free them. Assigning a record copies spans, not their contents:
    // use M_copy.


    """;
