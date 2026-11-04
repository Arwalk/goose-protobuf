// Round-trip test for tests/protos/submessages.proto (gpb-8qn.2).
// Run: scripts/roundtrip.sh submessages
import pb_wire;
import submessages;

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

fn check_encodes(name: u8[:], m: submessages::Outer&, want: const u8[:]) {
    var out: u8[>..] = [];
    submessages::Outer_encode(m, out);
    if !bytes_eq(out, want) { fail_at(name, str("encode [", hex(out), "] want [", hex(want), "]")); }
    if submessages::Outer_size_of(m) != want.len { fail_at(name, str("size_of ", submessages::Outer_size_of(m))); }
}

// want decodes, re-encodes to want and clears; decoding it again merges
// into the same bytes, and frees nothing it should not.
fn check_roundtrip(name: u8[:], want: const u8[:]) {
    var back = submessages::Outer { .. };
    let err = submessages::Outer_decode(want, back);
    if err != PB_OK { fail_at(name, str("decode error ", err)); return; }
    check_encodes(name, back, want);
    submessages::Outer_clear(back);
    if submessages::Outer_size_of(back) != 0 || submessages::Outer_has_inner(back) {
        fail_at(name, "clear left fields set");
    }
}

fn check_built() {
    var m = submessages::Outer { .. };
    if submessages::Outer_has_inner(m) || submessages::Outer_inner(m) { fail_at("built", "set when empty"); }
    let i .= submessages::Outer_mutable_inner(m);
    i.a = 1;
    submessages::Inner_set_s(i, "x");
    let l .= submessages::Inner_mutable_leaf(i);
    l.x = 2;
    l.y = 3;
    let same .= submessages::Outer_mutable_inner(m);
    if !(same .== i) { fail_at("built", "mutable_ made a second message"); }
    let n .= submessages::Outer_mutable_nested(m);
    n.n = 4;
    submessages::Outer_Nested_set_label(n, "lbl");
    submessages::Outer_mutable_opt_leaf(m).x = 5;
    m.after = 6;
    submessages::Outer_mutable_far_leaf(m).y = 7;
    submessages::Outer_mutable_sub_n(m).r = 8;
    check_encodes("built", m, embed_file("full.bin"));
    let got = submessages::Outer_inner(m);
    guard got else { fail_at("built", "inner is null"); return; }
    if got.a != 1 { fail_at("built", "inner.a"); }

    submessages::Outer_clear_inner(m);
    if submessages::Outer_has_inner(m) { fail_at("built", "clear_inner left it set"); }
    submessages::Outer_clear_inner(m);   // clearing twice is fine
    submessages::Outer_clear(m);
    if submessages::Outer_size_of(m) != 0 { fail_at("built", "clear left bytes"); }
}

// An empty sub-message is present, and encoded.
fn check_empty() {
    let want = embed_file("empty.bin");
    var m = submessages::Outer { .. };
    if submessages::Outer_decode(want, m) != PB_OK { fail_at("empty", "decode"); return; }
    if !submessages::Outer_has_nested(m) || !submessages::Outer_has_opt_leaf(m) { fail_at("empty", "not present"); }
    if submessages::Outer_has_sub_n(m) { fail_at("empty", "sub_n present"); }
    check_encodes("empty", m, want);
    submessages::Outer_clear(m);
}

// Decoding merges: a later occurrence of a sub-message merges into the
// message already there, in one buffer or across two decode calls.
fn check_merge() {
    let a = embed_file("split_a.bin");
    let b = embed_file("split_b.bin");
    let merged = embed_file("split_merged.bin");

    var whole: u8[>..] = [];
    whole.append(a);
    whole.append(b);
    var one = submessages::Outer { .. };
    if submessages::Outer_decode(whole, one) != PB_OK { fail_at("merge", "decode one buffer"); }
    check_encodes("merge one buffer", one, merged);
    submessages::Outer_clear(one);

    var two = submessages::Outer { .. };
    if submessages::Outer_decode(a, two) != PB_OK { fail_at("merge", "decode a"); }
    let held .= submessages::Outer_mutable_inner(two);
    if submessages::Outer_decode(b, two) != PB_OK { fail_at("merge", "decode b"); }
    check_encodes("merge two calls", two, merged);
    if !(held .== submessages::Outer_mutable_inner(two)) { fail_at("merge", "merge moved the sub-message"); }
    submessages::Outer_clear(two);
}

