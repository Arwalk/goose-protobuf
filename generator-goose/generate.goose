// The plugin, from a serialized CodeGeneratorRequest to a serialized
// CodeGeneratorResponse.
//
// protoc validates the descriptors it sends, and a plugin relies on that: one
// that protoc would refuse, such as a map entry with no value or a oneof_index out
// of range, may end in a runtime error, a nonzero exit, rather than in
// CodeGeneratorResponse.error.

import pb_wire;
import google.protobuf.compiler.plugin;
import google.protobuf.descriptor;
import support;
import features;
import emit;

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
    let outputs = new_map();
    for i in google_protobuf_compiler::CodeGeneratorRequest_file_to_generate_len(request) {
        let name = google_protobuf_compiler::CodeGeneratorRequest_file_to_generate_at(request, i);
        let file = find_file(name);
        guard file else {
            google_protobuf_compiler::CodeGeneratorResponse_set_error(response, str(name, ": not in proto_file"));
            return false;
        };
        if is_well_known(file) != wkt {
            if !wkt { continue; }
            google_protobuf_compiler::CodeGeneratorResponse_set_error(response, str(name, ": not a well-known type"));
            return false;
        }
        let content_at = w.len;
        if !generate_file(file) {
            google_protobuf_compiler::CodeGeneratorResponse_set_error(response, diag);
            return false;
        }
        let output = if wkt { well_known_output_name(name) } else { output_name(name) };
        let seen = map_get(outputs, output);
        if seen {
            google_protobuf_compiler::CodeGeneratorResponse_set_error(response, str(seen.text, " and ", name, " both map to the Goose file ", output));
            return false;
        }
        map_put(outputs, output).text = name;
        let out .= google_protobuf_compiler::CodeGeneratorResponse_add_file(response);
        google_protobuf_compiler::CodeGeneratorResponse_File_set_name(out, output);
        google_protobuf_compiler::CodeGeneratorResponse_File_set_content(out, w[content_at..]);
    }
    return true;
}

fn find_file(name: const u8[:]) -> FileDesc? {
    for i in google_protobuf_compiler::CodeGeneratorRequest_proto_file_len(request) {
        let f .= google_protobuf_compiler::CodeGeneratorRequest_proto_file_at(request, i);
        if file_name(f) == name { return f; }
    }
    return null;
}

// Decodes `input` and appends the response to `out`: one .goose file per file to
// generate, or `error` and no files for input the generator rejects. Returns PB_OK,
// or the PB_ERR_* code of a request that fails to decode, with nothing in `out`.
fn run_plugin(input: const u8[:], out: u8[>..]&) -> i32 {
    let err = google_protobuf_compiler::CodeGeneratorRequest_decode(input, request);
    if err != PB_OK { return err; }
    let proto3_optional = google_protobuf_compiler::CodeGeneratorResponse_Feature_FEATURE_PROTO3_OPTIONAL as u64;
    let editions = google_protobuf_compiler::CodeGeneratorResponse_Feature_FEATURE_SUPPORTS_EDITIONS as u64;
    google_protobuf_compiler::CodeGeneratorResponse_set_supported_features(response, proto3_optional | editions);
    google_protobuf_compiler::CodeGeneratorResponse_set_minimum_edition(response, google_protobuf::Edition_EDITION_PROTO2);
    google_protobuf_compiler::CodeGeneratorResponse_set_maximum_edition(response, google_protobuf::Edition_EDITION_2026);
    if !generate() { google_protobuf_compiler::CodeGeneratorResponse_clear_file(response); }
    google_protobuf_compiler::CodeGeneratorResponse_encode(response, out);
    return PB_OK;
}
