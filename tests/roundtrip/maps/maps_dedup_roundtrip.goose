// What decoding a map keeps when keys repeat, against a plain model: the last
// value wins, in the place of the first occurrence (gpb-dx9.7).
// Run: scripts/roundtrip.sh maps
import pb_wire;
import maps;
import pb_wire.wkt.struct_;

var failures = 0;

fn fail_at(what: u8[:], detail: u8[:]) {
    failures += 1;
    print("FAIL ", what, ": ", detail);
}

// Appends an entry of si (field 3): a string key and an int32 value.
fn put_si(buf: u8[>..]&, k: const u8[:], v: i64) {
    var e: u8[>..] = [];
    pb_write_varint(e, 0x0a);
    pb_write_varint(e, k.len as! u64);
    e.append(k);
    pb_write_varint(e, 0x10);
    pb_write_varint(e, v as! u64);
    pb_write_varint(buf, 0x1a);
    pb_write_varint(buf, e.len as! u64);
    buf.append(e);
}

fn check_order() {
    var b: u8[>..] = [];
    put_si(b, "a", 1);
    put_si(b, "b", 2);
    put_si(b, "a", 3);
    put_si(b, "c", 4);
    put_si(b, "b", 5);
    put_si(b, "a", 6);
    var m = maps::Maps { .. };
    if maps::Maps_decode(b, m) != PB_OK { fail_at("order", "decode"); }
    let n = maps::Maps_si_len(m);
    if n != 3 { fail_at("order", str(n, " entries")); return; }
    if maps::Maps_si_key_at(m, 0) != "a" || maps::Maps_si_value_at(m, 0) != 6 { fail_at("order", "first"); }
    if maps::Maps_si_key_at(m, 1) != "b" || maps::Maps_si_value_at(m, 1) != 5 { fail_at("order", "second"); }
    if maps::Maps_si_key_at(m, 2) != "c" || maps::Maps_si_value_at(m, 2) != 4 { fail_at("order", "third"); }
    maps::Maps_clear(m);
}

// a and b have the same keys in the same order, with other values. a's encoding
// then b's decodes to what b encodes to. Clears both.
fn check_replaced(name: u8[:], a: maps::Maps&, b: maps::Maps&) {
    var ea: u8[>..] = [];
    maps::Maps_encode(a, ea);
    var eb: u8[>..] = [];
    maps::Maps_encode(b, eb);
    var both: u8[>..] = [];
    both.append(ea);
    both.append(eb);
    var m = maps::Maps { .. };
    if maps::Maps_decode(both, m) != PB_OK { fail_at(name, "decode"); }
    var out: u8[>..] = [];
    maps::Maps_encode(m, out);
    if out != eb { fail_at(name, "duplicates of this key type were not folded"); }
    maps::Maps_clear(m);
    maps::Maps_clear(a);
    maps::Maps_clear(b);
}

