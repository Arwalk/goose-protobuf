// Round-trip test for tests/protos/oneofs.proto (gpb-gp4.3).
// Run: scripts/roundtrip.sh oneofs
import pb_wire;
import oneofs;

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

// built encodes to want (protoc's bytes) and sizes it, want decodes and
// re-encodes to itself, and clear leaves an empty message. Clears built.
fn check_built(name: u8[:], want: const u8[:], built: oneofs::Choice&) {
    var out: u8[>..] = [];
    oneofs::Choice_encode(built, out);
    if !bytes_eq(out, want) { fail_at(name, "encoding differs from protoc"); }
    if oneofs::Choice_size_of(built) != want.len { fail_at(name, "size_of"); }
    var back = oneofs::Choice { .. };
    let err = oneofs::Choice_decode(want, back);
    if err != PB_OK { fail_at(name, str("decode error ", err)); }
    var again: u8[>..] = [];
    oneofs::Choice_encode(back, again);
    if !bytes_eq(again, want) { fail_at(name, "re-encoding differs"); }
    oneofs::Choice_clear(back);
    if oneofs::Choice_size_of(back) != 0 { fail_at(name, "clear left data"); }
    oneofs::Choice_clear(built);
    if oneofs::Choice_size_of(built) != 0 { fail_at(name, "clear left data"); }
}

fn check_built_cases() {
    var m = oneofs::Choice { .. };
    m.before = 1; m.after = 2;
    check_built("none", embed_file("none.bin"), m);

    // A member set to its default is present: it is encoded.
    oneofs::Choice_set_p_int32(m, 0);
    check_built("zero", embed_file("zero.bin"), m);
    oneofs::Choice_set_p_bool(m, false);
    check_built("falsy", embed_file("falsy.bin"), m);

    m.before = 1; m.after = 2;
    oneofs::Choice_set_p_int32(m, -5);
    oneofs::Choice_set_maybe(m, 0);
    check_built("int32", embed_file("int32.bin"), m);
    oneofs::Choice_set_p_sint64(m, -3);
    check_built("sint64", embed_file("sint64.bin"), m);
    oneofs::Choice_set_p_uint64(m, 300);
    check_built("uint64", embed_file("uint64.bin"), m);
    oneofs::Choice_set_p_fixed32(m, 7);
    check_built("fixed32", embed_file("fixed32.bin"), m);
    oneofs::Choice_set_p_sfixed64(m, -8);
    check_built("sfixed64", embed_file("sfixed64.bin"), m);
    oneofs::Choice_set_p_float(m, 1.5);
    check_built("float", embed_file("float.bin"), m);
    oneofs::Choice_set_p_double(m, -2.5);
    check_built("double", embed_file("double.bin"), m);
    oneofs::Choice_set_p_bool(m, true);
    check_built("bool", embed_file("bool.bin"), m);
    oneofs::Choice_set_p_mode(m, oneofs::Mode_MODE_ON);
    check_built("mode", embed_file("mode.bin"), m);
    oneofs::Choice_set_p_string(m, "héllo");
    check_built("string", embed_file("string.bin"), m);
    oneofs::Choice_set_p_string(m, "");
    check_built("empty_string", embed_file("empty_string.bin"), m);
    let raw: u8[2] = [0xff, 0x00];
    oneofs::Choice_set_p_bytes(m, raw);
    check_built("bytes", embed_file("bytes.bin"), m);

    let s .= oneofs::Choice_mutable_p_sub(m);
    s.a = 1;
    oneofs::Sub_set_s(s, "x");
    oneofs::Sub_add_r(s, 1);
    oneofs::Sub_add_r(s, 2);
    check_built("sub", embed_file("sub.bin"), m);
    oneofs::Choice_mutable_p_sub(m);
    check_built("empty_sub", embed_file("empty_sub.bin"), m);
    oneofs::Choice_mutable_p_dep(m).seconds = 4;
    check_built("dep", embed_file("dep.bin"), m);

    let c .= oneofs::Choice_mutable_p_self(m);
    c.after = 3;
    let d .= oneofs::Choice_mutable_p_self(c);
    oneofs::Choice_set_p_string(d, "deep");
    oneofs::Choice_set_s_string(d, "t");
    check_built("self", embed_file("self.bin"), m);

    oneofs::Choice_set_type(m, 1);
    check_built("keyword", embed_file("keyword.bin"), m);
    oneofs::Choice_set_m(m, 2);
    check_built("m_member", embed_file("m_member.bin"), m);
    oneofs::Choice_set_v(m, 3);
    check_built("v_member", embed_file("v_member.bin"), m);

    // Two oneofs are independent.
    oneofs::Choice_set_p_int32(m, 9);
    oneofs::Choice_mutable_s_sub(m).a = 2;
    check_built("second", embed_file("second.bin"), m);
}

