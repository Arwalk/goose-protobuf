// protoc-gen-goose: protoc plugin that emits Goose code for the protobuf
// binary wire format. Port of generator/src/main.zig: the Zig generator is the
// specification, and scripts/selfhost_diff.sh compares the two byte for byte.

import os;
import pb_wire;
import google.protobuf.compiler.plugin;
import google.protobuf.descriptor;
import support;
import features;
import emit;

// CodeGeneratorResponse.Feature.FEATURE_PROTO3_OPTIONAL.
let FEATURE_PROTO3_OPTIONAL: u64 = 1;
// CodeGeneratorResponse.Feature.FEATURE_SUPPORTS_EDITIONS.
let FEATURE_SUPPORTS_EDITIONS: u64 = 2;

// The range of editions the plugin takes, as google.protobuf.Edition values:
// EDITION_PROTO2 and EDITION_2023.
let MINIMUM_EDITION: i32 = 998;
let MAXIMUM_EDITION: i32 = 1000;

var response = google_protobuf_compiler::CodeGeneratorResponse { .. };

// Fills response.file, or sets response.error and returns false.
// The well-known types ship in the pb_wire package, so a file naming one
// writes nothing. The parameter `wkt` writes those instead, as wkt/x.goose:
// scripts/wkt.sh regenerates the package's copy with it.
fn generate() -> bool {
    let parameter = google_protobuf_compiler::CodeGeneratorRequest_parameter(request);
    let wkt = parameter == "wkt";
    if parameter.len > 0 && !wkt {
        google_protobuf_compiler::CodeGeneratorResponse_set_error(response, str("unknown parameter: ", parameter));
        return false;
    }
    let outputs = newMap();
    for i in google_protobuf_compiler::CodeGeneratorRequest_file_to_generate(request).len {
        let name = google_protobuf_compiler::CodeGeneratorRequest_file_to_generate_at(request, i);
        let file = findFile(name);
        guard file else {
            google_protobuf_compiler::CodeGeneratorResponse_set_error(response, str(name, ": not in proto_file"));
            return false;
        };
        if isWellKnown(file) != wkt {
            if !wkt { continue; }
            google_protobuf_compiler::CodeGeneratorResponse_set_error(response, str(name, ": not a well-known type"));
            return false;
        }
        let content_at = w.len;
        if !generateFile(file) {
            google_protobuf_compiler::CodeGeneratorResponse_set_error(response, diag);
            return false;
        }
        let output = if wkt { wellKnownOutputName(name) } else { outputName(name) };
        let seen = mapGet(outputs, output);
        if seen {
            google_protobuf_compiler::CodeGeneratorResponse_set_error(response, str(seen.text, " and ", name, " both map to the Goose file ", output));
            return false;
        }
        mapPut(outputs, output).text = name;
        let out .= google_protobuf_compiler::CodeGeneratorResponse_add_file(response);
        google_protobuf_compiler::CodeGeneratorResponse_File_set_name(out, output);
        google_protobuf_compiler::CodeGeneratorResponse_File_set_content(out, w[content_at..]);
    }
    return true;
}

fn findFile(name: const u8[:]) -> FileDesc? {
    for i in google_protobuf_compiler::CodeGeneratorRequest_proto_file(request).len {
        let f .= google_protobuf_compiler::CodeGeneratorRequest_proto_file_at(request, i);
        if fileName(f) == name { return f; }
    }
    return null;
}

fn main() {
    var input: u8[>..] = [];
    read_stdin(input);
    // Decodes a serialized CodeGeneratorRequest and writes the serialized
    // CodeGeneratorResponse: one .goose file per file to generate, or `error` (and
    // no files) for input the generator rejects. Nothing is written if the request
    // fails to decode.
    let err = google_protobuf_compiler::CodeGeneratorRequest_decode(input, request);
    if err != PB_OK {
        write_stderr(str("protoc-gen-goose: failed to decode CodeGeneratorRequest: error ", err, "\n"));
        exit(1);
    }
    google_protobuf_compiler::CodeGeneratorResponse_set_supported_features(response, FEATURE_PROTO3_OPTIONAL | FEATURE_SUPPORTS_EDITIONS);
    google_protobuf_compiler::CodeGeneratorResponse_set_minimum_edition(response, MINIMUM_EDITION);
    google_protobuf_compiler::CodeGeneratorResponse_set_maximum_edition(response, MAXIMUM_EDITION);
    if !generate() { google_protobuf_compiler::CodeGeneratorResponse_clear_file(response); }
    var out: u8[>..] = [];
    google_protobuf_compiler::CodeGeneratorResponse_encode(response, out);
    write_stdout(out);
    flush_stdout();
}