// Each key type, with keys either side of zero where it has them.
fn check_key_types() {
    var a = maps::Maps { .. };
    var b = maps::Maps { .. };
    maps::Maps_ss_put(a, "b", "1"); maps::Maps_ss_put(a, "", "2"); maps::Maps_ss_put(a, "ab", "3"); maps::Maps_ss_put(a, "a", "4");
    maps::Maps_ss_put(b, "b", "5"); maps::Maps_ss_put(b, "", "6"); maps::Maps_ss_put(b, "ab", "7"); maps::Maps_ss_put(b, "a", "8");
    check_replaced("string", a, b);
    maps::Maps_is_put(a, 2, "1"); maps::Maps_is_put(a, -2, "2"); maps::Maps_is_put(a, 0, "3");
    maps::Maps_is_put(b, 2, "4"); maps::Maps_is_put(b, -2, "5"); maps::Maps_is_put(b, 0, "6");
    check_replaced("int32", a, b);
    maps::Maps_ll_put(a, 2, 1); maps::Maps_ll_put(a, -2, 2); maps::Maps_ll_put(a, 0, 3);
    maps::Maps_ll_put(b, 2, 4); maps::Maps_ll_put(b, -2, 5); maps::Maps_ll_put(b, 0, 6);
    check_replaced("int64", a, b);
    maps::Maps_uu_put(a, 2, 1); maps::Maps_uu_put(a, 4000000000, 2); maps::Maps_uu_put(a, 0, 3);
    maps::Maps_uu_put(b, 2, 4); maps::Maps_uu_put(b, 4000000000, 5); maps::Maps_uu_put(b, 0, 6);
    check_replaced("uint32", a, b);
    maps::Maps_vv_put(a, 2, 1); maps::Maps_vv_put(a, 18000000000000000000, 2); maps::Maps_vv_put(a, 0, 3);
    maps::Maps_vv_put(b, 2, 4); maps::Maps_vv_put(b, 18000000000000000000, 5); maps::Maps_vv_put(b, 0, 6);
    check_replaced("uint64", a, b);
    maps::Maps_zz_put(a, 2, 1); maps::Maps_zz_put(a, -2, 2); maps::Maps_zz_put(a, 0, 3);
    maps::Maps_zz_put(b, 2, 4); maps::Maps_zz_put(b, -2, 5); maps::Maps_zz_put(b, 0, 6);
    check_replaced("sint32", a, b);
    maps::Maps_yy_put(a, 2, 1); maps::Maps_yy_put(a, -2, 2); maps::Maps_yy_put(a, 0, 3);
    maps::Maps_yy_put(b, 2, 4); maps::Maps_yy_put(b, -2, 5); maps::Maps_yy_put(b, 0, 6);
    check_replaced("sint64", a, b);
    maps::Maps_ff_put(a, 2, 1); maps::Maps_ff_put(a, 4000000000, 2); maps::Maps_ff_put(a, 0, 3);
    maps::Maps_ff_put(b, 2, 4); maps::Maps_ff_put(b, 4000000000, 5); maps::Maps_ff_put(b, 0, 6);
    check_replaced("fixed32", a, b);
    maps::Maps_gg_put(a, 2, 1); maps::Maps_gg_put(a, 18000000000000000000, 2); maps::Maps_gg_put(a, 0, 3);
    maps::Maps_gg_put(b, 2, 4); maps::Maps_gg_put(b, 18000000000000000000, 5); maps::Maps_gg_put(b, 0, 6);
    check_replaced("fixed64", a, b);
    maps::Maps_hh_put(a, 2, 1); maps::Maps_hh_put(a, -2, 2); maps::Maps_hh_put(a, 0, 3);
    maps::Maps_hh_put(b, 2, 4); maps::Maps_hh_put(b, -2, 5); maps::Maps_hh_put(b, 0, 6);
    check_replaced("sfixed32", a, b);
    maps::Maps_jj_put(a, 2, 1); maps::Maps_jj_put(a, -2, 2); maps::Maps_jj_put(a, 0, 3);
    maps::Maps_jj_put(b, 2, 4); maps::Maps_jj_put(b, -2, 5); maps::Maps_jj_put(b, 0, 6);
    check_replaced("sfixed64", a, b);
    maps::Maps_bb_put(a, true, false); maps::Maps_bb_put(a, false, false);
    maps::Maps_bb_put(b, true, true); maps::Maps_bb_put(b, false, true);
    check_replaced("bool", a, b);
}

// A small generator of numbers, so a failure reproduces.
var seed: u64 = 88172645463325252;
fn next_random(limit: i64) -> i64 {
    seed ^= seed << 13;
    seed ^= seed >> 7;
    seed ^= seed << 17;
    return ((seed >> 1) % (limit as! u64)) as! i64;
}

// Random entries over few keys, in several decodes, against a plain model.
fn check_model() {
    for round in 20 {
        let keys = 1 + next_random(300);
        var model_keys: i64[>..] = [];
        var model_values: i64[>..] = [];
        var m = maps::Maps { .. };
        for decode in 1 + next_random(4) {
            var b: u8[>..] = [];
            for e in next_random(3000) {
                let k = next_random(keys);
                let v = next_random(1000);
                put_si(b, str("key", k), v);
                var at: i64 = -1;
                for i in model_keys.len { if model_keys[i] == k { at = i; break; } }
                if at < 0 { model_keys.push(k); model_values.push(v); }
                else { model_values[at] = v; }
            }
            if maps::Maps_decode(b, m) != PB_OK { fail_at("model", "decode"); }
        }
        let n = maps::Maps_si_len(m);
        if n != model_keys.len { fail_at("model", str(n, " entries, want ", model_keys.len)); }
        else {
            for i in n {
                if maps::Maps_si_key_at(m, i) != str("key", model_keys[i]) { fail_at("model", "order"); break; }
                if maps::Maps_si_value_at(m, i) != model_values[i] as! i32 { fail_at("model", "value"); break; }
            }
        }
        maps::Maps_clear(m);
    }
}

