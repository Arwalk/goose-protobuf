//! Goose emitter: turns one FileDescriptorProto into one .goose file.
//!
//! Naming (final, docs/decisions/0006-naming.md; user code depends on it):
//!   - package `a.b`        -> `namespace a_b;` (no package: global namespace)
//!   - message `Outer.Inner` -> struct `Outer_Inner`
//!   - enum value `RED` of enum `Outer.Color` -> `let Outer_Color_RED: i32`
//!     (Goose enums have no discriminants, so protobuf enums are i32
//!     constants; aliases are separate constants with the same value)
//!   - generated functions and globals are `<path>_<op>`, built from the
//!     unescaped path (`Node_decode`, `Node_set_name`, `Node_pool`)
//!   - a final name on the reserved list (keyword, builtin, `pb_`/`PB_`
//!     prefix) gets a trailing `_` (`message type` -> `type_`;
//!     `struct.self` -> `struct_self`; `message pb_x` -> `pb_x_`)
//!   - a nested type or enum constant whose name is a generated name gets
//!     a trailing `_` (`Outer.decode` -> `Outer_decode_`)
//! Every generated name is claimed before any type or constant. Two
//! declarations that still end up with the same name are an error,
//! reported through CodeGeneratorResponse.error.
//!
//! Output order follows the descriptor (protoc's declaration order), so the
//! same request always yields the same bytes.

const std = @import("std");
const pb_plugin = @import("pb_plugin");
const descriptor = pb_plugin.descriptor;

/// Goose keywords and contextual keywords (Goose reference, Appendix A).
const goose_keywords = [_][]const u8{
    "import",   "namespace", "struct",   "enum",   "type",   "fn",    "thread_fn",
    "export",   "simd",      "recursive", "let",   "var",    "extern", "const",
    "pad",      "reusable",  "if",       "else",   "while",  "for",   "in",
    "loop",     "block",     "guard",    "match",  "return", "break", "continue",
    "as",       "true",      "false",    "null",   "self",   "bool",  "varint",
    "i8",       "i16",       "i32",      "i64",    "u8",     "u16",   "u32",
    "u64",      "f32",       "f64",      "from",   "upto",   "inline", "checkfree",
    "fields",   "types",
};

pub fn isGooseKeyword(name: []const u8) bool {
    for (goose_keywords) |k| {
        if (std.mem.eql(u8, k, name)) return true;
    }
    return false;
}

/// Goose builtins (Goose reference, section 25).
const goose_builtins = [_][]const u8{
    "print",            "str",          "format",                 "assert",
    "abort",            "exit",         "copy",                   "default",
    "hardware_threads", "thread_spawn", "thread_spawn_contained", "thread_wait",
    "qput",             "qget",         "qpoll",                  "qlimit",
    "to_bytes",         "bytes_of",     "from_bytes",             "embed_file",
    "embed_shader",
};

/// True for names a generated declaration may not take as they are:
/// Goose keywords and builtins, and the `pb_`/`PB_` prefixes of the
/// pb_wire runtime (`pb_Span`, `PB_ERR_TRUNCATED`).
pub fn isReserved(name: []const u8) bool {
    if (isGooseKeyword(name)) return true;
    for (goose_builtins) |b| {
        if (std.mem.eql(u8, b, name)) return true;
    }
    return std.mem.startsWith(u8, name, "pb_") or std.mem.startsWith(u8, name, "PB_");
}

/// `name`, with a trailing `_` if it is reserved.
pub fn ident(a: std.mem.Allocator, name: []const u8) ![]const u8 {
    if (isReserved(name)) return std.fmt.allocPrint(a, "{s}_", .{name});
    return name;
}

/// `a.b.c` -> `a_b_c`, escaped if the result is a keyword.
pub fn namespaceName(a: std.mem.Allocator, package: []const u8) ![]const u8 {
    const joined = try a.dupe(u8, package);
    std.mem.replaceScalar(u8, joined, '.', '_');
    return ident(a, joined);
}

