// Round-trip test for tests/protos/editions.proto (gpb-buq.3).
// Run: scripts/roundtrip.sh editions
import pb_wire;
import editions;
import editions_file;

var failures = 0;

fn fail_at(what: u8[:], detail: u8[:]) {
    failures += 1;
    print("FAIL ", what, ": ", detail);
}

fn check_presence() {
    // Explicit: set at 0 is encoded. Implicit: 0 is not, and there is no has_.
    var m = ed2::Presence { .. };
    ed2::Presence_set_explicit_f(m, 0);
    m.implicit_f = 0;
    var out: u8[>..] = [];
    ed2::Presence_encode(m, out);
    let want: u8[2] = [0x08, 0];
    if out != want { fail_at("presence", "encoding"); }
    if !ed2::Presence_has_explicit_f(m) { fail_at("presence", "has_"); }
    ed2::Presence_clear(m);

    // Defaults: explicit [default], and the first value of a closed enum.
    if m.with_default != 7 || ed2::Presence_str_default(m)[0] != 'd' { fail_at("presence", "default"); }
    if m.first != ed2::Closed_C_ONE { fail_at("presence", "first enum value"); }
    m.implicit_f = 3;
    var out2: u8[>..] = [];
    ed2::Presence_encode(m, out2);
    let want2: u8[2] = [0x10, 3];
    if out2 != want2 || ed2::Presence_size_of(m) != 2 { fail_at("presence", "implicit set"); }
    ed2::Presence_clear(m);
    ed2::Presence_set_str_implicit(m, "");
    if ed2::Presence_size_of(m) != 0 { fail_at("presence", "implicit string"); }
    ed2::Presence_clear(m);
}

fn check_required() {
    var m = ed2::Req { .. };
    let none: u8[0] = [];
    if ed2::Req_decode(none, m) != PB_ERR_REQUIRED { fail_at("required", "unset accepted"); }
    ed2::Req_clear(m);
    let set: u8[2] = [0x08, 0];
    if ed2::Req_decode(set, m) != PB_OK || !ed2::Req_has_needed(m) { fail_at("required", "set rejected"); }
    ed2::Req_clear(m);
    var r = ed2::ReqSub { .. };
    let no_inner: u8[2] = [0x0a, 0];
    if ed2::ReqSub_decode(none, r) != PB_ERR_REQUIRED { fail_at("required", "message unset"); }
    ed2::ReqSub_clear(r);
    if ed2::ReqSub_decode(no_inner, r) != PB_ERR_REQUIRED { fail_at("required", "through a message"); }
    ed2::ReqSub_clear(r);
    // Through a delimited field.
    var d = ed2::Delimited { .. };
    let held: u8[4] = [0x33, 0x0a, 0, 0x34];
    if ed2::Delimited_decode(held, d) != PB_ERR_REQUIRED { fail_at("required", "through a delimited field"); }
    ed2::Delimited_clear(d);
}

fn check_enums() {
    var m = ed2::Enums { .. };
    // Open: stored whatever it is. Closed: unknown.
    let open: u8[2] = [0x08, 99];
    if ed2::Enums_decode(open, m) != PB_OK || m.open != 99 || m.pb_unknown.len != 0 { fail_at("enums", "open"); }
    ed2::Enums_clear(m);
    let closed: u8[2] = [0x10, 2];
    if ed2::Enums_decode(closed, m) != PB_OK || ed2::Enums_has_closed(m) || m.pb_unknown.len != 2 { fail_at("enums", "closed"); }
    ed2::Enums_clear(m);
    let good: u8[2] = [0x10, 5];
    if ed2::Enums_decode(good, m) != PB_OK || m.closed != ed2::Closed_C_FIVE { fail_at("enums", "closed known"); }
    ed2::Enums_clear(m);
    // Repeated, packed and not, oneof and map.
    let list: u8[4] = [0x1a, 2, 1, 2];
    if ed2::Enums_decode(list, m) != PB_OK || ed2::Enums_closed_packed(m).len != 1 || m.pb_unknown.len != 2 { fail_at("enums", "packed"); }
    ed2::Enums_clear(m);
    let exp: u8[4] = [0x20, 5, 0x20, 2];
    if ed2::Enums_decode(exp, m) != PB_OK || ed2::Enums_closed_expanded(m).len != 1 || m.pb_unknown.len != 2 { fail_at("enums", "expanded"); }
    ed2::Enums_clear(m);
    let member: u8[2] = [0x38, 2];
    if ed2::Enums_decode(member, m) != PB_OK || ed2::Enums_has_closed_member(m) || m.pb_unknown.len != 2 { fail_at("enums", "member"); }
    ed2::Enums_clear(m);
    let entry: u8[6] = [0x2a, 4, 0x08, 1, 0x10, 9];
    if ed2::Enums_decode(entry, m) != PB_OK || ed2::Enums_closed_map(m).len != 0 || m.pb_unknown.len != 6 { fail_at("enums", "closed map"); }
    ed2::Enums_clear(m);
    let open_entry: u8[6] = [0x32, 4, 0x08, 1, 0x10, 9];
    if ed2::Enums_decode(open_entry, m) != PB_OK || ed2::Enums_open_map(m).len != 1 || m.pb_unknown.len != 0 { fail_at("enums", "open map"); }
    ed2::Enums_clear(m);
}

