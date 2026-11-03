// Variant S (chosen, docs/decisions/0004-decode-errors.md): a sticky error
// code in a reader passed by reference. A failing primitive records the
// first error and moves pos to the window end, so every field loop stops;
// callers check r.err only after a nested message decode.
// message Node { int32 id = 1; repeated Node children = 2; bytes name = 3; }
// Run: goose run sticky.goose --debug   (`-- bench` for the benchmark)

import .bench;

let ERR_NONE = 0;
let ERR_TRUNCATED = 1;
let ERR_DEPTH = 2;
let ERR_MALFORMED = 3;
let MAX_DEPTH = 3;    // 100 in pb_wire (protobuf's default); 3 keeps tests short

struct Reader { buf: const u8[:], pos: i64, end: i64, err: i32, depth: i32 }

fn fail(r: Reader&, code: i32) {
    if r.err == ERR_NONE { r.err = code; }
    r.pos = r.end;       // every loop `while r.pos < r.end` stops at once
}

fn read_varint(r: Reader&) -> u64 {
    var v: u64 = 0;
    for k in 10 {
        if r.pos >= r.end { fail(r, ERR_TRUNCATED); return 0; }
        let c = r.buf[r.pos];
        r.pos++;
        v |= ((c & 0x7f) as u64) << (7 * k) as u64;
        if c < 0x80 { return v; }
    }
    fail(r, ERR_MALFORMED);   // more than 10 bytes
    return 0;
}

struct Node { id: i32, depth: i32, parent: i32, name_at: i64, name_len: i64 }

recursive fn decode_node(r: Reader&, pool: Node[>..]&, parent: i32) {
    let depth = r.depth;
    let me = pool.len as! i32;
    pool.push(Node { id: 0, depth: depth, parent: parent, name_at: 0, name_len: 0 });
    while r.pos < r.end {
        let tag = read_varint(r);
        let field = tag >> 3;
        if field == 1 {
            pool[me].id = read_varint(r) as! i32;
        } else if field == 2 {
            let n = read_varint(r) as! i64;
            if n > r.end - r.pos { fail(r, ERR_TRUNCATED); return; }
            if r.depth >= MAX_DEPTH { fail(r, ERR_DEPTH); return; }
            let outer = r.end;
            r.end = r.pos + n;
            r.depth++;
            decode_node(r, pool, me);
            if r.err != ERR_NONE { return; }
            r.depth--;
            r.end = outer;
        } else if field == 3 {
            let n = read_varint(r) as! i64;
            if n > r.end - r.pos { fail(r, ERR_TRUNCATED); return; }
            pool[me].name_at = r.pos;
            pool[me].name_len = n;
            r.pos += n;
        } else {
            fail(r, ERR_MALFORMED);   // the real decoder skips unknown fields
        }
    }
}

fn decode(buf: const u8[:], pool: Node[>..]&) -> i32 {
    var r = Reader { buf: buf, pos: 0, end: buf.len, err: ERR_NONE, depth: 0 };
    decode_node(r, pool, -1);
    return r.err;
}

fn main() {
    if bench_requested() { bench("sticky"); return; }
    // Node{id 1, children [Node{id 2, children [Node{id 3}]}]}
    let ok: u8[10] = [0x08, 0x01, 0x12, 0x06, 0x08, 0x02, 0x12, 0x02, 0x08, 0x03];
    var pool: Node[>..] = [];
    print("ok: err=", decode(ok, pool), " nodes=", pool.len, " deepest id=", pool[2].id);
    pool.resize(0);
    print("truncated: err=", decode(ok[..8], pool));
    pool.resize(0);
    // depth 5
    let deep: u8[10] = [0x12, 0x08, 0x12, 0x06, 0x12, 0x04, 0x12, 0x02, 0x12, 0x00];
    print("deep: err=", decode(deep, pool));
    pool.resize(0);
    let long_varint: u8[12] = [0x08, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01];
    print("long varint: err=", decode(long_varint, pool));
    pool.resize(0);
    // child claims 4 bytes but its parent's window has only 2 left; the buffer has more
    let overrun: u8[8] = [0x12, 0x03, 0x12, 0x04, 0x08, 0x01, 0x08, 0x02];
    print("overrun: err=", decode(overrun, pool));
}
