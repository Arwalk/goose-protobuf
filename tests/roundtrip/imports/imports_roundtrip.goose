// Round-trip test for tests/protos/imports.proto (gpb-8qn.9).
// Run: scripts/roundtrip.sh imports
import pb_wire;
import imports;

// imports.goose imports the other generated files itself.

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

fn check_full() {
    let want = embed_file("full.bin");
    var m = imports::Holder { .. };
    if imports::Holder_decode(want, m) != PB_OK { fail_at("full", "decode"); return; }
    if m.pb_unknown.len != 0 { fail_at("full", "a field stayed unknown"); }
    var out: u8[>..] = [];
    imports::Holder_encode(m, out);
    if !bytes_eq(out, want) { fail_at("full", "re-encode differs from protoc"); }
    if imports::Holder_size_of(m) != want.len { fail_at("full", "size_of"); }

    let d = imports::Holder_duration(m);
    guard d else { fail_at("full", "no duration"); return; }
    if d.seconds != 5 || d.nanos != 6 { fail_at("full", "duration"); }
    let s = imports::Holder_same(m);
    guard s else { fail_at("full", "no same"); return; }
    if s.a != 8 { fail_at("full", "same"); }
    let n = imports::Holder_nopkg(m);
    guard n else { fail_at("full", "no nopkg"); return; }
    if n.b != 9 { fail_at("full", "nopkg"); }
    let i = imports::Holder_inner(m);
    guard i else { fail_at("full", "no inner"); return; }
    if i.c != 10 { fail_at("full", "inner"); }

    imports::Holder_clear(m);
    if imports::Holder_size_of(m) != 0 || imports::Holder_has_duration(m) { fail_at("full", "clear"); }
}

fn check_built() {
    var m = imports::Holder { .. };
    imports::Holder_mutable_dotted(m).n = 1;
    my_api::Hyphenated_set_s(imports::Holder_mutable_hyphenated(m), "x");
    let d .= imports::Holder_mutable_duration(m);
    d.seconds = 5;
    d.nanos = 6;
    let n .= imports::Holder_mutable_nested(m);
    imports::Holder_Nested_mutable_later(n).seconds = 7;
    imports::Holder_mutable_same(m).a = 8;
    imports::Holder_mutable_nopkg(m).b = 9;
    imports::Holder_mutable_inner(m).c = 10;
    var out: u8[>..] = [];
    imports::Holder_encode(m, out);
    if !bytes_eq(out, embed_file("full.bin")) { fail_at("built", "encode differs from protoc"); }
    imports::Holder_clear(m);
}

fn check_merge() {
    var m = imports::Holder { .. };
    if imports::Holder_decode(embed_file("split_a.bin"), m) != PB_OK { fail_at("merge", "decode a"); }
    if imports::Holder_decode(embed_file("split_b.bin"), m) != PB_OK { fail_at("merge", "decode b"); }
    var out: u8[>..] = [];
    imports::Holder_encode(m, out);
    if !bytes_eq(out, embed_file("split_merged.bin")) { fail_at("merge", "not merged"); }
    imports::Holder_clear(m);
}

// A failure inside an imported message reaches the top.
fn check_errors() {
    let bad: u8[4] = [0x1a, 0x02, 0x08, 0x80];     // duration.seconds cut short
    var m = imports::Holder { .. };
    if imports::Holder_decode(bad, m) != PB_ERR_TRUNCATED { fail_at("errors", "no error"); }
    imports::Holder_clear(m);
}

fn check_reuse() {
    let want = embed_file("full.bin");
    var m = imports::Holder { .. };
    if imports::Holder_decode(want, m) != PB_OK { fail_at("reuse", "decode"); }
    imports::Holder_clear(m);
    let slots = google_protobuf::Duration_pool.len;
    for i in 5 {
        if imports::Holder_decode(want, m) != PB_OK { fail_at("reuse", "decode"); }
        imports::Holder_clear(m);
    }
    if google_protobuf::Duration_pool.len != slots { fail_at("reuse", "the pool of an imported type grew"); }
}

fn main() {
    check_full();
    check_built();
    check_merge();
    check_errors();
    check_reuse();
    if failures != 0 { abort(str(failures, " failures")); }
    print("imports round-trip: all passed");
}
