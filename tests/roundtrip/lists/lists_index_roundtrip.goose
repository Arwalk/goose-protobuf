// Repeated fields are read by index, whatever they hold: _len and _at are the way
// through (gpb-ky7.15, decision 0012).
// Run: scripts/roundtrip.sh lists
import pb_wire;
import lists;

fn expect(ok: bool, what: const u8[:]) {
    if !ok { abort(what); }
}

fn strings_by_index() {
    var m = lists::Lists { .. };
    expect(lists::Lists_names_len(m) == 0, "an empty field");
    lists::Lists_add_names(m, "first");
    lists::Lists_add_names(m, "");
    lists::Lists_add_names(m, "third");
    expect(lists::Lists_names_len(m) == 3, "an empty string counts");
    var joined: u8[>..] = [];
    for i in lists::Lists_names_len(m) {
        joined.append(lists::Lists_names_at(m, i));
        joined.push(';');
    }
    expect(joined == "first;;third;", "the text of each value, in order");
    lists::Lists_clear_names(m);
    expect(lists::Lists_names_len(m) == 0, "cleared");
}

fn bytes_by_index() {
    var m = lists::Lists { .. };
    let raw: u8[2] = [0xff, 0xfe];
    lists::Lists_add_blobs(m, raw[..]);
    expect(lists::Lists_blobs_len(m) == 1, "one value");
    expect(lists::Lists_blobs_at(m, 0)[1] == 0xfe, "its contents");
}

fn messages_by_index() {
    var m = lists::Lists { .. };
    for i in 3 { lists::Lists_add_items(m).id = (i + 1) as i32; }
    expect(lists::Lists_items_len(m) == 3, "three messages");
    var sum = 0;
    for i in lists::Lists_items_len(m) { sum += lists::Lists_items_at(m, i).id; }
    expect(sum == 6, "each message");
}

fn decoded_values_by_index() {
    var m = lists::Lists { .. };
    expect(lists::Lists_decode(embed_file("many.bin"), m) == PB_OK, "decode");
    expect(lists::Lists_names_len(m) == 5, "the names");
    expect(lists::Lists_items_len(m) == 3, "the items");
    expect(lists::Lists_blobs_len(m) > 0, "the blobs");
}

fn main() {
    strings_by_index();
    bytes_by_index();
    messages_by_index();
    decoded_values_by_index();
}