/// The unescaped path of a nested declaration: `prefix_name`, or `name` at
/// the top level. Its Goose name is ident() of it.
pub fn nestedPath(a: std.mem.Allocator, prefix: []const u8, name: []const u8) ![]const u8 {
    if (prefix.len == 0) return name;
    return std.fmt.allocPrint(a, "{s}_{s}", .{ prefix, name });
}

/// Operations and globals generated for every message, as `<path>_<op>`
/// (decision 0001: codecs, `M_copy`, the `M_Ref` link, the pools).
pub const message_ops = [_][]const u8{
    "decode", "encode", "size_of", "clear", "copy", "Ref", "pool", "links",
};

/// How a field is stored, which decides its accessors.
pub const FieldKind = enum { scalar, string, message, repeated, map };

/// One accessor of a field: `<path>_<prefix><field><suffix>`.
pub const Accessor = struct { prefix: []const u8, suffix: []const u8 };

/// The accessors generated for a field. This table is the one source of
/// truth for accessor names: the emitters of each field kind use it, and
/// the collision check claims every name in it. Scalars without presence
/// are read and written directly (`m.id = 5`), so they have none.
pub fn fieldAccessors(kind: FieldKind) []const Accessor {
    return switch (kind) {
        .scalar => &.{},
        .string => &.{ .{ .prefix = "", .suffix = "" }, .{ .prefix = "set_", .suffix = "" } },
        .message => &.{.{ .prefix = "", .suffix = "" }},
        .repeated => &.{
            .{ .prefix = "", .suffix = "" },
            .{ .prefix = "", .suffix = "_at" },
            .{ .prefix = "add_", .suffix = "" },
        },
        .map => &.{ .{ .prefix = "", .suffix = "_get" }, .{ .prefix = "", .suffix = "_put" } },
    };
}

/// The extra accessors of a field with explicit presence.
pub const presence_accessors = [_]Accessor{
    .{ .prefix = "has_", .suffix = "" },
    .{ .prefix = "clear_", .suffix = "" },
};

/// The Goose name of a generated function or global of the message at
/// `path` (unescaped): `<path>_<op>`, escaped if reserved.
pub fn generatedName(a: std.mem.Allocator, path: []const u8, op: []const u8) ![]const u8 {
    return ident(a, try std.fmt.allocPrint(a, "{s}_{s}", .{ path, op }));
}

/// The Goose name of accessor `acc` of field `field` of the message at
/// `path` (unescaped).
pub fn accessorName(a: std.mem.Allocator, path: []const u8, field: []const u8, acc: Accessor) ![]const u8 {
    return ident(a, try std.fmt.allocPrint(a, "{s}_{s}{s}{s}", .{ path, acc.prefix, field, acc.suffix }));
}

/// `foo/bar.proto` -> `foo/bar.goose`.
pub fn outputName(a: std.mem.Allocator, proto_name: []const u8) ![]const u8 {
    const stem = if (std.mem.endsWith(u8, proto_name, ".proto"))
        proto_name[0 .. proto_name.len - ".proto".len]
    else
        proto_name;
    return std.fmt.allocPrint(a, "{s}.goose", .{stem});
}

pub const Error = error{NameCollision} || std.mem.Allocator.Error || std.Io.Writer.Error;

/// Generates one file. On error.NameCollision, `diag` holds the message
/// for CodeGeneratorResponse.error.
const Owner = struct {
    /// For the collision message: a protobuf full name, or a description
    /// of a generated name.
    what: []const u8,
    /// A generated function or global, which a nested declaration yields to.
    generated: bool,
};

