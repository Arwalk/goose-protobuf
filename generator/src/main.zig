//! protoc-gen-goose: protoc plugin that emits Goose code for the protobuf
//! binary wire format.

const std = @import("std");
const pb_plugin = @import("pb_plugin");
const plugin = pb_plugin.plugin;
const descriptor = pb_plugin.descriptor;
const emit = @import("emit.zig");

test {
    _ = emit;
}

/// CodeGeneratorResponse.Feature.FEATURE_PROTO3_OPTIONAL.
pub const FEATURE_PROTO3_OPTIONAL: u64 = 1;
/// CodeGeneratorResponse.Feature.FEATURE_SUPPORTS_EDITIONS.
pub const FEATURE_SUPPORTS_EDITIONS: u64 = 2;

/// The range of editions the plugin takes, as google.protobuf.Edition values:
/// EDITION_PROTO2 and EDITION_2023.
pub const MINIMUM_EDITION: i32 = 998;
pub const MAXIMUM_EDITION: i32 = 1000;

/// Decodes a serialized CodeGeneratorRequest from `input` and writes the
/// serialized CodeGeneratorResponse to `out`: one .goose file per file to
/// generate, or `error` (and no files) for input the generator rejects.
/// Nothing is written if the request fails to decode.
pub fn run(gpa: std.mem.Allocator, input: []const u8, out: *std.Io.Writer) !void {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    var reader: std.Io.Reader = .fixed(input);
    const request: plugin.CodeGeneratorRequest = try .decode(&reader, allocator);

    var response: plugin.CodeGeneratorResponse = .{
        .supported_features = FEATURE_PROTO3_OPTIONAL | FEATURE_SUPPORTS_EDITIONS,
        .minimum_edition = MINIMUM_EDITION,
        .maximum_edition = MAXIMUM_EDITION,
    };
    generate(allocator, &request, &response) catch |err| switch (err) {
        error.Rejected => response.file = .empty,
        else => return err,
    };
    try response.encode(out, allocator);
}

/// Fills response.file, or sets response.error and returns error.Rejected.
/// The well-known types ship in the pb_wire package, so a file naming one
/// writes nothing. The parameter `wkt` writes those instead, as wkt/x.goose:
/// scripts/wkt.sh regenerates the package's copy with it.
fn generate(
    a: std.mem.Allocator,
    request: *const plugin.CodeGeneratorRequest,
    response: *plugin.CodeGeneratorResponse,
) !void {
    const parameter = request.parameter orelse "";
    const wkt = std.mem.eql(u8, parameter, "wkt");
    if (parameter.len > 0 and !wkt) {
        response.@"error" = try std.fmt.allocPrint(a, "unknown parameter: {s}", .{parameter});
        return error.Rejected;
    }
    var outputs: std.StringHashMapUnmanaged([]const u8) = .empty;
    for (request.file_to_generate.items) |name| {
        const file = findFile(request, name) orelse {
            response.@"error" = try std.fmt.allocPrint(a, "{s}: not in proto_file", .{name});
            return error.Rejected;
        };
        if (emit.isWellKnown(file) != wkt) {
            if (!wkt) continue;
            response.@"error" = try std.fmt.allocPrint(a, "{s}: not a well-known type", .{name});
            return error.Rejected;
        }
        var content: std.Io.Writer.Allocating = .init(a);
        var diag: []const u8 = "";
        emit.generateFile(a, file, request.proto_file.items, &content.writer, &diag) catch |err| switch (err) {
            error.NameCollision => {
                response.@"error" = diag;
                return error.Rejected;
            },
            else => return err,
        };
        const output = if (wkt) try emit.wellKnownOutputName(a, name) else try emit.outputName(a, name);
        const gop = try outputs.getOrPut(a, output);
        if (gop.found_existing) {
            response.@"error" = try std.fmt.allocPrint(
                a,
                "{s} and {s} both map to the Goose file {s}",
                .{ gop.value_ptr.*, name, output },
            );
            return error.Rejected;
        }
        gop.value_ptr.* = name;
        try response.file.append(a, .{ .name = output, .content = content.written() });
    }
}

