// Unit tests for runtime/pb_wire.goose scalar primitives (gpb-41j.1).
// Run: scripts/goose_tests.sh tests/runtime
// The runtime is imported as a directory package: a plain import cannot
// reach above this file's directory.
import pb_wire from "../../runtime";

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

// Encodes v, checks the bytes and the size, decodes it back.
fn check_varint(v: u64, want: const u8[:]) {
    var out: u8[>..] = [];
    pb_write_varint(out, v);
    if !bytes_eq(out, want) { fail_at("varint encode", str(v, " -> ", out)); }
    if pb_varint_size(v) != want.len { fail_at("varint size", str(v, " -> ", pb_varint_size(v))); }
    var r = pb_reader(out);
    let back = pb_read_varint(r);
    if r.err != PB_OK || back != v || r.pos != out.len {
        fail_at("varint decode", str(v, " -> ", back, " err ", r.err, " pos ", r.pos));
    }
}

fn check_decode_err(what: u8[:], input: const u8[:], want_err: i32) {
    var r = pb_reader(input);
    let v = pb_read_varint(r);
    if r.err != want_err { fail_at(what, str("err ", r.err, " want ", want_err, " value ", v)); }
    if r.pos != r.end { fail_at(what, "pos not at end after failure"); }
}

fn test_varint() {
    check_varint(0, [0x00]);
    check_varint(1, [0x01]);
    check_varint(127, [0x7f]);
    check_varint(128, [0x80, 0x01]);
    check_varint(150, [0x96, 0x01]);
    check_varint(16383, [0xff, 0x7f]);
    check_varint(16384, [0x80, 0x80, 0x01]);
    check_varint(0x8000000000000000, [0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01]);
    check_varint(0xffffffffffffffff, [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01]);

    // Negative int32 is sign-extended to 64 bits: 10 bytes on the wire.
    var out: u8[>..] = [];
    let minus_one: i32 = -1;
    pb_write_varint(out, pb_int32_to_u64(minus_one));
    if out.len != 10 { fail_at("int32 -1", str(out.len, " bytes")); }
    var r = pb_reader(out);
    if pb_u64_to_int32(pb_read_varint(r)) != minus_one { fail_at("int32 -1", "round trip"); }
    let min32: i32 = -2147483648;
    if pb_varint_size(pb_int32_to_u64(min32)) != 10 { fail_at("int32 min", "size"); }

    // A 10th byte with bits above 2^64 is accepted; they are dropped.
    let ten: u8[10] = [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f];
    var r10 = pb_reader(ten);
    if pb_read_varint(r10) != 0xffffffffffffffff || r10.err != PB_OK { fail_at("10th byte", "lenient"); }

    check_decode_err("11-byte varint", [0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01],
                     PB_ERR_MALFORMED);
    check_decode_err("truncated varint", [0x80, 0x80], PB_ERR_TRUNCATED);
    let none: u8[1] = [0x80];
    check_decode_err("empty input", none[..0], PB_ERR_TRUNCATED);

    // The first error sticks, and reads after it return 0.
    let one_byte: u8[1] = [0x80];
    var rs = pb_reader(one_byte);
    pb_read_varint(rs);
    pb_fail(rs, PB_ERR_DEPTH);
    if rs.err != PB_ERR_TRUNCATED || pb_read_varint(rs) != 0 { fail_at("sticky error", str(rs.err)); }
}

fn test_zigzag() {
    let cases32: i32[6] = [0, -1, 1, -2, 2147483647, -2147483648];
    let want32: u32[6] = [0, 1, 2, 3, 4294967294, 4294967295];
    for i in 6 {
        if pb_zigzag32(cases32[i]) != want32[i] { fail_at("zigzag32", str(cases32[i])); }
        if pb_unzigzag32(want32[i]) != cases32[i] { fail_at("unzigzag32", str(want32[i])); }
    }
    let max64: i64 = 9223372036854775807;
    let min64: i64 = -9223372036854775807 - 1;
    let cases64: i64[6] = [0, -1, 1, -2, max64, min64];
    let want64: u64[6] = [0, 1, 2, 3, 0xfffffffffffffffe, 0xffffffffffffffff];
    for i in 6 {
        if pb_zigzag64(cases64[i]) != want64[i] { fail_at("zigzag64", str(cases64[i])); }
        if pb_unzigzag64(want64[i]) != cases64[i] { fail_at("unzigzag64", str(want64[i])); }
    }
}

