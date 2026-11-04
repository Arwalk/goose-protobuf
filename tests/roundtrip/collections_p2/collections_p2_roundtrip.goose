// Round-trip test for tests/protos/collections_p2.proto (gpb-6xy.8).
// Run: scripts/roundtrip.sh collections_p2
import pb_wire;
import collections_p2;

var failures = 0;

fn fail_at(what: u8[:], detail: u8[:]) {
    failures += 1;
    print("FAIL ", what, ": ", detail);
}

fn lists_out(m: c2::Lists&) -> u8[>..] {
    var out: u8[>..] = [];
    c2::Lists_encode(m, out);
    if c2::Lists_size_of(m) != out.len { fail_at("lists", "size_of"); }
    return out;
}

fn pick_out(m: c2::Pick&) -> u8[>..] {
    var out: u8[>..] = [];
    c2::Pick_encode(m, out);
    if c2::Pick_size_of(m) != out.len { fail_at("pick", "size_of"); }
    return out;
}

fn maps_out(m: c2::Maps&) -> u8[>..] {
    var out: u8[>..] = [];
    c2::Maps_encode(m, out);
    if c2::Maps_size_of(m) != out.len { fail_at("maps", "size_of"); }
    return out;
}

fn check_lists() {
    // protoc's bytes, built through accessors, and decoded and encoded back.
    let want = embed_file("lists.bin");
    var m = c2::Lists { .. };
    c2::Lists_add_ints(m, 1);
    c2::Lists_add_ints(m, -2);
    c2::Lists_add_packed_ints(m, 3);
    c2::Lists_add_packed_ints(m, -4);
    c2::Lists_add_strs(m, "a");
    c2::Lists_add_strs(m, "");
    let ff: u8[1] = [0xff];
    c2::Lists_add_byts(m, ff);
    c2::Sub_set_a(c2::Lists_add_subs(m), 1);
    c2::Lists_add_subs(m);
    c2::Lists_add_colors(m, c2::Color_GREEN);
    c2::Lists_add_colors(m, c2::Color_RED);
    c2::Lists_add_packed_colors(m, c2::Color_BLUE);
    c2::Lists_add_packed_colors(m, c2::Color_GREEN);
    c2::Lists_add_doubles(m, 1.5);
    c2::Lists_add_doubles(m, 0.0);
    c2::Lists_add_packed_doubles(m, 2.5);
    c2::Lists_add_packed_doubles(m, -0.5);
    c2::Lists_add_zigs(m, -1);
    c2::Lists_add_zigs(m, 2);
    c2::Lists_add_bools(m, true);
    c2::Lists_add_bools(m, false);
    c2::Lists_add_fars(m, c2::Far_FAR_TWO);
    if lists_out(m) != want { fail_at("lists", "encoding differs from protoc"); }

    var b = c2::Lists { .. };
    if c2::Lists_decode(want, b) != PB_OK { fail_at("lists", "decode"); }
    if b.pb_unknown.len != 0 { fail_at("lists", "kept as unknown"); }
    if c2::Lists_ints(b).len != 2 || c2::Lists_ints_at(b, 1) != -2 { fail_at("lists", "ints"); }
    if c2::Lists_strs(b).len != 2 || c2::Lists_strs_at(b, 0)[0] != 'a' { fail_at("lists", "strs"); }
    if c2::Sub_has_a(c2::Lists_subs_at(b, 1)) { fail_at("lists", "subs"); }
    if c2::Lists_packed_colors_at(b, 0) != c2::Color_BLUE { fail_at("lists", "colors"); }
    if lists_out(b) != want { fail_at("lists", "re-encoding differs"); }

    var c = c2::Lists { .. };
    c2::Lists_copy(c, b);
    c2::Lists_clear(b);
    if lists_out(c) != want { fail_at("lists", "copy differs"); }
    c2::Lists_clear(c);
    c2::Lists_clear(m);

    // Either form is read, whichever the field declares.
    let packed_form: u8[4] = [0x0a, 2, 1, 2];
    let unpacked_form: u8[4] = [0x10, 1, 0x10, 2];
    if c2::Lists_decode(packed_form, m) != PB_OK || c2::Lists_ints(m).len != 2 { fail_at("forms", "packed into unpacked"); }
    if c2::Lists_decode(unpacked_form, m) != PB_OK || c2::Lists_packed_ints(m).len != 2 { fail_at("forms", "unpacked into packed"); }
    if m.pb_unknown.len != 0 { fail_at("forms", "unknown"); }
    c2::Lists_clear(m);

    // A bad string is not rejected, repeated or not.
    let bad: u8[3] = [0x1a, 1, 0xff];
    if c2::Lists_decode(bad, m) != PB_OK || c2::Lists_strs_at(m, 0)[0] != 0xff { fail_at("lists", "utf8"); }
    c2::Lists_clear(m);
}

