// Spike gpb-wof.1: message storage layout (docs/decisions/0001-message-layout.md).
// Hand-written stand-in for what protoc-gen-goose would emit for
//   message Node {
//     bytes name = 1;
//     repeated Node children = 2;
//     map<string, bytes> attrs = 3;
//   }
// Records are fixed-size; their variable parts live in global reusable
// pools and are reached through pb_Span runs and pool-relative links.
// Check: goose run main.goose --debug

import std;

// ---------------------------------------------------------------- runtime
// (pb_wire). Error idiom from docs/decisions/0004-decode-errors.md.

let PB_OK = 0;
let PB_ERR_TRUNCATED = 1;
let PB_ERR_MALFORMED = 2;
let PB_ERR_DEPTH = 3;
let PB_MAX_DEPTH = 100;

struct pb_Reader { buf: const u8[:], pos: i64, end: i64, err: i32, depth: i32 }

fn pb_fail(r: pb_Reader&, code: i32) {
    if r.err == PB_OK { r.err = code; }
    r.pos = r.end;
}

fn pb_read_varint(r: pb_Reader&) -> u64 {
    var v: u64 = 0;
    for k in 10 {
        if r.pos >= r.end { pb_fail(r, PB_ERR_TRUNCATED); return 0; }
        let c = r.buf[r.pos];
        r.pos++;
        v |= ((c & 0x7f) as u64) << (7 * k) as u64;
        if c < 0x80 { return v; }
    }
    pb_fail(r, PB_ERR_MALFORMED);
    return 0;
}

fn pb_read_len(r: pb_Reader&) -> i64 {
    let n = pb_read_varint(r);
    if n > (r.end - r.pos) as! u64 { pb_fail(r, PB_ERR_TRUNCATED); return 0; }
    return n as! i64;
}

fn pb_write_varint(out: u8[>..]&, v: u64) {
    var x = v;
    while x >= 0x80 {
        out.push((x & 0x7f | 0x80) as! u8);
        x >>= 7;
    }
    out.push(x as! u8);
}

fn pb_varint_size(v: u64) -> i64 {
    var n = 1;
    var x = v;
    while x >= 0x80 { x >>= 7; n++; }
    return n;
}

// A run in a slice pool: elements [at, at + len). Records hold spans, not
// slices, so they stay flat (no references): a slice loaded from a field
// would not be rooted at its pool, which recursion over pools needs.
struct pb_Span { at: u32, len: u32 }

// Every string and bytes field's contents are a run in this pool.
reusable[] var pb_bytes: u8[>..] = [];

fn pb_run<T>(pool: T[>..]&, s: pb_Span) -> T[:] {
    let lo: i64 = s.at;
    return pool[lo..lo + s.len];
}

// Resizes run s of pool to n elements (new ones default) and returns it.
fn pb_resize<T>(pool: T[>..]&, s: pb_Span, n: i64) -> pb_Span {
    if n == 0 {
        if s.len > 0 { pool.free_slice(pb_run(pool, s)); }
        return pb_Span { at: 0, len: 0 };
    }
    if s.len == 0 {
        let r = pool.alloc_slice(n);
        return pb_Span { at: pool.index_of(r[0]) as! u32, len: n as! u32 };
    }
    let r = pool.realloc_slice(pb_run(pool, s), n);
    return pb_Span { at: pool.index_of(r[0]) as! u32, len: n as! u32 };
}

fn pb_bytes_new(src: const u8[:]) -> pb_Span {
    let s = pb_resize(pb_bytes, pb_Span { at: 0, len: 0 }, src.len);
    copy_into(pb_run(pb_bytes, s), src);
    return s;
}

fn pb_bytes_free(s: pb_Span) { pb_resize(pb_bytes, s, 0); }

fn pb_read_bytes(r: pb_Reader&) -> pb_Span {
    let n = pb_read_len(r);
    let s = pb_bytes_new(r.buf[r.pos..r.pos + n]);
    r.pos += n;
    return s;
}

fn pb_bytes_equal(a: const u8[:], b: const u8[:]) -> bool {
    if a.len != b.len { return false; }
    for i in a.len { if a[i] != b[i] { return false; } }
    return true;
}

// ------------------------------------------------------------- generated

struct Node_AttrsEntry { key: pb_Span, value: pb_Span }

