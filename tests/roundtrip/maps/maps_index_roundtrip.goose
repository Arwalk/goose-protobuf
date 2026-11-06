// A map's entries are read by index, in insertion order: _len, _key_at and _value_at
// are the way through (gpb-ky7.15, decision 0012).
// Run: scripts/roundtrip.sh maps
import pb_wire;
import maps;

fn expect(ok: bool, what: const u8[:]) {
    if !ok { abort(what); }
}

fn string_keys_and_values() {
    var m = maps::Maps { .. };
    expect(maps::Maps_ss_len(m) == 0, "an empty map");
    maps::Maps_ss_put(m, "a", "one");
    maps::Maps_ss_put(m, "b", "");
    maps::Maps_ss_put(m, "a", "again");
    expect(maps::Maps_ss_len(m) == 2, "a key counts once");
    var joined: u8[>..] = [];
    for i in maps::Maps_ss_len(m) {
        joined.append(maps::Maps_ss_key_at(m, i));
        joined.push('=');
        joined.append(maps::Maps_ss_value_at(m, i));
        joined.push(';');
    }
    expect(joined == "a=again;b=;", "the text of each entry, in insertion order");
    expect(maps::Maps_ss_remove(m, "a"), "remove");
    expect(maps::Maps_ss_len(m) == 1, "one left");
    expect(maps::Maps_ss_key_at(m, 0) == "b", "the later one moved up");
    maps::Maps_clear_ss(m);
    expect(maps::Maps_ss_len(m) == 0, "cleared");
}

fn each_kind_of_value() {
    var m = maps::Maps { .. };
    maps::Maps_is_put(m, 7, "seven");
    expect(maps::Maps_is_key_at(m, 0) == 7 && maps::Maps_is_value_at(m, 0) == "seven", "a number key");
    let raw: u8[2] = [0xff, 0xfe];
    maps::Maps_sb_put(m, "k", raw[..]);
    expect(maps::Maps_sb_value_at(m, 0)[1] == 0xfe, "a bytes value");
    maps::Maps_si_put(m, "k", -3);
    expect(maps::Maps_si_value_at(m, 0) == -3, "a number value");
    maps::Maps_se_put(m, "k", maps::Mode_MODE_ON);
    expect(maps::Maps_se_value_at(m, 0) == maps::Mode_MODE_ON, "an enum value");
    maps::Maps_bb_put(m, true, false);
    expect(maps::Maps_bb_key_at(m, 0) && !maps::Maps_bb_value_at(m, 0), "bools");
}

fn message_values() {
    var m = maps::Maps { .. };
    maps::Maps_sm_put(m, "x").a = 5;
    maps::Maps_sm_put(m, "y");
    expect(maps::Maps_sm_len(m) == 2, "two entries");
    expect(maps::Maps_sm_value_at(m, 0).a == 5, "a value");
    expect(maps::Maps_sm_value_at(m, 1).a == 0, "an empty value");
    maps::Maps_sm_value_at(m, 1).a = 6;
    let y = maps::Maps_sm_get(m, "y");
    guard y else { abort("the value is there"); }
    expect(y.a == 6, "it is the map's own value");
}

fn decoded_entries() {
    var m = maps::Maps { .. };
    expect(maps::Maps_decode(embed_file("sm_empty.bin"), m) == PB_OK, "decode");
    expect(maps::Maps_sm_len(m) == 1, "one entry");
    expect(maps::Maps_sm_value_at(m, 0).a == 0, "an entry with no value has an empty one");
}

fn main() {
    string_keys_and_values();
    each_kind_of_value();
    message_values();
    decoded_entries();
}