fn check_closed_lists() {
    var m = c2::Lists { .. };
    // Field 6, unpacked: each value on its own.
    let un: u8[6] = [0x30, 1, 0x30, 9, 0x30, 5];
    if c2::Lists_decode(un, m) != PB_OK { fail_at("closed", "decode"); }
    if c2::Lists_colors(m).len != 2 || c2::Lists_colors_at(m, 1) != c2::Color_BLUE { fail_at("closed", "colors"); }
    let un_out: u8[6] = [0x30, 1, 0x30, 5, 0x30, 9];
    if lists_out(m) != un_out { fail_at("closed", "unpacked re-encoding"); }
    c2::Lists_clear(m);

    // Field 7, packed: an unknown element leaves on its own, with an unpacked tag.
    let pk: u8[5] = [0x3a, 3, 1, 9, 5];
    if c2::Lists_decode(pk, m) != PB_OK { fail_at("closed", "packed decode"); }
    if c2::Lists_packed_colors(m).len != 2 || c2::Lists_packed_colors_at(m, 1) != c2::Color_BLUE { fail_at("closed", "packed colors"); }
    let pk_out: u8[6] = [0x3a, 2, 1, 5, 0x38, 9];
    if lists_out(m) != pk_out { fail_at("closed", "packed re-encoding"); }
    c2::Lists_clear(m);

    // Every element unknown; an overlong one keeps its bytes, a negative its ten.
    let all: u8[15] = [0x3a, 13, 0x89, 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01, 2];
    if c2::Lists_decode(all, m) != PB_OK { fail_at("closed", "all decode"); }
    if c2::Lists_packed_colors(m).len != 0 { fail_at("closed", "all stored"); }
    let all_out: u8[16] = [0x38, 0x89, 0x00, 0x38, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01, 0x38, 2];
    if lists_out(m) != all_out { fail_at("closed", "all re-encoding"); }
    c2::Lists_clear(m);

    // Field 12, declared unpacked and sent packed: 9 is not a value of Far.
    let fa2: u8[5] = [0x62, 3, 1, 9, 2];
    if c2::Lists_decode(fa2, m) != PB_OK { fail_at("closed", "fars decode"); }
    let fa_out: u8[6] = [0x60, 1, 0x60, 2, 0x60, 9];
    if lists_out(m) != fa_out { fail_at("closed", "fars re-encoding"); }
    c2::Lists_clear(m);

    // A truncated element fails.
    let tr: u8[3] = [0x3a, 1, 0x81];
    if c2::Lists_decode(tr, m) == PB_OK { fail_at("closed", "truncated accepted"); }
    c2::Lists_clear(m);
}

fn check_pick_case(name: u8[:], want: const u8[:], built: c2::Pick&) {
    if pick_out(built) != want { fail_at(name, "encoding differs from protoc"); }
    var b = c2::Pick { .. };
    if c2::Pick_decode(want, b) != PB_OK { fail_at(name, "decode"); }
    if b.pb_unknown.len != 0 { fail_at(name, "kept as unknown"); }
    if pick_out(b) != want { fail_at(name, "re-encoding differs"); }
    var c = c2::Pick { .. };
    c2::Pick_copy(c, b);
    c2::Pick_clear(b);
    if pick_out(c) != want { fail_at(name, "copy differs"); }
    c2::Pick_clear(c);
    c2::Pick_clear(built);
}

