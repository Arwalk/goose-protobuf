// Round-trip test for tests/protos/defaults.proto (gpb-6xy.2).
// Run: scripts/roundtrip.sh defaults
import pb_wire;
import defaults;

var failures = 0;

fn fail_at(what: u8[:], detail: u8[:]) {
    failures += 1;
    print("FAIL ", what, ": ", detail);
}

fn check_defaults(what: u8[:], m: def::All&) {
    if m.v_int32 != -5 { fail_at(what, "int32"); }
    if m.v_int64 != -9223372036854775807 - 1 { fail_at(what, "int64"); }
    if m.v_uint32 != 4294967295 { fail_at(what, "uint32"); }
    if m.v_uint64 != 18446744073709551615 { fail_at(what, "uint64"); }
    if m.v_sint32 != -6 { fail_at(what, "sint32"); }
    if m.v_sint64 != -7 { fail_at(what, "sint64"); }
    if m.v_fixed32 != 8 { fail_at(what, "fixed32"); }
    if m.v_fixed64 != 9 { fail_at(what, "fixed64"); }
    if m.v_sfixed32 != -10 { fail_at(what, "sfixed32"); }
    if m.v_sfixed64 != -11 { fail_at(what, "sfixed64"); }
    if m.v_float != 1.5 { fail_at(what, "float"); }
    if m.v_double != -2.5e300 { fail_at(what, "double"); }
    if m.exp_float != 1e10 { fail_at(what, "float exponent"); }
    if m.hex_int != 16.0 { fail_at(what, "double from an integer"); }
    if !m.v_true || m.v_false { fail_at(what, "bool"); }
    let want_s: u8[11] = ['h', 0xc3, 0xa9, 'l', 'l', 'o', ' ', '"', 'q', '"', '\n'];
    if def::All_v_string(m) != want_s { fail_at(what, "string"); }
    let want_b: u8[7] = ['a', 1, 0xff, '\\', '"', 'A', '\n'];
    if def::All_v_bytes(m) != want_b { fail_at(what, "bytes"); }
    if m.v_named != def::Color_BLUE { fail_at(what, "named enum"); }
    if m.v_first != def::Color_YELLOW { fail_at(what, "first enum value"); }
    if m.v_imported != 2 { fail_at(what, "imported enum"); }
    if pb_f32_to_bits(m.inf_float) != 0x7f800000 { fail_at(what, "inf float"); }
    if pb_f32_to_bits(m.neg_inf_float) != 0xff800000 { fail_at(what, "-inf float"); }
    if pb_f32_to_bits(m.nan_float) != 0x7fc00000 { fail_at(what, "nan float"); }
    if pb_f64_to_bits(m.inf_double) != 0x7ff0000000000000 { fail_at(what, "inf double"); }
    if pb_f64_to_bits(m.neg_inf_double) != 0xfff0000000000000 { fail_at(what, "-inf double"); }
    if pb_f64_to_bits(m.nan_double) != 0x7ff8000000000000 { fail_at(what, "nan double"); }
    if pb_f64_to_bits(m.neg_zero) != 0x8000000000000000 { fail_at(what, "-0"); }
    if m.zero != 0 || def::All_empty(m).len != 0 { fail_at(what, "explicit zero"); }
    if m.hex != 16 { fail_at(what, "hex"); }
}

fn encoded_size(m: def::All&) -> i64 {
    var out: u8[>..] = [];
    def::All_encode(m, out);
    if def::All_size_of(m) != out.len { fail_at("encoded", "size_of"); }
    return out.len;
}

