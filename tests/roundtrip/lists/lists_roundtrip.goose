// Round-trip test for tests/protos/lists.proto (gpb-gp4.2).
// Run: scripts/roundtrip.sh lists
import pb_wire;
import lists;

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

fn check_lists(name: u8[:], input: const u8[:], want: const u8[:]) {
    var m = lists::Lists { .. };
    let err = lists::Lists_decode(input, m);
    if err != PB_OK { fail_at(name, str("decode error ", err)); return; }
    if m.pb_unknown.len != 0 { fail_at(name, "a field stayed unknown"); }
    var out: u8[>..] = [];
    lists::Lists_encode(m, out);
    if !bytes_eq(out, want) { fail_at(name, "encoding differs from protoc"); }
    if lists::Lists_size_of(m) != want.len { fail_at(name, str("size_of ", lists::Lists_size_of(m), " want ", want.len)); }
    lists::Lists_clear(m);
    if lists::Lists_size_of(m) != 0 || lists::Lists_names(m).len != 0 { fail_at(name, "clear"); }
}

fn check_values() {
    var m = lists::Lists { .. };
    if lists::Lists_decode(embed_file("many.bin"), m) != PB_OK { fail_at("values", "decode"); return; }
    if lists::Lists_names(m).len != 5 { fail_at("values", "names: empty strings count"); }
    if !bytes_eq(lists::Lists_names_at(m, 0), "first") || lists::Lists_names_at(m, 1).len != 0
        || !bytes_eq(lists::Lists_names_at(m, 2), "héllo") || !bytes_eq(lists::Lists_names_at(m, 4), "last") {
        fail_at("values", "names out of order");
    }
    let raw: u8[2] = [0xff, 0xfe];
    if !bytes_eq(lists::Lists_blobs_at(m, 2), raw) { fail_at("values", "blobs"); }
    if lists::Lists_items(m).len != 3 { fail_at("values", "items: empty messages count"); }
    let i0 .= lists::Lists_items_at(m, 0);
    if i0.id != 1 || !bytes_eq(lists::Item_label(i0), "one") { fail_at("values", "items[0]"); }
    if lists::Item_tags(i0).len != 3 || !bytes_eq(lists::Item_tags_at(i0, 2), "y") { fail_at("values", "items[0].tags"); }
    if lists::Lists_items_at(m, 1).id != 0 || lists::Lists_items_at(m, 2).id != 3 { fail_at("values", "items order"); }
    if lists::Lists_timeouts_at(m, 2).nanos != 3 { fail_at("values", "timeouts"); }
    if m.after != 7 { fail_at("values", "after"); }
    lists::Lists_clear(m);
}

fn check_built() {
    var m = lists::Lists { .. };
    lists::Lists_add_names(m, "first");
    lists::Lists_add_names(m, "");
    lists::Lists_add_names(m, "héllo");
    lists::Lists_add_names(m, "");
    lists::Lists_add_names(m, "last");
    let b0: u8[1] = [0x00];
    let b2: u8[2] = [0xff, 0xfe];
    lists::Lists_add_blobs(m, b0);
    lists::Lists_add_blobs(m, "");
    lists::Lists_add_blobs(m, b2);
    let i .= lists::Lists_add_items(m);
    i.id = 1;
    lists::Item_set_label(i, "one");
    lists::Item_add_tags(i, "x");
    lists::Item_add_tags(i, "");
    lists::Item_add_tags(i, "y");
    lists::Lists_add_items(m);
    // A reference from add_ survives adding others, and they it.
    let third .= lists::Lists_add_items(m);
    lists::Lists_add_timeouts(m).seconds = 1;
    lists::Lists_add_timeouts(m);
    lists::Lists_add_timeouts(m).nanos = 3;
    m.after = 7;
    third.id = 3;
    var out: u8[>..] = [];
    lists::Lists_encode(m, out);
    if !bytes_eq(out, embed_file("many.bin")) { fail_at("built", "encoding differs from protoc"); }

    // set_ replaces one value, also from its own contents.
    lists::Lists_set_names(m, 0, "changed");
    if !bytes_eq(lists::Lists_names_at(m, 0), "changed") { fail_at("built", "set_"); }
    lists::Lists_set_names(m, 0, lists::Lists_names_at(m, 0)[1..3]);
    if !bytes_eq(lists::Lists_names_at(m, 0), "ha") { fail_at("built", "set_ from itself"); }
    if !bytes_eq(lists::Lists_names_at(m, 4), "last") { fail_at("built", "set_ moved another value"); }

    lists::Lists_clear_items(m);
    if lists::Lists_items(m).len != 0 { fail_at("built", "clear_items"); }
    lists::Lists_clear_names(m);
    if lists::Lists_names(m).len != 0 { fail_at("built", "clear_names"); }
    lists::Lists_clear(m);
    if lists::Lists_size_of(m) != 0 { fail_at("built", "clear"); }
}

