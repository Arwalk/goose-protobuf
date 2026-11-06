// A sub-message that repeats on the wire, with one map entry each time, merges
// into one map. That is one input, and decoding it is not quadratic either
// (gpb-dx9.7): at this size a quadratic decode runs past the harness's limit
// for one test, so this fails rather than slows down.
import pb_wire;
import maps;

fn main() {
    let n: i64 = 1000000;
    var b: u8[>..] = [];
    for i in n {
        // A bijection on u32: distinct keys, in no useful order.
        let k = ((i + 1) as! u32) * 2654435761;
        var e: u8[>..] = [];
        pb_write_varint(e, 8);
        pb_write_varint(e, k);
        pb_write_varint(e, 16);
        pb_write_varint(e, 1);
        var one: u8[>..] = [];
        pb_write_varint(one, 0x32);   // uu, field 6 of Maps
        pb_write_varint(one, e.len as! u64);
        one.append(e);
        pb_write_varint(b, 0x0a);     // one, field 1 of Holder
        pb_write_varint(b, one.len as! u64);
        b.append(one);
    }
    var h = maps::Holder { .. };
    if maps::Holder_decode(b, h) != PB_OK { abort("decode"); }
    let m = maps::Holder_one(h);
    guard m else { abort("no sub-message"); return; }
    if maps::Maps_uu_len(m) != n { abort(str(maps::Maps_uu_len(m), " entries")); }
    maps::Holder_clear(h);
    print("ok");
}
