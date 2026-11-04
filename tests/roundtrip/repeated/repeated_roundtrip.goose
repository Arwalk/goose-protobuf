// Round-trip test for tests/protos/repeated.proto (gpb-gp4.1).
// Run: scripts/roundtrip.sh repeated
import pb_wire;
import repeated;

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

// Input in either form, decoded as Packed: re-encodes as want.
fn check_packed(name: u8[:], input: const u8[:], want: const u8[:]) {
    var m = repeated::Packed { .. };
    let err = repeated::Packed_decode(input, m);
    if err != PB_OK { fail_at(name, str("decode error ", err)); return; }
    if m.pb_unknown.len != 0 { fail_at(name, "a field stayed unknown"); }
    var out: u8[>..] = [];
    repeated::Packed_encode(m, out);
    if !bytes_eq(out, want) { fail_at(name, str("encode [", hex(out), "] want [", hex(want), "]")); }
    if repeated::Packed_size_of(m) != want.len { fail_at(name, str("size_of ", repeated::Packed_size_of(m), " want ", want.len)); }
    repeated::Packed_clear(m);
    if repeated::Packed_size_of(m) != 0 { fail_at(name, "clear"); }
}

fn check_unpacked(name: u8[:], input: const u8[:], want: const u8[:]) {
    var m = repeated::Unpacked { .. };
    let err = repeated::Unpacked_decode(input, m);
    if err != PB_OK { fail_at(name, str("decode error ", err)); return; }
    if m.pb_unknown.len != 0 { fail_at(name, "a field stayed unknown"); }
    var out: u8[>..] = [];
    repeated::Unpacked_encode(m, out);
    if !bytes_eq(out, want) { fail_at(name, str("encode [", hex(out), "] want [", hex(want), "]")); }
    if repeated::Unpacked_size_of(m) != want.len { fail_at(name, str("size_of ", repeated::Unpacked_size_of(m), " want ", want.len)); }
    repeated::Unpacked_clear(m);
}

// The values themselves, whichever form they came in.
fn check_values(name: u8[:], input: const u8[:]) {
    var m = repeated::Packed { .. };
    if repeated::Packed_decode(input, m) != PB_OK { fail_at(name, "decode"); return; }
    let i = repeated::Packed_f_int32(m);
    if i.len != 4 || i[0] != 1 || i[1] != -1 || i[2] != 300 || i[3] != 0 { fail_at(name, "f_int32"); }
    let s = repeated::Packed_f_sint32(m);
    if s.len != 3 || s[0] != -1 || s[1] != 1 || s[2] != -2147483648 { fail_at(name, "f_sint32"); }
    let u = repeated::Packed_f_uint64(m);
    if u.len != 1 || u[0] != 18446744073709551615 { fail_at(name, "f_uint64"); }
    let b = repeated::Packed_f_bool(m);
    if b.len != 3 || !b[0] || b[1] || !b[2] { fail_at(name, "f_bool"); }
    let e = repeated::Packed_f_enum(m);
    if e.len != 3 || e[0] != repeated::Color_COLOR_RED || e[2] != 77 { fail_at(name, "f_enum keeps unknown values"); }
    if repeated::Packed_f_double_at(m, 0) != -1.5e300 { fail_at(name, "f_double"); }
    if pb_f64_to_bits(repeated::Packed_f_double_at(m, 2)) != 0x8000000000000000 { fail_at(name, "f_double -0.0"); }
    if m.single != 9 { fail_at(name, "single"); }
    repeated::Packed_clear(m);
}

