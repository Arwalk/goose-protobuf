// generator-goose/emit.goose: the name rules, docs/decisions/0006-naming.md.
// Run by scripts/selfhost_tests.sh.
import pb_wire;
import google.protobuf.descriptor;
import emit;
import unit_support;

fn keywords_are_escaped() {
    expect_str(ident("match"), "match_");
    expect_str(ident("Match"), "Match");
    expect_str(ident("from"), "from_");
    expect_str(nested_path("", "type"), "type");
    expect_str(nested_path("struct", "self"), "struct_self");
    expect_str(namespace_name("a.fn.b"), "a_fn_b");
    expect_str(namespace_name("match"), "match_");
}

fn output_names() {
    expect_str(output_name("foo/bar.proto"), "foo/bar.goose");
    expect_str(output_name("x"), "x.goose");
    expect_str(output_name("api/foo.v1.proto"), "api/foo_v1.goose");
    expect_str(output_name("my-api.proto"), "my_api.goose");
    expect_str(output_name("my-api/v.2/x.proto"), "my_api/v_2/x.goose");
    // Every segment is escaped, directories too.
    expect_str(output_name("recursive.proto"), "recursive_.goose");
    expect_str(output_name("type/fn/str.proto"), "type_/fn_/str_.goose");
    expect_str(output_name("pb_wire.proto"), "pb_wire_.goose");
    // Anything else an import path cannot hold.
    expect_str(output_name("a b+c.proto"), "a_b_c.goose");
    expect_str(output_name("3d/1.proto"), "_3d/_1.goose");
}

// The Goose reference, appendix A and section 25, for Goose v2026.3. A pin change
// compares them again: a word missing from the generator's lists makes bad code.
const reference_names = [
    "import", "namespace", "struct", "enum", "type", "fn", "thread_fn", "export", "simd",
    "recursive", "let", "var", "extern", "const", "pad", "reusable", "if", "else", "while",
    "for", "in", "loop", "block", "guard", "match", "return", "break", "continue", "as",
    "true", "false", "null", "self", "bool", "varint", "i8", "i16", "i32", "i64", "u8", "u16",
    "u32", "u64", "f32", "f64", "from", "upto", "inline", "checkfree", "fields", "types",
    "print", "str", "format", "assert", "abort", "exit", "copy", "default", "hardware_threads",
    "thread_spawn", "thread_spawn_contained", "thread_wait", "qput", "qget", "qpoll", "qlimit",
    "to_bytes", "bytes_of", "from_bytes", "embed_file", "embed_shader",
];

const reserved_names = ["str", "print", "copy", "default", "thread_spawn", "embed_shader", "pb_x", "pb_Span", "PB_OK"];
const free_names = ["Str", "strs", "pbx", "Pb_x", "pb", "my_pb_x", "Outer_decode"];

fn builtins_and_runtime_prefixes_are_reserved() {
    for n in reference_names { expect(is_reserved(n), n); }
    for n in reserved_names { expect(is_reserved(n), n); }
    for n in free_names { expect(!is_reserved(n), n); }
    expect_str(ident("str"), "str_");
    expect_str(ident("pb_x"), "pb_x_");
    expect_str(generated_name("type", "decode"), "type_decode");
    expect_str(generated_name("pb_x", "decode"), "pb_x_decode_");
    expect_str(accessor_name("Node", "name", set_acc), "Node_set_name");
    expect_str(accessor_name("Node", "children", at_acc), "Node_children_at");
}

fn accessors_depend_on_kind_and_presence() {
    expect(field_accessors(KIND_SCALAR, false).len == 0, "a plain scalar has none");
    let p = field_accessors(KIND_SCALAR, true);
    expect(p.len == 3, "a scalar with presence");
    expect_str(p[0].prefix, "set_");
    expect_str(p[1].prefix, "has_");
    expect_str(p[2].prefix, "clear_");
    expect(field_accessors(KIND_STRING, true).len == 4, "a string with presence");
    expect(field_accessors(KIND_STRING, false).len == 2, "a string without");
    expect(field_accessors(KIND_MESSAGE, true).len == 4, "a message");
    expect(field_accessors(KIND_REPEATED, false).len == 5, "a repeated scalar");
    expect(field_accessors(KIND_REPEATED_MESSAGE, false).len == 4, "a repeated message");
    expect(field_accessors(KIND_ONEOF_SCALAR, true).len == 4, "a oneof scalar");
    expect(field_accessors(KIND_MAP, false).len == 6, "a map");
}

fn well_known_file(name: const u8[:], package: const u8[:]) -> FileDesc& {
    return add_file(name, package, "");
}

fn well_known_files_are_recognised() {
    reset_generator();
    expect(is_well_known(well_known_file("google/protobuf/any.proto", "google.protobuf")), "any");
    expect(!is_well_known(well_known_file("google/protobuf/any.proto", "mine")), "another package");
    let api .= well_known_file("google/protobuf/api.proto", "google.protobuf");
    expect(!is_well_known(api), "api is an ordinary proto");
    expect_str(well_known_output_name("google/protobuf/any.proto"), "wkt/any.goose");
    expect_str(import_path_of(well_known_file("google/protobuf/struct.proto", "google.protobuf")), "pb_wire.wkt.struct_");
    expect_str(import_path_of(api), "google.protobuf.api");
}

fn main() {
    keywords_are_escaped();
    output_names();
    builtins_and_runtime_prefixes_are_reserved();
    accessors_depend_on_kind_and_presence();
    well_known_files_are_recognised();
}
