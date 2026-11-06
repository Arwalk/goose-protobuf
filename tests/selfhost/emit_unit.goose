// generator-goose/emit.goose: how a descriptor decides what is generated, and what
// it rejects. The rest of the text is for the golden tests.
// Run by scripts/selfhost_tests.sh.
import pb_wire;
import google.protobuf.descriptor;
import features;
import emit;
import unit_support;

fn test_features(file: FileDesc&, fd: FieldDesc&) -> Features {
    return featuresOfField(file, featuresOfFile(file), fd);
}

fn nested_and_top_level_names_collide() {
    reset_generator();
    let file .= add_file("c.proto", "p", "");
    add_nested(add_message(file, "A"), "B");
    add_message(file, "A_B");
    expect_str(collision_of(file), "c.proto: p.A.B and p.A_B both map to the Goose name A_B");
}

fn nested_names_equal_to_generated_names_are_escaped() {
    reset_generator();
    let file .= add_file("n.proto", "", "proto3");
    let node .= add_message(file, "Node");
    add_field(node, "name", 1, LABEL_OPTIONAL, TYPE_STRING);
    add_nested(node, "decode");
    add_nested(node, "set_name");
    let out = generated_text(file);
    expect_has(out, "struct Node_decode_ {\n");
    expect_has(out, "struct Node_set_name_ {\n");
}

fn a_top_level_name_equal_to_a_generated_name_collides() {
    reset_generator();
    let file .= add_file("t.proto", "p", "proto3");
    add_message(file, "Outer");
    add_message(file, "Outer_decode");
    expect_str(collision_of(file), "t.proto: generated decode of p.Outer and p.Outer_decode both map to the Goose name Outer_decode");
}

fn two_accessors_with_one_name_collide() {
    reset_generator();
    let file .= add_file("t.proto", "", "proto3");
    let m .= add_message(file, "M");
    add_field(m, "x", 1, LABEL_OPTIONAL, TYPE_STRING);
    add_field(m, "set_x", 2, LABEL_OPTIONAL, TYPE_STRING);
    expect_str(collision_of(file), "t.proto: accessor set_x of M and accessor set_x of M both map to the Goose name M_set_x");
}

fn an_escaped_name_still_taken_collides() {
    reset_generator();
    let file .= add_file("t.proto", "", "proto3");
    let outer .= add_message(file, "Outer");
    add_nested(outer, "decode_");
    add_nested(outer, "decode");
    expect_str(collision_of(file), "t.proto: Outer.decode_ and Outer.decode both map to the Goose name Outer_decode_");
}

fn an_enum_value_collides() {
    reset_generator();
    let file .= add_file("t.proto", "", "proto3");
    let e .= google_protobuf::FileDescriptorProto_add_enum_type(file);
    google_protobuf::EnumDescriptorProto_set_name(e, "E");
    add_enum_value(e, "X", 0);
    add_message(file, "E_X");
    expect_str(collision_of(file), "t.proto: E.X and E_X both map to the Goose name E_X");
}

fn two_record_fields_with_one_name_collide() {
    reset_generator();
    let file .= add_file("t.proto", "", "proto2");
    let m .= add_message(file, "A");
    add_field(m, "type", 1, LABEL_OPTIONAL, TYPE_INT32);
    add_field(m, "type_", 2, LABEL_OPTIONAL, TYPE_INT32);
    expect_str(collision_of(file), "t.proto: two fields of A map to the Goose record field type_");
}

fn an_imported_file_that_collides_is_reported() {
    reset_generator();
    let bad .= add_file("imported_bad.proto", "", "proto3");
    add_nested(add_message(bad, "C"), "D");
    add_message(bad, "C_D");
    let file .= add_file("t.proto", "", "proto3");
    add_message_field(add_message(file, "U"), "c", 1, LABEL_OPTIONAL, ".C");
    expect_str(collision_of(file), "imported_bad.proto: C.D and C_D both map to the Goose name C_D");
}