fn check_accessors() {
    var m = oneofs::Choice { .. };
    match m.pick { pb_none => {}, _ => { fail_at("accessors", "not none at first"); } }
    if oneofs::Choice_has_p_int32(m) { fail_at("accessors", "has_ of an empty oneof"); }
    if oneofs::Choice_p_int32(m) != 0 { fail_at("accessors", "default int32"); }
    if oneofs::Choice_p_float(m) != 0.0 { fail_at("accessors", "default float"); }
    if oneofs::Choice_p_bool(m) { fail_at("accessors", "default bool"); }
    if oneofs::Choice_p_string(m).len != 0 { fail_at("accessors", "default string"); }
    if oneofs::Choice_p_sub(m) != null { fail_at("accessors", "default message"); }

    // What a generated file's header says to match with.
    oneofs::Choice_set_p_int32(m, 7);
    let as_header_says = match m.pick { pb_none => -1, p_float => -2, p_int32 x => x.v, _ => -3 };
    if as_header_says != 7 { fail_at("accessors", "match as the header says"); }
    oneofs::Choice_clear_p_int32(m);

    // Setting a member replaces the other, and match sees it.
    oneofs::Choice_set_p_int32(m, 5);
    if !oneofs::Choice_has_p_int32(m) || oneofs::Choice_p_int32(m) != 5 { fail_at("accessors", "int32"); }
    let seen = match m.pick { p_int32 x => x.v, _ => -1 };
    if seen != 5 { fail_at("accessors", "match"); }
    oneofs::Choice_set_p_string(m, "abcd");
    if oneofs::Choice_has_p_int32(m) || oneofs::Choice_p_int32(m) != 0 { fail_at("accessors", "replaced int32"); }
    if !bytes_eq(oneofs::Choice_p_string(m), "abcd") { fail_at("accessors", "string"); }

    // A value from the field's own contents.
    oneofs::Choice_set_p_string(m, oneofs::Choice_p_string(m)[1..3]);
    if !bytes_eq(oneofs::Choice_p_string(m), "bc") { fail_at("accessors", "set_ from itself"); }

    // clear_ of another member does nothing; of the member, or the oneof, clears.
    oneofs::Choice_clear_p_int32(m);
    if !oneofs::Choice_has_p_string(m) { fail_at("accessors", "clear_ of another member"); }
    oneofs::Choice_clear_p_string(m);
    if oneofs::Choice_has_p_string(m) { fail_at("accessors", "clear_ of the member"); }
    oneofs::Choice_set_p_bytes(m, "z");
    oneofs::Choice_clear_pick(m);
    if oneofs::Choice_has_p_bytes(m) { fail_at("accessors", "clear_pick"); }

    // A message member: mutable_ keeps one that is there, and replaces another.
    let s .= oneofs::Choice_mutable_p_sub(m);
    s.a = 7;
    if !oneofs::Choice_has_p_sub(m) { fail_at("accessors", "has_ message"); }
    if oneofs::Choice_mutable_p_sub(m).a != 7 { fail_at("accessors", "mutable_ kept"); }
    let got = oneofs::Choice_p_sub(m);
    guard got else { fail_at("accessors", "message getter"); return; }
    if got.a != 7 { fail_at("accessors", "message getter value"); }
    oneofs::Choice_set_p_int32(m, 1);
    if oneofs::Choice_p_sub(m) != null { fail_at("accessors", "message replaced"); }
    oneofs::Choice_clear(m);
}