fn check_repeats() {
    let want = embed_file("repeats.bin");
    var m = ed2::Repeats { .. };
    ed2::Repeats_add_packed_f(m, 1);
    ed2::Repeats_add_packed_f(m, 2);
    ed2::Repeats_add_expanded(m, 3);
    ed2::Repeats_add_expanded(m, 4);
    var out: u8[>..] = [];
    ed2::Repeats_encode(m, out);
    if out != want { fail_at("repeats", "encoding differs from protoc"); }
    ed2::Repeats_clear(m);

    // Features of the file reach nested messages, and a field overrides them.
    var o = edf::Overrides { .. };
    edf::Overrides_add_inherited(o, 1);
    edf::Overrides_add_packed_f(o, 2);
    let n .= edf::Overrides_mutable_nested(o);
    edf::Overrides_Nested_add_inherited(n, 3);
    var oo: u8[>..] = [];
    edf::Overrides_encode(o, oo);
    let want_o: u8[9] = [0x08, 1, 0x12, 1, 2, 0x1a, 2, 0x08, 3];
    if oo != want_o { fail_at("repeats", "overrides"); }
    edf::Overrides_clear(o);
    let unchecked: u8[5] = [0x1a, 3, 0x12, 1, 0xff];
    if edf::Overrides_decode(unchecked, o) != PB_OK { fail_at("repeats", "nested unchecked"); }
    edf::Overrides_clear(o);
    let checked: u8[5] = [0x1a, 3, 0x1a, 1, 0xff];
    if edf::Overrides_decode(checked, o) != PB_ERR_UTF8 { fail_at("repeats", "nested checked"); }
    edf::Overrides_clear(o);
}

fn check_utf8() {
    var m = ed2::Utf8 { .. };
    // tag, then a bad string, for the singular, repeated and oneof fields.
    let tags: u8[6] = [0x0a, 0x12, 0x1a, 0x22, 0x3a, 0x42];
    let want: i32[6] = [PB_ERR_UTF8, PB_OK, PB_ERR_UTF8, PB_OK, PB_ERR_UTF8, PB_OK];
    for i in 6 {
        let bad: u8[3] = [tags[i], 1, 0xff];
        if ed2::Utf8_decode(bad, m) != want[i] { fail_at("utf8", str("field with tag ", tags[i])); }
        ed2::Utf8_clear(m);
    }
    // A map's features go to its key and value.
    let key_v: u8[5] = [0x2a, 3, 0x0a, 1, 0xff];
    if ed2::Utf8_decode(key_v, m) != PB_ERR_UTF8 { fail_at("utf8", "verified key"); }
    ed2::Utf8_clear(m);
    let val_v: u8[5] = [0x2a, 3, 0x12, 1, 0xff];
    if ed2::Utf8_decode(val_v, m) != PB_ERR_UTF8 { fail_at("utf8", "verified value"); }
    ed2::Utf8_clear(m);
    let key_u: u8[5] = [0x32, 3, 0x0a, 1, 0xff];
    if ed2::Utf8_decode(key_u, m) != PB_OK { fail_at("utf8", "unchecked key"); }
    ed2::Utf8_clear(m);
    let val_u: u8[5] = [0x32, 3, 0x12, 1, 0xff];
    if ed2::Utf8_decode(val_u, m) != PB_OK { fail_at("utf8", "unchecked value"); }
    ed2::Utf8_clear(m);
}