pub const FileEmitter = struct {
    a: std.mem.Allocator,
    w: *std.Io.Writer,
    file: *const descriptor.FileDescriptorProto,
    /// Goose name -> what claimed it.
    names: std.StringHashMapUnmanaged(Owner) = .empty,
    /// Unescaped message path -> full name. Two messages with one path
    /// also share every generated name; this reports the types instead.
    message_paths: std.StringHashMapUnmanaged([]const u8) = .empty,
    diag: []const u8 = "",

    pub fn emit(self: *FileEmitter) Error!void {
        const f = self.file;
        const proto_name = f.name orelse "";
        try self.w.print(
            \\// Code generated by protoc-gen-goose. DO NOT EDIT.
            \\// source: {s}
            \\
            \\
        , .{proto_name});
        const package = f.package orelse "";
        if (package.len > 0) {
            try self.w.print("namespace {s};\n\n", .{try namespaceName(self.a, package)});
        }
        try self.w.writeAll("import pb_wire;\n");

        for (f.message_type.items) |*m| try self.claimGenerated(m, "", package);

        for (f.enum_type.items) |*e| try self.emitEnum(e, "", package);
        for (f.message_type.items) |*m| try self.emitMessage(m, "", package);
    }

    fn fullName(self: *FileEmitter, scope: []const u8, name: []const u8) ![]const u8 {
        if (scope.len == 0) return name;
        return std.fmt.allocPrint(self.a, "{s}.{s}", .{ scope, name });
    }

    fn claim(self: *FileEmitter, goose_name: []const u8, owner: Owner) Error!void {
        const gop = try self.names.getOrPut(self.a, goose_name);
        if (gop.found_existing) {
            self.diag = try std.fmt.allocPrint(
                self.a,
                "{s}: {s} and {s} both map to the Goose name {s}",
                .{ self.file.name orelse "", gop.value_ptr.what, owner.what, goose_name },
            );
            return error.NameCollision;
        }
        gop.value_ptr.* = owner;
    }

    /// Claims the Goose name of a type or enum constant at `path` and
    /// returns it. A nested declaration whose name is a generated name
    /// gets a trailing `_`; a top-level one is a collision.
    fn claimDecl(self: *FileEmitter, path: []const u8, full: []const u8, nested: bool) Error![]const u8 {
        var goose_name = try ident(self.a, path);
        if (nested) {
            if (self.names.get(goose_name)) |owner| {
                if (owner.generated) goose_name = try std.fmt.allocPrint(self.a, "{s}_", .{goose_name});
            }
        }
        try self.claim(goose_name, .{ .what = full, .generated = false });
        return goose_name;
    }

    /// Claims every function and global generated for `m` and its nested
    /// messages, so that types and constants claimed later yield to them.
    fn claimGenerated(
        self: *FileEmitter,
        m: *const descriptor.DescriptorProto,
        prefix: []const u8,
        scope: []const u8,
    ) Error!void {
        const name = m.name orelse "";
        const path = try nestedPath(self.a, prefix, name);
        const full = try self.fullName(scope, name);
        const gop = try self.message_paths.getOrPut(self.a, path);
        if (gop.found_existing) {
            self.diag = try std.fmt.allocPrint(
                self.a,
                "{s}: {s} and {s} both map to the Goose name {s}",
                .{ self.file.name orelse "", gop.value_ptr.*, full, try ident(self.a, path) },
            );
            return error.NameCollision;
        }
        gop.value_ptr.* = full;
        for (message_ops) |op| {
            try self.claim(try generatedName(self.a, path, op), .{
                .what = try std.fmt.allocPrint(self.a, "generated {s} of {s}", .{ op, full }),
                .generated = true,
            });
        }
        for (m.field.items) |*fd| {
            const fname = fd.name orelse "";
            const kind = fieldKind(m, full, fd);
            const presence: []const Accessor = if (hasPresence(self.file, fd)) &presence_accessors else &.{};
            for ([_][]const Accessor{ fieldAccessors(kind), presence }) |accs| {
                for (accs) |acc| {
                    try self.claim(try accessorName(self.a, path, fname, acc), .{
                        .what = try std.fmt.allocPrint(self.a, "accessor {s}{s}{s} of {s}", .{ acc.prefix, fname, acc.suffix, full }),
                        .generated = true,
                    });
                }
            }
        }
        for (m.nested_type.items) |*n| try self.claimGenerated(n, path, full);
    }

    fn emitEnum(
        self: *FileEmitter,
        e: *const descriptor.EnumDescriptorProto,
        prefix: []const u8,
        scope: []const u8,
    ) Error!void {
        const name = e.name orelse "";
        const path = try nestedPath(self.a, prefix, name);
        const full = try self.fullName(scope, name);
        _ = try self.claimDecl(path, full, prefix.len > 0);
        try self.w.print("\n// enum {s}\n", .{full});
        for (e.value.items) |v| {
            const vname = v.name orelse "";
            const const_name = try self.claimDecl(
                try nestedPath(self.a, path, vname),
                try self.fullName(full, vname),
                true,
            );
            try self.w.print("let {s}: i32 = {d};\n", .{ const_name, v.number orelse 0 });
        }
    }

    fn emitMessage(
        self: *FileEmitter,
        m: *const descriptor.DescriptorProto,
        prefix: []const u8,
        scope: []const u8,
    ) Error!void {
        const name = m.name orelse "";
        const path = try nestedPath(self.a, prefix, name);
        const full = try self.fullName(scope, name);
        const goose_name = try self.claimDecl(path, full, prefix.len > 0);
        try self.w.print("\n// message {s}\n", .{full});
        try self.w.print("struct {s} {{}}\n", .{goose_name});
        for (m.enum_type.items) |*e| try self.emitEnum(e, path, full);
        for (m.nested_type.items) |*n| try self.emitMessage(n, path, full);
    }
};

