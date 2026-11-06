import pb_wire from "../..";
import event;

fn build(e: event::Event&) {
    event::Event_mutable_starts(e).seconds = 1700000000;
    event::Event_mutable_length(e).seconds = 90;

    // A Struct is a map of strings to Values.
    let extra .= event::Event_mutable_extra(e);
    let host .= google_protobuf::Struct_fields_put(extra, "host");
    google_protobuf::Value_set_string_value(host, "Ada");

    event::Event_seats_put(e, "front", 10);
    event::Event_seats_put(e, "back", 40);
    event::Event_seats_put(e, "front", 12);    // replaces the value, and keeps its place

    let venue .= event::Event_venues_put(e, "main");
    event::Venue_set_city(venue, "Oslo");
}

fn show(e: event::Event&) {
    // The getter of a sub-message is null if it is not set.
    let starts .= event::Event_starts(e);
    let length .= event::Event_length(e);
    guard starts else { abort("no start"); }
    guard length else { abort("no length"); }
    print("starts at ", starts.seconds, " for ", length.seconds, " s");

    let extra .= event::Event_extra(e);
    guard extra else { abort("no extra"); }
    let host .= google_protobuf::Struct_fields_get(extra, "host");
    guard host else { abort("no host"); }
    print("host ", google_protobuf::Value_string_value(host));

    // Maps keep their insertion order.
    for i in event::Event_seats_len(e) {
        print(event::Event_seats_key_at(e, i), " has ", event::Event_seats_value_at(e, i), " seats");
    }
    let seats, found = event::Event_seats_get(e, "back");
    print("back: ", seats, " ", found);

    for i in event::Event_venues_len(e) {
        let venue .= event::Event_venues_value_at(e, i);
        print(event::Event_venues_key_at(e, i), " is in ", event::Venue_city(venue));
    }
}

fn main() {
    var e = event::Event { .. };
    build(e);

    var bytes: u8[>..] = [];
    event::Event_encode(e, bytes);
    event::Event_clear(e);

    var back = event::Event { .. };
    let err = event::Event_decode(bytes, back);
    if err != PB_OK { abort(str("decode failed: ", pb_error_text(err))); }
    show(back);
    event::Event_clear(back);
}
