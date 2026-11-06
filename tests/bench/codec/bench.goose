// The Goose side of scripts/bench_codec.py. For a message and a file of its encoding,
// times decoding and encoding the way a program does them, and prints the fastest of
// some rounds. bench.cc does the same for protobuf C++.
// Usage: bench <message> <file> <seconds per round> <rounds>
// Prints: <message> <input bytes> <encoded bytes> <decode ns> <encode ns>
import os;
import pb_wire;
import codec;

var seconds: f64 = 0;
var rounds: i64 = 0;
var out: u8[>..] = [];

// The fastest time per call of F, in nanoseconds.
fn timed<F>() -> i64 {
    var best: f64 = 1e30;
    for round in rounds {
        var n: i64 = 0;
        let start = clock();
        while clock() - start < seconds {
            F();
            n++;
        }
        let each = (clock() - start) / n;
        if each < best { best = each; }
    }
    return (best * 1e9) as! i64;
}

fn report(name: const u8[:], input: const u8[:], decode_ns: i64, encode_ns: i64) {
    print(name, " ", input.len, " ", out.len, " ", decode_ns, " ", encode_ns);
}

fn check(err: i32) {
    if err != PB_OK { abort(str("decode failed: ", pb_error_text(err))); }
}

fn run_Small(input: const u8[:]) {
    var m = codec::Small { .. };
    let d = timed() { check(codec::Small_decode(input, m)); codec::Small_clear(m); };
    check(codec::Small_decode(input, m));
    let e = timed() { out.clear(); codec::Small_encode(m, out); };
    report("Small", input, d, e);
    codec::Small_clear(m);
}

fn run_Record(input: const u8[:]) {
    var m = codec::Record { .. };
    let d = timed() { check(codec::Record_decode(input, m)); codec::Record_clear(m); };
    check(codec::Record_decode(input, m));
    let e = timed() { out.clear(); codec::Record_encode(m, out); };
    report("Record", input, d, e);
    codec::Record_clear(m);
}

fn run_Batch(input: const u8[:]) {
    var m = codec::Batch { .. };
    let d = timed() { check(codec::Batch_decode(input, m)); codec::Batch_clear(m); };
    check(codec::Batch_decode(input, m));
    let e = timed() { out.clear(); codec::Batch_encode(m, out); };
    report("Batch", input, d, e);
    codec::Batch_clear(m);
}

fn run_Ints(input: const u8[:]) {
    var m = codec::Ints { .. };
    let d = timed() { check(codec::Ints_decode(input, m)); codec::Ints_clear(m); };
    check(codec::Ints_decode(input, m));
    let e = timed() { out.clear(); codec::Ints_encode(m, out); };
    report("Ints", input, d, e);
    codec::Ints_clear(m);
}

fn run_Strings(input: const u8[:]) {
    var m = codec::Strings { .. };
    let d = timed() { check(codec::Strings_decode(input, m)); codec::Strings_clear(m); };
    check(codec::Strings_decode(input, m));
    let e = timed() { out.clear(); codec::Strings_encode(m, out); };
    report("Strings", input, d, e);
    codec::Strings_clear(m);
}

fn run_Blob(input: const u8[:]) {
    var m = codec::Blob { .. };
    let d = timed() { check(codec::Blob_decode(input, m)); codec::Blob_clear(m); };
    check(codec::Blob_decode(input, m));
    let e = timed() { out.clear(); codec::Blob_encode(m, out); };
    report("Blob", input, d, e);
    codec::Blob_clear(m);
}

fn run_Table(input: const u8[:]) {
    var m = codec::Table { .. };
    let d = timed() { check(codec::Table_decode(input, m)); codec::Table_clear(m); };
    check(codec::Table_decode(input, m));
    let e = timed() { out.clear(); codec::Table_encode(m, out); };
    report("Table", input, d, e);
    codec::Table_clear(m);
}

fn main() {
    let argv = args();
    if argv.len != 5 { abort("usage: bench <message> <file> <seconds per round> <rounds>"); }
    let name = argv[1];
    var input: u8[>..] = [];
    if !read_file(argv[2], input) { abort("cannot read the input"); }
    let s, s_ok = parse_flt(argv[3]);
    let r, r_ok = parse_int(argv[4]);
    if !s_ok || !r_ok { abort("bad seconds or rounds"); }
    seconds = s;
    rounds = r;
    if name == "Small" { run_Small(input); }
    else if name == "Record" { run_Record(input); }
    else if name == "Batch" { run_Batch(input); }
    else if name == "Ints" { run_Ints(input); }
    else if name == "Strings" { run_Strings(input); }
    else if name == "Blob" { run_Blob(input); }
    else if name == "Table" { run_Table(input); }
    else { abort(str("no message ", name)); }
}