fn field_kinds_and_presence() {
    reset_generator();
    let file .= add_file("t.proto", "p", "proto3");
    let m .= add_message(file, "M");
    add_map_entry(m, "AEntry");
    add_nested(m, "Sub");
    let map_f .= add_message_field(m, "a", 1, LABEL_REPEATED, ".p.M.AEntry");
    let rep_f .= add_message_field(m, "s", 2, LABEL_REPEATED, ".p.M.Sub");
    let msg_f .= add_message_field(m, "b", 3, LABEL_OPTIONAL, ".p.M.Sub");
    let str_f .= add_field(m, "c", 4, LABEL_OPTIONAL, TYPE_BYTES);
    let int_f .= add_field(m, "d", 5, LABEL_OPTIONAL, TYPE_INT64);
    let opt_f .= add_field(m, "e", 6, LABEL_OPTIONAL, TYPE_INT64);
    google_protobuf::FieldDescriptorProto_set_proto3_optional(opt_f, true);
    expect(fieldKind(m, "p.M", map_f) == KIND_MAP, "a map");
    expect(fieldKind(m, "p.M", rep_f) == KIND_REPEATED_MESSAGE, "repeated messages");
    expect(fieldKind(m, "p.M", msg_f) == KIND_MESSAGE, "a message");
    expect(fieldKind(m, "p.M", str_f) == KIND_STRING, "bytes");
    expect(fieldKind(m, "p.M", int_f) == KIND_SCALAR, "a scalar");

    let p2 .= add_file("p2.proto", "", "");
    expect(!hasPresence(test_features(file, int_f), int_f), "a proto3 scalar");
    expect(hasPresence(test_features(file, opt_f), opt_f), "a proto3 optional");
    expect(hasPresence(test_features(file, msg_f), msg_f), "a message");
    expect(!hasPresence(test_features(file, rep_f), rep_f), "a repeated field");
    expect(hasPresence(test_features(p2, int_f), int_f), "a proto2 scalar");
}

fn proto3_optional_has_a_bit_and_a_real_oneof_an_adt() {
    reset_generator();
    let file .= add_file("t.proto", "", "proto3");
    let m .= add_message(file, "M");
    add_oneof(m, "_o");
    add_oneof(m, "pick");
    let o .= add_field(m, "o", 1, LABEL_OPTIONAL, TYPE_INT32);
    google_protobuf::FieldDescriptorProto_set_oneof_index(o, 0);
    google_protobuf::FieldDescriptorProto_set_proto3_optional(o, true);
    google_protobuf::FieldDescriptorProto_set_oneof_index(add_field(m, "u", 2, LABEL_OPTIONAL, TYPE_INT32), 1);
    expect(!isRealOneof(m, 0), "a synthetic oneof");
    expect(isRealOneof(m, 1), "a real oneof");
    let out = generated_text(file);
    expect_has(out, "    o: i32,\n    pick: M_pick = M_pick.pb_none,\n    pb_has0: u32,");
    expect_has(out, "fn M_set_o(m: M&, v: i32)");
    expect_has(out, "enum M_pick {\n    pb_none,\n    u { v: i32 },\n}");
    expect_lacks(out, "    u: i32,");
    expect_lacks(out, "enum M__o");
}

fn repeated_scalars_of_proto2_are_unpacked() {
    reset_generator();
    let p2 .= add_file("p2.proto", "", "proto2");
    let ed .= add_file("ed.proto", "", "editions");
    var plain = FieldDesc { .. };
    set_field(plain, "a", 1, LABEL_REPEATED, TYPE_INT32);
    expect(!test_features(p2, plain).packed_repeated, "proto2");
    expect(test_features(ed, plain).packed_repeated, "editions");
    expect(repeatedScalarOf(test_features(p2, plain), plain) != null, "stored in proto2");
    expect(repeatedScalarOf(test_features(ed, plain), plain) != null, "stored in editions");
}

fn read_of(ff: Features, fd: FieldDesc&) -> const u8[:] {
    let sc = scalarOf(ff, fd);
    guard sc else { return ""; }
    return sc.read;
}

fn singular_fields_are_stored_and_messages_are_not_scalars() {
    reset_generator();
    let p2 .= add_file("p2.proto", "", "");
    let named .= add_file("named.proto", "", "proto2");
    let ed .= add_file("ed.proto", "", "editions");
    var i = FieldDesc { .. };
    set_field(i, "i", 1, LABEL_OPTIONAL, TYPE_INT32);
    var r = FieldDesc { .. };
    set_field(r, "r", 2, LABEL_REQUIRED, TYPE_INT32);
    var s = FieldDesc { .. };
    set_field(s, "s", 3, LABEL_OPTIONAL, TYPE_STRING);
    var e = FieldDesc { .. };
    set_field(e, "e", 4, LABEL_OPTIONAL, TYPE_ENUM);
    var g = FieldDesc { .. };
    set_field(g, "g", 5, LABEL_OPTIONAL, TYPE_GROUP);
    let int32_read = sc_int32.read;
    expect_str(read_of(test_features(p2, i), i), int32_read);
    expect_str(read_of(test_features(named, i), i), int32_read);
    expect_str(read_of(test_features(p2, r), r), int32_read);
    expect_str(read_of(test_features(p2, s), s), "pb_read_bytes(r, $)");
    expect_str(read_of(test_features(p2, e), e), int32_read);
    expect(scalarOf(test_features(p2, g), g) == null, "a group is no scalar");
    expect_str(read_of(test_features(ed, i), i), int32_read);
    expect_str(read_of(test_features(ed, s), s), "pb_read_string(r, $)");
    expect(hasPresence(test_features(p2, i), i), "proto2 presence");
}

