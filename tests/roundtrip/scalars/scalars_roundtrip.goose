// Round-trip test for tests/protos/scalars.proto (gpb-41j.4).
// Run: scripts/roundtrip.sh scalars
// scripts/roundtrip.sh generates scalars.goose next to this file, with
// pb_wire.goose, and encodes each *.txtpb here with protoc --encode into
// <case>.bin, which the test embeds.
import pb_wire;
import scalars;

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

// Field-by-field equality; floats by bits, so -0.0 differs from 0.0.
fn same(a: scalars::Scalars&, b: scalars::Scalars&) -> bool {
    return a.f_int32 == b.f_int32 && a.f_int64 == b.f_int64
        && a.f_uint32 == b.f_uint32 && a.f_uint64 == b.f_uint64
        && a.f_sint32 == b.f_sint32 && a.f_sint64 == b.f_sint64
        && a.f_fixed32 == b.f_fixed32 && a.f_fixed64 == b.f_fixed64
        && a.f_sfixed32 == b.f_sfixed32 && a.f_sfixed64 == b.f_sfixed64
        && pb_f32_to_bits(a.f_float) == pb_f32_to_bits(b.f_float)
        && pb_f64_to_bits(a.f_double) == pb_f64_to_bits(b.f_double)
        && a.f_bool == b.f_bool && a.f_color == b.f_color
        && a.f_mid == b.f_mid && a.f_big == b.f_big;
}

// want: the protoc --encode bytes of a case; built: the same message built
// in Goose. Checks that built encodes to want, that size_of agrees, and
// that want decodes to built and re-encodes to the same bytes.
fn check_case(name: u8[:], want: const u8[:], built: scalars::Scalars&) {
    var out: u8[>..] = [];
    scalars::Scalars_encode(built, out);
    if !bytes_eq(out, want) { fail_at(name, str("encode [", hex(out), "] want [", hex(want), "]")); }
    if scalars::Scalars_size_of(built) != want.len {
        fail_at(name, str("size_of ", scalars::Scalars_size_of(built), " want ", want.len));
    }

    var back = scalars::Scalars { .. };
    let err = scalars::Scalars_decode(want, back);
    if err != PB_OK { fail_at(name, str("decode error ", err)); return; }
    if !same(back, built) { fail_at(name, "decoded fields differ from the built message"); }
    var again: u8[>..] = [];
    scalars::Scalars_encode(back, again);
    if !bytes_eq(again, want) { fail_at(name, str("re-encode [", hex(again), "] want [", hex(want), "]")); }

    // Merging the same bytes twice: the last value wins, nothing changes.
    if want.len > 0 {
        var twice: u8[>..] = [];
        twice.append(want);
        twice.append(want);
        var merged = scalars::Scalars { .. };
        if scalars::Scalars_decode(twice, merged) != PB_OK || !same(merged, built) {
            fail_at(name, "decoding the bytes twice changed the message");
        }
        // Dropping the last byte cuts the last field's value short.
        var cut = scalars::Scalars { .. };
        if scalars::Scalars_decode(want[0..want.len - 1], cut) != PB_ERR_TRUNCATED {
            fail_at(name, "a truncated encoding decoded");
        }
    }

    scalars::Scalars_clear(back);
    if scalars::Scalars_size_of(back) != 0 { fail_at(name, "clear left fields set"); }
}

fn main() {
    var all = scalars::Scalars { .. };
    all.f_int32 = -5;
    all.f_int64 = 1234567890123;
    all.f_uint32 = 4000000000;
    all.f_uint64 = 18000000000000000000;
    all.f_sint32 = -300;
    all.f_sint64 = -70000000000;
    all.f_fixed32 = 3000000000;
    all.f_fixed64 = 9000000000000000000;
    all.f_sfixed32 = -123456;
    all.f_sfixed64 = -1234567890123456;
    all.f_float = 1.5;
    all.f_double = -2.25;
    all.f_bool = true;
    all.f_color = scalars::Color_COLOR_RED;
    all.f_mid = 300;
    all.f_big = 7;
    check_case("all_set", embed_file("all_set.bin"), all);

    var ext = scalars::Scalars { .. };
    ext.f_int32 = -2147483648;
    ext.f_int64 = -9223372036854775808;
    ext.f_uint32 = 4294967295;
    ext.f_uint64 = 18446744073709551615;
    ext.f_sint32 = -2147483648;
    ext.f_sint64 = -9223372036854775808;
    ext.f_fixed32 = 4294967295;
    ext.f_fixed64 = 18446744073709551615;
    ext.f_sfixed32 = -2147483648;
    ext.f_sfixed64 = -9223372036854775808;
    ext.f_float = pb_f32_from_bits(0xff800000);    // -inf
    ext.f_double = pb_f64_from_bits(0x7ff0000000000000);   // +inf
    ext.f_color = scalars::Color_COLOR_NEGATIVE;
    ext.f_mid = 2147483647;
    ext.f_big = -1;
    check_case("extremes", embed_file("extremes.bin"), ext);

    var defaults = scalars::Scalars { .. };
    let empty = embed_file("defaults.bin");
    if empty.len != 0 { fail_at("defaults", "protoc encoded a default value"); }
    check_case("defaults", empty, defaults);

    var neg = scalars::Scalars { .. };
    neg.f_float = pb_f32_from_bits(0x80000000);
    neg.f_double = pb_f64_from_bits(0x8000000000000000);
    check_case("negative_zero", embed_file("negative_zero.bin"), neg);

    // Fields of other kinds between them: the scalars still decode.
    var skipped = scalars::Scalars { .. };
    if scalars::Scalars_decode(embed_file("skipped.bin"), skipped) != PB_OK
        || skipped.f_int32 != 1 || skipped.f_mid != 2 {
        fail_at("skipped", "stored fields around skipped ones did not decode");
    }

    // A known field number with another wire type is not that field.
    var mismatch = scalars::Scalars { .. };
    let fixed_one: u8[5] = [0x0d, 1, 0, 0, 0];   // field 1 as fixed32
    if scalars::Scalars_decode(fixed_one, mismatch) != PB_OK || mismatch.f_int32 != 0 {
        fail_at("mismatch", "a wire-type mismatch was decoded into the field");
    }

    // int32 is sign-extended on the wire; a 64-bit varint is truncated.
    var trunc = scalars::Scalars { .. };
    let wide: u8[6] = [0x08, 0x81, 0x80, 0x80, 0x80, 0x10];   // 2^32 + 1
    if scalars::Scalars_decode(wide, trunc) != PB_OK || trunc.f_int32 != 1 {
        fail_at("int32 truncation", str("got ", trunc.f_int32));
    }

    // Merging: a later value replaces an earlier one.
    var last = scalars::Scalars { .. };
    let two: u8[4] = [0x08, 0x01, 0x08, 0x02];
    if scalars::Scalars_decode(two, last) != PB_OK || last.f_int32 != 2 {
        fail_at("last wins", str("got ", last.f_int32));
    }

    if failures != 0 { abort(str(failures, " failures")); }
    print("scalars round-trip: all passed");
}
