// testee.goose: conformance testee for protoc-gen-goose.
//
// Protocol (conformance_test_runner from third_party/protobuf):
//   read  4-byte little-endian length + ConformanceRequest
//   write 4-byte little-endian length + ConformanceResponse, then flush
//   repeat until stdin reaches EOF.
//
// The first request has message_type == "conformance.FailureSet"; reply
// with a serialized FailureSet in protobuf_payload. Binary only: any
// request whose payload is not protobuf_payload, or whose
// requested_output_format is not PROTOBUF, gets `skipped`.
//
// Note: os.read_stdin reads to EOF, so exact-length reads need another
// mechanism (see the stdin spike in docs/decisions/).
//
// Stub: implemented by the Phase 0 testee task (see `bd ready`).

fn main() {
}
