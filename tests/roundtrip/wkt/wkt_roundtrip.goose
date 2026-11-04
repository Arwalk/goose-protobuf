// Round-trip test for the well-known types in tests/protos/wkt.proto
// (gpb-8qn.5): each decodes protoc's encoding of a sample value and
// re-encodes it byte for byte.
// Run: scripts/roundtrip.sh wkt
import pb_wire;
import google.protobuf.any;
import google.protobuf.duration;
import google.protobuf.empty;
import google.protobuf.timestamp;
import google.protobuf.wrappers;

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

// The outcome of decoding want and encoding the result.
fn check(name: u8[:], want: const u8[:], err: i32, out: const u8[:], size: i64) {
    if err != PB_OK { fail_at(name, str("decode error ", err)); return; }
    if !bytes_eq(out, want) { fail_at(name, "re-encode differs from protoc"); }
    if size != want.len { fail_at(name, str("size_of ", size)); }
}

fn check_any() {
    let want = embed_file("any.bin");
    var m = google_protobuf::Any { .. };
    let err = google_protobuf::Any_decode(want, m);
    var out: u8[>..] = [];
    google_protobuf::Any_encode(m, out);
    check("any", want, err, out, google_protobuf::Any_size_of(m));
    google_protobuf::Any_clear(m);
    if google_protobuf::Any_size_of(m) != 0 { fail_at("any", "clear"); }
}

fn check_any_empty() {
    let want = embed_file("any_empty.bin");
    var m = google_protobuf::Any { .. };
    let err = google_protobuf::Any_decode(want, m);
    var out: u8[>..] = [];
    google_protobuf::Any_encode(m, out);
    check("any_empty", want, err, out, google_protobuf::Any_size_of(m));
    google_protobuf::Any_clear(m);
    if google_protobuf::Any_size_of(m) != 0 { fail_at("any_empty", "clear"); }
}

fn check_timestamp() {
    let want = embed_file("timestamp.bin");
    var m = google_protobuf::Timestamp { .. };
    let err = google_protobuf::Timestamp_decode(want, m);
    var out: u8[>..] = [];
    google_protobuf::Timestamp_encode(m, out);
    check("timestamp", want, err, out, google_protobuf::Timestamp_size_of(m));
    google_protobuf::Timestamp_clear(m);
    if google_protobuf::Timestamp_size_of(m) != 0 { fail_at("timestamp", "clear"); }
}

fn check_timestamp_negative() {
    let want = embed_file("timestamp_negative.bin");
    var m = google_protobuf::Timestamp { .. };
    let err = google_protobuf::Timestamp_decode(want, m);
    var out: u8[>..] = [];
    google_protobuf::Timestamp_encode(m, out);
    check("timestamp_negative", want, err, out, google_protobuf::Timestamp_size_of(m));
    google_protobuf::Timestamp_clear(m);
    if google_protobuf::Timestamp_size_of(m) != 0 { fail_at("timestamp_negative", "clear"); }
}

fn check_duration() {
    let want = embed_file("duration.bin");
    var m = google_protobuf::Duration { .. };
    let err = google_protobuf::Duration_decode(want, m);
    var out: u8[>..] = [];
    google_protobuf::Duration_encode(m, out);
    check("duration", want, err, out, google_protobuf::Duration_size_of(m));
    google_protobuf::Duration_clear(m);
    if google_protobuf::Duration_size_of(m) != 0 { fail_at("duration", "clear"); }
}

fn check_duration_negative() {
    let want = embed_file("duration_negative.bin");
    var m = google_protobuf::Duration { .. };
    let err = google_protobuf::Duration_decode(want, m);
    var out: u8[>..] = [];
    google_protobuf::Duration_encode(m, out);
    check("duration_negative", want, err, out, google_protobuf::Duration_size_of(m));
    google_protobuf::Duration_clear(m);
    if google_protobuf::Duration_size_of(m) != 0 { fail_at("duration_negative", "clear"); }
}

fn check_empty() {
    let want = embed_file("empty.bin");
    var m = google_protobuf::Empty { .. };
    let err = google_protobuf::Empty_decode(want, m);
    var out: u8[>..] = [];
    google_protobuf::Empty_encode(m, out);
    check("empty", want, err, out, google_protobuf::Empty_size_of(m));
    google_protobuf::Empty_clear(m);
    if google_protobuf::Empty_size_of(m) != 0 { fail_at("empty", "clear"); }
}

