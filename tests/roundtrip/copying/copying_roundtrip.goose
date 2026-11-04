// Round-trip test for tests/protos/copying.proto (gpb-8qn.7).
// Run: scripts/roundtrip.sh copying
import pb_wire;
import copying;

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

fn check_encodes(name: u8[:], m: copying::Msg&, want: const u8[:]) {
    var out: u8[>..] = [];
    copying::Msg_encode(m, out);
    if !bytes_eq(out, want) { fail_at(name, "encoding differs"); }
    if copying::Msg_size_of(m) != want.len { fail_at(name, "size_of"); }
}

// The copy outlives the source, and encodes the same.
fn check_outlives() {
    let want = embed_file("full.bin");
    var src = copying::Msg { .. };
    if copying::Msg_decode(want, src) != PB_OK { fail_at("outlives", "decode"); return; }
    var dst = copying::Msg { .. };
    copying::Msg_copy(dst, src);
    check_encodes("copy", dst, want);
    copying::Msg_clear(src);
    check_encodes("copy after clearing the source", dst, want);
    // Slots the source freed get reused: the copy must not be holding them.
    if copying::Msg_decode(want, src) != PB_OK { fail_at("outlives", "decode again"); return; }
    copying::Msg_set_s(src, "overwritten");
    copying::Msg_set_s(copying::Msg_mutable_next(src), "overwritten too");
    copying::Leaf_set_name(copying::Msg_mutable_leaf(src), "x");
    check_encodes("copy after reusing the slots", dst, want);
    copying::Msg_clear(dst);
    copying::Msg_clear(src);
}

// The source is untouched by changing or clearing the copy.
fn check_independent() {
    let want = embed_file("full.bin");
    var src = copying::Msg { .. };
    if copying::Msg_decode(want, src) != PB_OK { fail_at("independent", "decode"); return; }
    var dst = copying::Msg { .. };
    copying::Msg_copy(dst, src);
    copying::Msg_set_b(dst, "changed");
    copying::Msg_set_s(copying::Msg_mutable_next(dst), "changed");
    copying::Msg_clear_leaf(dst);
    copying::Msg_mutable_timeout(dst).seconds = 1;
    check_encodes("source after changing the copy", src, want);
    copying::Msg_clear(dst);
    check_encodes("source after clearing the copy", src, want);
    copying::Msg_clear(src);
}

// A copy replaces what dst held; it does not merge, and frees it.
fn check_replaces() {
    var dst = copying::Msg { .. };
    dst.n = 9;
    copying::Msg_set_o(dst, 9);
    copying::Msg_set_s(dst, "old");
    copying::Msg_mutable_leaf(dst);
    copying::Msg_mutable_next(dst).n = 9;
    var src = copying::Msg { .. };
    src.d = 1.0;
    copying::Msg_copy(dst, src);
    if dst.n != 0 || copying::Msg_has_o(dst) || copying::Msg_s(dst).len != 0 { fail_at("replaces", "kept a field"); }
    if copying::Msg_has_leaf(dst) || copying::Msg_has_next(dst) { fail_at("replaces", "kept a sub-message"); }
    if dst.d != 1.0 { fail_at("replaces", "d"); }
    copying::Msg_clear(dst);
}

// Presence travels: a present field holding the default stays present.
fn check_presence() {
    let want = embed_file("flags.bin");
    var src = copying::Flags { .. };
    if copying::Flags_decode(want, src) != PB_OK { fail_at("presence", "decode"); return; }
    var dst = copying::Flags { .. };
    copying::Flags_copy(dst, src);
    if !copying::Flags_has_a(dst) || copying::Flags_has_b(dst) { fail_at("presence", "has-bits"); }
    var out: u8[>..] = [];
    copying::Flags_encode(dst, out);
    if !bytes_eq(out, want) { fail_at("presence", "encoding differs"); }
}

fn check_unknown() {
    let buf: u8[2] = [0x78, 0x01];   // field 15, unknown
    var src = copying::Msg { .. };
    if copying::Msg_decode(buf, src) != PB_OK { fail_at("unknown", "decode"); return; }
    var dst = copying::Msg { .. };
    copying::Msg_copy(dst, src);
    copying::Msg_clear(src);
    check_encodes("unknown", dst, buf);
    copying::Msg_clear(dst);
}

// Copying onto itself keeps it.
fn check_self() {
    let want = embed_file("full.bin");
    var m = copying::Msg { .. };
    if copying::Msg_decode(want, m) != PB_OK { fail_at("self", "decode"); return; }
    copying::Msg_copy(m, m);
    check_encodes("self", m, want);
    copying::Msg_clear(m);
}

// Copying and clearing returns every slot.
fn check_reuse() {
    let want = embed_file("full.bin");
    var src = copying::Msg { .. };
    if copying::Msg_decode(want, src) != PB_OK { fail_at("reuse", "decode"); return; }
    var dst = copying::Msg { .. };
    copying::Msg_copy(dst, src);
    copying::Msg_clear(dst);
    let msgs = copying::Msg_pool.len;
    let leaves = copying::Leaf_pool.len;
    let durations = google_protobuf::Duration_pool.len;
    let bytes = pb_bytes.len;
    for i in 5 {
        copying::Msg_copy(dst, src);
        copying::Msg_clear(dst);
    }
    if copying::Msg_pool.len != msgs || copying::Leaf_pool.len != leaves
        || google_protobuf::Duration_pool.len != durations || pb_bytes.len != bytes {
        fail_at("reuse", "the pools grew");
    }
    copying::Msg_clear(src);
}

fn main() {
    check_outlives();
    check_independent();
    check_replaces();
    check_presence();
    check_unknown();
    check_self();
    check_reuse();
    if failures != 0 { abort(str(failures, " failures")); }
    print("copying round-trip: all passed");
}