/// The storage kind of field `fd` of message `m`, whose full name is `full`.
fn fieldKind(m: *const descriptor.DescriptorProto, full: []const u8, fd: *const descriptor.FieldDescriptorProto) FieldKind {
    const t = fd.type orelse .TYPE_INT32;
    const is_msg = t == .TYPE_MESSAGE or t == .TYPE_GROUP;
    if (fd.label == .LABEL_REPEATED) {
        if (is_msg and isMapEntry(m, full, fd.type_name orelse "")) return .map;
        return .repeated;
    }
    if (is_msg) return .message;
    if (t == .TYPE_STRING or t == .TYPE_BYTES) return .string;
    return .scalar;
}

/// True if `type_name` (`.pkg.M.XEntry`) names a map entry nested in `m`.
fn isMapEntry(m: *const descriptor.DescriptorProto, full: []const u8, type_name: []const u8) bool {
    const tn = if (std.mem.startsWith(u8, type_name, ".")) type_name[1..] else type_name;
    if (!std.mem.startsWith(u8, tn, full) or tn.len <= full.len + 1 or tn[full.len] != '.') return false;
    const local = tn[full.len + 1 ..];
    for (m.nested_type.items) |n| {
        if (std.mem.eql(u8, n.name orelse "", local)) {
            const opts = n.options orelse return false;
            return opts.map_entry orelse false;
        }
    }
    return false;
}

/// True if singular field `fd` tracks presence: a message, a proto3
/// `optional`, or any singular field outside proto3.
fn hasPresence(file: *const descriptor.FileDescriptorProto, fd: *const descriptor.FieldDescriptorProto) bool {
    if (fd.label == .LABEL_REPEATED) return false;
    const t = fd.type orelse .TYPE_INT32;
    if (t == .TYPE_MESSAGE or t == .TYPE_GROUP) return true;
    if (fd.proto3_optional orelse false) return true;
    return !std.mem.eql(u8, file.syntax orelse "proto2", "proto3");
}

/// Generates the .goose source for `file` into `w`. Returns the collision
/// message on error.NameCollision through `diag`.
pub fn generateFile(
    a: std.mem.Allocator,
    file: *const descriptor.FileDescriptorProto,
    w: *std.Io.Writer,
    diag: *[]const u8,
) Error!void {
    var fe: FileEmitter = .{ .a = a, .w = w, .file = file };
    fe.emit() catch |err| {
        diag.* = fe.diag;
        return err;
    };
}