fn test_fixed() {
    var out: u8[>..] = [];
    pb_write_fixed32(out, 0x12345678);
    pb_write_fixed64(out, 0x0102030405060708);
    if !bytes_eq(out, [0x78, 0x56, 0x34, 0x12, 0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01]) {
        fail_at("fixed encode", str(out));
    }
    var r = pb_reader(out);
    if pb_read_fixed32(r) != 0x12345678 { fail_at("fixed32 decode", ""); }
    if pb_read_fixed64(r) != 0x0102030405060708 { fail_at("fixed64 decode", ""); }
    if r.err != PB_OK || r.pos != 12 { fail_at("fixed decode", "state"); }

    var t32 = pb_reader(out[..3]);
    if pb_read_fixed32(t32) != 0 || t32.err != PB_ERR_TRUNCATED { fail_at("fixed32 truncated", ""); }
    var t64 = pb_reader(out[..7]);
    if pb_read_fixed64(t64) != 0 || t64.err != PB_ERR_TRUNCATED { fail_at("fixed64 truncated", ""); }
}

fn test_tags() {
    var out: u8[>..] = [];
    pb_write_tag(out, 1, PB_WT_VARINT);
    pb_write_tag(out, 16, PB_WT_LEN);
    pb_write_tag(out, 536870911, PB_WT_I32);     // max field number
    if pb_tag_size(1) != 1 || pb_tag_size(16) != 2 || pb_tag_size(536870911) != 5 {
        fail_at("tag size", "");
    }
    var r = pb_reader(out);
    let t1 = pb_read_tag(r);
    let t2 = pb_read_tag(r);
    let t3 = pb_read_tag(r);
    if pb_tag_field(t1) != 1 || pb_tag_wire(t1) != PB_WT_VARINT { fail_at("tag 1", str(t1)); }
    if pb_tag_field(t2) != 16 || pb_tag_wire(t2) != PB_WT_LEN { fail_at("tag 16", str(t2)); }
    if pb_tag_field(t3) != 536870911 || pb_tag_wire(t3) != PB_WT_I32 { fail_at("tag max", str(t3)); }
    if r.err != PB_OK { fail_at("tags", "err"); }

    // Field number 0, wire types 6 and 7, and tags over 32 bits are malformed.
    let bad: u8[4][4] = [[0x00, 0, 0, 0], [0x0e, 0, 0, 0], [0x0f, 0, 0, 0], [0x80, 0x80, 0x80, 0x80]];
    let lens: i64[4] = [1, 1, 1, 4];
    for i in 4 {
        var rb = pb_reader(bad[i][..lens[i]]);
        if pb_read_tag(rb) != 0 || rb.err == PB_OK { fail_at("bad tag", str(i)); }
    }
    let big_tag: u8[5] = [0x80, 0x80, 0x80, 0x80, 0x10];   // field 2^29
    var big = pb_reader(big_tag);
    if pb_read_tag(big) != 0 || big.err != PB_ERR_MALFORMED { fail_at("tag over 32 bits", str(big.err)); }

    // A tag is at most 5 bytes, as in protobuf: tag 8 padded to 5 bytes
    // reads, padded to 6 or 9 bytes (conformance BadTag_OverlongVarint) is
    // malformed even though its value fits.
    let padded: u8[9] = [0x88, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x00];
    let five: u8[5] = [0x88, 0x80, 0x80, 0x80, 0x00];
    var r5 = pb_reader(five);
    if pb_read_tag(r5) != 8 || r5.err != PB_OK || r5.pos != 5 { fail_at("5-byte tag", str(r5.err)); }
    let six: u8[6] = [0x88, 0x80, 0x80, 0x80, 0x80, 0x00];
    var r6 = pb_reader(six);
    if pb_read_tag(r6) != 0 || r6.err != PB_ERR_MALFORMED { fail_at("6-byte tag", str(r6.err)); }
    var r9 = pb_reader(padded);
    if pb_read_tag(r9) != 0 || r9.err != PB_ERR_MALFORMED { fail_at("9-byte tag", str(r9.err)); }
}