fn check_pick() {
    var m = c2::Pick { .. };
    c2::Pick_set_i(m, 5); c2::Pick_set_after(m, 9);
    if !c2::Pick_has_i(m) || c2::Pick_i(m) != 5 { fail_at("pick", "i"); }
    check_pick_case("pick i", embed_file("pick_i.bin"), m);
    c2::Pick_set_s(m, "x"); c2::Pick_set_after(m, 9);
    check_pick_case("pick s", embed_file("pick_s.bin"), m);
    let ff: u8[1] = [0xff];
    c2::Pick_set_b(m, ff); c2::Pick_set_after(m, 9);
    check_pick_case("pick b", embed_file("pick_b.bin"), m);
    c2::Sub_set_a(c2::Pick_mutable_m(m), 2); c2::Pick_set_after(m, 9);
    check_pick_case("pick m", embed_file("pick_m.bin"), m);
    c2::Pick_set_c(m, c2::Color_BLUE); c2::Pick_set_after(m, 9);
    check_pick_case("pick c", embed_file("pick_c.bin"), m);
    c2::Pick_set_f(m, c2::Far_FAR_TWO); c2::Pick_set_after(m, 9);
    check_pick_case("pick f", embed_file("pick_f.bin"), m);

    // The last member wins, and a value of 0 is encoded.
    let last: u8[4] = [0x08, 1, 0x28, 0];
    if c2::Pick_decode(last, m) != PB_OK || c2::Pick_has_i(m) || !c2::Pick_has_c(m) { fail_at("pick", "last member"); }
    if pick_out(m) != last[2..4] { fail_at("pick", "default re-encoding"); }
    c2::Pick_clear(m);

    // An unknown value of a closed enum leaves the member set as it was.
    let keep: u8[4] = [0x08, 1, 0x28, 9];
    if c2::Pick_decode(keep, m) != PB_OK { fail_at("pick closed", "decode"); }
    if !c2::Pick_has_i(m) || c2::Pick_i(m) != 1 || c2::Pick_has_c(m) { fail_at("pick closed", "member"); }
    if pick_out(m) != keep { fail_at("pick closed", "re-encoding"); }
    c2::Pick_clear(m);
    let f_bad: u8[2] = [0x30, 0];
    if c2::Pick_decode(f_bad, m) != PB_OK || c2::Pick_has_f(m) || m.pb_unknown.len != 2 { fail_at("pick closed", "far"); }
    c2::Pick_clear(m);

    // A bad string is not rejected.
    let bad: u8[3] = [0x12, 1, 0xff];
    if c2::Pick_decode(bad, m) != PB_OK || c2::Pick_s(m)[0] != 0xff { fail_at("pick", "utf8"); }
    c2::Pick_clear(m);
}

