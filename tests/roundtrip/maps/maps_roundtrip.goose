// Round-trip test for tests/protos/maps.proto (gpb-gp4.4, gpb-gp4.8, gpb-gp4.9).
// Run: scripts/roundtrip.sh maps
//
// Encoding runs in insertion order. protoc's order for several entries is not
// insertion order, so only single-entry cases compare bytes with it.
import pb_wire;
import maps;

var failures = 0;

fn fail_at(what: u8[:], detail: u8[:]) {
    failures += 1;
    print("FAIL ", what, ": ", detail);
}

// built encodes to want (protoc's bytes) and sizes it, want decodes and
// re-encodes to itself, and clear leaves an empty message. Clears built.
fn check_built(name: u8[:], want: const u8[:], built: maps::Maps&) {
    var out: u8[>..] = [];
    maps::Maps_encode(built, out);
    if out != want { fail_at(name, "encoding differs from protoc"); }
    if maps::Maps_size_of(built) != want.len { fail_at(name, "size_of"); }
    var back = maps::Maps { .. };
    let err = maps::Maps_decode(want, back);
    if err != PB_OK { fail_at(name, str("decode error ", err)); }
    var again: u8[>..] = [];
    maps::Maps_encode(back, again);
    if again != want { fail_at(name, "re-encoding differs"); }
    maps::Maps_clear(back);
    if maps::Maps_size_of(back) != 0 { fail_at(name, "clear left data"); }
    maps::Maps_clear(built);
    if maps::Maps_size_of(built) != 0 { fail_at(name, "clear left data"); }
}

fn check_built_cases() {
    var m = maps::Maps { .. };
    m.after = 1;
    check_built("none", embed_file("none.bin"), m);
    maps::Maps_ss_put(m, "a", "b");
    check_built("ss", embed_file("ss.bin"), m);
    // Key and value are encoded even when they are the defaults.
    maps::Maps_ss_put(m, "", "");
    check_built("ss_defaults", embed_file("ss_defaults.bin"), m);
    let ff: u8[1] = [0xff];
    maps::Maps_sb_put(m, "a", ff);
    check_built("sb", embed_file("sb.bin"), m);
    maps::Maps_si_put(m, "n", -1);
    check_built("si", embed_file("si.bin"), m);
    maps::Maps_is_put(m, -2, "x");
    check_built("is", embed_file("is.bin"), m);
    maps::Maps_ll_put(m, -3, -4);
    check_built("ll", embed_file("ll.bin"), m);
    maps::Maps_uu_put(m, 5, 6);
    check_built("uu", embed_file("uu.bin"), m);
    maps::Maps_vv_put(m, 300, 301);
    check_built("vv", embed_file("vv.bin"), m);
    maps::Maps_zz_put(m, -7, -8);
    check_built("zz", embed_file("zz.bin"), m);
    maps::Maps_yy_put(m, -9, -10);
    check_built("yy", embed_file("yy.bin"), m);
    maps::Maps_ff_put(m, 11, 12);
    check_built("ff", embed_file("ff.bin"), m);
    maps::Maps_gg_put(m, 13, 14);
    check_built("gg", embed_file("gg.bin"), m);
    maps::Maps_hh_put(m, -15, -16);
    check_built("hh", embed_file("hh.bin"), m);
    maps::Maps_jj_put(m, -17, -18);
    check_built("jj", embed_file("jj.bin"), m);
    maps::Maps_bb_put(m, true, true);
    check_built("bb", embed_file("bb.bin"), m);
    maps::Maps_bb_put(m, false, false);
    check_built("bb_false", embed_file("bb_false.bin"), m);
    maps::Maps_sf_put(m, "f", 1.5);
    check_built("sf", embed_file("sf.bin"), m);
    maps::Maps_sd_put(m, "d", -2.5);
    check_built("sd", embed_file("sd.bin"), m);
    maps::Maps_se_put(m, "e", maps::Mode_MODE_ON);
    check_built("se", embed_file("se.bin"), m);
    let s .= maps::Maps_sm_put(m, "m");
    s.a = 1;
    maps::Sub_set_s(s, "x");
    maps::Sub_add_r(s, 1);
    maps::Sub_add_r(s, 2);
    check_built("sm", embed_file("sm.bin"), m);
    maps::Maps_sm_put(m, "m");
    check_built("sm_empty", embed_file("sm_empty.bin"), m);
    maps::Maps_dur_put(m, 1).seconds = 4;
    check_built("dur", embed_file("dur.bin"), m);
    let k .= maps::Maps_self_put(m, "k");
    k.after = 2;
    maps::Maps_si_put(maps::Maps_self_put(k, "in"), "n", 1);
    check_built("nested", embed_file("nested.bin"), m);
}