fn check_built() {
    var m = repeated::Packed { .. };
    repeated::Packed_add_f_int32(m, 1);
    repeated::Packed_add_f_int32(m, 2);
    if repeated::Packed_f_int32_at(m, 1) != 2 { fail_at("built", "add"); }
    let vs: i32[3] = [7, 8, 9];
    repeated::Packed_set_f_int32(m, vs);
    if repeated::Packed_f_int32(m).len != 3 || repeated::Packed_f_int32_at(m, 2) != 9 { fail_at("built", "set"); }
    // Setting from its own values.
    repeated::Packed_set_f_int32(m, repeated::Packed_f_int32(m)[1..]);
    if repeated::Packed_f_int32(m).len != 2 || repeated::Packed_f_int32_at(m, 0) != 8 { fail_at("built", "self set"); }
    repeated::Packed_clear_f_int32(m);
    if repeated::Packed_f_int32(m).len != 0 { fail_at("built", "clear_"); }
    if repeated::Packed_size_of(m) != 0 { fail_at("built", "an empty field took bytes"); }
    // Many values through add_: the decoder's doubling is not involved.
    for i in 1000 { repeated::Packed_add_f_uint32(m, i as! u32); }
    var out: u8[>..] = [];
    repeated::Packed_encode(m, out);
    var back = repeated::Packed { .. };
    if repeated::Packed_decode(out, back) != PB_OK { fail_at("built", "decode"); }
    if repeated::Packed_f_uint32(back).len != 1000 || repeated::Packed_f_uint32_at(back, 999) != 999 { fail_at("built", "1000 values"); }
    if repeated::Packed_size_of(back) != out.len { fail_at("built", "size_of"); }
    repeated::Packed_clear(m);
    repeated::Packed_clear(back);
}

// Decoding appends: to what is there, and across a run being moved by
// another field's growth.
fn check_merge() {
    var m = repeated::Packed { .. };
    if repeated::Packed_decode(embed_file("mix_a.bin"), m) != PB_OK { fail_at("merge", "a"); }
    if repeated::Packed_decode(embed_file("mix_b.bin"), m) != PB_OK { fail_at("merge", "b"); }
    var out: u8[>..] = [];
    repeated::Packed_encode(m, out);
    if !bytes_eq(out, embed_file("mix_packed.bin")) { fail_at("merge", "two decode calls"); }
    repeated::Packed_clear(m);

    // Interleaved occurrences of two fields of one pool.
    var buf: u8[>..] = [];
    for i in 200 {
        pb_write_varint(buf, 8);                      // f_int32
        pb_write_varint(buf, i as! u64);
        pb_write_varint(buf, 16000);                  // far, unpacked
        pb_write_varint(buf, (1000 + i) as! u64);
    }
    if repeated::Packed_decode(buf, m) != PB_OK { fail_at("interleaved", "decode"); }
    let a = repeated::Packed_f_int32(m);
    let b = repeated::Packed_far(m);
    if a.len != 200 || b.len != 200 { fail_at("interleaved", "lengths"); }
    for i in 200 {
        if a[i] != i || b[i] != 1000 + i { fail_at("interleaved", "values"); break; }
    }
    repeated::Packed_clear(m);
}

fn expect_error(name: u8[:], buf: const u8[:], want: i32) {
    var m = repeated::Packed { .. };
    let err = repeated::Packed_decode(buf, m);
    if err != want { fail_at(name, str("error ", err, " want ", want)); }
    repeated::Packed_clear(m);
    if repeated::Packed_size_of(m) != 0 { fail_at(name, "partial message did not clear"); }
}

fn check_errors() {
    let over: u8[3] = [0x0a, 0x05, 0x01];              // length past the buffer
    expect_error("packed length overruns", over, PB_ERR_TRUNCATED);
    // A fixed32 cut by the end of its run, though the buffer goes on.
    let fixed: u8[10] = [0x3a, 0x03, 1, 2, 3, 0x78, 0x01, 0, 0, 0];
    expect_error("fixed32 cut by the packed run", fixed, PB_ERR_TRUNCATED);
    let fixed64: u8[12] = [0x42, 0x09, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0];
    expect_error("fixed64 cut by the packed run", fixed64, PB_ERR_TRUNCATED);
    // A varint running past the end of its run.
    let cut: u8[4] = [0x0a, 0x01, 0x80, 0x01];
    expect_error("varint cut by the packed run", cut, PB_ERR_TRUNCATED);
    let eleven: u8[13] = [0x0a, 0x0b, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01];
    expect_error("11-byte varint in a packed run", eleven, PB_ERR_MALFORMED);
    let unpacked: u8[2] = [0x08, 0x80];                // a value on its own, cut
    expect_error("unpacked value cut", unpacked, PB_ERR_TRUNCATED);
}