fn test_len() {
    let input: u8[6] = [0x03, 0x61, 0x62, 0x63, 0x05, 0x61];
    var r = pb_reader(input);
    if pb_read_len(r) != 3 { fail_at("len", "3"); }
    r.pos += 3;
    if pb_read_len(r) != 0 || r.err != PB_ERR_TRUNCATED { fail_at("len overrun", str(r.err)); }
    // A length larger than any i64 must not wrap negative.
    let huge_len: u8[10] = [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01];
    var huge = pb_reader(huge_len);
    if pb_read_len(huge) != 0 || huge.err != PB_ERR_TRUNCATED { fail_at("len 2^64-1", str(huge.err)); }
}

fn check_f32(name: u8[:], bits: u32) {
    let back = pb_f32_to_bits(pb_f32_from_bits(bits));
    var out: u8[>..] = [];
    pb_write_float(out, pb_f32_from_bits(bits));
    var r = pb_reader(out);
    let wire = pb_f32_to_bits(pb_read_float(r));
    if back != bits || wire != bits { fail_at(str("f32 ", name), str(bits, " -> ", back, " / ", wire)); }
}

fn check_f64(name: u8[:], bits: u64) {
    let back = pb_f64_to_bits(pb_f64_from_bits(bits));
    var out: u8[>..] = [];
    pb_write_double(out, pb_f64_from_bits(bits));
    var r = pb_reader(out);
    let wire = pb_f64_to_bits(pb_read_double(r));
    if back != bits || wire != bits { fail_at(str("f64 ", name), str(bits, " -> ", back, " / ", wire)); }
}

// The 26 vectors of docs/decisions/0002-float-bits.md.
fn test_floats() {
    let zero32: f32 = 0.0;
    let zero64: f64 = 0.0;
    if pb_f32_to_bits(-zero32) != 0x80000000 { fail_at("f32 -0.0", "to_bits"); }
    if pb_f64_to_bits(-zero64) != 0x8000000000000000 { fail_at("f64 -0.0", "to_bits"); }
    if pb_f32_to_bits(1.0) != 0x3F800000 { fail_at("f32 1.0", "to_bits"); }
    if pb_f64_to_bits(-2.5) != 0xC004000000000000 { fail_at("f64 -2.5", "to_bits"); }
    if pb_f32_to_bits(1.0 / zero32) != 0x7F800000 { fail_at("f32 +inf", "to_bits"); }
    if pb_f64_to_bits(-1.0 / zero64) != 0xFFF0000000000000 { fail_at("f64 -inf", "to_bits"); }

    check_f32("+0.0", 0x00000000);
    check_f32("-0.0", 0x80000000);
    check_f32("1.0", 0x3F800000);
    check_f32("-2.5", 0xC0200000);
    check_f32("+inf", 0x7F800000);
    check_f32("-inf", 0xFF800000);
    check_f32("qNaN payload 1", 0x7FC00001);
    check_f32("-qNaN payload", 0xFFC0BEEF);
    check_f32("sNaN payload 1", 0x7F800001);
    check_f32("sNaN max payload", 0x7FBFFFFF);
    check_f32("min subnormal", 0x00000001);
    check_f32("max subnormal", 0x007FFFFF);
    check_f32("max finite", 0x7F7FFFFF);

    check_f64("+0.0", 0x0000000000000000);
    check_f64("-0.0", 0x8000000000000000);
    check_f64("1.0", 0x3FF0000000000000);
    check_f64("-2.5", 0xC004000000000000);
    check_f64("+inf", 0x7FF0000000000000);
    check_f64("-inf", 0xFFF0000000000000);
    check_f64("qNaN payload 1", 0x7FF8000000000001);
    check_f64("-qNaN payload", 0xFFF800000000BEEF);
    check_f64("sNaN payload 1", 0x7FF0000000000001);
    check_f64("sNaN max payload", 0x7FF7FFFFFFFFFFFF);
    check_f64("min subnormal", 0x0000000000000001);
    check_f64("max subnormal", 0x000FFFFFFFFFFFFF);
    check_f64("max finite", 0x7FEFFFFFFFFFFFFF);
}

fn test_bool() {
    if pb_bool_to_u64(true) != 1 || pb_bool_to_u64(false) != 0 { fail_at("bool", "pb_bool_to_u64"); }
}

fn main() {
    test_varint();
    test_zigzag();
    test_fixed();
    test_tags();
    test_len();
    test_floats();
    test_bool();
    if failures != 0 { abort(str(failures, " failures")); }
    print("pb_wire scalar tests: all passed");
}