fn check_accessors() {
    var m = maps::Maps { .. };
    if maps::Maps_si_len(m) != 0 { fail_at("accessors", "an empty map"); }
    let v0, found0 = maps::Maps_si_get(m, "a");
    if found0 || v0 != 0 { fail_at("accessors", "get of a missing key"); }
    if maps::Maps_si_remove(m, "a") { fail_at("accessors", "remove of a missing key"); }

    maps::Maps_si_put(m, "a", 1);
    maps::Maps_si_put(m, "b", 2);
    maps::Maps_si_put(m, "a", 3);
    if maps::Maps_si_len(m) != 2 { fail_at("accessors", "put of a key there adds"); }
    let v1, found1 = maps::Maps_si_get(m, "a");
    if !found1 || v1 != 3 { fail_at("accessors", "put replaces"); }
    // Insertion order, by index too.
    if maps::Maps_si_key_at(m, 1) != "b" { fail_at("accessors", "key_at order"); }
    if maps::Maps_si_value_at(m, 1) != 2 { fail_at("accessors", "value_at"); }

    if !maps::Maps_si_remove(m, "a") { fail_at("accessors", "remove"); }
    let v2, found2 = maps::Maps_si_get(m, "a");
    if found2 { fail_at("accessors", "get after remove"); }
    let v3, found3 = maps::Maps_si_get(m, "b");
    if !found3 || v3 != 2 { fail_at("accessors", "remove took another"); }
    maps::Maps_clear_si(m);
    if maps::Maps_si_len(m) != 0 { fail_at("accessors", "clear_"); }

    // A key and value from the pool, even from this very entry.
    maps::Maps_ss_put(m, "key", "value");
    let val, f4 = maps::Maps_ss_get(m, "key");
    maps::Maps_ss_put(m, "key", val[1..3]);
    let val2, f5 = maps::Maps_ss_get(m, "key");
    if !f4 || !f5 || val2 != "al" { fail_at("accessors", "put from itself"); }
    maps::Maps_ss_put(m, val2, val2);
    let val3, f6 = maps::Maps_ss_get(m, "al");
    if !f6 || val3 != "al" { fail_at("accessors", "put of a key from the pool"); }

    // Default string value when missing; numeric and bool keys.
    let val4, f7 = maps::Maps_ss_get(m, "nope");
    if f7 || val4.len != 0 { fail_at("accessors", "missing string"); }
    maps::Maps_bb_put(m, true, false);
    maps::Maps_bb_put(m, false, true);
    let bv, bf = maps::Maps_bb_get(m, false);
    if !bf || !bv { fail_at("accessors", "bool key"); }
    maps::Maps_is_put(m, 7, "seven");
    let sv, sf = maps::Maps_is_get(m, 7);
    if !sf || sv != "seven" { fail_at("accessors", "int key"); }

    // Message values: get is null if missing; put keeps what is there, and a
    // reference survives other puts until the entry changes.
    if maps::Maps_sm_get(m, "m") != null { fail_at("accessors", "missing message"); }
    let s .= maps::Maps_sm_put(m, "m");
    s.a = 5;
    for i in 100 { maps::Maps_sm_put(m, str("k", i)); }
    if s.a != 5 { fail_at("accessors", "reference moved"); }
    s.a = 6;
    let got = maps::Maps_sm_get(m, "m");
    guard got else { fail_at("accessors", "message get"); return; }
    if got.a != 6 { fail_at("accessors", "message get value"); }
    if maps::Maps_sm_put(m, "m").a != 6 { fail_at("accessors", "put of a message replaced it"); }
    if !maps::Maps_sm_remove(m, "m") { fail_at("accessors", "remove message"); }
    if maps::Maps_sm_get(m, "m") != null { fail_at("accessors", "message after remove"); }
    maps::Maps_clear(m);
}

fn decode_all(parts: const u8[:], m: maps::Maps&) {
    let err = maps::Maps_decode(parts, m);
    if err != PB_OK { fail_at("decode_all", str("decode error ", err)); }
}