fn check_refs_stay() {
    var m = lists::Lists { .. };
    let first .= lists::Lists_add_items(m);
    first.id = 41;
    for i in 100 { lists::Lists_add_items(m).id = i as! i32; }
    if first.id != 41 { fail_at("refs", "a reference moved"); }
    first.id = 42;
    if lists::Lists_items_at(m, 0).id != 42 { fail_at("refs", "a write through it vanished"); }
    lists::Lists_clear(m);
}

// A second decode appends, and repeated messages never merge.
fn check_merge() {
    var whole: u8[>..] = [];
    whole.append(embed_file("merge_a.bin"));
    whole.append(embed_file("merge_b.bin"));
    check_lists("merge in one buffer", whole, embed_file("merge_all.bin"));

    var m = lists::Lists { .. };
    if lists::Lists_decode(embed_file("merge_a.bin"), m) != PB_OK { fail_at("merge", "a"); }
    let held .= lists::Lists_items_at(m, 0);
    if lists::Lists_decode(embed_file("merge_b.bin"), m) != PB_OK { fail_at("merge", "b"); }
    var out: u8[>..] = [];
    lists::Lists_encode(m, out);
    if !bytes_eq(out, embed_file("merge_all.bin")) { fail_at("merge", "two decode calls"); }
    if !(held .== lists::Lists_items_at(m, 0)) { fail_at("merge", "moved a message"); }
    lists::Lists_clear(m);
}

// Fields of one pool interleaved, the slack trimmed each time.
fn check_interleaved() {
    var buf: u8[>..] = [];
    for i in 300 {
        pb_write_varint(buf, 0x0a);   // names
        pb_write_varint(buf, 1);
        buf.push((97 + i % 26) as! u8);
        pb_write_varint(buf, 0x12);   // blobs
        pb_write_varint(buf, 2);
        buf.push(i as! u8);
        buf.push(0xff);
    }
    var m = lists::Lists { .. };
    if lists::Lists_decode(buf, m) != PB_OK { fail_at("interleaved", "decode"); return; }
    if lists::Lists_names(m).len != 300 || lists::Lists_blobs(m).len != 300 { fail_at("interleaved", "lengths"); }
    for i in 300 {
        if lists::Lists_names_at(m, i)[0] != (97 + i % 26) as! u8 { fail_at("interleaved", "names"); break; }
        if lists::Lists_blobs_at(m, i)[1] != 0xff { fail_at("interleaved", "blobs"); break; }
    }
    if lists::Lists_size_of(m) != buf.len { fail_at("interleaved", "size_of"); }
    lists::Lists_clear(m);
}

fn expect_error(name: u8[:], buf: const u8[:], want: i32) {
    var m = lists::Lists { .. };
    let err = lists::Lists_decode(buf, m);
    if err != want { fail_at(name, str("error ", err, " want ", want)); }
    lists::Lists_clear(m);
    if lists::Lists_size_of(m) != 0 { fail_at(name, "partial message did not clear"); }
}

fn check_errors() {
    let utf8: u8[4] = [0x0a, 0x02, 0xc0, 0x80];
    expect_error("invalid UTF-8 in a repeated string", utf8, PB_ERR_UTF8);
    let later: u8[7] = [0x0a, 0x01, 0x61, 0x0a, 0x02, 0xc0, 0x80];
    expect_error("invalid UTF-8 in a later value", later, PB_ERR_UTF8);
    let over: u8[3] = [0x0a, 0x05, 0x61];
    expect_error("a string overruns", over, PB_ERR_TRUNCATED);
    let msg: u8[3] = [0x1a, 0x05, 0x08];
    expect_error("a message overruns", msg, PB_ERR_TRUNCATED);
    // The second element is bad: the first is kept, to be cleared.
    let second: u8[7] = [0x1a, 0x02, 0x08, 0x01, 0x1a, 0x01, 0x08];
    expect_error("a value cut by its message", second, PB_ERR_TRUNCATED);

    // Invalid UTF-8 in bytes is data.
    let b: u8[4] = [0x12, 0x02, 0xc0, 0x80];
    var m = lists::Lists { .. };
    if lists::Lists_decode(b, m) != PB_OK || lists::Lists_blobs(m).len != 1 { fail_at("bytes", "rejected"); }
    lists::Lists_clear(m);

    // Another wire type is an unknown field.
    let wrong: u8[2] = [0x08, 0x01];
    if lists::Lists_decode(wrong, m) != PB_OK || m.pb_unknown.len != 2 || lists::Lists_names(m).len != 0 {
        fail_at("wire type", "not unknown");
    }
    lists::Lists_clear(m);

    // A map stays an unknown field.
    let entry: u8[7] = [0x32, 0x05, 0x0a, 0x01, 0x6b, 0x10, 0x07];
    if lists::Lists_decode(entry, m) != PB_OK || m.pb_unknown.len != 7 { fail_at("map", "not unknown"); }
    lists::Lists_clear(m);
}

