// Round-trip test for tests/protos/unknown.proto (gpb-41j.6).
// Run: scripts/roundtrip.sh unknown
import pb_wire;
import unknown;

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

// Decodes buf as Known and checks the re-encoding is want, and size_of.
fn check(name: u8[:], buf: const u8[:], want: const u8[:]) {
    var k = unknown::Known { .. };
    let err = unknown::Known_decode(buf, k);
    if err != PB_OK { fail_at(name, str("decode error ", err)); return; }
    var out: u8[>..] = [];
    unknown::Known_encode(k, out);
    if !bytes_eq(out, want) { fail_at(name, str("re-encode [", hex(out), "] want [", hex(want), "]")); }
    if unknown::Known_size_of(k) != want.len {
        fail_at(name, str("size_of ", unknown::Known_size_of(k), " want ", want.len));
    }
    unknown::Known_clear(k);
    if k.pb_unknown.len != 0 || unknown::Known_size_of(k) != 0 { fail_at(name, "clear kept unknown fields"); }
}

fn main() {
    // Unknown fields of every protobuf-3 wire type, interleaved with known
    // ones: the known fields come first on re-encode, then the unknown
    // ones in their original order.
    let wide = embed_file("wide.bin");
    var known_part = unknown::Known { .. };
    known_part.a = 7;
    known_part.d = 1.5;
    var want: u8[>..] = [];
    unknown::Known_encode(known_part, want);
    want.append(embed_file("wide_rest.bin"));
    check("wide", wide, want);

    // The fields decoded through the unknown ones.
    var k = unknown::Known { .. };
    if unknown::Known_decode(wide, k) != PB_OK || k.a != 7 || k.d != 1.5 {
        fail_at("wide fields", str("a ", k.a, " d ", k.d));
    }
    // Merging appends unknown fields again, as protobuf does.
    let rest = embed_file("wide_rest.bin");
    unknown::Known_decode(wide, k);
    if k.pb_unknown.len != 2 * rest.len { fail_at("merge", str("unknown len ", k.pb_unknown.len)); }
    unknown::Known_clear(k);

    // Groups (not expressible in proto3 text): a = 1, a group 3 holding a
    // varint and a nested group 5, then d. The group is kept whole.
    let grouped: u8[19] = [0x08, 0x01,
                           0x1b, 0x08, 0x05, 0x2b, 0x2c, 0x1c,
                           0x21, 0, 0, 0, 0, 0, 0, 0xf0, 0x3f,
                           0x38, 0x09];
    var gwant: u8[>..] = [0x08, 0x01, 0x21, 0, 0, 0, 0, 0, 0, 0xf0, 0x3f,
                          0x1b, 0x08, 0x05, 0x2b, 0x2c, 0x1c, 0x38, 0x09];
    check("groups", grouped, gwant);

    // A known field number with another wire type is an unknown field.
    let mismatch: u8[5] = [0x0d, 1, 2, 3, 4];   // field 1 as fixed32
    check("wire-type mismatch", mismatch, mismatch);

    // Errors: an unmatched end-group, and a truncated unknown field.
    var bad = unknown::Known { .. };
    let egroup: u8[1] = [0x0c];
    if unknown::Known_decode(egroup, bad) != PB_ERR_MALFORMED { fail_at("end-group", "decoded"); }
    let cut: u8[3] = [0x08, 0x01, 0x12];   // field 2's tag, no length
    if unknown::Known_decode(cut, bad) != PB_ERR_TRUNCATED { fail_at("truncated", "decoded"); }
    if bad.a != 1 || bad.pb_unknown.len != 0 { fail_at("truncated", "partial message is wrong"); }
    unknown::Known_clear(bad);

    // A message held in its generated pool, reached through a run of
    // links (decision 0001): decode into the slot, re-encode, free it.
    var links = pb_resize(unknown::Known_links, pb_Span { at: 0, len: 0 }, 1);
    let slot .= unknown::Known_pool.alloc_ref(unknown::Known { .. });
    pb_run(unknown::Known_links, links)[0].m .= slot;
    let l = pb_run(unknown::Known_links, links)[0].m;
    assert(l);
    if unknown::Known_decode(wide, l) != PB_OK { fail_at("pool slot", "decode"); }
    var pout: u8[>..] = [];
    unknown::Known_encode(l, pout);
    if !bytes_eq(pout, want) { fail_at("pool slot", str("re-encode [", hex(pout), "]")); }
    unknown::Known_clear(l);
    unknown::Known_pool.free(unknown::Known_pool.index_of(l));
    links = pb_resize(unknown::Known_links, links, 0);

    if failures != 0 { abort(str(failures, " failures")); }
    print("unknown round-trip: all passed");
}