fn check_double_value() {
    let want = embed_file("double_value.bin");
    var m = google_protobuf::DoubleValue { .. };
    let err = google_protobuf::DoubleValue_decode(want, m);
    var out: u8[>..] = [];
    google_protobuf::DoubleValue_encode(m, out);
    check("double_value", want, err, out, google_protobuf::DoubleValue_size_of(m));
    google_protobuf::DoubleValue_clear(m);
    if google_protobuf::DoubleValue_size_of(m) != 0 { fail_at("double_value", "clear"); }
}

fn check_float_value() {
    let want = embed_file("float_value.bin");
    var m = google_protobuf::FloatValue { .. };
    let err = google_protobuf::FloatValue_decode(want, m);
    var out: u8[>..] = [];
    google_protobuf::FloatValue_encode(m, out);
    check("float_value", want, err, out, google_protobuf::FloatValue_size_of(m));
    google_protobuf::FloatValue_clear(m);
    if google_protobuf::FloatValue_size_of(m) != 0 { fail_at("float_value", "clear"); }
}

fn check_int64_value() {
    let want = embed_file("int64_value.bin");
    var m = google_protobuf::Int64Value { .. };
    let err = google_protobuf::Int64Value_decode(want, m);
    var out: u8[>..] = [];
    google_protobuf::Int64Value_encode(m, out);
    check("int64_value", want, err, out, google_protobuf::Int64Value_size_of(m));
    google_protobuf::Int64Value_clear(m);
    if google_protobuf::Int64Value_size_of(m) != 0 { fail_at("int64_value", "clear"); }
}

fn check_uint64_value() {
    let want = embed_file("uint64_value.bin");
    var m = google_protobuf::UInt64Value { .. };
    let err = google_protobuf::UInt64Value_decode(want, m);
    var out: u8[>..] = [];
    google_protobuf::UInt64Value_encode(m, out);
    check("uint64_value", want, err, out, google_protobuf::UInt64Value_size_of(m));
    google_protobuf::UInt64Value_clear(m);
    if google_protobuf::UInt64Value_size_of(m) != 0 { fail_at("uint64_value", "clear"); }
}

fn check_int32_value() {
    let want = embed_file("int32_value.bin");
    var m = google_protobuf::Int32Value { .. };
    let err = google_protobuf::Int32Value_decode(want, m);
    var out: u8[>..] = [];
    google_protobuf::Int32Value_encode(m, out);
    check("int32_value", want, err, out, google_protobuf::Int32Value_size_of(m));
    google_protobuf::Int32Value_clear(m);
    if google_protobuf::Int32Value_size_of(m) != 0 { fail_at("int32_value", "clear"); }
}

fn check_uint32_value() {
    let want = embed_file("uint32_value.bin");
    var m = google_protobuf::UInt32Value { .. };
    let err = google_protobuf::UInt32Value_decode(want, m);
    var out: u8[>..] = [];
    google_protobuf::UInt32Value_encode(m, out);
    check("uint32_value", want, err, out, google_protobuf::UInt32Value_size_of(m));
    google_protobuf::UInt32Value_clear(m);
    if google_protobuf::UInt32Value_size_of(m) != 0 { fail_at("uint32_value", "clear"); }
}

fn check_bool_value() {
    let want = embed_file("bool_value.bin");
    var m = google_protobuf::BoolValue { .. };
    let err = google_protobuf::BoolValue_decode(want, m);
    var out: u8[>..] = [];
    google_protobuf::BoolValue_encode(m, out);
    check("bool_value", want, err, out, google_protobuf::BoolValue_size_of(m));
    google_protobuf::BoolValue_clear(m);
    if google_protobuf::BoolValue_size_of(m) != 0 { fail_at("bool_value", "clear"); }
}

fn check_string_value() {
    let want = embed_file("string_value.bin");
    var m = google_protobuf::StringValue { .. };
    let err = google_protobuf::StringValue_decode(want, m);
    var out: u8[>..] = [];
    google_protobuf::StringValue_encode(m, out);
    check("string_value", want, err, out, google_protobuf::StringValue_size_of(m));
    google_protobuf::StringValue_clear(m);
    if google_protobuf::StringValue_size_of(m) != 0 { fail_at("string_value", "clear"); }
}

