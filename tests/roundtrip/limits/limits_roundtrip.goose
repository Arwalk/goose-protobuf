// pb_set_decode_limit: input that asks for more memory than the limit gets
// PB_ERR_TOO_LARGE from every kind of field, and the same input decodes under a
// higher limit. With the default limit, input that would end the program gets the
// error too.
import pb_wire;
import limits;

let SMALL: i64 = 1 << 20;   // a limit
let BIG: i64 = 1 << 30;     // a limit that all but the last case stay within
let COUNT: i64 = 1 << 19;   // of an element, whose cost is at least 1 byte

fn put_varint(out: u8[>..]&, v: i64) {
    var x = v as! u64;
    while x >= 0x80 {
        out.push((x | 0x80) as! u8);
        x >>= 7;
    }
    out.push(x as! u8);
}

// count copies of the field with this tag and these bytes after it.
fn repeat(tag: i64, value: const u8[:], count: i64) -> u8[>..] {
    var out: u8[>..] = [];
    for i in count {
        put_varint(out, tag);
        out.append(value);
    }
    return out;
}

// One field with this tag: a length, then count copies of value.
fn delimited(tag: i64, value: const u8[:], count: i64) -> u8[>..] {
    var out: u8[>..] = [];
    put_varint(out, tag);
    put_varint(out, value.len * count);
    for i in count { out.append(value); }
    return out;
}

// A complete binary tree of this depth, as the bytes of a Tree.
fn tree(depth: i64) -> u8[>..] {
    var side: u8[>..] = [];
    for d in depth {
        var out: u8[>..] = [];
        put_varint(out, 10);
        put_varint(out, side.len);
        out.append(side);
        put_varint(out, 18);
        put_varint(out, side.len);
        out.append(side);
        side = copy(out);
    }
    return side;
}

fn check(what: const u8[:], input: const u8[:]) {
    var m = limits::All { .. };
    pb_set_decode_limit(SMALL);
    let small = limits::All_decode(input, m);
    limits::All_clear(m);
    if small != PB_ERR_TOO_LARGE {
        abort(str(what, " under a small limit: ", pb_error_text(small)));
    }
    pb_set_decode_limit(BIG);
    let big = limits::All_decode(input, m);
    limits::All_clear(m);
    if big != PB_OK { abort(str(what, " under a big limit: ", pb_error_text(big))); }
}

fn main() {
    let zero_len: u8[] = [0];
    let one: u8[] = [1];

    check("repeated message", repeat(10, zero_len, COUNT));
    check("group", repeat(19, [20 as u8], COUNT));
    check("map", repeat(26, zero_len, COUNT));
    check("map of messages", repeat(34, zero_len, COUNT));
    check("unpacked", repeat(40, one, COUNT));
    check("packed", delimited(50, one, COUNT));
    check("packed bool", delimited(58, one, 2 * SMALL));
    check("repeated string", repeat(66, zero_len, COUNT));
    check("repeated bytes", repeat(74, zero_len, COUNT));
    check("string", delimited(82, [97 as u8], 2 * SMALL));
    check("bytes", delimited(90, one, 2 * SMALL));
    check("closed enum", repeat(96, one, COUNT));
    check("closed enum, packed", delimited(106, one, COUNT));
    check("closed enum, unknown value", repeat(96, [2 as u8], 2 * SMALL));
    check("closed enum, packed unknown value", delimited(106, [2 as u8], 2 * SMALL));
    check("unknown fields", repeat(800, one, 2 * SMALL));
    var with_tree = delimited(114, tree(17), 1);
    check("singular messages", with_tree);
    with_tree.clear();
    check("oneof", repeat(122, [2 as u8, 18 as u8, 0 as u8], COUNT));

    // The limit is for each decode, and not for all of them together.
    var m = limits::All { .. };
    pb_set_decode_limit(32);
    if limits::All_decode(repeat(40, one, 3), m) != PB_OK { abort("3 values of 8 bytes under 32"); }
    limits::All_clear(m);
    if limits::All_decode(repeat(40, one, 3), m) != PB_OK { abort("and again"); }
    limits::All_clear(m);

    // Without a limit set, input that needs well past the 2 GB of a data stack gets
    // the error and not an uncatchable end of the program.
    pb_set_decode_limit(PB_DEFAULT_DECODE_LIMIT);
    let huge = limits::All_decode(repeat(10, zero_len, 128 << 20), m);
    if huge != PB_ERR_TOO_LARGE { abort(str("the default limit: ", pb_error_text(huge))); }
    limits::All_clear(m);

    if pb_error_text(PB_ERR_TOO_LARGE).len == 0 { abort("pb_error_text"); }
}
