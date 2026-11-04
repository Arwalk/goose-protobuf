// Round-trip test for Struct, Value, ListValue and FieldMask (gpb-gp4.6): each
// decodes protoc's encoding of a nested sample into stored fields, with nothing
// left as an unknown field, and re-encodes it byte for byte.
// Run: scripts/roundtrip.sh wkt
import pb_wire;
import pb_wire.wkt.field_mask;
import pb_wire.wkt.struct_;

var failures = 0;

fn fail_at(what: u8[:], detail: u8[:]) {
    failures += 1;
    print("FAIL ", what, ": ", detail);
}

// The number of unknown bytes in s, everywhere in it.
recursive fn unknown_in_struct(s: google_protobuf::Struct&) -> i64 {
    var n: i64 = s.pb_unknown.len;
    let entries = google_protobuf::Struct_fields(s);
    for i in entries.len {
        n += entries[i].pb_unknown.len;
        let v = entries[i].value.m;
        if v { n += unknown_in_value(v); }
    }
    return n;
}

recursive fn unknown_in_list(l: google_protobuf::ListValue&) -> i64 {
    var n: i64 = l.pb_unknown.len;
    for i in google_protobuf::ListValue_values(l).len {
        n += unknown_in_value(google_protobuf::ListValue_values_at(l, i));
    }
    return n;
}

recursive fn unknown_in_value(v: google_protobuf::Value&) -> i64 {
    var n: i64 = v.pb_unknown.len;
    let s = google_protobuf::Value_struct_value(v);
    if s { n += unknown_in_struct(s); }
    let l = google_protobuf::Value_list_value(v);
    if l { n += unknown_in_list(l); }
    return n;
}

fn check_struct(name: u8[:], want: const u8[:]) {
    var m = google_protobuf::Struct { .. };
    let err = google_protobuf::Struct_decode(want, m);
    if err != PB_OK { fail_at(name, str("decode error ", err)); }
    if unknown_in_struct(m) != 0 { fail_at(name, "kept as unknown fields"); }
    var out: u8[>..] = [];
    google_protobuf::Struct_encode(m, out);
    if out != want { fail_at(name, "re-encode differs from protoc"); }
    if google_protobuf::Struct_size_of(m) != want.len { fail_at(name, "size_of"); }
    google_protobuf::Struct_clear(m);
    if google_protobuf::Struct_size_of(m) != 0 { fail_at(name, "clear"); }
}

fn check_value(name: u8[:], want: const u8[:]) {
    var m = google_protobuf::Value { .. };
    let err = google_protobuf::Value_decode(want, m);
    if err != PB_OK { fail_at(name, str("decode error ", err)); }
    if unknown_in_value(m) != 0 { fail_at(name, "kept as unknown fields"); }
    var out: u8[>..] = [];
    google_protobuf::Value_encode(m, out);
    if out != want { fail_at(name, "re-encode differs from protoc"); }
    if google_protobuf::Value_size_of(m) != want.len { fail_at(name, "size_of"); }
    google_protobuf::Value_clear(m);
    if google_protobuf::Value_size_of(m) != 0 { fail_at(name, "clear"); }
}

fn check_list(name: u8[:], want: const u8[:]) {
    var m = google_protobuf::ListValue { .. };
    let err = google_protobuf::ListValue_decode(want, m);
    if err != PB_OK { fail_at(name, str("decode error ", err)); }
    if unknown_in_list(m) != 0 { fail_at(name, "kept as unknown fields"); }
    var out: u8[>..] = [];
    google_protobuf::ListValue_encode(m, out);
    if out != want { fail_at(name, "re-encode differs from protoc"); }
    if google_protobuf::ListValue_size_of(m) != want.len { fail_at(name, "size_of"); }
    google_protobuf::ListValue_clear(m);
    if google_protobuf::ListValue_size_of(m) != 0 { fail_at(name, "clear"); }
}

fn check_field_mask(name: u8[:], want: const u8[:], n: i64) {
    var m = google_protobuf::FieldMask { .. };
    let err = google_protobuf::FieldMask_decode(want, m);
    if err != PB_OK { fail_at(name, str("decode error ", err)); }
    if m.pb_unknown.len != 0 { fail_at(name, "kept as unknown fields"); }
    if google_protobuf::FieldMask_paths(m).len != n { fail_at(name, "paths"); }
    var out: u8[>..] = [];
    google_protobuf::FieldMask_encode(m, out);
    if out != want { fail_at(name, "re-encode differs from protoc"); }
    if google_protobuf::FieldMask_size_of(m) != want.len { fail_at(name, "size_of"); }
    google_protobuf::FieldMask_clear(m);
    if google_protobuf::FieldMask_size_of(m) != 0 { fail_at(name, "clear"); }
}

