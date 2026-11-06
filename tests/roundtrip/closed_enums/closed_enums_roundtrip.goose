// Round-trip test for tests/protos/closed_enums.proto (gpb-6xy.3).
// Run: scripts/roundtrip.sh closed_enums
import pb_wire;
import closed_enums;
import closed_enums_open;

var failures = 0;

fn fail_at(what: u8[:], detail: u8[:]) {
    failures += 1;
    print("FAIL ", what, ": ", detail);
}

fn encoded(m: closed_e::M&) -> u8[>..] {
    var out: u8[>..] = [];
    closed_e::M_encode(m, out);
    if closed_e::M_size_of(m) != out.len { fail_at("encoded", "size_of"); }
    return out;
}

// One value of field 1, a known or an unknown one.
fn check_mode(name: u8[:], input: const u8[:], known: bool, want: i32) {
    var m = closed_e::M { .. };
    if closed_e::M_decode(input, m) != PB_OK { fail_at(name, "decode"); }
    if closed_e::M_has_mode(m) != known { fail_at(name, "has_"); }
    if m.mode != want { fail_at(name, "value"); }
    if known && m.pb_unknown.len != 0 { fail_at(name, "kept as unknown"); }
    if !known && m.pb_unknown.len != input.len { fail_at(name, "not kept as unknown"); }
    if encoded(m) != input { fail_at(name, "re-encoding differs"); }
    closed_e::M_clear(m);
}