fn check_maps() {
    let want = embed_file("maps.bin");
    var m = c2::Maps { .. };
    c2::Maps_counts_put(m, "k", 4);
    c2::Maps_names_put(m, 7, "n");
    c2::Sub_set_a(c2::Maps_subs_put(m, "s"), 3);
    c2::Maps_colors_put(m, 1, c2::Color_BLUE);
    if maps_out(m) != want { fail_at("maps", "encoding differs from protoc"); }

    var b = c2::Maps { .. };
    if c2::Maps_decode(want, b) != PB_OK { fail_at("maps", "decode"); }
    if b.pb_unknown.len != 0 { fail_at("maps", "kept as unknown"); }
    let n, found = c2::Maps_counts_get(b, "k");
    if !found || n != 4 { fail_at("maps", "counts"); }
    let c, cfound = c2::Maps_colors_get(b, 1);
    if !cfound || c != c2::Color_BLUE { fail_at("maps", "colors"); }
    if maps_out(b) != want { fail_at("maps", "re-encoding differs"); }
    var d = c2::Maps { .. };
    c2::Maps_copy(d, b);
    c2::Maps_clear(b);
    if maps_out(d) != want { fail_at("maps", "copy differs"); }
    c2::Maps_clear(d);
    c2::Maps_clear(m);

    // A repeated key: the last value wins. A missing value is 0, which is known.
    let rep: u8[12] = [0x22, 4, 0x08, 1, 0x10, 1, 0x22, 4, 0x08, 1, 0x10, 5];
    if c2::Maps_decode(rep, m) != PB_OK { fail_at("maps", "repeat decode"); }
    let c2v, c2f = c2::Maps_colors_get(m, 1);
    if !c2f || c2v != c2::Color_BLUE || c2::Maps_colors(m).len != 1 { fail_at("maps", "repeat"); }
    c2::Maps_clear(m);
    let nov: u8[4] = [0x22, 2, 0x08, 1];
    if c2::Maps_decode(nov, m) != PB_OK || m.pb_unknown.len != 0 { fail_at("maps", "no value"); }
    let c3v, c3f = c2::Maps_colors_get(m, 1);
    if !c3f || c3v != c2::Color_RED { fail_at("maps", "no value is not 0"); }
    c2::Maps_clear(m);

    // An unknown value sends the whole entry to unknown fields, its bytes as they
    // are, and leaves an entry of that key in place.
    let bad: u8[12] = [0x22, 4, 0x08, 1, 0x10, 5, 0x22, 4, 0x10, 9, 0x08, 1];
    if c2::Maps_decode(bad, m) != PB_OK { fail_at("maps closed", "decode"); }
    if c2::Maps_colors(m).len != 1 { fail_at("maps closed", "entries"); }
    let c4v, c4f = c2::Maps_colors_get(m, 1);
    if !c4f || c4v != c2::Color_BLUE { fail_at("maps closed", "value"); }
    if m.pb_unknown.len != 6 { fail_at("maps closed", "unknown"); }
    if maps_out(m) != bad { fail_at("maps closed", "re-encoding"); }
    c2::Maps_clear(m);

    // A bad string key or value is not rejected.
    let k: u8[5] = [0x0a, 3, 0x0a, 1, 0xff];
    if c2::Maps_decode(k, m) != PB_OK || c2::Maps_counts(m).len != 1 { fail_at("maps", "utf8 key"); }
    c2::Maps_clear(m);
    let v: u8[5] = [0x12, 3, 0x12, 1, 0xff];
    if c2::Maps_decode(v, m) != PB_OK || c2::Maps_names(m).len != 1 { fail_at("maps", "utf8 value"); }
    c2::Maps_clear(m);
}

fn check_required() {
    var m = c2::Reqs { .. };
    // Each with an element that lacks r, then one that has it.
    let l_bad: u8[2] = [0x0a, 0];
    if c2::Reqs_decode(l_bad, m) != PB_ERR_REQUIRED { fail_at("required", "list"); }
    c2::Reqs_clear(m);
    let l_ok: u8[4] = [0x0a, 2, 0x08, 0];
    if c2::Reqs_decode(l_ok, m) != PB_OK { fail_at("required", "list set"); }
    c2::Reqs_clear(m);
    let e_bad: u8[5] = [0x12, 3, 0x0a, 1, 'k'];
    if c2::Reqs_decode(e_bad, m) != PB_ERR_REQUIRED { fail_at("required", "map"); }
    c2::Reqs_clear(m);
    let e_ok: u8[9] = [0x12, 7, 0x0a, 1, 'k', 0x12, 2, 0x08, 0];
    if c2::Reqs_decode(e_ok, m) != PB_OK { fail_at("required", "map set"); }
    c2::Reqs_clear(m);
    let o_bad: u8[2] = [0x1a, 0];
    if c2::Reqs_decode(o_bad, m) != PB_ERR_REQUIRED { fail_at("required", "oneof"); }
    c2::Reqs_clear(m);
    let o_ok: u8[4] = [0x1a, 2, 0x08, 0];
    if c2::Reqs_decode(o_ok, m) != PB_OK { fail_at("required", "oneof set"); }
    c2::Reqs_clear(m);
}

fn check_only_group() {
    // Its oneof has no member stored, so the group stays unknown.
    var m = c2::OnlyGroup { .. };
    let g: u8[4] = [0x0b, 0x08, 1, 0x0c];
    if c2::OnlyGroup_decode(g, m) != PB_OK || m.pb_unknown.len != 4 { fail_at("group", "not unknown"); }
    var out: u8[>..] = [];
    c2::OnlyGroup_encode(m, out);
    if out != g { fail_at("group", "re-encoding"); }
    c2::OnlyGroup_clear(m);
}

fn main() {
    check_lists();
    check_closed_lists();
    check_pick();
    check_maps();
    check_required();
    check_only_group();
    if failures > 0 { abort(str(failures, " failures")); }
    print("ok");
}