// Decodes the concatenation of cases into a new message.
fn decode_all(parts: const u8[:], m: oneofs::Choice&) {
    let err = oneofs::Choice_decode(parts, m);
    if err != PB_OK { fail_at("decode_all", str("decode error ", err)); }
}

fn check_last_wins() {
    // int32, then string, then int32: the last occurrence on the wire wins.
    var w: u8[>..] = [];
    w.append(embed_file("int32.bin"));
    w.append(embed_file("string.bin"));
    var m = oneofs::Choice { .. };
    decode_all(w, m);
    if oneofs::Choice_has_p_int32(m) { fail_at("last wins", "first member kept"); }
    if !bytes_eq(oneofs::Choice_p_string(m), "héllo") { fail_at("last wins", "string"); }
    oneofs::Choice_clear(m);

    var w2: u8[>..] = [];
    w2.append(embed_file("string.bin"));
    w2.append(embed_file("zero.bin"));
    decode_all(w2, m);
    if oneofs::Choice_has_p_string(m) { fail_at("last wins", "string kept"); }
    if !oneofs::Choice_has_p_int32(m) { fail_at("last wins", "default member is present"); }
    var out: u8[>..] = [];
    oneofs::Choice_encode(m, out);
    if !bytes_eq(out, embed_file("zero.bin")) { fail_at("last wins", "encoding"); }
    oneofs::Choice_clear(m);

    // Two decodes merge the same way as one of the concatenation.
    decode_all(embed_file("string.bin"), m);
    decode_all(embed_file("bool.bin"), m);
    if oneofs::Choice_has_p_string(m) || !oneofs::Choice_p_bool(m) { fail_at("last wins", "two decodes"); }
    oneofs::Choice_clear(m);
}

fn check_message_merge() {
    // The same message member twice merges.
    var w: u8[>..] = [];
    w.append(embed_file("sub_a.bin"));
    w.append(embed_file("sub_b.bin"));
    var m = oneofs::Choice { .. };
    decode_all(w, m);
    let s = oneofs::Choice_p_sub(m);
    guard s else { fail_at("merge", "no message"); return; }
    if s.a != 1 { fail_at("merge", "a lost"); }
    if !bytes_eq(oneofs::Sub_s(s), "x") { fail_at("merge", "s"); }
    if oneofs::Sub_r(s).len != 2 { fail_at("merge", "r not appended"); }
    oneofs::Choice_clear(m);

    // Another member in between ends the first message: it does not merge.
    var w2: u8[>..] = [];
    w2.append(embed_file("sub_a.bin"));
    w2.append(embed_file("zero.bin"));
    w2.append(embed_file("sub_b.bin"));
    decode_all(w2, m);
    let t = oneofs::Choice_p_sub(m);
    guard t else { fail_at("merge", "no message after the other member"); return; }
    if t.a != 0 || oneofs::Sub_r(t).len != 1 { fail_at("merge", "merged across another member"); }
    oneofs::Choice_clear(m);
}

fn check_copy() {
    var a = oneofs::Choice { .. };
    var b = oneofs::Choice { .. };
    // Replaces what dst held; shares nothing with src.
    oneofs::Choice_set_p_string(b, "old");
    decode_all(embed_file("self.bin"), a);
    oneofs::Choice_copy(b, a);
    var ea: u8[>..] = [];
    oneofs::Choice_encode(b, ea);
    if !bytes_eq(ea, embed_file("self.bin")) { fail_at("copy", "message member"); }
    oneofs::Choice_clear(a);
    var eb: u8[>..] = [];
    oneofs::Choice_encode(b, eb);
    if !bytes_eq(eb, embed_file("self.bin")) { fail_at("copy", "shares with its source"); }
    oneofs::Choice_clear(b);

    oneofs::Choice_set_p_string(a, "str");
    oneofs::Choice_copy(b, a);
    oneofs::Choice_set_p_string(a, "changed");
    if !bytes_eq(oneofs::Choice_p_string(b), "str") { fail_at("copy", "string"); }
    oneofs::Choice_set_p_double(a, 2.5);
    oneofs::Choice_copy(b, a);
    if oneofs::Choice_p_double(b) != 2.5 || oneofs::Choice_has_p_string(b) { fail_at("copy", "scalar"); }
    oneofs::Choice_clear(a);
    oneofs::Choice_copy(b, a);
    if oneofs::Choice_has_p_double(b) { fail_at("copy", "none"); }
}

