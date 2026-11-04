// A sub-message that repeats on the wire, with an unknown field each time, keeps
// them all, in order. That is one input, and decoding it is not quadratic
// (gpb-dx9.8): at this size a quadratic decode runs past the harness's limit for
// one test, so this fails rather than slows down.
import pb_wire;
import unknown;

fn main() {
    let n: i64 = 4000000;
    var b: u8[>..] = [];
    for i in n {
        b.push(0x3a);                // sub, field 7 of Wide
        b.push(2);
        b.push(0x10);                // v, field 2, which Known does not have
        b.push((i & 127) as! u8);
    }
    var w = unknown::Wide { .. };
    if unknown::Wide_decode(b, w) != PB_OK { abort("decode"); }
    let m = unknown::Wide_sub(w);
    guard m else { abort("no sub-message"); return; }
    if m.pb_unknown.len != 2 * n { abort(str(m.pb_unknown.len, " bytes kept")); }
    var out: u8[>..] = [];
    unknown::Known_encode(m, out);
    for i in n {
        if out[2 * i] != 0x10 || out[2 * i + 1] != (i & 127) as! u8 { abort(str("wrong at ", i)); }
    }
    unknown::Wide_clear(w);
    print("ok");
}
