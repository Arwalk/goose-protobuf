// Decoding a large map is not quadratic (gpb-dx9.7). At this size a quadratic
// decode runs for many minutes, past the harness's limit for one test, so this
// fails rather than slows down. scripts/bench_maps.sh has the measurements.
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
        pb_write_varint(b, 0x32);   // uu, field 6
        pb_write_varint(b, e.len as! u64);
        b.append(e);
    }
    var m = maps::Maps { .. };
    if maps::Maps_decode(b, m) != PB_OK { abort("decode"); }
    if maps::Maps_uu(m).len != n { abort(str(maps::Maps_uu(m).len, " entries")); }
    let v, found = maps::Maps_uu_get(m, 2654435761);
    if !found || v != 1 { abort("first key"); }
    maps::Maps_clear(m);
    print("ok");
}