// Entries already there count, and those made by put_ too.
fn check_existing() {
    var m = maps::Maps { .. };
    maps::Maps_si_put(m, "z", 1);
    maps::Maps_si_put(m, "y", 2);
    var b: u8[>..] = [];
    put_si(b, "x", 3);
    put_si(b, "z", 4);
    if maps::Maps_decode(b, m) != PB_OK { fail_at("existing", "decode"); }
    let n = maps::Maps_si_len(m);
    if n != 3 { fail_at("existing", str(n, " entries")); return; }
    if maps::Maps_si_key_at(m, 0) != "z" || maps::Maps_si_value_at(m, 0) != 4 { fail_at("existing", "z"); }
    if maps::Maps_si_key_at(m, 1) != "y" || maps::Maps_si_value_at(m, 1) != 2 { fail_at("existing", "y"); }
    if maps::Maps_si_key_at(m, 2) != "x" || maps::Maps_si_value_at(m, 2) != 3 { fail_at("existing", "x"); }
    // get_ and put_ work on what was decoded.
    let got, found = maps::Maps_si_get(m, "z");
    if !found || got != 4 { fail_at("existing", "get"); }
    maps::Maps_clear(m);
}

// A map in a value of a map: each level folds its own keys.
fn check_nested() {
    var inner: u8[>..] = [];
    put_si(inner, "n", 1);
    put_si(inner, "n", 2);
    var value: u8[>..] = [];
    pb_write_varint(value, 0x12);
    pb_write_varint(value, inner.len as! u64);
    value.append(inner);
    var entry: u8[>..] = [];
    pb_write_varint(entry, 0x0a);
    pb_write_varint(entry, 1);
    entry.push(0x6b);
    entry.append(value);
    var b: u8[>..] = [];
    for i in 3 {
        pb_write_varint(b, 162);
        pb_write_varint(b, entry.len as! u64);
        b.append(entry);
    }
    var m = maps::Maps { .. };
    if maps::Maps_decode(b, m) != PB_OK { fail_at("nested", "decode"); }
    if maps::Maps_self_len(m) != 1 { fail_at("nested", "outer keys"); }
    let k = maps::Maps_self_get(m, "k");
    guard k else { fail_at("nested", "value"); return; }
    if maps::Maps_si_len(k) != 1 { fail_at("nested", "inner keys"); }
    let v, found = maps::Maps_si_get(k, "n");
    if !found || v != 2 { fail_at("nested", "inner value"); }
    maps::Maps_clear(m);
}

// Appends a length-delimited field with a one-byte tag.
fn put_field(buf: u8[>..]&, tag: u64, value: const u8[:]) {
    pb_write_varint(buf, tag);
    pb_write_varint(buf, value.len as! u64);
    buf.append(value);
}

