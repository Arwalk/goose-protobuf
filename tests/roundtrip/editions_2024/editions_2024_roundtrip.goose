// Round-trip test for tests/protos/editions_2024.proto: what edition 2024 adds does
// not change the wire format, and each edition 2023 feature still applies.
// Run: scripts/roundtrip.sh editions_2024
import pb_wire;
import editions_2024;

var failures = 0;

fn fail_at(what: u8[:]) {
    failures += 1;
    print("FAIL ", what);
}

fn check_all() {
    let data = embed_file("all.bin");
    var m = ed24::Book { .. };
    if ed24::Book_decode(data, m) != PB_OK { fail_at("decode"); return; }
    if ed24::Book_title(m) != "Emma" { fail_at("title"); }
    if !ed24::Book_has_explicit_field(m) { fail_at("explicit presence is kept at 0"); }
    if m.implicit_field != 3 { fail_at("implicit field"); }
    if m.color != ed24::Color_COLOR_RED { fail_at("open enum"); }
    if m.closed != ed24::Closed_CLOSED_ONE { fail_at("closed enum"); }
    if ed24::Book_packed_values(m).len != 2 { fail_at("packed"); }
    if ed24::Book_expanded_values(m)[1] != 4 { fail_at("expanded"); }
    let v, found = ed24::Book_counts_get(m, "a");
    if !found || v != 5 { fail_at("map"); }
    if ed24::Book_word(m) != "w" { fail_at("oneof"); }
    var out: u8[>..] = [];
    ed24::Book_encode(m, out);
    if out != data { fail_at("encoding is not what protoc wrote"); }
    ed24::Book_clear(m);
}

fn check_delimited_is_a_group() {
    // Field 13, delimited: start group, field 1 = 2, end group.
    let want: u8[4] = [0x6B, 0x08, 2, 0x6C];
    var m = ed24::Book { .. };
    ed24::Book_Inner_set_i(ed24::Book_mutable_delimited_inner(m), 2);
    var out: u8[>..] = [];
    ed24::Book_encode(m, out);
    if out != want { fail_at("delimited encoding"); }
    ed24::Book_clear(m);
}

fn check_implicit_zero_is_not_written() {
    var m = ed24::Book { .. };
    m.implicit_field = 0;
    if ed24::Book_size_of(m) != 0 { fail_at("implicit zero"); }
    ed24::Book_clear(m);
}

fn main() {
    check_all();
    check_delimited_is_a_group();
    check_implicit_zero_is_not_written();
    if failures > 0 { abort("editions_2024 failed"); }
}
