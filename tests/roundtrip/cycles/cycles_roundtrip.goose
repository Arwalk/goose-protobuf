// Round-trip test for tests/protos/cycles.proto (gpb-8qn.3).
// Run: scripts/roundtrip.sh cycles
import pb_wire;
import cycles;

var failures = 0;

fn fail_at(what: u8[:], detail: u8[:]) {
    failures += 1;
    print("FAIL ", what, ": ", detail);
}

fn bytes_eq(a: const u8[:], b: const u8[:]) -> bool {
    if a.len != b.len { return false; }
    for i in a.len { if a[i] != b[i] { return false; } }
    return true;
}

// `depth` messages nested in the first field `tag`, innermost holding
// `core`: what a depth-deep message of tag's type looks like inside its
// root.
fn nest(tag: u8, depth: i64, core: const u8[:]) -> u8[>..] {
    var b: u8[>..] = [];
    b.append(core);
    for i in depth {
        var w: u8[>..] = [];
        w.push(tag);
        pb_write_varint(w, b.len as! u64);
        w.append(b);
        b.resize(0);
        b.append(w);
    }
    return b;
}

fn check_node(name: u8[:], want: const u8[:]) {
    var m = cycles::Node { .. };
    let err = cycles::Node_decode(want, m);
    if err != PB_OK { fail_at(name, str("decode error ", err)); return; }
    var out: u8[>..] = [];
    cycles::Node_encode(m, out);
    if !bytes_eq(out, want) { fail_at(name, "re-encode differs"); }
    if cycles::Node_size_of(m) != want.len { fail_at(name, "size_of"); }
    cycles::Node_clear(m);
    if cycles::Node_size_of(m) != 0 || cycles::Node_has_child(m) { fail_at(name, "clear"); }
}

fn check_ping(name: u8[:], want: const u8[:]) {
    var m = cycles::Ping { .. };
    let err = cycles::Ping_decode(want, m);
    if err != PB_OK { fail_at(name, str("decode error ", err)); return; }
    var out: u8[>..] = [];
    cycles::Ping_encode(m, out);
    if !bytes_eq(out, want) { fail_at(name, "re-encode differs"); }
    if cycles::Ping_size_of(m) != want.len { fail_at(name, "size_of"); }
    cycles::Ping_clear(m);
    if cycles::Ping_size_of(m) != 0 { fail_at(name, "clear"); }
}

fn check_a(name: u8[:], want: const u8[:]) {
    var m = cycles::A { .. };
    if cycles::A_decode(want, m) != PB_OK { fail_at(name, "decode"); return; }
    var out: u8[>..] = [];
    cycles::A_encode(m, out);
    if !bytes_eq(out, want) { fail_at(name, "re-encode differs"); }
    cycles::A_clear(m);
    if cycles::A_size_of(m) != 0 { fail_at(name, "clear"); }
}

fn check_holder(name: u8[:], want: const u8[:]) {
    var m = cycles::Holder { .. };
    if cycles::Holder_decode(want, m) != PB_OK { fail_at(name, "decode"); return; }
    var out: u8[>..] = [];
    cycles::Holder_encode(m, out);
    if !bytes_eq(out, want) { fail_at(name, "re-encode differs"); }
    cycles::Holder_clear(m);
    if cycles::Holder_size_of(m) != 0 { fail_at(name, "clear"); }
}

fn check_built() {
    var m = cycles::Node { .. };
    m.v = 1;
    cycles::Node_set_name(m, "a");
    let c .= cycles::Node_mutable_child(m);
    c.v = 2;
    let d .= cycles::Node_mutable_child(c);
    cycles::Node_set_name(d, "c");
    cycles::Node_mutable_child(d);
    var out: u8[>..] = [];
    cycles::Node_encode(m, out);
    if !bytes_eq(out, embed_file("node.bin")) { fail_at("built", "encode differs from protoc"); }
    cycles::Node_clear_child(m);
    if cycles::Node_has_child(m) || m.v != 1 { fail_at("built", "clear_child"); }
    cycles::Node_clear(m);
}

fn check_merge() {
    var whole: u8[>..] = [];
    whole.append(embed_file("split_a.bin"));
    whole.append(embed_file("split_b.bin"));
    var m = cycles::Node { .. };
    if cycles::Node_decode(whole, m) != PB_OK { fail_at("merge", "decode"); return; }
    var out: u8[>..] = [];
    cycles::Node_encode(m, out);
    if !bytes_eq(out, embed_file("split_merged.bin")) { fail_at("merge", "not merged at every level"); }
    cycles::Node_clear(m);
}

// The number of messages nested below m.
recursive fn levels_below(m: cycles::Node&) -> i64 {
    let c = cycles::Node_child(m);
    guard c else { return 0; }
    return 1 + levels_below(c);
}