fn check_errors() {
    // p_string (field 11) with invalid UTF-8: not stored, and the error is it.
    let bad: u8[3] = [0x5a, 1, 0xff];
    var m = oneofs::Choice { .. };
    oneofs::Choice_set_p_int32(m, 1);
    if oneofs::Choice_decode(bad, m) != PB_ERR_UTF8 { fail_at("errors", "invalid UTF-8"); }
    if !oneofs::Choice_has_p_int32(m) { fail_at("errors", "a failed read replaced the member"); }
    oneofs::Choice_clear(m);

    // The same in a bytes member (field 12) is fine.
    let ok: u8[3] = [0x62, 1, 0xff];
    if oneofs::Choice_decode(ok, m) != PB_OK { fail_at("errors", "bytes are not UTF-8"); }
    oneofs::Choice_clear(m);

    // Truncated: inside an int32, and inside a message member.
    let t1: u8[1] = [0x10];
    if oneofs::Choice_decode(t1, m) != PB_ERR_TRUNCATED { fail_at("errors", "truncated varint"); }
    if oneofs::Choice_has_p_int32(m) { fail_at("errors", "truncated value stored"); }
    oneofs::Choice_clear(m);
    let t2: u8[3] = [0x6a, 2, 0x08];
    if oneofs::Choice_decode(t2, m) != PB_ERR_TRUNCATED { fail_at("errors", "truncated message"); }
    oneofs::Choice_clear(m);
    if oneofs::Choice_size_of(m) != 0 { fail_at("errors", "clear after failure"); }

    // A member with another wire type is an unknown field, and does not set it.
    let wrong: u8[5] = [0x15, 1, 2, 3, 4];
    if oneofs::Choice_decode(wrong, m) != PB_OK { fail_at("errors", "wrong wire type"); }
    if oneofs::Choice_has_p_int32(m) { fail_at("errors", "wrong wire type set the member"); }
    if oneofs::Choice_size_of(m) != 5 { fail_at("errors", "wrong wire type not kept"); }
    oneofs::Choice_clear(m);

    // Depth: p_self nested beyond the limit.
    // Each level's length has to cover the rest; build from the inside out.
    var nest: u8[>..] = [];
    for i in 150 {
        var next: u8[>..] = [];
        pb_write_varint(next, 122);
        pb_write_varint(next, nest.len as! u64);
        next.append(nest);
        nest = copy(next);
    }
    if oneofs::Choice_decode(nest, m) != PB_ERR_DEPTH { fail_at("errors", "depth"); }
    oneofs::Choice_clear(m);
}

// Replacing members and clearing frees what they held: the pools stop growing.
fn check_no_leak() {
    var m = oneofs::Choice { .. };
    var bytes_len: i64 = 0;
    var pool_len: i64 = 0;
    for i in 200 {
        oneofs::Choice_set_p_string(m, "some string");
        oneofs::Choice_set_p_bytes(m, "other");
        oneofs::Sub_set_s(oneofs::Choice_mutable_p_sub(m), "in a sub");
        oneofs::Choice_set_p_int32(m, 1);
        decode_all(embed_file("self.bin"), m);
        oneofs::Choice_clear(m);
        if i == 0 { bytes_len = pb_bytes.len; pool_len = oneofs::Choice_pool.len; }
    }
    if pb_bytes.len != bytes_len { fail_at("leak", str("pb_bytes grew to ", pb_bytes.len, " from ", bytes_len)); }
    if oneofs::Choice_pool.len != pool_len { fail_at("leak", "Choice_pool grew"); }
}

fn main() {
    check_built_cases();
    check_accessors();
    check_last_wins();
    check_message_merge();
    check_copy();
    check_errors();
    check_no_leak();
    if failures > 0 { abort(str(failures, " failures")); }
    print("ok");
}
