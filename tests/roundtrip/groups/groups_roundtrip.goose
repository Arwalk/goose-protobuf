// Round-trip test for tests/protos/groups.proto (gpb-6xy.5).
// Run: scripts/roundtrip.sh groups
import pb_wire;
import groups;

var failures = 0;

fn fail_at(what: u8[:], detail: u8[:]) {
    failures += 1;
    print("FAIL ", what, ": ", detail);
}

fn encoded(m: grp::G&) -> u8[>..] {
    var out: u8[>..] = [];
    grp::G_encode(m, out);
    if grp::G_size_of(m) != out.len { fail_at("encoded", "size_of"); }
    return out;
}

fn check_all() {
    // Built through accessors, as protoc encodes it.
    let want = embed_file("all.bin");
    var m = grp::G { .. };
    let one .= grp::G_mutable_one(m);
    grp::G_One_set_a(one, 1);
    let inner .= grp::G_One_mutable_inner(one);
    grp::G_One_Inner_set_b(inner, 2);
    grp::G_One_Inner_set_s(inner, "x");
    grp::G_Many_set_c(grp::G_add_many(m), 3);
    grp::G_add_many(m);
    grp::G_Many_set_c(grp::G_add_many(m), 4);
    grp::G_Pg_set_d(grp::G_mutable_pg(m), 5);
    let am .= grp::G_mutable_as_message(m);
    grp::G_One_set_a(am, 6);
    grp::G_One_Inner_set_b(grp::G_One_mutable_inner(am), 7);
    grp::G_set_after(m, 8);
    grp::G_Far_set_e(grp::G_mutable_far(m), 9);
    if encoded(m) != want { fail_at("all", "encoding differs from protoc"); }

    // Decoded back, with nothing left unknown.
    var b = grp::G { .. };
    if grp::G_decode(want, b) != PB_OK { fail_at("all", "decode"); }
    if b.pb_unknown.len != 0 { fail_at("all", "kept as unknown"); }
    let bo = grp::G_one(b);
    guard bo else { fail_at("all", "one"); return; }
    if bo.a != 1 { fail_at("all", "one a"); }
    let bi = grp::G_One_inner(bo);
    guard bi else { fail_at("all", "inner"); return; }
    if bi.b != 2 || grp::G_One_Inner_s(bi)[0] != 'x' { fail_at("all", "inner values"); }
    if grp::G_many_len(b) != 3 || grp::G_many_at(b, 2).c != 4 || grp::G_Many_has_c(grp::G_many_at(b, 1)) { fail_at("all", "many"); }
    if !grp::G_has_pg(b) { fail_at("all", "pg"); }
    if b.after != 8 { fail_at("all", "after"); }
    if !grp::G_has_far(b) { fail_at("all", "far"); }
    if encoded(b) != want { fail_at("all", "re-encoding differs"); }

    // A deep copy, and clearing.
    var c = grp::G { .. };
    grp::G_copy(c, b);
    grp::G_clear(b);
    if encoded(c) != want { fail_at("all", "copy differs"); }
    grp::G_clear(c);
    if grp::G_size_of(c) != 0 { fail_at("all", "clear"); }
    grp::G_clear(m);
}

fn check_wire() {
    var m = grp::G { .. };

    // Occurrences of a group merge; of a repeated one, append.
    let twice: u8[8] = [0x0b, 0x08, 1, 0x0c, 0x0b, 0x13, 0x14, 0x0c];
    if grp::G_decode(twice, m) != PB_OK { fail_at("merge", "decode"); }
    let o = grp::G_one(m);
    guard o else { fail_at("merge", "one"); return; }
    if o.a != 1 || !grp::G_One_has_inner(o) { fail_at("merge", "values"); }
    grp::G_clear(m);

    // An empty group is set.
    let empty: u8[2] = [0x0b, 0x0c];
    if grp::G_decode(empty, m) != PB_OK || !grp::G_has_one(m) { fail_at("empty", "not set"); }
    if encoded(m) != empty { fail_at("empty", "re-encoding"); }
    grp::G_clear(m);

    // Unknown fields inside a group, a group among them, stay in that group.
    let unk_whole: u8[10] = [0x0b, 0x48, 1, 0x53, 0x08, 1, 0x54, 0x08, 2, 0x0c];
    if grp::G_decode(unk_whole, m) != PB_OK { fail_at("unknown", "decode"); }
    if m.pb_unknown.len != 0 { fail_at("unknown", "left the group"); }
    let u1 = grp::G_one(m);
    guard u1 else { fail_at("unknown", "one"); return; }
    if u1.a != 2 || u1.pb_unknown.len != 6 { fail_at("unknown", "in the group"); }
    grp::G_clear(m);

    // An end tag that is not canonical still ends the group.
    let long_end: u8[5] = [0x0b, 0x08, 1, 0x8c, 0x00];
    if grp::G_decode(long_end, m) != PB_OK { fail_at("long end", "decode"); }
    let le = grp::G_one(m);
    guard le else { fail_at("long end", "one"); return; }
    if le.a != 1 { fail_at("long end", "value"); }
    grp::G_clear(m);

    // Another wire type is unknown both ways: a length on a group field, a group
    // on a field that is not one.
    let as_len: u8[2] = [0x0a, 0];
    if grp::G_decode(as_len, m) != PB_OK || grp::G_has_one(m) || m.pb_unknown.len != 2 { fail_at("wire", "length"); }
    grp::G_clear(m);
    let as_grp: u8[2] = [0x2b, 0x2c];
    if grp::G_decode(as_grp, m) != PB_OK || grp::G_has_as_message(m) || m.pb_unknown.len != 2 { fail_at("wire", "group"); }
    grp::G_clear(m);

    // A group that another member of its oneof replaces is freed.
    let swap: u8[6] = [0x1b, 0x1c, 0x20, 1, 0x1b, 0x1c];
    if grp::G_decode(swap, m) != PB_OK || !grp::G_has_pg(m) || grp::G_has_other(m) { fail_at("oneof", "last member"); }
    grp::G_clear(m);
}

