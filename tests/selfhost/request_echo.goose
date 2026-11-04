// Reads a CodeGeneratorRequest on stdin and writes it back through the generated
// bindings, with what it found on stderr. Run by scripts/selfhost_bindings.sh.
// A global, as the record is large.
import os;
import pb_wire;
import google.protobuf.compiler.plugin;
import google.protobuf.descriptor;

var req = google_protobuf_compiler::CodeGeneratorRequest { .. };

fn main() {
    var input: u8[>..] = [];
    read_stdin(input);
    let err = google_protobuf_compiler::CodeGeneratorRequest_decode(input, req);
    if err != PB_OK { abort(str("decode error ", err)); }
    let files = google_protobuf_compiler::CodeGeneratorRequest_proto_file(req).len;
    let targets = google_protobuf_compiler::CodeGeneratorRequest_file_to_generate(req).len;
    if files == 0 || targets == 0 { abort("no files in the request"); }
    write_stderr(str(targets, " to generate, ", files, " files\n"));
    var out: u8[>..] = [];
    google_protobuf_compiler::CodeGeneratorRequest_encode(req, out);
    write_stdout(out);
}