// Fixed-size and flat: a Node can be a local, a global, an array element.
struct Node {
    name: pb_Span,        // bytes, in pb_bytes
    children: pb_Span,    // links into Node_pool, in Node_links
    attrs: pb_Span,       // Node_AttrsEntry, in Node_AttrsEntry_pool
}

// One slot per sub-message, so a Node& stays valid while siblings are
// added; a repeated field is a run of 4-byte links.
reusable var Node_pool: Node[>..] = [];
// A link is wrapped in a struct: index_of cannot name a bare link's slot.
struct Node_Ref { m: Node&<u32 in Node_pool>? }
reusable[] var Node_links: Node_Ref[>..] = [];
reusable[] var Node_AttrsEntry_pool: Node_AttrsEntry[>..] = [];

fn Node_name(m: Node&) -> u8[:] { return pb_run(pb_bytes, m.name); }
fn Node_children(m: Node&) -> Node_Ref[:] { return pb_run(Node_links, m.children); }
// The i-th child. Links are optional only because a slice pool fills new
// slots with a default; every link of a finished message is set.
fn Node_children_at(m: Node&, i: i64) -> Node& {
    let l = Node_children(m)[i].m;
    assert(l);
    return l;
}
fn Node_attrs(m: Node&) -> Node_AttrsEntry[:] { return pb_run(Node_AttrsEntry_pool, m.attrs); }
fn Node_AttrsEntry_key(e: Node_AttrsEntry&) -> u8[:] { return pb_run(pb_bytes, e.key); }
fn Node_AttrsEntry_value(e: Node_AttrsEntry&) -> u8[:] { return pb_run(pb_bytes, e.value); }

fn Node_set_name(m: Node&, v: const u8[:]) {
    pb_bytes_free(m.name);
    m.name = pb_bytes_new(v);
}

// Appends an empty child and returns it; it stays valid until m is cleared.
fn Node_add_children(m: Node&) -> Node& {
    let n = m.children.len;
    m.children = pb_resize(Node_links, m.children, n + 1);
    let c .= Node_pool.alloc_ref(Node { .. });
    Node_children(m)[n].m .= c;
    return c;
}

// Map lookup: the value, and whether the key is present.
fn Node_attrs_get(m: Node&, key: const u8[:]) -> u8[:], bool {
    for &e in Node_attrs(m) {
        if pb_bytes_equal(Node_AttrsEntry_key(e), key) { return Node_AttrsEntry_value(e), true; }
    }
    return pb_run(pb_bytes, pb_Span { at: 0, len: 0 }), false;
}

fn Node_attrs_put_span(m: Node&, key: pb_Span, value: pb_Span) {
    for &e in Node_attrs(m) {
        if pb_bytes_equal(Node_AttrsEntry_key(e), pb_run(pb_bytes, key)) {
            pb_bytes_free(key);
            pb_bytes_free(e.value);
            e.value = value;
            return;
        }
    }
    let n = m.attrs.len;
    m.attrs = pb_resize(Node_AttrsEntry_pool, m.attrs, n + 1);
    let e .= Node_attrs(m)[n];
    e.key = key;
    e.value = value;
}

fn Node_attrs_put(m: Node&, key: const u8[:], value: const u8[:]) {
    Node_attrs_put_span(m, pb_bytes_new(key), pb_bytes_new(value));
}

// Frees everything m owns and resets it to empty. m itself is the caller's.
recursive fn Node_clear(m: Node&) {
    pb_bytes_free(m.name);
    for ref in Node_children(m) {
        let l = ref.m;
        guard l else { continue; }       // slack slots of an interrupted decode
        Node_clear(l);
        Node_pool.free(Node_pool.index_of(l));
    }
    pb_resize(Node_links, m.children, 0);
    for &e in Node_attrs(m) { pb_bytes_free(e.key); pb_bytes_free(e.value); }
    pb_resize(Node_AttrsEntry_pool, m.attrs, 0);
    m.name = pb_Span { at: 0, len: 0 };
    m.children = pb_Span { at: 0, len: 0 };
    m.attrs = pb_Span { at: 0, len: 0 };
}

fn Node_AttrsEntry_size_of(e: Node_AttrsEntry&) -> i64 {
    var n: i64 = 0;
    if e.key.len > 0 { n += 1 + pb_varint_size(e.key.len) + e.key.len; }
    if e.value.len > 0 { n += 1 + pb_varint_size(e.value.len) + e.value.len; }
    return n;
}