// Another wire type is an unknown field; an empty packed run is nothing.
fn check_unknown() {
    let wrong: u8[5] = [0x0d, 1, 2, 3, 4];             // f_int32 as fixed32
    var m = repeated::Packed { .. };
    if repeated::Packed_decode(wrong, m) != PB_OK { fail_at("wire type", "decode"); return; }
    if repeated::Packed_f_int32(m).len != 0 || m.pb_unknown.len != 5 { fail_at("wire type", "not unknown"); }
    repeated::Packed_clear(m);
    let none: u8[2] = [0x0a, 0x00];
    if repeated::Packed_decode(none, m) != PB_OK { fail_at("empty run", "decode"); return; }
    if repeated::Packed_f_int32(m).len != 0 || repeated::Packed_size_of(m) != 0 { fail_at("empty run", "kept"); }
    repeated::Packed_clear(m);
}

fn check_copy() {
    let want = embed_file("packed.bin");
    var src = repeated::Packed { .. };
    if repeated::Packed_decode(want, src) != PB_OK { fail_at("copy", "decode"); return; }
    var dst = repeated::Packed { .. };
    repeated::Packed_copy(dst, src);
    repeated::Packed_clear(src);
    var out: u8[>..] = [];
    repeated::Packed_encode(dst, out);
    if !bytes_eq(out, want) { fail_at("copy", "after clearing the source"); }
    repeated::Packed_clear(dst);
}

fn check_tree() {
    let want = embed_file("tree.bin");
    var m = repeated::Tree { .. };
    if repeated::Tree_decode(want, m) != PB_OK { fail_at("tree", "decode"); return; }
    var out: u8[>..] = [];
    repeated::Tree_encode(m, out);
    if !bytes_eq(out, want) { fail_at("tree", "re-encode"); }
    if repeated::Tree_size_of(m) != want.len { fail_at("tree", "size_of"); }
    var cp = repeated::Tree { .. };
    repeated::Tree_copy(cp, m);
    repeated::Tree_clear(m);
    var again: u8[>..] = [];
    repeated::Tree_encode(cp, again);
    if !bytes_eq(again, want) { fail_at("tree", "copy"); }
    repeated::Tree_clear(cp);
}

// Decoding trims and clearing frees: the pools do not grow.
fn check_reuse() {
    let want = embed_file("packed.bin");
    var m = repeated::Packed { .. };
    if repeated::Packed_decode(want, m) != PB_OK { fail_at("reuse", "decode"); }
    repeated::Packed_clear(m);
    let i32s = pb_i32s.len;
    let f64s = pb_f64s.len;
    for i in 5 {
        if repeated::Packed_decode(want, m) != PB_OK { fail_at("reuse", "decode"); }
        repeated::Packed_clear(m);
    }
    if pb_i32s.len != i32s || pb_f64s.len != f64s { fail_at("reuse", "the pools grew"); }
}

fn main() {
    let packed = embed_file("packed.bin");
    let unpacked = embed_file("unpacked.bin");
    check_packed("packed as packed", packed, packed);
    check_unpacked("unpacked as unpacked", unpacked, unpacked);
    check_packed("unpacked as packed", unpacked, packed);
    check_unpacked("packed as unpacked", packed, unpacked);
    check_values("values, packed", packed);
    check_values("values, unpacked", unpacked);
    var mix: u8[>..] = [];
    mix.append(embed_file("mix_a.bin"));
    mix.append(embed_file("mix_b.bin"));
    check_packed("a mix of both", mix, embed_file("mix_packed.bin"));
    if embed_file("empty.bin").len != 0 { fail_at("empty", "protoc wrote bytes"); }
    check_packed("empty", embed_file("empty.bin"), embed_file("empty.bin"));
    check_built();
    check_merge();
    check_errors();
    check_unknown();
    check_copy();
    check_tree();
    check_reuse();
    if failures != 0 { abort(str(failures, " failures")); }
    print("repeated round-trip: all passed");
}
