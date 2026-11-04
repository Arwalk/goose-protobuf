// Times decoding one message holding one map. Run by scripts/bench_maps.sh.
// Usage: bench_maps <shape> <entries>
//   int_random   distinct int32 keys in a scrambled order
//   str_random   distinct short string keys in a scrambled order
//   str_prefix   distinct string keys sharing a 64-byte prefix, the costly
//                case for comparisons
//   int_dup      every entry has the same int32 key
//   int_half     each int32 key twice, first in order and then in order again
//   str_long     distinct string keys sharing a 64 KiB prefix: few entries, large
//                input, the costliest comparisons
//   int_merge    distinct int32 keys, in many M_decode calls of 100 entries each
//                into one message, each of which folds the run
//   wrap_map     <entries> occurrences of a sub-message, each with one map entry
//                of a distinct key, which merge: a single crafted input
//   wrap_list    the same, each with one element of a repeated int32
//   wrap_unknown the same, each with one unknown field
//   two_maps     <entries> occurrences alternating between two sub-messages, each
//                with one map entry: two runs of one pool, which keep moving
//   two_lists    the same, each with one element of a repeated int32
//   small_maps   <entries> messages, each with a map of 4 entries: the common
//                case, which must not get slower
// Prints: shape entries input_bytes unique_entries decode_seconds
import os;
import pb_wire;
import bench_maps;

// A bijection on u32, so keys are distinct and in no useful order.
fn scramble(i: i64) -> u32 { return ((i + 1) as! u32) * 2654435761; }

fn put_int_entry(buf: u8[>..]&, key: u32, value: u64) {
    var e: u8[>..] = [];
    pb_write_varint(e, 8);
    pb_write_varint(e, pb_int32_to_u64(key as! i32));
    pb_write_varint(e, 16);
    pb_write_varint(e, value);
    pb_write_varint(buf, 10);
    pb_write_varint(buf, e.len as! u64);
    buf.append(e);
}

fn put_str_entry(buf: u8[>..]&, prefix: const u8[:], key: u32, value: u64) {
    let k = str(prefix, key);
    var e: u8[>..] = [];
    pb_write_varint(e, 10);
    pb_write_varint(e, k.len as! u64);
    e.append(k);
    pb_write_varint(e, 16);
    pb_write_varint(e, value);
    pb_write_varint(buf, 18);
    pb_write_varint(buf, e.len as! u64);
    buf.append(e);
}

fn main() {
    let a = args();
    if a.len != 3 { abort("usage: bench_maps <shape> <entries>"); }
    let shape = a[1];
    var n: i64 = 0;
    for c in a[2] { n = n * 10 + (c - 48) as i64; }

    var prefix: u8[>..] = [];
    let prefix_len: i64 = if shape == "str_long" { 65536 } else { 64 };
    for i in prefix_len { prefix.push(120); }
    var buf: u8[>..] = [];
    for i in n {
        if shape == "small_maps" || shape == "int_merge" || shape == "wrap_map" || shape == "wrap_list" || shape == "wrap_unknown" || shape == "two_maps" || shape == "two_lists" { break; }
        if shape == "int_random" { put_int_entry(buf, scramble(i), 1); }
        else if shape == "str_random" { put_str_entry(buf, "", scramble(i), 1); }
        else if shape == "str_prefix" || shape == "str_long" { put_str_entry(buf, prefix, scramble(i), 1); }
        else if shape == "int_dup" { put_int_entry(buf, 7, (i & 127) as! u64); }
        else if shape == "int_half" { put_int_entry(buf, scramble(i % (n / 2)), 1); }
        else { abort("unknown shape"); }
    }

    if shape == "two_maps" || shape == "two_lists" {
        var tb: u8[>..] = [];
        for i in n {
            var inner: u8[>..] = [];
            if shape == "two_maps" { put_int_entry(inner, scramble(i), 1); }
            else { pb_write_varint(inner, 0x18); pb_write_varint(inner, 1); }
            pb_write_varint(tb, if i % 2 == 0 { 10 } else { 18 });
            pb_write_varint(tb, inner.len as! u64);
            tb.append(inner);
        }
        var t = bench::Wrap { .. };
        let t0 = clock();
        let te = bench::Wrap_decode(tb, t);
        let t1 = clock();
        if te != PB_OK { abort(str("decode error ", te)); }
        print(shape, " ", n, " ", tb.len, " ", 0, " ", t1 - t0);
        return;
    }

    if shape == "wrap_map" || shape == "wrap_list" || shape == "wrap_unknown" {
        var wb: u8[>..] = [];
        for i in n {
            var inner: u8[>..] = [];
            if shape == "wrap_map" { put_int_entry(inner, scramble(i), 1); }
            else if shape == "wrap_list" { pb_write_varint(inner, 0x18); pb_write_varint(inner, 1); }
            else { pb_write_varint(inner, 0x78); pb_write_varint(inner, 1); }
            pb_write_varint(wb, 10);
            pb_write_varint(wb, inner.len as! u64);
            wb.append(inner);
        }
        var w = bench::Wrap { .. };
        let w0 = clock();
        let we = bench::Wrap_decode(wb, w);
        let w1 = clock();
        if we != PB_OK { abort(str("decode error ", we)); }
        let wm = bench::Wrap_b(w);
        guard wm else { abort("no sub-message"); return; }
        print(shape, " ", n, " ", wb.len, " ", bench::B_ints(wm).len + bench::B_list(wm).len + wm.pb_unknown.len / 2, " ", w1 - w0);
        return;
    }

    if shape == "int_merge" {
        var chunks: u8[>..] = [];
        var ends: i64[>..] = [];
        for i in n {
            put_int_entry(chunks, scramble(i), 1);
            if i % 100 == 99 || i == n - 1 { ends.push(chunks.len); }
        }
        var mm = bench::B { .. };
        let m0 = clock();
        var from: i64 = 0;
        for to in ends {
            if bench::B_decode(chunks[from..to], mm) != PB_OK { abort("decode error"); }
            from = to;
        }
        let m1 = clock();
        print(shape, " ", n, " ", chunks.len, " ", bench::B_ints(mm).len, " ", m1 - m0);
        return;
    }

    if shape == "small_maps" {
        var one: u8[>..] = [];
        for i in 4 { put_int_entry(one, scramble(i), 1); }
        var outer_buf: u8[>..] = [];
        for i in n {
            pb_write_varint(outer_buf, 10);
            pb_write_varint(outer_buf, one.len as! u64);
            outer_buf.append(one);
        }
        var o = bench::Outer { .. };
        let s0 = clock();
        let e = bench::Outer_decode(outer_buf, o);
        let s1 = clock();
        if e != PB_OK { abort(str("decode error ", e)); }
        print(shape, " ", n, " ", outer_buf.len, " ", bench::B_ints(bench::Outer_items_at(o, 0)).len, " ", s1 - s0);
        return;
    }

    var m = bench::B { .. };
    let t0 = clock();
    let err = bench::B_decode(buf, m);
    let t1 = clock();
    if err != PB_OK { abort(str("decode error ", err)); }
    let unique = bench::B_ints(m).len + bench::B_strs(m).len;
    print(shape, " ", n, " ", buf.len, " ", unique, " ", t1 - t0);
}