recursive fn Node_size_of(m: Node&) -> i64 {
    var n: i64 = 0;
    if m.name.len > 0 { n += 1 + pb_varint_size(m.name.len) + m.name.len; }
    for ref in Node_children(m) {
        let l = ref.m;
        guard l else { continue; }
        let k = Node_size_of(l);
        n += 1 + pb_varint_size(k as! u64) + k;
    }
    for &e in Node_attrs(m) {
        let k = Node_AttrsEntry_size_of(e);
        n += 1 + pb_varint_size(k as! u64) + k;
    }
    return n;
}

fn pb_write_bytes_field(out: u8[>..]&, tag: u8, s: pb_Span) {
    if s.len == 0 { return; }
    out.push(tag);
    pb_write_varint(out, s.len);
    out.append(pb_run(pb_bytes, s));
}

recursive fn Node_encode(m: Node&, out: u8[>..]&) {
    pb_write_bytes_field(out, 0x0a, m.name);
    for ref in Node_children(m) {
        let l = ref.m;
        guard l else { continue; }
        out.push(0x12);
        pb_write_varint(out, Node_size_of(l) as! u64);
        Node_encode(l, out);
    }
    for &e in Node_attrs(m) {
        out.push(0x1a);
        pb_write_varint(out, Node_AttrsEntry_size_of(e) as! u64);
        pb_write_bytes_field(out, 0x0a, e.key);
        pb_write_bytes_field(out, 0x12, e.value);
    }
}

fn Node_AttrsEntry_decode_from(r: pb_Reader&, m: Node&) {
    var key = pb_Span { at: 0, len: 0 };
    var value = pb_Span { at: 0, len: 0 };
    while r.pos < r.end {
        let tag = pb_read_varint(r);
        if tag == 0x0a { pb_bytes_free(key); key = pb_read_bytes(r); }
        else if tag == 0x12 { pb_bytes_free(value); value = pb_read_bytes(r); }
        else { pb_fail(r, PB_ERR_MALFORMED); }   // the real decoder skips unknown fields
    }
    Node_attrs_put_span(m, key, value);          // the last value for a key wins
}

// Merges fields from r's window into m (see 0004).
recursive fn Node_decode_from(r: pb_Reader&, m: Node&) {
    // Repeated runs grow by doubling while decoding and are trimmed at the
    // end; children_len is the used part of m.children.
    var children_len = m.children.len;
    while r.pos < r.end {
        let tag = pb_read_varint(r);
        if tag == 0x0a {
            pb_bytes_free(m.name);
            m.name = pb_read_bytes(r);
        } else if tag == 0x12 {
            let n = pb_read_len(r);
            if r.err != PB_OK { break; }
            if r.depth >= PB_MAX_DEPTH { pb_fail(r, PB_ERR_DEPTH); break; }
            if children_len == m.children.len {
                m.children = pb_resize(Node_links, m.children, children_len * 2 + 1);
            }
            let c .= Node_pool.alloc_ref(Node { .. });
            Node_children(m)[children_len].m .= c;
            let outer = r.end;
            r.end = r.pos + n;
            r.depth++;
            Node_decode_from(r, c);
            children_len++;
            if r.err != PB_OK { break; }
            r.depth--;
            r.end = outer;
        } else if tag == 0x1a {
            let n = pb_read_len(r);
            if r.err != PB_OK { break; }
            let outer = r.end;
            r.end = r.pos + n;
            Node_AttrsEntry_decode_from(r, m);
            if r.err != PB_OK { break; }
            r.end = outer;
        } else {
            pb_fail(r, PB_ERR_MALFORMED);       // the real decoder skips unknown fields
        }
    }
    // Trim the doubling slack (on error too, so Node_clear frees every run).
    if children_len < m.children.len {
        m.children = pb_resize(Node_links, m.children, children_len);
    }
}

// Merges buf into m. 0 on success, else a PB_ERR_* code; m then holds a
// partial message, which the caller clears.
fn Node_decode(buf: const u8[:], m: Node&) -> i32 {
    var r = pb_Reader { buf: buf, pos: 0, end: buf.len, err: PB_OK, depth: 0 };
    Node_decode_from(r, m);
    return r.err;
}