fn check_delimited() {
    let want = embed_file("delimited.bin");
    var m = ed2::Delimited { .. };
    ed2::Sub_set_a(ed2::Delimited_mutable_prefixed(m), 1);
    ed2::Sub_set_a(ed2::Delimited_mutable_delimited(m), 2);
    ed2::Sub_set_a(ed2::Delimited_add_list_delimited(m), 3);
    ed2::Sub_set_a(ed2::Delimited_add_list_delimited(m), 4);
    ed2::Sub_set_a(ed2::Delimited_mutable_member_delimited(m), 5);
    var out: u8[>..] = [];
    ed2::Delimited_encode(m, out);
    if out != want { fail_at("delimited", "encoding differs from protoc"); }
    if ed2::Delimited_size_of(m) != want.len { fail_at("delimited", "size_of"); }
    ed2::Delimited_clear(m);
    if ed2::Delimited_decode(want, m) != PB_OK || m.pb_unknown.len != 0 { fail_at("delimited", "decode"); }
    if ed2::Delimited_list_delimited(m).len != 2 || !ed2::Delimited_has_member_delimited(m) { fail_at("delimited", "values"); }
    ed2::Delimited_clear(m);

    // The other member of the oneof is length-prefixed, as the field says.
    let lp: u8[4] = [0x2a, 2, 0x08, 1];
    if ed2::Delimited_decode(lp, m) != PB_OK || !ed2::Delimited_has_member_prefixed(m) { fail_at("delimited", "member override"); }
    ed2::Delimited_clear(m);
    // Each encoding on the wrong field is unknown.
    let wrong1: u8[2] = [0x13, 0x14];
    let wrong2: u8[2] = [0x0a, 0];
    if ed2::Delimited_decode(wrong2, m) != PB_OK || !ed2::Delimited_has_prefixed(m) { fail_at("delimited", "length on prefixed"); }
    ed2::Delimited_clear(m);
    if ed2::Delimited_decode(wrong1, m) != PB_OK || !ed2::Delimited_has_delimited(m) { fail_at("delimited", "group on delimited"); }
    ed2::Delimited_clear(m);
    let as_len: u8[2] = [0x12, 0];
    if ed2::Delimited_decode(as_len, m) != PB_OK || ed2::Delimited_has_delimited(m) || m.pb_unknown.len != 2 { fail_at("delimited", "length on delimited"); }
    ed2::Delimited_clear(m);
    let bad_end: u8[2] = [0x13, 0x1c];
    if ed2::Delimited_decode(bad_end, m) != PB_ERR_MALFORMED { fail_at("delimited", "another end"); }
    ed2::Delimited_clear(m);
}

fn check_file_features() {
    // All from the file; only what a field says differs. Bytes from protoc.
    let want = embed_file("file_all.bin");
    var m = edf::All { .. };
    if edf::All_decode(want, m) != PB_OK { fail_at("file", "decode"); }
    if m.pb_unknown.len != 0 { fail_at("file", "kept as unknown"); }
    if m.implicit_f != 1 || m.closed != edf::ClosedByFile_CB_ONE || edf::All_expanded(m).len != 2 { fail_at("file", "values"); }
    if !edf::All_has_explicit_f(m) || m.explicit_f != 0 || edf::All_packed_f(m).len != 2 { fail_at("file", "overrides"); }
    if edf::All_subs(m).len != 1 || m.open != edf::Inherited_I_TWO { fail_at("file", "map, enum"); }
    var out: u8[>..] = [];
    edf::All_encode(m, out);
    if out != want { fail_at("file", "re-encoding differs"); }
    if edf::All_size_of(m) != want.len { fail_at("file", "size_of"); }
    edf::All_clear(m);

    // The file makes strings unchecked, and enums closed; an enum may undo that.
    let u: u8[3] = [0x22, 1, 0xff];
    if edf::All_decode(u, m) != PB_OK { fail_at("file", "unchecked"); }
    edf::All_clear(m);
    let c: u8[3] = [0x52, 1, 0xff];
    if edf::All_decode(c, m) != PB_ERR_UTF8 { fail_at("file", "checked"); }
    edf::All_clear(m);
    let closed: u8[2] = [0x10, 9];
    if edf::All_decode(closed, m) != PB_OK || m.closed != 0 || m.pb_unknown.len != 2 { fail_at("file", "closed"); }
    edf::All_clear(m);
    let open: u8[2] = [0x58, 9];
    if edf::All_decode(open, m) != PB_OK || m.open != 9 || m.pb_unknown.len != 0 { fail_at("file", "open"); }
    edf::All_clear(m);

    // Across files: a closed enum and a delimited field inside the other file.
    var i = ed2::Imported { .. };
    let imp: u8[2] = [0x10, 9];
    if ed2::Imported_decode(imp, i) != PB_OK || i.closed != 0 || i.pb_unknown.len != 2 { fail_at("imported", "closed"); }
    ed2::Imported_clear(i);
}

fn main() {
    check_presence();
    check_required();
    check_enums();
    check_repeats();
    check_utf8();
    check_delimited();
    check_file_features();
    if failures > 0 { abort(str(failures, " failures")); }
    print("ok");
}