fn check_decode() {
    var m = maps::Maps { .. };

    // Two entries.
    decode_all(embed_file("two_a.bin"), m);
    if maps::Maps_si_len(m) != 2 { fail_at("decode", "two entries"); }
    maps::Maps_clear(m);

    // A duplicate key: the last value wins, in the first one's place.
    var w: u8[>..] = [];
    w.append(embed_file("dup_a.bin"));
    w.append(embed_file("dup_c.bin"));
    w.append(embed_file("dup_b.bin"));
    decode_all(w, m);
    if maps::Maps_si_len(m) != 2 { fail_at("decode", str("duplicate key: ", maps::Maps_si_len(m), " entries")); }
    let v, found = maps::Maps_si_get(m, "a");
    if !found || v != 9 { fail_at("decode", "duplicate key: last value"); }
    if maps::Maps_si_key_at(m, 0) != "a" { fail_at("decode", "duplicate key: place"); }
    maps::Maps_clear(m);

    // The same across two decodes.
    decode_all(embed_file("dup_a.bin"), m);
    decode_all(embed_file("dup_b.bin"), m);
    let v2, f2 = maps::Maps_si_get(m, "a");
    if !f2 || v2 != 9 || maps::Maps_si_len(m) != 1 { fail_at("decode", "duplicate key over decodes"); }
    maps::Maps_clear(m);

    // A duplicate key with a message value replaces, it does not merge.
    var w2: u8[>..] = [];
    w2.append(embed_file("sm_a.bin"));
    w2.append(embed_file("sm_b.bin"));
    decode_all(w2, m);
    let s = maps::Maps_sm_get(m, "m");
    guard s else { fail_at("decode", "message value"); return; }
    if s.a != 0 || maps::Sub_r(s).len != 1 { fail_at("decode", "values of a duplicate key merged"); }
    maps::Maps_clear(m);

    // Hand-made entries of si (field 3, tag 0x1a), and of sm (18, 0x92 0x01).
    // Value before key.
    let rev: u8[7] = [0x1a, 5, 0x10, 4, 0x0a, 1, 0x61];
    decode_all(rev, m);
    let v3, f3 = maps::Maps_si_get(m, "a");
    if !f3 || v3 != 4 { fail_at("decode", "value before key"); }
    maps::Maps_clear(m);
    // No key and no value: two such entries are one, with the defaults.
    let empty: u8[4] = [0x1a, 0, 0x1a, 0];
    decode_all(empty, m);
    let v4, f4 = maps::Maps_si_get(m, "");
    if !f4 || v4 != 0 || maps::Maps_si_len(m) != 1 { fail_at("decode", "empty entries"); }
    var eo: u8[>..] = [];
    maps::Maps_encode(m, eo);
    if eo != embed_file("si_defaults.bin") { fail_at("decode", "defaults are encoded"); }
    maps::Maps_clear(m);
    // A message value that is missing is an empty one.
    let noval: u8[3] = [0x92, 0x01, 0];
    decode_all(noval, m);
    if maps::Maps_sm_get(m, "") == null { fail_at("decode", "missing message value"); }
    maps::Maps_clear(m);
    // The key twice in an entry: the last wins.
    let keys: u8[10] = [0x1a, 8, 0x0a, 1, 0x61, 0x0a, 1, 0x62, 0x10, 2];
    decode_all(keys, m);
    let v5, f5 = maps::Maps_si_get(m, "b");
    if !f5 || v5 != 2 || maps::Maps_si_len(m) != 1 { fail_at("decode", "key twice"); }
    maps::Maps_clear(m);
    // The value message twice in one entry merges: value { a: 1 } value { r: 2 }.
    let vals: u8[11] = [0x92, 0x01, 8, 0x12, 2, 0x08, 1, 0x12, 2, 0x18, 2];
    decode_all(vals, m);
    let mv = maps::Maps_sm_get(m, "");
    guard mv else { fail_at("decode", "value twice"); return; }
    if mv.a != 1 || maps::Sub_r(mv).len != 1 { fail_at("decode", "value twice did not merge"); }
    maps::Maps_clear(m);
    // An unknown field in an entry is dropped, as protobuf C++ does.
    let unk: u8[6] = [0x1a, 4, 0x18, 1, 0x10, 2];
    decode_all(unk, m);
    if maps::Maps_size_of(m) != 6 { fail_at("decode", str("unknown in an entry: size ", maps::Maps_size_of(m))); }
    maps::Maps_clear(m);

    // A map field with another wire type is an unknown field.
    let wrong: u8[2] = [0x18, 1];
    decode_all(wrong, m);
    if maps::Maps_si_len(m) != 0 || maps::Maps_size_of(m) != 2 { fail_at("decode", "map field with another wire type"); }
    maps::Maps_clear(m);
}