recursive fn depth_of(t: lists::Tree&) -> i64 {
    var deepest: i64 = 0;
    for i in lists::Tree_children(t).len {
        let d = 1 + depth_of(lists::Tree_children_at(t, i));
        if d > deepest { deepest = d; }
    }
    return deepest;
}

fn nest(depth: i64) -> u8[>..] {
    var b: u8[>..] = [];
    for i in depth {
        var w: u8[>..] = [];
        w.push(0x12);                                  // children
        pb_write_varint(w, b.len as! u64);
        w.append(b);
        b.resize(0);
        b.append(w);
    }
    return b;
}

fn check_recursive() {
    let want = embed_file("tree.bin");
    var t = lists::Tree { .. };
    if lists::Tree_decode(want, t) != PB_OK { fail_at("tree", "decode"); return; }
    var out: u8[>..] = [];
    lists::Tree_encode(t, out);
    if !bytes_eq(out, want) { fail_at("tree", "re-encode"); }
    if lists::Tree_size_of(t) != want.len { fail_at("tree", "size_of"); }
    if depth_of(t) != 2 { fail_at("tree", "depth"); }
    if !bytes_eq(lists::Tree_name(lists::Tree_children_at(lists::Tree_children_at(t, 0), 0)), "b") { fail_at("tree", "name"); }
    lists::Tree_clear(t);

    let at100 = nest(100);
    if lists::Tree_decode(at100, t) != PB_OK { fail_at("depth 100", "error"); }
    if depth_of(t) != 100 { fail_at("depth 100", "levels"); }
    lists::Tree_clear(t);
    let at101 = nest(101);
    if lists::Tree_decode(at101, t) != PB_ERR_DEPTH { fail_at("depth 101", "no error"); }
    lists::Tree_clear(t);
    if lists::Tree_children(t).len != 0 { fail_at("depth 101", "clear"); }

    let fw = embed_file("forest.bin");
    var f = lists::Forest { .. };
    if lists::Forest_decode(fw, f) != PB_OK { fail_at("forest", "decode"); return; }
    var fo: u8[>..] = [];
    lists::Forest_encode(f, fo);
    if !bytes_eq(fo, fw) { fail_at("forest", "re-encode"); }
    lists::Forest_clear(f);
}

fn check_copy() {
    let want = embed_file("many.bin");
    var src = lists::Lists { .. };
    if lists::Lists_decode(want, src) != PB_OK { fail_at("copy", "decode"); return; }
    var dst = lists::Lists { .. };
    lists::Lists_copy(dst, src);
    lists::Lists_clear(src);
    // Slots the source freed get reused: the copy must not be holding them.
    if lists::Lists_decode(embed_file("merge_b.bin"), src) != PB_OK { fail_at("copy", "reuse"); }
    var out: u8[>..] = [];
    lists::Lists_encode(dst, out);
    if !bytes_eq(out, want) { fail_at("copy", "encoding differs after clearing the source"); }
    lists::Lists_clear(src);
    lists::Lists_clear(dst);

    let tw = embed_file("tree.bin");
    var t = lists::Tree { .. };
    if lists::Tree_decode(tw, t) != PB_OK { fail_at("copy tree", "decode"); return; }
    var c = lists::Tree { .. };
    lists::Tree_copy(c, t);
    lists::Tree_clear(t);
    var o2: u8[>..] = [];
    lists::Tree_encode(c, o2);
    if !bytes_eq(o2, tw) { fail_at("copy tree", "encoding differs"); }
    lists::Tree_clear(c);
}

// Decoding, copying and clearing return every slot and run.
fn check_reuse() {
    let want = embed_file("many.bin");
    var m = lists::Lists { .. };
    var c = lists::Lists { .. };
    if lists::Lists_decode(want, m) != PB_OK { fail_at("reuse", "decode"); }
    lists::Lists_copy(c, m);
    lists::Lists_clear(c);
    lists::Lists_clear(m);
    let items = lists::Item_pool.len;
    let links = lists::Item_links.len;
    let spans = pb_spans.len;
    let bytes = pb_bytes.len;
    for i in 5 {
        if lists::Lists_decode(want, m) != PB_OK { fail_at("reuse", "decode"); }
        lists::Lists_copy(c, m);
        lists::Lists_clear(c);
        lists::Lists_clear(m);
    }
    if lists::Item_pool.len != items || lists::Item_links.len != links || pb_spans.len != spans || pb_bytes.len != bytes {
        fail_at("reuse", "the pools grew");
    }
}

fn main() {
    check_lists("none", embed_file("none.bin"), embed_file("none.bin"));
    check_lists("one", embed_file("one.bin"), embed_file("one.bin"));
    check_lists("many", embed_file("many.bin"), embed_file("many.bin"));
    check_values();
    check_built();
    check_refs_stay();
    check_merge();
    check_interleaved();
    check_errors();
    check_recursive();
    check_copy();
    check_reuse();
    if failures != 0 { abort(str(failures, " failures")); }
    print("lists round-trip: all passed");
}
