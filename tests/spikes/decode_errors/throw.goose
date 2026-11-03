// Variant T: wire primitives throw an i32 error code; the non-recursive
// entry catches it with exception::try. Decoders never check.
// message Node { int32 id = 1; repeated Node children = 2; bytes name = 3; }
import exception;

import .bench;

let ERR_TRUNCATED = 1;
let ERR_DEPTH = 2;

struct Reader { buf: const u8[:], pos: i64, end: i64 }

fn read_varint(r: Reader&) -> u64 {
    var v: u64 = 0;
    for k in 10 {
        if r.pos >= r.end { exception::throw(ERR_TRUNCATED); }
        let c = r.buf[r.pos];
        r.pos++;
        v |= ((c & 0x7f) as u64) << (7 * k) as u64;
        if c < 0x80 { return v; }
    }
    exception::throw(ERR_TRUNCATED);
}

fn read_len(r: Reader&) -> i64 {
    let n = read_varint(r);
    if n > (r.end - r.pos) as! u64 { exception::throw(ERR_TRUNCATED); }
    return n as! i64;
}

struct Node { id: i32, depth: i32, parent: i32, name_at: i64, name_len: i64 }

recursive fn decode_node(r: Reader&, pool: Node[>..]&, parent: i32, depth: i32) {
    if depth > 3 { exception::throw(ERR_DEPTH); }
    let me = pool.len as! i32;
    pool.push(Node { id: 0, depth: depth, parent: parent, name_at: 0, name_len: 0 });
    while r.pos < r.end {
        let tag = read_varint(r);
        let field = tag >> 3;
        if field == 1 {
            pool[me].id = read_varint(r) as! i32;
        } else if field == 2 {
            let n = read_len(r);
            let outer = r.end;
            r.end = r.pos + n;
            decode_node(r, pool, me, depth + 1);
            r.end = outer;
        } else if field == 3 {
            let n = read_len(r);
            pool[me].name_at = r.pos;
            pool[me].name_len = n;
            r.pos += n;
        } else {
            exception::throw(ERR_TRUNCATED);
        }
    }
}

fn decode(buf: const u8[:], pool: Node[>..]&) -> i32 {
    var r = Reader { buf: buf, pos: 0, end: buf.len };
    var err: i32 = 0;
    fn body() { decode_node(r, pool, -1, 0); }
    exception::try<i32>(body) { e => err = e; };
    return err;
}

fn main() {
    if bench_requested() { bench("throw"); return; }
    let ok: u8[10] = [0x08, 0x01, 0x12, 0x06, 0x08, 0x02, 0x12, 0x02, 0x08, 0x03];
    var pool: Node[>..] = [];
    print("ok: err=", decode(ok, pool), " nodes=", pool.len, " deepest id=", pool[2].id);
    pool.resize(0);
    print("truncated: err=", decode(ok[..8], pool));
    pool.resize(0);
    let deep: u8[10] = [0x12, 0x08, 0x12, 0x06, 0x12, 0x04, 0x12, 0x02, 0x12, 0x00];
    print("deep: err=", decode(deep, pool));
}