// The sample's values, read through the accessors.
fn check_read() {
    var m = google_protobuf::Struct { .. };
    if google_protobuf::Struct_decode(embed_file("struct_nested.bin"), m) != PB_OK { fail_at("read", "decode"); }
    if google_protobuf::Struct_fields(m).len != 2 { fail_at("read", "entries"); }
    let num = google_protobuf::Struct_fields_get(m, "num");
    guard num else { fail_at("read", "num"); return; }
    if google_protobuf::Value_number_value(num) != 1.5 { fail_at("read", "number"); }
    if google_protobuf::Struct_fields_get(m, "missing") != null { fail_at("read", "missing key"); }

    let lv = google_protobuf::Struct_fields_get(m, "list");
    guard lv else { fail_at("read", "list"); return; }
    let l = google_protobuf::Value_list_value(lv);
    guard l else { fail_at("read", "list member"); return; }
    if google_protobuf::ListValue_values(l).len != 5 { fail_at("read", "list length"); }
    if google_protobuf::Value_string_value(google_protobuf::ListValue_values_at(l, 0)) != "x" { fail_at("read", "string"); }
    if !google_protobuf::Value_bool_value(google_protobuf::ListValue_values_at(l, 1)) { fail_at("read", "bool"); }
    let null_v .= google_protobuf::ListValue_values_at(l, 2);
    if !google_protobuf::Value_has_null_value(null_v) || google_protobuf::Value_null_value(null_v) != google_protobuf::NullValue_NULL_VALUE {
        fail_at("read", "null");
    }

    // Down the struct: list[3].in.deep. The kind is an ADT to match on, too.
    let sv = google_protobuf::Value_struct_value(google_protobuf::ListValue_values_at(l, 3));
    guard sv else { fail_at("read", "struct"); return; }
    let inner = google_protobuf::Struct_fields_get(sv, "in");
    guard inner else { fail_at("read", "in"); return; }
    let inner_s = google_protobuf::Value_struct_value(inner);
    guard inner_s else { fail_at("read", "in member"); return; }
    let deep = google_protobuf::Struct_fields_get(inner_s, "deep");
    guard deep else { fail_at("read", "deep"); return; }
    let d = match deep.kind { number_value x => x.v, _ => -1.0 };
    if d != 2.5 { fail_at("read", "deep value"); }
    google_protobuf::Struct_clear(m);
}

// A nested value built through the API encodes as protoc's does, and a deep
// copy outlives it.
fn check_built() {
    var m = google_protobuf::Struct { .. };
    let a .= google_protobuf::Struct_fields_put(m, "a");
    let l .= google_protobuf::Value_mutable_list_value(a);
    google_protobuf::Value_set_number_value(google_protobuf::ListValue_add_values(l), 1.0);
    google_protobuf::Value_set_string_value(google_protobuf::ListValue_add_values(l), "x");
    let s .= google_protobuf::Value_mutable_struct_value(google_protobuf::ListValue_add_values(l));
    google_protobuf::Value_set_null_value(google_protobuf::Struct_fields_put(s, "b"), google_protobuf::NullValue_NULL_VALUE);
    let want = embed_file("struct_built.bin");
    var out: u8[>..] = [];
    google_protobuf::Struct_encode(m, out);
    if out != want { fail_at("built", "encoding differs from protoc"); }

    var c = google_protobuf::Struct { .. };
    google_protobuf::Struct_copy(c, m);
    google_protobuf::Struct_clear(m);
    var again: u8[>..] = [];
    google_protobuf::Struct_encode(c, again);
    if again != want { fail_at("built", "the copy does not outlive its source"); }
    google_protobuf::Struct_clear(c);
}

// Clearing a nested value gives back what it held.
fn check_no_leak() {
    var m = google_protobuf::Struct { .. };
    var bytes_len: i64 = 0;
    var value_len: i64 = 0;
    for i in 100 {
        if google_protobuf::Struct_decode(embed_file("struct_nested.bin"), m) != PB_OK { fail_at("leak", "decode"); }
        google_protobuf::Struct_clear(m);
        if i == 0 { bytes_len = pb_bytes.len; value_len = google_protobuf::Value_pool.len; }
    }
    if pb_bytes.len != bytes_len { fail_at("leak", "pb_bytes grew"); }
    if google_protobuf::Value_pool.len != value_len { fail_at("leak", "Value_pool grew"); }
}

fn main() {
    check_field_mask("field_mask", embed_file("field_mask.bin"), 3);
    check_field_mask("field_mask_empty", embed_file("field_mask_empty.bin"), 0);
    check_struct("struct_empty", embed_file("struct_empty.bin"));
    check_struct("struct_nested", embed_file("struct_nested.bin"));
    check_struct("struct_built", embed_file("struct_built.bin"));
    check_value("value_null", embed_file("value_null.bin"));
    check_value("value_number", embed_file("value_number.bin"));
    check_value("value_number_zero", embed_file("value_number_zero.bin"));
    check_value("value_string", embed_file("value_string.bin"));
    check_value("value_string_empty", embed_file("value_string_empty.bin"));
    check_value("value_bool", embed_file("value_bool.bin"));
    check_value("value_bool_false", embed_file("value_bool_false.bin"));
    check_value("value_struct", embed_file("value_struct.bin"));
    check_value("value_list", embed_file("value_list.bin"));
    check_value("value_none", embed_file("value_none.bin"));
    check_list("list_empty", embed_file("list_empty.bin"));
    check_list("list_mixed", embed_file("list_mixed.bin"));
    check_read();
    check_built();
    check_no_leak();
    if failures > 0 { abort(str(failures, " failures")); }
    print("ok");
}