fn expect_error(name: u8[:], buf: const u8[:], want: i32) {
    var m = submessages::Outer { .. };
    let err = submessages::Outer_decode(buf, m);
    if err != want { fail_at(name, str("error ", err, " want ", want)); }
    submessages::Outer_clear(m);
    if submessages::Outer_size_of(m) != 0 { fail_at(name, "partial message did not clear"); }
}

fn check_errors() {
    // inner: length 3, then only one byte.
    let truncated: u8[3] = [0x0a, 0x03, 0x08];
    expect_error("sub-message overruns the buffer", truncated, PB_ERR_TRUNCATED);
    // inner: length 2 holding a tag whose varint needs 3 bytes; the window
    // ends the value even though the buffer goes on.
    let window: u8[5] = [0x0a, 0x02, 0x08, 0x80, 0x01];
    expect_error("value overruns the sub-message window", window, PB_ERR_TRUNCATED);
    // inner.leaf: length 5 inside inner of length 2.
    let nested: u8[4] = [0x0a, 0x02, 0x22, 0x05];
    expect_error("sub-message overruns its parent", nested, PB_ERR_TRUNCATED);
    // inner.s: invalid UTF-8.
    let utf8: u8[6] = [0x0a, 0x04, 0x12, 0x02, 0xc0, 0x80];
    expect_error("bad string in a sub-message", utf8, PB_ERR_UTF8);
    // Field number 0 inside inner.
    let tag0: u8[4] = [0x0a, 0x02, 0x00, 0x00];
    expect_error("bad tag in a sub-message", tag0, PB_ERR_MALFORMED);
    // inner with an end-group tag of no start.
    let egroup: u8[3] = [0x0a, 0x01, 0x0c];
    expect_error("end group in a sub-message", egroup, PB_ERR_MALFORMED);
}

// Fields after a sub-message read their own window; unknown fields stay
// with the message they arrived in.
fn check_unknown() {
    // inner { field 15: varint 1 }, after: 2
    let buf: u8[6] = [0x0a, 0x02, 0x78, 0x01, 0x20, 0x02];
    var m = submessages::Outer { .. };
    if submessages::Outer_decode(buf, m) != PB_OK { fail_at("unknown", "decode"); return; }
    if m.after != 2 { fail_at("unknown", "after"); }
    if m.pb_unknown.len != 0 { fail_at("unknown", "the parent kept it"); }
    check_encodes("unknown", m, buf);
    submessages::Outer_clear(m);

    // inner as a varint: another wire type is an unknown field.
    let as_varint: u8[2] = [0x08, 0x01];
    var v = submessages::Outer { .. };
    if submessages::Outer_decode(as_varint, v) != PB_OK { fail_at("wire type", "decode"); return; }
    if submessages::Outer_has_inner(v) || v.pb_unknown.len != 2 { fail_at("wire type", "not unknown"); }
    check_encodes("wire type", v, as_varint);
    submessages::Outer_clear(v);
}

// Clearing returns every slot: rebuilding reuses them.
fn check_reuse() {
    let full = embed_file("full.bin");
    var m = submessages::Outer { .. };
    if submessages::Outer_decode(full, m) != PB_OK { fail_at("reuse", "decode"); }
    submessages::Outer_clear(m);
    let inners = submessages::Inner_pool.len;
    let leaves = submessages::Leaf_pool.len;
    let bytes = pb_bytes.len;
    for i in 5 {
        if submessages::Outer_decode(full, m) != PB_OK { fail_at("reuse", "decode"); }
        submessages::Outer_clear(m);
    }
    if submessages::Inner_pool.len != inners || submessages::Leaf_pool.len != leaves || pb_bytes.len != bytes {
        fail_at("reuse", "the pools grew");
    }
}

fn main() {
    check_built();
    check_roundtrip("full", embed_file("full.bin"));
    check_roundtrip("empty", embed_file("empty.bin"));
    check_roundtrip("split_merged", embed_file("split_merged.bin"));
    check_empty();
    check_merge();
    check_errors();
    check_unknown();
    check_reuse();
    if failures != 0 { abort(str(failures, " failures")); }
    print("submessages round-trip: all passed");
}