fn proto3_strings_are_validated_and_bytes_are_not() {
    reset_generator();
    let p3 .= add_file("p3.proto", "", "proto3");
    var s = FieldDesc { .. };
    set_field(s, "s", 1, LABEL_OPTIONAL, TYPE_STRING);
    var b = FieldDesc { .. };
    set_field(b, "b", 2, LABEL_OPTIONAL, TYPE_BYTES);
    expect_str(read_of(test_features(p3, s), s), "pb_read_string(r, $)");
    expect_str(read_of(test_features(p3, b), b), "pb_read_bytes(r, $)");
    let bytes_sc = scalarOf(test_features(p3, b), b);
    assert(bytes_sc);
    expect_str(sc_setType(bytes_sc), "const u8[:]");
    expect_str(sc_setType(sc_int32), "i32");
}

fn a_nested_name_equal_to_a_oneof_name_is_escaped() {
    reset_generator();
    let file .= add_file("t.proto", "", "proto3");
    let m .= add_message(file, "M");
    add_oneof(m, "pick");
    google_protobuf::FieldDescriptorProto_set_oneof_index(add_field(m, "u", 1, LABEL_OPTIONAL, TYPE_INT32), 0);
    add_nested(m, "pick");
    add_nested(m, "clear_pick");
    let out = generated_text(file);
    expect_has(out, "enum M_pick {");
    expect_has(out, "struct M_pick_ {");
    expect_has(out, "struct M_clear_pick_ {");
}

fn sub_messages_are_stored_and_cycles_are_recursive() {
    reset_generator();
    let file .= add_file("t.proto", "p", "proto3");
    let m .= add_message(file, "M");
    add_message_field(m, "later", 1, LABEL_OPTIONAL, ".p.Later");
    add_message_field(m, "co", 2, LABEL_OPTIONAL, ".p.Co");
    add_message_field(m, "other", 3, LABEL_OPTIONAL, ".q.Other");
    add_message_field(add_message(file, "Co"), "back", 1, LABEL_OPTIONAL, ".p.M");
    add_message_field(add_message(file, "Self"), "next", 1, LABEL_OPTIONAL, ".p.Self");
    add_message_field(add_message(file, "Holder"), "self_", 1, LABEL_OPTIONAL, ".p.Self");
    add_message(file, "Later");
    let out = generated_text(file);
    expect_has(out, "    later: Later_Ref,\n");
    expect_has(out, "fn M_mutable_later(m: M&) -> Later& {");
    // A type no file declares is not stored: it is kept as an unknown field.
    expect_lacks(out, "    other: ");
    const cycle = ["M", "Co", "Self"];
    for name in cycle {
        expect_has(out, str("recursive fn ", name, "_decode_from("));
        expect_has(out, str("recursive fn ", name, "_encode("));
        expect_has(out, str("recursive fn ", name, "_size_of("));
        expect_has(out, str("recursive fn ", name, "_clear("));
    }
    expect_has(out, "\nfn Holder_decode_from(");
    expect_has(out, "\nfn Later_clear(");
    expect_has(out, "recursive fn Self_copy(dst: Self&, src: Self&) {");
    expect_has(out, "\nfn Later_copy(dst: Later&, src: Later&) {");
}

fn repeated_messages_cycle_and_maps_store_a_run() {
    reset_generator();
    let file .= add_file("t.proto", "p", "proto3");
    add_message_field(add_message(file, "Node"), "children", 1, LABEL_REPEATED, ".p.Node");
    let m .= add_message(file, "M");
    let entry .= add_map_entry(m, "AEntry");
    add_field(entry, "key", 1, LABEL_OPTIONAL, TYPE_INT32);
    add_field(entry, "value", 2, LABEL_OPTIONAL, TYPE_INT32);
    add_message_field(m, "a", 1, LABEL_REPEATED, ".p.M.AEntry");
    let out = generated_text(file);
    expect_has(out, "recursive fn Node_decode_from(");
    expect_has(out, "    children: pb_Span,\n");
    expect_has(out, "fn Node_add_children(m: Node&) -> Node& {");
    expect_has(out, "    a: pb_Span,\n");
    expect_has(out, "fn M_a_put(m: M&, k: i32, v: i32) {");
    expect_has(out, "reusable[] var M_AEntry_entries: M_AEntry[>..] = [];");
}