// A map's keys are folded through every kind of field that reaches it, and a
// sub-message that repeats on the wire folds as one: its occurrences merge.
fn check_reach() {
    var one: u8[>..] = [];
    put_si(one, "a", 1);
    var two: u8[>..] = [];
    put_si(two, "b", 2);
    put_si(two, "a", 3);

    // Singular, across occurrences.
    var b: u8[>..] = [];
    put_field(b, 0x0a, one);
    put_field(b, 0x0a, two);
    var h = maps::Holder { .. };
    if maps::Holder_decode(b, h) != PB_OK { fail_at("reach", "singular decode"); }
    let s = maps::Holder_one(h);
    guard s else { fail_at("reach", "singular"); return; }
    if maps::Maps_si_len(s) != 2 { fail_at("reach", str("singular: ", maps::Maps_si_len(s), " entries")); }
    let v, found = maps::Maps_si_get(s, "a");
    if !found || v != 3 { fail_at("reach", "singular value"); }
    maps::Holder_clear(h);

    // Repeated: elements do not merge, and each folds its own.
    var both: u8[>..] = [];
    both.append(one);
    both.append(two);
    var r: u8[>..] = [];
    put_field(r, 0x12, both);
    put_field(r, 0x12, one);
    if maps::Holder_decode(r, h) != PB_OK { fail_at("reach", "repeated decode"); }
    if maps::Holder_many_len(h) != 2 { fail_at("reach", "repeated elements"); }
    if maps::Maps_si_len(maps::Holder_many_at(h, 0)) != 2 { fail_at("reach", "repeated: not folded"); }
    if maps::Maps_si_len(maps::Holder_many_at(h, 1)) != 1 { fail_at("reach", "repeated: second"); }
    maps::Holder_clear(h);

    // A oneof member, across occurrences.
    var o: u8[>..] = [];
    put_field(o, 0x1a, one);
    put_field(o, 0x1a, two);
    if maps::Holder_decode(o, h) != PB_OK { fail_at("reach", "member decode"); }
    let mem = maps::Holder_member(h);
    guard mem else { fail_at("reach", "member"); return; }
    if maps::Maps_si_len(mem) != 2 { fail_at("reach", "member: not folded"); }
    maps::Holder_clear(h);

    // A message of an imported file: Struct's fields, field 1 of it.
    var sf: u8[>..] = [];
    put_field(sf, 0x0a, embed_file("nums.bin"));
    put_field(sf, 0x0a, embed_file("nums.bin"));
    var i: u8[>..] = [];
    put_field(i, 0x22, sf);
    if maps::Holder_decode(i, h) != PB_OK { fail_at("reach", "imported decode"); }
    let st = maps::Holder_imported(h);
    guard st else { fail_at("reach", "imported"); return; }
    if google_protobuf::Struct_fields_len(st) != 1 { fail_at("reach", "imported: not folded"); }
    maps::Holder_clear(h);

    // A failed decode leaves a partial message, which clears, and a later
    // decode into it folds what the failed one left.
    var bad: u8[>..] = [];
    bad.append(two);
    bad.append(two);
    bad.push(0x1a);
    bad.push(100);
    var m = maps::Maps { .. };
    if maps::Maps_decode(bad, m) != PB_ERR_TRUNCATED { fail_at("reach", "failed decode"); }
    if maps::Maps_decode(one, m) != PB_OK { fail_at("reach", "decode after a failure"); }
    if maps::Maps_si_len(m) != 2 { fail_at("reach", "not folded after a failure"); }
    maps::Maps_clear(m);
}

// What duplicates held is freed, also when the decode fails after them.
fn check_no_leak() {
    var good: u8[>..] = [];
    for i in 50 {
        put_si(good, "a string key that repeats", i);
        put_si(good, str("key", i % 7), i);
    }
    // sm (field 18): a message value that repeats.
    let sm = embed_file("sm.bin");
    for i in 20 { good.append(sm); }
    var bad: u8[>..] = [];
    bad.append(good);
    bad.push(0x1a);
    bad.push(100);

    var m = maps::Maps { .. };
    var bytes_len: i64 = 0;
    var entries_len: i64 = 0;
    var sub_len: i64 = 0;
    for i in 100 {
        if maps::Maps_decode(good, m) != PB_OK { fail_at("leak", "decode"); }
        maps::Maps_clear(m);
        if maps::Maps_decode(bad, m) != PB_ERR_TRUNCATED { fail_at("leak", "decode of the bad one"); }
        maps::Maps_clear(m);
        if i == 0 {
            bytes_len = pb_bytes.len;
            entries_len = maps::Maps_SiEntry_entries.len;
            sub_len = maps::Sub_pool.len;
        }
    }
    if pb_bytes.len != bytes_len { fail_at("leak", str("pb_bytes grew to ", pb_bytes.len, " from ", bytes_len)); }
    if maps::Maps_SiEntry_entries.len != entries_len { fail_at("leak", "entries grew"); }
    if maps::Sub_pool.len != sub_len { fail_at("leak", "Sub_pool grew"); }
}

fn main() {
    check_order();
    check_key_types();
    check_model();
    check_existing();
    check_nested();
    check_reach();
    check_no_leak();
    if failures > 0 { abort(str(failures, " failures")); }
    print("ok");
}
