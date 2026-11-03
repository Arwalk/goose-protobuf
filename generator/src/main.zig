//! protoc-gen-goose: protoc plugin that emits Goose code for the protobuf
//! binary wire format.

const std = @import("std");
const pb_plugin = @import("pb_plugin");
const plugin = pb_plugin.plugin;

/// CodeGeneratorResponse.Feature.FEATURE_PROTO3_OPTIONAL.
pub const FEATURE_PROTO3_OPTIONAL: u64 = 1;

/// Decodes a serialized CodeGeneratorRequest from `input` and writes the
/// serialized CodeGeneratorResponse to `out`. Nothing is written if the
/// request fails to decode.
pub fn run(gpa: std.mem.Allocator, input: []const u8, out: *std.Io.Writer) !void {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    var reader: std.Io.Reader = .fixed(input);
    const request: plugin.CodeGeneratorRequest = try .decode(&reader, allocator);
    _ = request;

    const response: plugin.CodeGeneratorResponse = .{
        .supported_features = FEATURE_PROTO3_OPTIONAL,
    };
    try response.encode(out, allocator);
}

pub fn main() u8 {
    const gpa = std.heap.smp_allocator;
    var threaded: std.Io.Threaded = .init(gpa, .{ .environ = .empty });
    const io = threaded.io();

    var stdin_buf: [4096]u8 = undefined;
    var stdin = std.Io.File.stdin().reader(io, &stdin_buf);
    const input = stdin.interface.allocRemaining(gpa, .unlimited) catch |err| {
        std.debug.print("protoc-gen-goose: failed to read stdin: {t}\n", .{err});
        return 1;
    };
    defer gpa.free(input);

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    run(gpa, input, &out.writer) catch |err| {
        std.debug.print("protoc-gen-goose: failed to decode CodeGeneratorRequest: {t}\n", .{err});
        return 1;
    };

    var stdout_buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &stdout_buf);
    stdout.interface.writeAll(out.written()) catch |err| {
        std.debug.print("protoc-gen-goose: failed to write stdout: {t}\n", .{err});
        return 1;
    };
    stdout.interface.flush() catch |err| {
        std.debug.print("protoc-gen-goose: failed to write stdout: {t}\n", .{err});
        return 1;
    };
    return 0;
}

test "empty request yields response with proto3 optional and no files" {
    const gpa = std.testing.allocator;
    var req: plugin.CodeGeneratorRequest = .{};
    defer req.file_to_generate.deinit(gpa);
    try req.file_to_generate.append(gpa, "a.proto");

    var req_bytes: std.Io.Writer.Allocating = .init(gpa);
    defer req_bytes.deinit();
    try req.encode(&req_bytes.writer, gpa);

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try run(gpa, req_bytes.written(), &out.writer);

    try std.testing.expectEqualSlices(u8, &.{ 0x10, 0x01 }, out.written());

    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var reader: std.Io.Reader = .fixed(out.written());
    const res: plugin.CodeGeneratorResponse = try .decode(&reader, arena.allocator());
    try std.testing.expectEqual(@as(?u64, FEATURE_PROTO3_OPTIONAL), res.supported_features);
    try std.testing.expectEqual(@as(usize, 0), res.file.items.len);
    try std.testing.expectEqual(@as(?[]const u8, null), res.@"error");
}

test "truncated request is an error" {
    const gpa = std.testing.allocator;
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    // field 1 (file_to_generate), length 5, but only 1 byte follows.
    if (run(gpa, &.{ 0x0A, 0x05, 'a' }, &out.writer)) |_| {
        return error.TestExpectedError;
    } else |_| {}
    try std.testing.expectEqual(@as(usize, 0), out.written().len);
}
