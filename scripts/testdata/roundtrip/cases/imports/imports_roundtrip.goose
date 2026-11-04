// Passes only if the harness generated the file imports.proto imports.
import pb_wire;
import google.protobuf.duration;

fn main() {
    var d = google_protobuf::Duration { .. };
    d.seconds = 1;
    var out: u8[>..] = [];
    google_protobuf::Duration_encode(d, out);
    if out.len != 2 { abort("wrong size"); }
}
