// protoc-gen-goose: protoc plugin that emits Goose code for the protobuf
// binary wire format. Port of generator/src/main.zig: the Zig generator is the
// specification, and scripts/selfhost_diff.sh compares the two byte for byte.

import os;
import pb_wire;
import support;
import generate;

fn decodeErrorText(err: i32) -> const u8[:] {
    if err == PB_ERR_TRUNCATED { return "truncated input"; }
    if err == PB_ERR_MALFORMED { return "malformed input"; }
    if err == PB_ERR_DEPTH { return "messages nested too deeply"; }
    if err == PB_ERR_UTF8 { return "a string that is not valid UTF-8"; }
    if err == PB_ERR_REQUIRED { return "a required field is not set"; }
    return keep(str("error ", err));
}

fn main() {
    var input: u8[>..] = [];
    read_stdin(input);
    var out: u8[>..] = [];
    let err = runPlugin(input, out);
    if err != PB_OK {
        write_stderr(str("protoc-gen-goose: failed to decode CodeGeneratorRequest: ", decodeErrorText(err), "\n"));
        exit(1);
    }
    write_stdout(out);
    flush_stdout();
}