fn main() {
    // Every kind of enum, from protoc's bytes.
    let known = embed_file("known.bin");
    var m = closed_e::M { .. };
    if closed_e::M_decode(known, m) != PB_OK { fail_at("known", "decode"); }
    if m.pb_unknown.len != 0 { fail_at("known", "kept as unknown"); }
    if m.mode != closed_e::Mode_MODE_NEG || m.inner != closed_e::M_Inner_INNER_ONE || m.open != open_e::Open_OPEN_ONE {
        fail_at("known", "values");
    }
    if !closed_e::M_has_nested(m) || m.nested != 2 { fail_at("known", "imported enum"); }
    if encoded(m) != known { fail_at("known", "re-encoding differs"); }

    // Accessors, and a deep copy keeps presence.
    closed_e::M_clear_mode(m);
    if closed_e::M_has_mode(m) || m.mode != closed_e::Mode_MODE_SEVEN { fail_at("accessors", "clear_"); }
    closed_e::M_set_mode(m, closed_e::Mode_MODE_ZERO);
    if !closed_e::M_has_mode(m) { fail_at("accessors", "set_"); }
    var c = closed_e::M { .. };
    closed_e::M_copy(c, m);
    if !closed_e::M_has_mode(c) { fail_at("copy", "has_"); }
    closed_e::M_clear(c);
    closed_e::M_clear(m);

    // The name of a value: in any order, at both ends of the range, the first
    // declared of an alias, and nothing for a value the enum does not declare.
    if closed_e::Mode_name(closed_e::Mode_MODE_ZERO) != "MODE_ZERO" { fail_at("name", "zero"); }
    if closed_e::Mode_name(7) != "MODE_SEVEN" { fail_at("name", "first declared"); }
    if closed_e::Mode_name(closed_e::Mode_MODE_SIX_AGAIN) != "MODE_SIX" { fail_at("name", "alias"); }
    if closed_e::Mode_name(-1) != "MODE_NEG" { fail_at("name", "negative"); }
    if closed_e::Mode_name(closed_e::Mode_MODE_MIN) != "MODE_MIN" { fail_at("name", "minimum"); }
    if closed_e::Mode_name(closed_e::Mode_MODE_MAX) != "MODE_MAX" { fail_at("name", "maximum"); }
    if closed_e::Mode_name(5) != "" { fail_at("name", "undeclared"); }
    if closed_e::M_Inner_name(closed_e::M_Inner_INNER_ONE) != "INNER_ONE" { fail_at("name", "nested"); }

    // The declared values, and their neighbours.
    let v0: u8[2] = [0x08, 0];
    check_mode("0", v0, true, 0);
    let v6: u8[2] = [0x08, 6];
    check_mode("6", v6, true, 6);
    let v7: u8[2] = [0x08, 7];
    check_mode("7", v7, true, 7);
    let v8: u8[2] = [0x08, 8];
    check_mode("8", v8, true, 8);
    let v1: u8[2] = [0x08, 1];
    check_mode("1", v1, false, closed_e::Mode_MODE_SEVEN);
    let v5: u8[2] = [0x08, 5];
    check_mode("5", v5, false, closed_e::Mode_MODE_SEVEN);
    let v9: u8[2] = [0x08, 9];
    check_mode("9", v9, false, closed_e::Mode_MODE_SEVEN);
    let neg1: u8[11] = [0x08, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01];
    check_mode("-1", neg1, true, -1);
    let neg2: u8[11] = [0x08, 0xfe, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01];
    check_mode("-2", neg2, false, closed_e::Mode_MODE_SEVEN);
    let imax: u8[6] = [0x08, 0xff, 0xff, 0xff, 0xff, 0x07];
    check_mode("max", imax, true, 2147483647);
    let imin: u8[11] = [0x08, 0x80, 0x80, 0x80, 0x80, 0xf8, 0xff, 0xff, 0xff, 0xff, 0x01];
    check_mode("min", imin, true, -2147483647 - 1);

    // A non-canonical unknown value keeps its bytes, as an overlong varint.
    let long: u8[3] = [0x08, 0x81, 0x00];
    check_mode("overlong", long, false, closed_e::Mode_MODE_SEVEN);

    // An unknown value leaves an earlier one in place, and a later one wins.
    let seq: u8[6] = [0x08, 6, 0x08, 1, 0x08, 7];
    if closed_e::M_decode(seq, m) != PB_OK { fail_at("seq", "decode"); }
    if m.mode != 7 || m.pb_unknown.len != 2 { fail_at("seq", "value"); }
    let seq_out: u8[4] = [0x08, 7, 0x08, 1];
    if encoded(m) != seq_out { fail_at("seq", "re-encoding"); }
    closed_e::M_clear(m);

    // Merging in a second decode appends to what is unknown already.
    let one: u8[2] = [0x08, 1];
    let two: u8[2] = [0x08, 2];
    if closed_e::M_decode(one, m) != PB_OK || closed_e::M_decode(two, m) != PB_OK { fail_at("merge", "decode"); }
    let both: u8[4] = [0x08, 1, 0x08, 2];
    if encoded(m) != both { fail_at("merge", "re-encoding"); }
    closed_e::M_clear(m);

    // Nested and imported closed enums are checked against their own values.
    let in_bad: u8[2] = [0x10, 2];
    if closed_e::M_decode(in_bad, m) != PB_OK || closed_e::M_has_inner(m) || m.pb_unknown.len != 2 { fail_at("inner", "not unknown"); }
    closed_e::M_clear(m);
    let in_good: u8[2] = [0x10, 1];
    if closed_e::M_decode(in_good, m) != PB_OK || !closed_e::M_has_inner(m) { fail_at("inner", "not stored"); }
    closed_e::M_clear(m);
    let ne_bad: u8[2] = [0x18, 1];
    if closed_e::M_decode(ne_bad, m) != PB_OK || closed_e::M_has_nested(m) || m.pb_unknown.len != 2 { fail_at("nested", "not unknown"); }
    closed_e::M_clear(m);

    // A proto3 enum is open: any value is stored.
    let op: u8[2] = [0x20, 99];
    if closed_e::M_decode(op, m) != PB_OK || !closed_e::M_has_open(m) || m.open != 99 || m.pb_unknown.len != 0 { fail_at("open", "not stored"); }
    closed_e::M_clear(m);

    // A truncated value fails, and leaves nothing behind.
    let trunc: u8[2] = [0x08, 0x81];
    if closed_e::M_decode(trunc, m) == PB_OK { fail_at("truncated", "accepted"); }
    if closed_e::M_has_mode(m) { fail_at("truncated", "has_"); }
    closed_e::M_clear(m);

    // A required enum is checked. An unknown value leaves it unset.
    var r = closed_e::Req { .. };
    let none: u8[0] = [];
    if closed_e::Req_decode(none, r) != PB_ERR_REQUIRED { fail_at("required", "unset accepted"); }
    closed_e::Req_clear(r);
    if closed_e::Req_decode(v0, r) != PB_OK { fail_at("required", "default rejected"); }
    closed_e::Req_clear(r);
    if closed_e::Req_decode(v1, r) != PB_ERR_REQUIRED { fail_at("required", "unknown value accepted"); }
    if r.pb_unknown.len != 2 { fail_at("required", "not kept as unknown"); }
    closed_e::Req_clear(r);
    var h = closed_e::Holder { .. };
    let inner_bad: u8[4] = [0x0a, 2, 0x08, 1];
    if closed_e::Holder_decode(inner_bad, h) != PB_ERR_REQUIRED { fail_at("holder", "unknown value accepted"); }
    closed_e::Holder_clear(h);

    if failures > 0 { abort(str(failures, " failures")); }
    print("ok");
}