fn defaults_are_literal_and_bytes_unescaped() {
    expect_str(cUnescape("a\\001\\377\\\\\\\"\\n\\?\\x41"), "a\x01\xff\\\"\n?A");
    expect_str(cUnescape("\\a\\b\\f\\r\\t\\v\\7\\18"), "\x07\x08\x0c\r\t\x0b\x07\x018");
    // What is cut short stays as it is.
    expect_str(cUnescape("a\\"), "a\\");
    var named = FieldDesc { .. };
    google_protobuf::FieldDescriptorProto_set_type(named, TYPE_BYTES);
    google_protobuf::FieldDescriptorProto_set_default_value(named, "\\377");
    expect(hasDefaultBytes(named), "a bytes default");
    expect_str(defaultBytes(named), "\xff");
    var text = FieldDesc { .. };
    google_protobuf::FieldDescriptorProto_set_type(text, TYPE_STRING);
    google_protobuf::FieldDescriptorProto_set_default_value(text, "\\377");
    expect_str(defaultBytes(text), "\\377");
    var empty = FieldDesc { .. };
    google_protobuf::FieldDescriptorProto_set_type(empty, TYPE_STRING);
    google_protobuf::FieldDescriptorProto_set_default_value(empty, "");
    expect(!hasDefaultBytes(empty), "an empty default is none");

    var e = EnumDesc { .. };
    add_enum_value(e, "A", 3);
    add_enum_value(e, "B", 1);
    var no_default = FieldDesc { .. };
    expect(enumDefault(e, no_default) == 3, "the first value");
    var with_default = FieldDesc { .. };
    google_protobuf::FieldDescriptorProto_set_default_value(with_default, "B");
    expect(enumDefault(e, with_default) == 1, "the value named");
}

fn a_closed_enum_is_checked_as_sorted_runs() {
    var e = EnumDesc { .. };
    const values: i32[7] = [7, 0, 6, 6, 8, -1, 3];
    for v in values { add_enum_value(e, "", v); }
    expect_str(knownValues(e), "(pb_v >= -1 && pb_v <= 0) || pb_v == 3 || (pb_v >= 6 && pb_v <= 8)");
}

fn fields_of_an_imported_type_are_qualified() {
    reset_generator();
    add_nested(add_message(add_file("z/q.v1.proto", "q.r", "proto3"), "Other"), "In");
    add_message(add_file("bare.proto", "", "proto3"), "Bare");
    add_message(add_file("same.proto", "p", "proto3"), "Same");
    add_message(add_file("unused.proto", "", "proto3"), "Unused");
    let file .= add_file("t.proto", "p", "proto3");
    let m .= add_message(file, "M");
    add_message_field(m, "other", 1, LABEL_OPTIONAL, ".q.r.Other.In");
    add_message_field(m, "bare", 2, LABEL_OPTIONAL, ".Bare");
    add_message_field(m, "same", 3, LABEL_OPTIONAL, ".p.Same");
    let out = generated_text(file);
    expect_has(out, "import pb_wire;\nimport bare;\nimport same;\nimport z.q_v1;\n");
    expect_lacks(out, "import unused");
    expect_has(out, "    other: q_r::Other_In_Ref,\n");
    expect_has(out, "    bare: ::Bare_Ref,\n");
    expect_has(out, "    same: Same_Ref,\n");
    expect_has(out, "fn M_other(m: M&) -> q_r::Other_In&?");
    expect_has(out, "q_r::Other_In_decode_from(r, M_mutable_other(m));");
    expect_has(out, "q_r::Other_In_pool.alloc_ref(q_r::Other_In { .. })");
}

fn main() {
    nested_and_top_level_names_collide();
    nested_names_equal_to_generated_names_are_escaped();
    a_top_level_name_equal_to_a_generated_name_collides();
    two_accessors_with_one_name_collide();
    an_escaped_name_still_taken_collides();
    an_enum_value_collides();
    two_record_fields_with_one_name_collide();
    an_imported_file_that_collides_is_reported();
    field_kinds_and_presence();
    proto3_optional_has_a_bit_and_a_real_oneof_an_adt();
    repeated_scalars_of_proto2_are_unpacked();
    singular_fields_are_stored_and_messages_are_not_scalars();
    proto3_strings_are_validated_and_bytes_are_not();
    a_nested_name_equal_to_a_oneof_name_is_escaped();
    sub_messages_are_stored_and_cycles_are_recursive();
    repeated_messages_cycle_and_maps_store_a_run();
    defaults_are_literal_and_bytes_unescaped();
    a_closed_enum_is_checked_as_sorted_runs();
    fields_of_an_imported_type_are_qualified();
}