fn findFile(request: *const plugin.CodeGeneratorRequest, name: []const u8) ?*const descriptor.FileDescriptorProto {
    for (request.proto_file.items) |*f| {
        if (std.mem.eql(u8, f.name orelse "", name)) return f;
    }
    return null;
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

test "request with nothing to generate yields proto3 optional and no files" {
    const gpa = std.testing.allocator;
    const req: plugin.CodeGeneratorRequest = .{};

    var req_bytes: std.Io.Writer.Allocating = .init(gpa);
    defer req_bytes.deinit();
    try req.encode(&req_bytes.writer, gpa);

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try run(gpa, req_bytes.written(), &out.writer);

    // supported_features 3, minimum_edition 998, maximum_edition 1000.
    try std.testing.expectEqualSlices(u8, &.{ 0x10, 0x03, 0x18, 0xe6, 0x07, 0x20, 0xe8, 0x07 }, out.written());

    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var reader: std.Io.Reader = .fixed(out.written());
    const res: plugin.CodeGeneratorResponse = try .decode(&reader, arena.allocator());
    try std.testing.expectEqual(@as(?u64, FEATURE_PROTO3_OPTIONAL | FEATURE_SUPPORTS_EDITIONS), res.supported_features);
    try std.testing.expectEqual(@as(?i32, MINIMUM_EDITION), res.minimum_edition);
    try std.testing.expectEqual(@as(?i32, MAXIMUM_EDITION), res.maximum_edition);
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

fn runOn(a: std.mem.Allocator, req: *const plugin.CodeGeneratorRequest) !plugin.CodeGeneratorResponse {
    var req_bytes: std.Io.Writer.Allocating = .init(a);
    try req.encode(&req_bytes.writer, a);
    var out: std.Io.Writer.Allocating = .init(a);
    try run(std.testing.allocator, req_bytes.written(), &out.writer);
    var reader: std.Io.Reader = .fixed(out.written());
    return try .decode(&reader, a);
}

test "one .goose file per file to generate" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var req: plugin.CodeGeneratorRequest = .{};
    try req.file_to_generate.append(a, "dir/a.proto");
    var file: descriptor.FileDescriptorProto = .{ .name = "dir/a.proto", .package = "pkg.sub" };
    try file.message_type.append(a, .{ .name = "M" });
    try req.proto_file.append(a, .{ .name = "dep.proto" });
    try req.proto_file.append(a, file);

    const res = try runOn(a, &req);
    try std.testing.expectEqual(@as(?[]const u8, null), res.@"error");
    try std.testing.expectEqual(@as(usize, 1), res.file.items.len);
    try std.testing.expectEqualStrings("dir/a.goose", res.file.items[0].name.?);
    // The rest of the file is covered by the golden tests.
    const content = res.file.items[0].content.?;
    try std.testing.expectStringStartsWith(content,
        \\// Code generated by protoc-gen-goose. DO NOT EDIT.
        \\// source: dir/a.proto
        \\
    );
    try std.testing.expect(std.mem.indexOf(u8, content,
        \\namespace pkg_sub;
        \\
        \\import pb_wire;
        \\
        \\// message pkg.sub.M
        \\struct M {
        \\    pb_unknown: pb_Span,   // unknown fields: raw wire bytes in pb_bytes
        \\}
        \\
    ) != null);
}

test "a name collision is a response error with no files" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var req: plugin.CodeGeneratorRequest = .{};
    try req.file_to_generate.append(a, "ok.proto");
    try req.file_to_generate.append(a, "bad.proto");
    try req.proto_file.append(a, .{ .name = "ok.proto" });
    var bad: descriptor.FileDescriptorProto = .{ .name = "bad.proto" };
    var e: descriptor.EnumDescriptorProto = .{ .name = "E" };
    try e.value.append(a, .{ .name = "X", .number = 0 });
    try bad.enum_type.append(a, e);
    try bad.message_type.append(a, .{ .name = "E_X" });
    try req.proto_file.append(a, bad);

    const res = try runOn(a, &req);
    try std.testing.expectEqualStrings("bad.proto: E.X and E_X both map to the Goose name E_X", res.@"error".?);
    try std.testing.expectEqual(@as(usize, 0), res.file.items.len);
}

test "two protos with one output file are a response error with no files" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var req: plugin.CodeGeneratorRequest = .{};
    try req.file_to_generate.append(a, "a.b.proto");
    try req.file_to_generate.append(a, "c.proto");
    try req.file_to_generate.append(a, "a-b.proto");
    try req.proto_file.append(a, .{ .name = "a.b.proto" });
    try req.proto_file.append(a, .{ .name = "c.proto" });
    try req.proto_file.append(a, .{ .name = "a-b.proto" });

    const res = try runOn(a, &req);
    try std.testing.expectEqualStrings("a.b.proto and a-b.proto both map to the Goose file a_b.goose", res.@"error".?);
    try std.testing.expectEqual(@as(usize, 0), res.file.items.len);
}

test "a well-known file writes nothing, unless the parameter asks for it" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var req: plugin.CodeGeneratorRequest = .{};
    try req.file_to_generate.append(a, "google/protobuf/empty.proto");
    try req.proto_file.append(a, .{ .name = "google/protobuf/empty.proto", .package = "google.protobuf" });

    var res = try runOn(a, &req);
    try std.testing.expectEqual(@as(?[]const u8, null), res.@"error");
    try std.testing.expectEqual(@as(usize, 0), res.file.items.len);

    req.parameter = "wkt";
    res = try runOn(a, &req);
    try std.testing.expectEqual(@as(?[]const u8, null), res.@"error");
    try std.testing.expectEqualStrings("wkt/empty.goose", res.file.items[0].name.?);
}

test "the wkt parameter refuses other files, and others are refused" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var req: plugin.CodeGeneratorRequest = .{ .parameter = "wkt" };
    try req.file_to_generate.append(a, "a.proto");
    try req.proto_file.append(a, .{ .name = "a.proto" });
    var res = try runOn(a, &req);
    try std.testing.expectEqualStrings("a.proto: not a well-known type", res.@"error".?);

    req.parameter = "nope";
    res = try runOn(a, &req);
    try std.testing.expectEqualStrings("unknown parameter: nope", res.@"error".?);
    try std.testing.expectEqual(@as(usize, 0), res.file.items.len);
}
