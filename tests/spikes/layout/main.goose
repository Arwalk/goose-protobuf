// Round-trip check for layout.goose. Run: goose run main.goose --debug
import layout;

fn check(ok: bool, what: u8[:]) {
    if !ok { abort(what); }
    print("ok   ", what);
}

fn build(root: Node&) {
    // root
    //   name "root", attrs {a: "1", b: "2"}
    //   child "c0" with grandchildren "g0", "g1" (attrs {x: "y"} on g1)
    //   child "c1"
    Node_set_name(root, "root");
    Node_attrs_put(root, "a", "1");
    Node_attrs_put(root, "b", "2");
    let c0 .= Node_add_children(root);
    Node_set_name(c0, "c0");
    let g0 .= Node_add_children(c0);
    Node_set_name(g0, "g0");
    let g1 .= Node_add_children(c0);
    Node_set_name(g1, "g1");
    Node_attrs_put(g1, "x", "y");
    let c1 .= Node_add_children(root);
    Node_set_name(c1, "c1");
}

fn main() {
    var root = Node { .. };
    build(root);
    var wire: u8[>..] = [];
    Node_encode(root, wire);
    check(wire.len == Node_size_of(root), "size_of matches encode");

    var back = Node { .. };
    check(Node_decode(wire, back) == PB_OK, "decode ok");
    check(pb_bytes_equal(Node_name(back), "root"), "root name");
    check(Node_children(back).len == 2, "2 children");
    check(Node_children(Node_children_at(back, 0)).len == 2, "2 grandchildren");
    check(pb_bytes_equal(Node_name(Node_children_at(Node_children_at(back, 0), 1)), "g1"), "grandchild name");
    let v, found = Node_attrs_get(Node_children_at(Node_children_at(back, 0), 1), "x");
    check(found && pb_bytes_equal(v, "y"), "grandchild map entry");
    let b, has_b = Node_attrs_get(back, "b");
    check(has_b && pb_bytes_equal(b, "2"), "root map entry");

    var again: u8[>..] = [];
    Node_encode(back, again);
    check(pb_bytes_equal(wire, again), "re-encode is byte-identical");

    // Records are flat: a message can live in the caller's own array.
    var batch: Node[>..] = [];
    batch.push(Node { .. });
    batch.push(Node { .. });
    check(Node_decode(wire, batch[1]) == PB_OK
          && Node_children(Node_children_at(batch[1], 0)).len == 2, "decode into an array element");
    for &m in batch { Node_clear(m); }

    // A child reference survives adding siblings (one slot per message).
    var parent = Node { .. };
    let first .= Node_add_children(parent);
    Node_add_children(first);
    for i in 100 { Node_add_children(parent); }
    Node_set_name(first, "first");
    check(pb_bytes_equal(Node_name(Node_children_at(parent, 0)), "first"),
          "child reference stable across appends");
    Node_clear(parent);

    // Duplicate map key on the wire: the last value wins.
    var dup: u8[>..] = [];
    for val in ["1", "2"] {
        dup.push(0x1a); dup.push(6);
        dup.push(0x0a); dup.push(1); dup.push('k');
        dup.push(0x12); dup.push(1); dup.append(val);
    }
    var d = Node { .. };
    check(Node_decode(dup, d) == PB_OK && d.attrs.len == 1, "duplicate key: one entry");
    let dv, _ = Node_attrs_get(d, "k");
    check(pb_bytes_equal(dv, "2"), "duplicate key: last wins");

    // Truncated input: an error, and the partial message frees cleanly.
    var t = Node { .. };
    check(Node_decode(wire[..wire.len - 3], t) == PB_ERR_TRUNCATED, "truncated input fails");
    Node_clear(t);

    // Freeing everything returns every slot: rebuilding reuses them.
    let nodes_before = Node_pool.len;
    let bytes_before = pb_bytes.len;
    Node_clear(root);
    Node_clear(back);
    Node_clear(d);
    var rebuilt = Node { .. };
    build(rebuilt);
    Node_clear(rebuilt);
    check(Node_pool.len == nodes_before && pb_bytes.len == bytes_before,
          "free + rebuild reuses pool slots");
    print("pools: ", Node_pool.len, " Node slots, ", pb_bytes.len, " bytes, ",
          Node_AttrsEntry_pool.len, " map entries");
}