test "keywords are escaped" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("match_", try ident(a, "match"));
    try std.testing.expectEqualStrings("Match", try ident(a, "Match"));
    try std.testing.expectEqualStrings("from_", try ident(a, "from"));
    try std.testing.expectEqualStrings("type", try nestedPath(a, "", "type"));
    try std.testing.expectEqualStrings("struct_self", try nestedPath(a, "struct", "self"));
    try std.testing.expectEqualStrings("a_fn_b", try namespaceName(a, "a.fn.b"));
    try std.testing.expectEqualStrings("match_", try namespaceName(a, "match"));
}

test "output names" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("foo/bar.goose", try outputName(a, "foo/bar.proto"));
    try std.testing.expectEqualStrings("x.goose", try outputName(a, "x"));
}

test "nested and top-level names that collide are reported" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var outer: descriptor.DescriptorProto = .{ .name = "A" };
    try outer.nested_type.append(a, .{ .name = "B" });
    var file: descriptor.FileDescriptorProto = .{ .name = "c.proto", .package = "p" };
    try file.message_type.append(a, outer);
    try file.message_type.append(a, .{ .name = "A_B" });

    var out: std.Io.Writer.Allocating = .init(a);
    var diag: []const u8 = "";
    try std.testing.expectError(error.NameCollision, generateFile(a, &file, &out.writer, &diag));
    try std.testing.expectEqualStrings("c.proto: p.A.B and p.A_B both map to the Goose name A_B", diag);
}

test "builtins and runtime prefixes are reserved" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "str", "print", "copy", "default", "thread_spawn", "embed_shader", "pb_x", "pb_Span", "PB_OK" }) |n| {
        try std.testing.expect(isReserved(n));
    }
    for ([_][]const u8{ "Str", "strs", "pbx", "Pb_x", "pb", "my_pb_x", "Outer_decode" }) |n| {
        try std.testing.expect(!isReserved(n));
    }
    try std.testing.expectEqualStrings("str_", try ident(a, "str"));
    try std.testing.expectEqualStrings("pb_x_", try ident(a, "pb_x"));
    try std.testing.expectEqualStrings("type_decode", try generatedName(a, "type", "decode"));
    try std.testing.expectEqualStrings("pb_x_decode_", try generatedName(a, "pb_x", "decode"));
    try std.testing.expectEqualStrings("Node_set_name", try accessorName(a, "Node", "name", .{ .prefix = "set_", .suffix = "" }));
    try std.testing.expectEqualStrings("Node_children_at", try accessorName(a, "Node", "children", .{ .prefix = "", .suffix = "_at" }));
}

fn generateForTest(a: std.mem.Allocator, file: *const descriptor.FileDescriptorProto, diag: *[]const u8) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(a);
    try generateFile(a, file, &out.writer, diag);
    return out.written();
}

test "nested names equal to generated names are escaped" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var node: descriptor.DescriptorProto = .{ .name = "Node" };
    try node.field.append(a, .{ .name = "name", .number = 1, .label = .LABEL_OPTIONAL, .type = .TYPE_STRING });
    try node.nested_type.append(a, .{ .name = "decode" });
    try node.nested_type.append(a, .{ .name = "set_name" });
    var file: descriptor.FileDescriptorProto = .{ .name = "n.proto", .syntax = "proto3" };
    try file.message_type.append(a, node);

    var diag: []const u8 = "";
    const out = try generateForTest(a, &file, &diag);
    try std.testing.expect(std.mem.indexOf(u8, out, "struct Node_decode_ {}") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "struct Node_set_name_ {}") != null);
}

test "a top-level name equal to a generated name is a collision" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var file: descriptor.FileDescriptorProto = .{ .name = "t.proto", .package = "p", .syntax = "proto3" };
    try file.message_type.append(a, .{ .name = "Outer" });
    try file.message_type.append(a, .{ .name = "Outer_decode" });

    var diag: []const u8 = "";
    try std.testing.expectError(error.NameCollision, generateForTest(a, &file, &diag));
    try std.testing.expectEqualStrings(
        "t.proto: generated decode of p.Outer and p.Outer_decode both map to the Goose name Outer_decode",
        diag,
    );
}

