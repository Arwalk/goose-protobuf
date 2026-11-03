//! protoc-gen-goose: protoc plugin that emits Goose code for the protobuf
//! binary wire format.
//!
//! Stub. The plugin protocol (CodeGeneratorRequest on stdin,
//! CodeGeneratorResponse on stdout) is implemented by the Phase 0
//! "generator plugin skeleton" task; see `bd ready`.

const std = @import("std");
const protobuf = @import("protobuf");

comptime {
    _ = protobuf;
}

pub fn main() u8 {
    std.debug.print("protoc-gen-goose: not implemented yet\n", .{});
    return 1;
}