fn check_rejected() {
    var m = grp::G { .. };
    let wrong_end: u8[2] = [0x0b, 0x14];
    if grp::G_decode(wrong_end, m) != PB_ERR_MALFORMED { fail_at("rejected", "another group's end"); }
    grp::G_clear(m);
    let nested_end: u8[4] = [0x0b, 0x13, 0x0c, 0x14];
    if grp::G_decode(nested_end, m) != PB_ERR_MALFORMED { fail_at("rejected", "crossed ends"); }
    grp::G_clear(m);
    let no_end: u8[3] = [0x0b, 0x08, 1];
    if grp::G_decode(no_end, m) != PB_ERR_TRUNCATED { fail_at("rejected", "no end"); }
    grp::G_clear(m);
    let stray: u8[1] = [0x0c];
    if grp::G_decode(stray, m) != PB_ERR_MALFORMED { fail_at("rejected", "stray end"); }
    grp::G_clear(m);
    // The end of a group cannot be inside a length-delimited field in it.
    let in_field: u8[4] = [0x0b, 0x12 + 0x40, 1, 0x0c];
    if grp::G_decode(in_field, m) != PB_ERR_TRUNCATED { fail_at("rejected", "end inside a field"); }
    grp::G_clear(m);
    // Nor a message's end cross it: an end tag inside a sub-message is its own.
    let in_sub: u8[5] = [0x2a, 1, 0x0c, 0x0b, 0x0c];
    if grp::G_decode(in_sub, m) != PB_ERR_MALFORMED { fail_at("rejected", "end inside a sub-message"); }
    grp::G_clear(m);
}

// `levels` of a Rec holding a Rec in a group, each two levels of nesting.
fn nested(levels: i64) -> u8[>..] {
    var buf: u8[>..] = [];
    for i in levels {
        var next: u8[>..] = [];
        next.push(0x0b);
        next.push(0x0a);
        pb_write_varint(next, buf.len as! u64);
        next.append(buf);
        next.push(0x0c);
        buf = copy(next);
    }
    return buf;
}

fn check_depth() {
    var m = grp::Rec { .. };
    let fits = nested(49);
    if grp::Rec_decode(fits, m) != PB_OK { fail_at("depth", "98 levels"); }
    var out: u8[>..] = [];
    grp::Rec_encode(m, out);
    if out != fits { fail_at("depth", "re-encoding"); }
    grp::Rec_clear(m);
    let deep = nested(60);
    if grp::Rec_decode(deep, m) != PB_ERR_DEPTH { fail_at("depth", "120 levels"); }
    grp::Rec_clear(m);
}

fn check_required() {
    var m = grp::ReqG { .. };
    let none: u8[0] = [];
    if grp::ReqG_decode(none, m) != PB_ERR_REQUIRED { fail_at("required", "no group"); }
    grp::ReqG_clear(m);
    let unset: u8[2] = [0x0b, 0x0c];
    if grp::ReqG_decode(unset, m) != PB_ERR_REQUIRED { fail_at("required", "field in the group"); }
    grp::ReqG_clear(m);
    let set: u8[4] = [0x0b, 0x08, 0, 0x0c];
    if grp::ReqG_decode(set, m) != PB_OK { fail_at("required", "set"); }
    grp::ReqG_clear(m);
    var h = grp::Holder { .. };
    let held: u8[4] = [0x0b, 0x0a, 0, 0x0c];
    if grp::Holder_decode(held, h) != PB_ERR_REQUIRED { fail_at("required", "through a group"); }
    grp::Holder_clear(h);
}

fn main() {
    check_all();
    check_wire();
    check_rejected();
    check_depth();
    check_required();
    if failures > 0 { abort(str(failures, " failures")); }
    print("ok");
}