test "two accessors with the same name are a collision" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m: descriptor.DescriptorProto = .{ .name = "M" };
    try m.field.append(a, .{ .name = "x", .number = 1, .label = .LABEL_OPTIONAL, .type = .TYPE_STRING });
    try m.field.append(a, .{ .name = "set_x", .number = 2, .label = .LABEL_OPTIONAL, .type = .TYPE_STRING });
    var file: descriptor.FileDescriptorProto = .{ .name = "t.proto", .syntax = "proto3" };
    try file.message_type.append(a, m);

    var diag: []const u8 = "";
    try std.testing.expectError(error.NameCollision, generateForTest(a, &file, &diag));
    try std.testing.expectEqualStrings(
        "t.proto: accessor set_x of M and accessor set_x of M both map to the Goose name M_set_x",
        diag,
    );
}

test "an escaped name that is still taken is a collision" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var outer: descriptor.DescriptorProto = .{ .name = "Outer" };
    try outer.nested_type.append(a, .{ .name = "decode_" });
    try outer.nested_type.append(a, .{ .name = "decode" });
    var file: descriptor.FileDescriptorProto = .{ .name = "t.proto", .syntax = "proto3" };
    try file.message_type.append(a, outer);

    var diag: []const u8 = "";
    try std.testing.expectError(error.NameCollision, generateForTest(a, &file, &diag));
    try std.testing.expectEqualStrings(
        "t.proto: Outer.decode_ and Outer.decode both map to the Goose name Outer_decode_",
        diag,
    );
}

test "field kinds and presence" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m: descriptor.DescriptorProto = .{ .name = "M" };
    try m.nested_type.append(a, .{ .name = "AEntry", .options = .{ .map_entry = true } });
    try m.nested_type.append(a, .{ .name = "Sub" });
    const map_f: descriptor.FieldDescriptorProto = .{ .name = "a", .label = .LABEL_REPEATED, .type = .TYPE_MESSAGE, .type_name = ".p.M.AEntry" };
    const rep_f: descriptor.FieldDescriptorProto = .{ .name = "s", .label = .LABEL_REPEATED, .type = .TYPE_MESSAGE, .type_name = ".p.M.Sub" };
    const msg_f: descriptor.FieldDescriptorProto = .{ .name = "b", .label = .LABEL_OPTIONAL, .type = .TYPE_MESSAGE, .type_name = ".p.M.Sub" };
    const str_f: descriptor.FieldDescriptorProto = .{ .name = "c", .label = .LABEL_OPTIONAL, .type = .TYPE_BYTES };
    const int_f: descriptor.FieldDescriptorProto = .{ .name = "d", .label = .LABEL_OPTIONAL, .type = .TYPE_INT64 };
    const opt_f: descriptor.FieldDescriptorProto = .{ .name = "e", .label = .LABEL_OPTIONAL, .type = .TYPE_INT64, .proto3_optional = true };
    try std.testing.expectEqual(FieldKind.map, fieldKind(&m, "p.M", &map_f));
    try std.testing.expectEqual(FieldKind.repeated, fieldKind(&m, "p.M", &rep_f));
    try std.testing.expectEqual(FieldKind.message, fieldKind(&m, "p.M", &msg_f));
    try std.testing.expectEqual(FieldKind.string, fieldKind(&m, "p.M", &str_f));
    try std.testing.expectEqual(FieldKind.scalar, fieldKind(&m, "p.M", &int_f));

    const p3: descriptor.FileDescriptorProto = .{ .syntax = "proto3" };
    const p2: descriptor.FileDescriptorProto = .{};
    try std.testing.expect(!hasPresence(&p3, &int_f));
    try std.testing.expect(hasPresence(&p3, &opt_f));
    try std.testing.expect(hasPresence(&p3, &msg_f));
    try std.testing.expect(!hasPresence(&p3, &rep_f));
    try std.testing.expect(hasPresence(&p2, &int_f));
}