fn check_bytes_value() {
    let want = embed_file("bytes_value.bin");
    var m = google_protobuf::BytesValue { .. };
    let err = google_protobuf::BytesValue_decode(want, m);
    var out: u8[>..] = [];
    google_protobuf::BytesValue_encode(m, out);
    check("bytes_value", want, err, out, google_protobuf::BytesValue_size_of(m));
    google_protobuf::BytesValue_clear(m);
    if google_protobuf::BytesValue_size_of(m) != 0 { fail_at("bytes_value", "clear"); }
}

fn check_int32_zero() {
    let want = embed_file("int32_zero.bin");
    var m = google_protobuf::Int32Value { .. };
    let err = google_protobuf::Int32Value_decode(want, m);
    var out: u8[>..] = [];
    google_protobuf::Int32Value_encode(m, out);
    check("int32_zero", want, err, out, google_protobuf::Int32Value_size_of(m));
    google_protobuf::Int32Value_clear(m);
    if google_protobuf::Int32Value_size_of(m) != 0 { fail_at("int32_zero", "clear"); }
}

// The decoded values are the ones protoc was given.
fn check_values() {
    var any = google_protobuf::Any { .. };
    google_protobuf::Any_decode(embed_file("any.bin"), any);
    if !bytes_eq(google_protobuf::Any_type_url(any), "type.googleapis.com/foo.Bar") { fail_at("any", "type_url"); }
    let v: u8[9] = [0x00, 0xff, 0x01, 0x62, 0x69, 0x6e, 0x61, 0x72, 0x79];
    if !bytes_eq(google_protobuf::Any_value(any), v) { fail_at("any", "value"); }
    google_protobuf::Any_clear(any);

    var ts = google_protobuf::Timestamp { .. };
    google_protobuf::Timestamp_decode(embed_file("timestamp_negative.bin"), ts);
    if ts.seconds != -62135596800 || ts.nanos != 1 { fail_at("timestamp", str(ts.seconds, " ", ts.nanos)); }

    var d = google_protobuf::Duration { .. };
    google_protobuf::Duration_decode(embed_file("duration_negative.bin"), d);
    if d.seconds != -1 || d.nanos != -500000000 { fail_at("duration", str(d.seconds, " ", d.nanos)); }

    var i = google_protobuf::Int64Value { .. };
    google_protobuf::Int64Value_decode(embed_file("int64_value.bin"), i);
    if i.value != -9223372036854775807 - 1 { fail_at("int64", str(i.value)); }

    var u = google_protobuf::UInt64Value { .. };
    google_protobuf::UInt64Value_decode(embed_file("uint64_value.bin"), u);
    if u.value != 18446744073709551615 { fail_at("uint64", str(u.value)); }

    var b = google_protobuf::BoolValue { .. };
    google_protobuf::BoolValue_decode(embed_file("bool_value.bin"), b);
    if !b.value { fail_at("bool", "false"); }

    var s = google_protobuf::StringValue { .. };
    google_protobuf::StringValue_decode(embed_file("string_value.bin"), s);
    if !bytes_eq(google_protobuf::StringValue_value(s), "héllo") { fail_at("string", "value"); }
    google_protobuf::StringValue_clear(s);

    // A wrapper holding its default has no bytes on the wire, as proto3
    // has it: only the presence of the wrapper itself says it is set.
    if embed_file("int32_zero.bin").len != 0 { fail_at("int32_zero", "protoc wrote bytes"); }

    // Empty keeps what it does not know.
    let unknown: u8[2] = [0x08, 0x01];
    var e = google_protobuf::Empty { .. };
    if google_protobuf::Empty_decode(unknown, e) != PB_OK { fail_at("empty", "decode"); }
    var out: u8[>..] = [];
    google_protobuf::Empty_encode(e, out);
    if !bytes_eq(out, unknown) { fail_at("empty", "dropped an unknown field"); }
    google_protobuf::Empty_clear(e);
}

fn main() {
    check_any();
    check_any_empty();
    check_timestamp();
    check_timestamp_negative();
    check_duration();
    check_duration_negative();
    check_empty();
    check_double_value();
    check_float_value();
    check_int64_value();
    check_uint64_value();
    check_int32_value();
    check_uint32_value();
    check_bool_value();
    check_string_value();
    check_bytes_value();
    check_int32_zero();
    check_values();
    if failures != 0 { abort(str(failures, " failures")); }
    print("wkt round-trip: all passed");
}
