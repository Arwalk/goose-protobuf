// Round-trip test for tests/protos/optional.proto (gpb-41j.5).
// Run: scripts/roundtrip.sh optional
import pb_wire;
import optional;

var failures = 0;

fn fail_at(what: u8[:], detail: u8[:]) {
    failures += 1;
    print("FAIL ", what, ": ", detail);
}

fn bytes_eq(a: const u8[:], b: const u8[:]) -> bool {
    if a.len != b.len { return false; }
    for i in a.len { if a[i] != b[i] { return false; } }
    return true;
}

fn hex(b: const u8[:]) -> u8[>..] {
    let digits = "0123456789abcdef";
    var s: u8[>..] = [];
    for i in b.len {
        if i > 0 { s.push(32); }
        s.push(digits[(b[i] >> 4) as i64]);
        s.push(digits[(b[i] & 15) as i64]);
    }
    return s;
}

// Values and has-bits; floats by bits.
fn same(a: optional::Opt&, b: optional::Opt&) -> bool {
    return a.pb_has0 == b.pb_has0 && a.pb_has1 == b.pb_has1
        && a.o_int32 == b.o_int32 && a.o_sint64 == b.o_sint64
        && pb_f64_to_bits(a.o_double) == pb_f64_to_bits(b.o_double)
        && pb_f32_to_bits(a.o_float) == pb_f32_to_bits(b.o_float)
        && a.o_bool == b.o_bool && a.o_mode == b.o_mode
        && a.o_fixed64 == b.o_fixed64 && a.plain == b.plain
        && a.o9 == b.o9 && a.o20 == b.o20 && a.o32 == b.o32
        && a.o33 == b.o33 && a.o34 == b.o34;
}

// built encodes to want (protoc's bytes), and want decodes to built.
fn check_case(name: u8[:], want: const u8[:], built: optional::Opt&) {
    var out: u8[>..] = [];
    optional::Opt_encode(built, out);
    if !bytes_eq(out, want) { fail_at(name, str("encode [", hex(out), "] want [", hex(want), "]")); }
    if optional::Opt_size_of(built) != want.len {
        fail_at(name, str("size_of ", optional::Opt_size_of(built), " want ", want.len));
    }
    var back = optional::Opt { .. };
    let err = optional::Opt_decode(want, back);
    if err != PB_OK { fail_at(name, str("decode error ", err)); return; }
    if !same(back, built) { fail_at(name, "decoded message differs from the built one"); }
    var again: u8[>..] = [];
    optional::Opt_encode(back, again);
    if !bytes_eq(again, want) { fail_at(name, str("re-encode [", hex(again), "] want [", hex(want), "]")); }
    optional::Opt_clear(back);
    if back.pb_has0 != 0 || back.pb_has1 != 0 || optional::Opt_size_of(back) != 0 {
        fail_at(name, "clear left fields set");
    }
}

fn main() {
    var zero = optional::Opt { .. };
    optional::Opt_set_o_int32(zero, 0);
    optional::Opt_set_o_sint64(zero, 0);
    optional::Opt_set_o_double(zero, 0.0);
    optional::Opt_set_o_float(zero, 0.0);
    optional::Opt_set_o_bool(zero, false);
    optional::Opt_set_o_mode(zero, optional::Mode_MODE_UNSPECIFIED);
    optional::Opt_set_o_fixed64(zero, 0);
    optional::Opt_set_o9(zero, 0);
    optional::Opt_set_o32(zero, 0);
    optional::Opt_set_o33(zero, 0);
    optional::Opt_set_o34(zero, 0);
    check_case("set_zero", embed_file("set_zero.bin"), zero);
    if !optional::Opt_has_o_int32(zero) || !optional::Opt_has_o34(zero) || optional::Opt_has_o20(zero) {
        fail_at("set_zero", "has_ disagrees with set_");
    }

    var unset = optional::Opt { .. };
    unset.plain = 5;
    check_case("unset", embed_file("unset.bin"), unset);
    var decoded = optional::Opt { .. };
    optional::Opt_decode(embed_file("unset.bin"), decoded);
    if optional::Opt_has_o_int32(decoded) || optional::Opt_has_o34(decoded) {
        fail_at("unset", "decode set a has-bit for an absent field");
    }

    var vals = optional::Opt { .. };
    optional::Opt_set_o_int32(vals, -7);
    optional::Opt_set_o_sint64(vals, -9000000000);
    optional::Opt_set_o_double(vals, 0.5);
    optional::Opt_set_o_float(vals, pb_f32_from_bits(0x80000000));
    optional::Opt_set_o_bool(vals, true);
    optional::Opt_set_o_mode(vals, optional::Mode_MODE_ON);
    optional::Opt_set_o_fixed64(vals, 1);
    optional::Opt_set_o20(vals, 20);
    optional::Opt_set_o34(vals, 4000000000);
    check_case("values", embed_file("values.bin"), vals);

    // clear_ drops one field: value and has-bit.
    optional::Opt_clear_o34(vals);
    if optional::Opt_has_o34(vals) || vals.o34 != 0 || !optional::Opt_has_o20(vals) {
        fail_at("clear_o34", "clear_ did not drop exactly that field");
    }
    var cleared: u8[>..] = [];
    optional::Opt_encode(vals, cleared);
    let full = embed_file("values.bin");
    // o34 is last in field order: its tag (2 bytes) and 5-byte varint go.
    if !bytes_eq(cleared, full[0..full.len - 7]) {
        fail_at("clear_o34", str("encode [", hex(cleared), "]"));
    }

    // Without set_, a written value has no has-bit, so it is not encoded.
    var direct = optional::Opt { .. };
    direct.o_int32 = 3;
    if optional::Opt_size_of(direct) != 0 { fail_at("direct", "a value without its has-bit was encoded"); }

    if failures != 0 { abort(str(failures, " failures")); }
    print("optional round-trip: all passed");
}