fn check_errors() {
    var m = maps::Maps { .. };
    // ss: invalid UTF-8 as key, and as value. sb's value may be anything.
    let badk: u8[5] = [0x0a, 3, 0x0a, 1, 0xff];
    if maps::Maps_decode(badk, m) != PB_ERR_UTF8 { fail_at("errors", "key UTF-8"); }
    maps::Maps_clear(m);
    let badv: u8[5] = [0x0a, 3, 0x12, 1, 0xff];
    if maps::Maps_decode(badv, m) != PB_ERR_UTF8 { fail_at("errors", "value UTF-8"); }
    maps::Maps_clear(m);
    let okb: u8[5] = [0x12, 3, 0x12, 1, 0xff];
    if maps::Maps_decode(okb, m) != PB_OK { fail_at("errors", "bytes value"); }
    maps::Maps_clear(m);
    // Truncated: an entry longer than the buffer, and inside an entry.
    let t1: u8[2] = [0x1a, 5];
    if maps::Maps_decode(t1, m) != PB_ERR_TRUNCATED { fail_at("errors", "truncated entry"); }
    maps::Maps_clear(m);
    let t2: u8[4] = [0x1a, 2, 0x0a, 5];
    if maps::Maps_decode(t2, m) != PB_ERR_TRUNCATED { fail_at("errors", "truncated key"); }
    maps::Maps_clear(m);
    if maps::Maps_size_of(m) != 0 { fail_at("errors", "clear after failure"); }

    // Depth: self values nested beyond the limit, each one's length covering
    // the rest, built from the inside out.
    var nest: u8[>..] = [];
    for i in 60 {
        var value: u8[>..] = [];
        pb_write_varint(value, 0x12);
        pb_write_varint(value, nest.len as! u64);
        value.append(nest);
        var entry: u8[>..] = [];
        pb_write_varint(entry, 162);
        pb_write_varint(entry, value.len as! u64);
        entry.append(value);
        nest = copy(entry);
    }
    if maps::Maps_decode(nest, m) != PB_ERR_DEPTH { fail_at("errors", "depth"); }
    maps::Maps_clear(m);
}

fn check_copy() {
    var a = maps::Maps { .. };
    var b = maps::Maps { .. };
    maps::Maps_ss_put(b, "old", "gone");
    decode_all(embed_file("nested.bin"), a);
    maps::Maps_ss_put(a, "s", "v");
    maps::Maps_sm_put(a, "m").a = 1;
    maps::Maps_copy(b, a);
    var want: u8[>..] = [];
    maps::Maps_encode(a, want);
    maps::Maps_clear(a);
    var got: u8[>..] = [];
    maps::Maps_encode(b, got);
    if got != want { fail_at("copy", "the copy does not outlive its source"); }
    let old, f = maps::Maps_ss_get(b, "old");
    if f { fail_at("copy", "what dst held stayed"); }
    maps::Maps_ss_put(a, "s", "changed");
    let v, f2 = maps::Maps_ss_get(b, "s");
    if !f2 || v != "v" { fail_at("copy", "shares with its source"); }
    maps::Maps_clear(a);
    maps::Maps_clear(b);
}

// Replacing values, duplicates and clearing free what they held.
fn check_no_leak() {
    var m = maps::Maps { .. };
    var bytes_len: i64 = 0;
    var entries_len: i64 = 0;
    var sub_len: i64 = 0;
    for i in 200 {
        maps::Maps_ss_put(m, "key", "value");
        maps::Maps_ss_put(m, "key", "other value");
        maps::Sub_set_s(maps::Maps_sm_put(m, "m"), "in a sub");
        maps::Maps_sm_remove(m, "m");
        decode_all(embed_file("sm_a.bin"), m);
        decode_all(embed_file("sm_b.bin"), m);
        decode_all(embed_file("nested.bin"), m);
        maps::Maps_clear(m);
        if i == 0 {
            bytes_len = pb_bytes.len;
            entries_len = maps::Maps_SsEntry_entries.len;
            sub_len = maps::Sub_pool.len;
        }
    }
    if pb_bytes.len != bytes_len { fail_at("leak", str("pb_bytes grew to ", pb_bytes.len, " from ", bytes_len)); }
    if maps::Maps_SsEntry_entries.len != entries_len { fail_at("leak", "entries grew"); }
    if maps::Sub_pool.len != sub_len { fail_at("leak", "Sub_pool grew"); }
}

fn main() {
    check_built_cases();
    check_accessors();
    check_decode();
    check_errors();
    check_copy();
    check_no_leak();
    if failures > 0 { abort(str(failures, " failures")); }
    print("ok");
}