fn check_all() {
    var m = def::All { .. };
    check_defaults("new", m);
    if encoded_size(m) != 0 { fail_at("new", "encoded"); }
    if def::All_has_v_int32(m) || def::All_has_v_string(m) { fail_at("new", "has_"); }

    // A decode of nothing leaves them, as does one of anything else.
    let none: u8[0] = [];
    if def::All_decode(none, m) != PB_OK { fail_at("decode", "empty"); }
    check_defaults("decoded", m);

    // Set to the default: encoded. protoc agrees on the bytes.
    let want = embed_file("set.bin");
    def::All_set_v_int32(m, -5);
    def::All_set_v_string(m, "");
    def::All_set_v_named(m, def::Color_BLUE);
    def::All_set_v_first(m, def::Color_GREEN);
    def::All_set_nan_float(m, 1.0);
    def::All_set_zero(m, 0);
    var out: u8[>..] = [];
    def::All_encode(m, out);
    if out != want { fail_at("set", "encoding differs from protoc"); }
    if def::All_v_string(m).len != 0 { fail_at("set", "empty string reads as the default"); }
    if m.v_first != def::Color_GREEN { fail_at("set", "enum"); }

    // A decoded value replaces the default; its copy has it too.
    var b = def::All { .. };
    if def::All_decode(want, b) != PB_OK { fail_at("decode", "set"); }
    if !def::All_has_v_string(b) || def::All_v_string(b).len != 0 { fail_at("decode", "string"); }
    if m.nan_float != 1.0 { fail_at("decode", "float"); }
    var c = def::All { .. };
    def::All_copy(c, b);
    if !def::All_has_v_string(c) || def::All_v_string(c).len != 0 || c.v_first != def::Color_GREEN { fail_at("copy", "values"); }
    if c.v_uint32 != 4294967295 { fail_at("copy", "default"); }
    def::All_clear(b);
    def::All_clear(c);
    check_defaults("cleared copy", c);

    // clear_ goes back to the default, one field at a time.
    def::All_clear_v_int32(m);
    def::All_clear_v_string(m);
    def::All_clear_v_named(m);
    def::All_clear_v_first(m);
    if m.v_int32 != -5 || m.v_named != def::Color_BLUE || m.v_first != def::Color_YELLOW { fail_at("clear_", "values"); }
    if def::All_v_string(m).len != 11 || def::All_has_v_string(m) { fail_at("clear_", "string"); }

    def::All_set_v_bytes(m, "z");
    if def::All_v_bytes(m).len != 1 { fail_at("set", "bytes"); }
    // M_clear too, and it frees what the field held.
    def::All_clear(m);
    check_defaults("cleared", m);
    if encoded_size(m) != 0 { fail_at("cleared", "encoded"); }
}

fn check_pick() {
    var m = def::Pick { .. };
    if def::Pick_p_int(m) != 3 { fail_at("pick", "int"); }
    if def::Pick_p_string(m)[0] != 'x' || def::Pick_p_bytes(m)[0] != 0xff { fail_at("pick", "bytes"); }
    if def::Pick_p_named(m) != def::Color_BLUE || def::Pick_p_first(m) != def::Color_YELLOW { fail_at("pick", "enum"); }
    if pb_f64_to_bits(def::Pick_p_nan(m)) != 0x7ff8000000000000 || !def::Pick_p_bool(m) { fail_at("pick", "nan, bool"); }

    // Another member set: still the default. Itself set: its value.
    def::Pick_set_p_int(m, 0);
    if def::Pick_p_int(m) != 0 || def::Pick_p_named(m) != def::Color_BLUE { fail_at("pick", "set"); }
    def::Pick_set_p_string(m, "");
    if def::Pick_p_string(m).len != 0 || def::Pick_p_int(m) != 3 { fail_at("pick", "string"); }
    def::Pick_clear(m);
}

fn check_req() {
    // A default does not make a required field set.
    var m = def::Req { .. };
    if m.r != 7 { fail_at("req", "default"); }
    if def::Req_is_initialized(m) { fail_at("req", "initialized"); }
    let none: u8[0] = [];
    if def::Req_decode(none, m) != PB_ERR_REQUIRED { fail_at("req", "accepted"); }
    def::Req_clear(m);
}

fn check_holder() {
    // What lives in pools starts from its defaults too.
    var m = def::Holder { .. };
    check_defaults("sub-message", def::Holder_mutable_one(m));
    check_defaults("element", def::Holder_add_many(m));
    let wire: u8[4] = [0x0a, 0, 0x12, 0];
    var d = def::Holder { .. };
    if def::Holder_decode(wire, d) != PB_OK { fail_at("holder", "decode"); }
    let one = def::Holder_one(d);
    guard one else { fail_at("holder", "one"); return; }
    check_defaults("decoded sub-message", one);
    check_defaults("decoded element", def::Holder_many_at(d, 0));
    def::Holder_clear(d);
    def::Holder_clear(m);
    // A slot that is used again starts over.
    def::All_set_v_int32(def::Holder_mutable_one(m), 1);
    def::Holder_clear(m);
    check_defaults("reused slot", def::Holder_mutable_one(m));
    def::Holder_clear(m);
}

fn main() {
    check_all();
    check_pick();
    check_req();
    check_holder();
    if failures > 0 { abort(str(failures, " failures")); }
    print("ok");
}