// Protobuf's limit: 100 nested messages decode, a 101st fails. The root
// does not count.
fn check_depth() {
    let v: u8[2] = [0x08, 0x07];   // v: 7, innermost

    let at100 = nest(0x12, 100, v);
    var m = cycles::Node { .. };
    let err = cycles::Node_decode(at100, m);
    if err != PB_OK { fail_at("depth 100", str("error ", err)); }
    if levels_below(m) != 100 { fail_at("depth 100", str(levels_below(m), " levels")); }
    var out: u8[>..] = [];
    cycles::Node_encode(m, out);
    if !bytes_eq(out, at100) { fail_at("depth 100", "re-encode differs"); }
    if cycles::Node_size_of(m) != at100.len { fail_at("depth 100", "size_of"); }
    cycles::Node_clear(m);

    let at101 = nest(0x12, 101, v);
    let e2 = cycles::Node_decode(at101, m);
    if e2 != PB_ERR_DEPTH { fail_at("depth 101", str("error ", e2)); }
    cycles::Node_clear(m);   // a partial message clears
    if cycles::Node_has_child(m) { fail_at("depth 101", "clear"); }

    // Far beyond the limit: a clean error, not a blown stack.
    let at5000 = nest(0x12, 5000, v);
    if cycles::Node_decode(at5000, m) != PB_ERR_DEPTH { fail_at("depth 5000", "no error"); }
    cycles::Node_clear(m);

    // Decoding from a second root starts at depth 0 again.
    if cycles::Node_decode(at100, m) != PB_OK { fail_at("depth 100 again", "error"); }
    cycles::Node_clear(m);

    // Mutual recursion counts every level: Ping.pong.ping...
    // Tag 0x0a is pong in Ping and ping in Pong; 100 levels end in a Ping.
    var ping = cycles::Ping { .. };
    let v_p: u8[2] = [0x10, 0x07];   // p: 7
    let pp100 = nest(0x0a, 100, v_p);
    if cycles::Ping_decode(pp100, ping) != PB_OK { fail_at("mutual depth 100", "error"); }
    cycles::Ping_clear(ping);
    let pp101 = nest(0x0a, 101, v_p);
    if cycles::Ping_decode(pp101, ping) != PB_ERR_DEPTH { fail_at("mutual depth 101", "no error"); }
    cycles::Ping_clear(ping);

    // A root that is not in the cycle still counts its first level.
    var h = cycles::Holder { .. };
    let inner100 = nest(0x12, 99, v);      // 99 inside node
    var buf: u8[>..] = [];
    buf.push(0x0a);
    pb_write_varint(buf, inner100.len as! u64);
    buf.append(inner100);
    if cycles::Holder_decode(buf, h) != PB_OK { fail_at("holder depth 100", "error"); }
    cycles::Holder_clear(h);
    let inner101 = nest(0x12, 100, v);
    var buf2: u8[>..] = [];
    buf2.push(0x0a);
    pb_write_varint(buf2, inner101.len as! u64);
    buf2.append(inner101);
    if cycles::Holder_decode(buf2, h) != PB_ERR_DEPTH { fail_at("holder depth 101", "no error"); }
    cycles::Holder_clear(h);

    // Unknown groups share the limit with message nesting.
    let group1: u8[2] = [0x7b, 0x7c];                 // field 15, one group
    let g_ok = nest(0x12, 99, group1);
    if cycles::Node_decode(g_ok, m) != PB_OK { fail_at("group at the limit", "error"); }
    cycles::Node_clear(m);
    let group2: u8[4] = [0x7b, 0x7b, 0x7c, 0x7c];     // two nested groups
    let g_deep = nest(0x12, 99, group2);
    if cycles::Node_decode(g_deep, m) != PB_ERR_DEPTH { fail_at("group over the limit", "no error"); }
    cycles::Node_clear(m);
}

// A failure deep inside restores nothing: the error reaches the top.
fn check_errors() {
    let bad: u8[2] = [0x1a, 0x05];                     // name: overruns
    let deep = nest(0x12, 50, bad);
    var m = cycles::Node { .. };
    if cycles::Node_decode(deep, m) != PB_ERR_TRUNCATED { fail_at("deep truncation", "no error"); }
    cycles::Node_clear(m);
    if cycles::Node_size_of(m) != 0 { fail_at("deep truncation", "clear"); }

    // A trailing field after a deep failure is not read as the parent's.
    let utf8: u8[4] = [0x1a, 0x02, 0xc0, 0x80];
    var buf = nest(0x12, 3, utf8);
    buf.push(0x08);
    buf.push(0x05);
    if cycles::Node_decode(buf, m) != PB_ERR_UTF8 { fail_at("deep utf8", "no error"); }
    if m.v != 0 { fail_at("deep utf8", "the parent read on"); }
    cycles::Node_clear(m);
}

// Clearing a deep message returns every slot.
fn check_reuse() {
    let v: u8[2] = [0x08, 0x07];
    let at100 = nest(0x12, 100, v);
    var m = cycles::Node { .. };
    if cycles::Node_decode(at100, m) != PB_OK { fail_at("reuse", "decode"); }
    cycles::Node_clear(m);
    let slots = cycles::Node_pool.len;
    for i in 5 {
        if cycles::Node_decode(at100, m) != PB_OK { fail_at("reuse", "decode"); }
        cycles::Node_clear(m);
    }
    if cycles::Node_pool.len != slots { fail_at("reuse", "the pool grew"); }
}

fn main() {
    check_node("node", embed_file("node.bin"));
    check_ping("ping", embed_file("ping.bin"));
    check_a("cycle3", embed_file("cycle3.bin"));
    check_holder("holder", embed_file("holder.bin"));
    check_built();
    check_merge();
    check_depth();
    check_errors();
    check_reuse();
    if failures != 0 { abort(str(failures, " failures")); }
    print("cycles round-trip: all passed");
}
