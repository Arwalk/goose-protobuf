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
/// (decisions 0001 and 0004: codecs, `M_copy`, the `M_Ref` link, the pools).
pub const message_ops = [_][]const u8{
    "decode", "decode_from", "encode", "size_of", "clear", "copy", "Ref", "pool", "links",
};

/// How a field is stored, which decides its accessors.
pub const FieldKind = enum { scalar, string, message, repeated, map };

/// One accessor of a field: `<path>_<prefix><field><suffix>`.
pub const Accessor = struct { prefix: []const u8, suffix: []const u8 };

/// The accessors generated for a field. This table is the one source of
/// truth for accessor names: the emitters of each field kind use it, and
/// the collision check claims every name in it. Scalars are read
/// directly (`m.id`); without presence they are also written directly
/// (`m.id = 5`), so they have none. A scalar with presence is written
/// with `set_`, which also sets its has-bit.
pub fn fieldAccessors(kind: FieldKind, presence: bool) []const Accessor {
    return switch (kind) {
        .scalar => if (presence) &(.{set_acc} ++ presence_accessors) else &.{},
        .string => if (presence)
            &(.{ get_acc, set_acc } ++ presence_accessors)
        else
            &.{ get_acc, set_acc },
        .message => &(.{ get_acc, mutable_acc } ++ presence_accessors),
        .repeated => &.{
            .{ .prefix = "", .suffix = "" },
            .{ .prefix = "", .suffix = "_at" },
            .{ .prefix = "add_", .suffix = "" },
        },
        .map => &.{ .{ .prefix = "", .suffix = "_get" }, .{ .prefix = "", .suffix = "_put" } },
    };
}

const get_acc: Accessor = .{ .prefix = "", .suffix = "" };
const set_acc: Accessor = .{ .prefix = "set_", .suffix = "" };
const has_acc: Accessor = .{ .prefix = "has_", .suffix = "" };
const clear_acc: Accessor = .{ .prefix = "clear_", .suffix = "" };
const mutable_acc: Accessor = .{ .prefix = "mutable_", .suffix = "" };

/// The accessors every field with explicit presence has.
const presence_accessors = [_]Accessor{ has_acc, clear_acc };

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

/// The output file of a .proto, which `import a.b.c;` loads as a/b/c.goose:
/// `api/foo.v1.proto` -> `api/foo_v1.goose`. In each path segment, whatever
/// an identifier cannot hold becomes `_`, a leading digit gets a `_` before
/// it, and a reserved result is escaped.
pub fn outputName(a: std.mem.Allocator, proto_name: []const u8) ![]const u8 {
    const stem = if (std.mem.endsWith(u8, proto_name, ".proto"))
        proto_name[0 .. proto_name.len - ".proto".len]
    else
        proto_name;
    var out: std.ArrayList(u8) = .empty;
    var segments = std.mem.splitScalar(u8, stem, '/');
    var first = true;
    while (segments.next()) |segment| {
        if (!first) try out.append(a, '/');
        first = false;
        const mangled = try a.dupe(u8, segment);
        for (mangled) |*c| {
            if (!std.ascii.isAlphanumeric(c.*) and c.* != '_') c.* = '_';
        }
        if (mangled.len > 0 and std.ascii.isDigit(mangled[0])) try out.append(a, '_');
        try out.appendSlice(a, try ident(a, mangled));
    }
    try out.appendSlice(a, ".goose");
    return out.items;
}

/// How a generated file imports the file generated from `proto_name`.
/// Goose resolves it from the root file's directory.
pub fn importPath(a: std.mem.Allocator, proto_name: []const u8) ![]const u8 {
    const out = try outputName(a, proto_name);
    const path = try a.dupe(u8, out[0 .. out.len - ".goose".len]);
    std.mem.replaceScalar(u8, path, '/', '.');
    return path;
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
    /// Every file of the request, where the types of imported files are.
    files: []const descriptor.FileDescriptorProto,
    /// Goose name -> what claimed it.
    names: std.StringHashMapUnmanaged(Owner) = .empty,
    /// Unescaped message path -> full name. Two messages with one path
    /// also share every generated name; this reports the types instead.
    message_paths: std.StringHashMapUnmanaged([]const u8) = .empty,
    /// Full name of a type or enum value in this file -> its Goose name.
    decls: std.StringHashMapUnmanaged([]const u8) = .empty,
    /// Full name of a message in this file -> the message.
    messages: std.StringHashMapUnmanaged(MessageInfo) = .empty,
    /// Full name of a message of another file whose names are claimed ->
    /// the message, its names qualified from this file.
    foreign: std.StringHashMapUnmanaged(MessageInfo) = .empty,
    /// Other files whose names are claimed, by their proto name.
    foreign_files: std.StringHashMapUnmanaged(void) = .empty,
    /// Import paths of the files that the stored fields need.
    imports: std.StringHashMapUnmanaged(void) = .empty,
    /// How the codec functions of the current message are declared.
    fn_kw: []const u8 = "fn",
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
        try self.w.writeAll(api_comment);
        const package = f.package orelse "";
        if (package.len > 0) {
            try self.w.print("namespace {s};\n\n", .{try namespaceName(self.a, package)});
        }
        try self.w.writeAll("import pb_wire;\n");

        try self.claimAll();
        for (f.message_type.items) |*m| try self.collectImports(m);
        const imports = try self.a.alloc([]const u8, self.imports.count());
        var it = self.imports.keyIterator();
        for (imports) |*i| i.* = it.next().?.*;
        std.mem.sortUnstable([]const u8, imports, {}, stringLess);
        for (imports) |i| try self.w.print("import {s};\n", .{i});

        for (f.enum_type.items) |*e| try self.emitEnum(e, package);
        for (f.message_type.items) |*m| try self.emitMessage(m, "", package);
    }

    /// Claims every name of the file, in the order the declarations are
    /// emitted, so that generated names come first.
    fn claimAll(self: *FileEmitter) Error!void {
        const f = self.file;
        const package = f.package orelse "";
        for (f.message_type.items) |*m| try self.claimGenerated(m, "", package);
        for (f.enum_type.items) |*e| try self.claimEnum(e, "", package);
        for (f.message_type.items) |*m| try self.claimMessage(m, "", package);
    }

    /// Records the files the stored fields of `m` and its nested messages
    /// need. Importing only those lets a file build without the others.
    fn collectImports(self: *FileEmitter, m: *const descriptor.DescriptorProto) Error!void {
        for (m.field.items) |*fd| _ = try self.subMessageOf(fd);
        for (m.nested_type.items) |*n| try self.collectImports(n);
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
            for (fieldAccessors(kind, hasPresence(self.file, fd))) |acc| {
                try self.claim(try accessorName(self.a, path, fname, acc), .{
                    .what = try std.fmt.allocPrint(self.a, "accessor {s}{s}{s} of {s}", .{ acc.prefix, fname, acc.suffix, full }),
                    .generated = true,
                });
            }
        }
        for (m.nested_type.items) |*n| try self.claimGenerated(n, path, full);
    }

    /// Claims the names of an enum and its values, in the order they are
    /// emitted.
    fn claimEnum(
        self: *FileEmitter,
        e: *const descriptor.EnumDescriptorProto,
        prefix: []const u8,
        scope: []const u8,
    ) Error!void {
        const name = e.name orelse "";
        const path = try nestedPath(self.a, prefix, name);
        const full = try self.fullName(scope, name);
        try self.decls.put(self.a, full, try self.claimDecl(path, full, prefix.len > 0));
        for (e.value.items) |v| {
            const vname = v.name orelse "";
            const vfull = try self.fullName(full, vname);
            try self.decls.put(self.a, vfull, try self.claimDecl(try nestedPath(self.a, path, vname), vfull, true));
        }
    }

    /// Claims the names of a message and what is nested in it, in the
    /// order they are emitted. Fields name their types through this, and
    /// a type may be declared after the field that uses it.
    fn claimMessage(
        self: *FileEmitter,
        m: *const descriptor.DescriptorProto,
        prefix: []const u8,
        scope: []const u8,
    ) Error!void {
        const name = m.name orelse "";
        const path = try nestedPath(self.a, prefix, name);
        const full = try self.fullName(scope, name);
        const goose_name = try self.claimDecl(path, full, prefix.len > 0);
        try self.decls.put(self.a, full, goose_name);
        try self.messages.put(self.a, full, .{ .desc = m, .path = path, .goose_name = goose_name });
        for (m.enum_type.items) |*e| try self.claimEnum(e, path, full);
        for (m.nested_type.items) |*n| try self.claimMessage(n, path, full);
    }

    /// The message that field `fd` stores as a sub-message, or null if it
    /// is not stored.
    fn subMessageOf(self: *FileEmitter, fd: *const descriptor.FieldDescriptorProto) Error!?MessageInfo {
        if (!isStorable(self.file, fd) or fd.type != .TYPE_MESSAGE) return null;
        const tn = fd.type_name orelse return null;
        const t = if (std.mem.startsWith(u8, tn, ".")) tn[1..] else tn;
        if (self.messages.get(t)) |info| return info;
        return self.foreignMessage(t);
    }

    /// Message `t` of another file, whose names it claims the first time
    /// (as generating that file does), and which it marks for import.
    fn foreignMessage(self: *FileEmitter, t: []const u8) Error!?MessageInfo {
        if (self.foreign.get(t)) |info| return info;
        for (self.files) |*f| {
            const fname = f.name orelse "";
            if (std.mem.eql(u8, fname, self.file.name orelse "") or self.foreign_files.contains(fname)) continue;
            if (!try self.declaresMessage(f.message_type.items, f.package orelse "", t)) continue;
            try self.foreign_files.put(self.a, fname, {});
            var other: FileEmitter = .{ .a = self.a, .w = self.w, .file = f, .files = self.files };
            other.claimAll() catch |err| {
                self.diag = other.diag;
                return err;
            };
            const ns = try self.qualifier(f.package orelse "");
            var it = other.messages.iterator();
            while (it.next()) |e| {
                var info = e.value_ptr.*;
                info.ns = ns;
                info.goose_name = try std.fmt.allocPrint(self.a, "{s}{s}", .{ ns, info.goose_name });
                info.import_path = try importPath(self.a, fname);
                try self.foreign.put(self.a, e.key_ptr.*, info);
            }
            break;
        }
        const info = self.foreign.get(t) orelse return null;
        try self.imports.put(self.a, info.import_path, {});
        return info;
    }

    fn declaresMessage(self: *FileEmitter, msgs: []const descriptor.DescriptorProto, scope: []const u8, t: []const u8) Error!bool {
        for (msgs) |*m| {
            const full = try self.fullName(scope, m.name orelse "");
            if (std.mem.eql(u8, full, t)) return true;
            if (try self.declaresMessage(m.nested_type.items, full, t)) return true;
        }
        return false;
    }

    /// What names in the namespace of `package` are written with from
    /// this file.
    fn qualifier(self: *FileEmitter, package: []const u8) Error![]const u8 {
        if (std.mem.eql(u8, package, self.file.package orelse "")) return "";
        if (package.len == 0) return "::";
        return std.fmt.allocPrint(self.a, "{s}::", .{try namespaceName(self.a, package)});
    }

    /// The name of generated function or global `op` of `sub`, as this file
    /// writes it.
    fn subName(self: *FileEmitter, sub: MessageInfo, op: []const u8) Error![]const u8 {
        return std.fmt.allocPrint(self.a, "{s}{s}", .{ sub.ns, try generatedName(self.a, sub.path, op) });
    }

    /// True if a message of type `full` can hold another of its type: its
    /// codec functions are in a cycle, so they are `recursive fn`.
    fn isRecursive(self: *FileEmitter, full: []const u8) Error!bool {
        const info = self.messages.get(full) orelse return false;
        for (info.desc.field.items) |*fd| {
            const t = self.sameFileMessageType(fd) orelse continue;
            var seen: std.StringHashMapUnmanaged(void) = .empty;
            if (try self.reaches(t, full, &seen)) return true;
        }
        return false;
    }

    /// The full name of the message in this file that `fd` holds, if it
    /// is a field kind this generator stores.
    fn sameFileMessageType(self: *FileEmitter, fd: *const descriptor.FieldDescriptorProto) ?[]const u8 {
        if (!isStorable(self.file, fd) or fd.type != .TYPE_MESSAGE) return null;
        const tn = fd.type_name orelse return null;
        const t = if (std.mem.startsWith(u8, tn, ".")) tn[1..] else tn;
        return if (self.messages.contains(t)) t else null;
    }

    /// True if a message of type `from` can hold one of type `target`.
    fn reaches(self: *FileEmitter, from: []const u8, target: []const u8, seen: *std.StringHashMapUnmanaged(void)) Error!bool {
        if (std.mem.eql(u8, from, target)) return true;
        if ((try seen.getOrPut(self.a, from)).found_existing) return false;
        const info = self.messages.get(from) orelse return false;
        for (info.desc.field.items) |*fd| {
            const t = self.sameFileMessageType(fd) orelse continue;
            if (try self.reaches(t, target, seen)) return true;
        }
        return false;
    }

    fn emitEnum(
        self: *FileEmitter,
        e: *const descriptor.EnumDescriptorProto,
        scope: []const u8,
    ) Error!void {
        const full = try self.fullName(scope, e.name orelse "");
        try self.w.print("\n// enum {s}\n", .{full});
        for (e.value.items) |v| {
            const const_name = self.decls.get(try self.fullName(full, v.name orelse "")).?;
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
        const goose_name = self.decls.get(full).?;
        try self.w.print("\n// message {s}\n", .{full});

        // The fields this generator stores; every other field is kept as an
        // unknown field.
        var fields: std.ArrayList(Field) = .empty;
        var record_names: std.StringHashMapUnmanaged(void) = .empty;
        var bits: u32 = 0;
        for (m.field.items) |*fd| {
            const sub = try self.subMessageOf(fd);
            const sc = if (sub) |s| try self.refStorage(s) else scalarOf(self.file, fd) orelse continue;
            const rname = try ident(self.a, fd.name orelse "");
            if ((try record_names.getOrPut(self.a, rname)).found_existing) {
                self.diag = try std.fmt.allocPrint(
                    self.a,
                    "{s}: two fields of {s} map to the Goose record field {s}",
                    .{ self.file.name orelse "", full, rname },
                );
                return error.NameCollision;
            }
            var bit: ?u32 = null;
            if (sub == null and hasPresence(self.file, fd)) {
                bit = bits;
                bits += 1;
            }
            try fields.append(self.a, .{ .fd = fd, .sc = sc, .name = rname, .bit = bit, .sub = sub });
        }
        const has_words = (bits + 31) / 32;
        const by_number = try self.a.dupe(Field, fields.items);
        std.mem.sortUnstable(Field, by_number, {}, Field.lessThan);
        self.fn_kw = if (try self.isRecursive(full)) "recursive fn" else "fn";

        try self.emitRecord(goose_name, fields.items, has_words);
        try self.emitPools(goose_name, path);
        try self.emitDecode(goose_name, path, fields.items);
        try self.emitEncode(goose_name, path, by_number);
        try self.emitSizeOf(goose_name, path, by_number);
        try self.emitClear(goose_name, path, fields.items, has_words);
        try self.emitCopy(goose_name, path, fields.items, has_words);
        for (fields.items) |f| try self.emitAccessors(goose_name, path, f);

        for (m.enum_type.items) |*e| try self.emitEnum(e, full);
        for (m.nested_type.items) |*n| try self.emitMessage(n, path, full);
    }

    /// The storage of a sub-message field: a link, whose presence is the
    /// field's. Only its type and wire type apply: the emitters handle
    /// the rest of a field with `sub` set themselves.
    fn refStorage(self: *FileEmitter, sub: MessageInfo) Error!*const Scalar {
        const sc = try self.a.create(Scalar);
        sc.* = .{
            .goose = try self.subName(sub, "Ref"),
            .wire = 2,
            .clear = "",
            .read = "",
            .write = "",
            .nonzero = "",
            .size = .message,
        };
        return sc;
    }

    fn emitRecord(self: *FileEmitter, goose_name: []const u8, fields: []const Field, has_words: u32) Error!void {
        try self.w.print("struct {s} {{\n", .{goose_name});
        for (fields) |f| try self.w.print("    {s}: {s},\n", .{ f.name, f.sc.goose });
        for (0..has_words) |i| try self.w.print("    pb_has{d}: u32,   // has-bits of fields with presence\n", .{i});
        try self.w.writeAll("    pb_unknown: pb_Span,   // unknown fields: raw wire bytes in pb_bytes\n}\n");
    }

    /// The link type and pools of decision 0001: sub-messages of this type
    /// live one per slot in M_pool, and repeated fields hold runs of links
    /// in M_links.
    fn emitPools(self: *FileEmitter, goose_name: []const u8, path: []const u8) Error!void {
        const ref = try generatedName(self.a, path, "Ref");
        const pool = try generatedName(self.a, path, "pool");
        try self.w.print(
            \\
            \\// A link to a {s} in {s}, for sub-message fields.
            \\struct {s} {{ m: {s}&<u32 in {s}>? }}
            \\reusable var {s}: {s}[>..] = [];
            \\reusable[] var {s}: {s}[>..] = [];
            \\
        , .{ goose_name, pool, ref, goose_name, pool, pool, goose_name, try generatedName(self.a, path, "links"), ref });
    }

    fn emitDecode(self: *FileEmitter, goose_name: []const u8, path: []const u8, fields: []const Field) Error!void {
        const decode = try generatedName(self.a, path, "decode");
        const decode_from = try generatedName(self.a, path, "decode_from");
        try self.w.print(
            \\
            \\// Merges the fields in r's window into m; on failure r.err is set.
            \\// Fields it does not know, or with another wire type, are kept as
            \\// unknown fields.
            \\{s} {s}(r: pb_Reader&, m: {s}&) {{
            \\    var unknown_len: i64 = m.pb_unknown.len;
            \\    while r.pos < r.end {{
            \\        let start = r.pos;
            \\        let tag = pb_read_tag(r);
            \\        if r.err != PB_OK {{ break; }}
            \\
        , .{ self.fn_kw, decode_from, goose_name });
        for (fields, 0..) |f, i| {
            try self.w.print("        {s}if tag == {d} {{\n", .{ if (i == 0) "" else "} else ", f.tag() });
            const x = try std.fmt.allocPrint(self.a, "m.{s}", .{f.name});
            if (f.sub) |sub| {
                try self.emitDecodeSubMessage(path, f, sub);
                continue;
            }
            try self.w.print("            {s} = {f};\n", .{ x, Subst{ .t = f.sc.read, .x = x } });
            if (f.bit) |b| try self.w.print("            m.pb_has{d} |= 0x{x:0>8};\n", .{ b / 32, bitMask(b) });
        }
        if (fields.len == 0) {
            try self.w.writeAll("        pb_unknown_append(r, start, tag, m.pb_unknown, unknown_len);\n");
        } else {
            try self.w.writeAll(
                \\        } else {
                \\            pb_unknown_append(r, start, tag, m.pb_unknown, unknown_len);
                \\        }
                \\
            );
        }
        try self.w.print(
            \\    }}
            \\    m.pb_unknown = pb_bytes_trim(m.pb_unknown, unknown_len);
            \\}}
            \\
            \\// Merges buf into m. 0 on success, else a PB_ERR_* code; m then holds a
            \\// partial message, which the caller clears.
            \\fn {s}(buf: const u8[:], m: {s}&) -> i32 {{
            \\    var r = pb_reader(buf);
            \\    {s}(r, m);
            \\    return r.err;
            \\}}
            \\
        , .{ decode, goose_name, decode_from });
    }

    /// The branch of decode_from for a sub-message: an occurrence merges
    /// into the message already there (decision 0004). After a failure
    /// r.end is not restored: the caller stops on r.err too.
    fn emitDecodeSubMessage(self: *FileEmitter, path: []const u8, f: Field, sub: MessageInfo) Error!void {
        try self.w.print(
            \\            let pb_n = pb_read_len(r);
            \\            if r.err != PB_OK {{ break; }}
            \\            if r.depth >= PB_MAX_DEPTH {{ pb_fail(r, PB_ERR_DEPTH); break; }}
            \\            let pb_outer = r.end;
            \\            r.end = r.pos + pb_n;
            \\            r.depth++;
            \\            {s}(r, {s}(m));
            \\            if r.err != PB_OK {{ break; }}
            \\            r.depth--;
            \\            r.end = pb_outer;
            \\
        , .{ try self.subName(sub, "decode_from"), try accessorName(self.a, path, f.fd.name orelse "", mutable_acc) });
    }

    fn emitEncode(self: *FileEmitter, goose_name: []const u8, path: []const u8, fields: []const Field) Error!void {
        try self.w.print(
            \\
            \\// Appends m's wire encoding, {s}(m) bytes, to out.
            \\{s} {s}(m: {s}&, out: u8[>..]&) {{
            \\
        , .{ try generatedName(self.a, path, "size_of"), self.fn_kw, try generatedName(self.a, path, "encode"), goose_name });
        for (fields) |f| {
            const x = try std.fmt.allocPrint(self.a, "m.{s}", .{f.name});
            if (f.sub) |sub| {
                try self.w.print(
                    \\    let pb_f{d} = {s}.m;
                    \\    if pb_f{d} {{
                    \\        pb_write_varint(out, {d});
                    \\        pb_write_varint(out, {s}(pb_f{d}) as! u64);
                    \\        {s}(pb_f{d}, out);
                    \\    }}
                    \\
                , .{
                    f.number(), x, f.number(), f.tag(),
                    try self.subName(sub, "size_of"), f.number(),
                    try self.subName(sub, "encode"), f.number(),
                });
                continue;
            }
            try self.w.print("    if {f} {{\n", .{f.isSet(x)});
            try self.w.print("        pb_write_varint(out, {d});\n", .{f.tag()});
            try self.w.print("        {f};\n", .{Subst{ .t = f.sc.write, .x = x }});
            try self.w.writeAll("    }\n");
        }
        try self.w.writeAll("    out.append(pb_run(pb_bytes, m.pb_unknown));\n}\n");
    }

    fn emitSizeOf(self: *FileEmitter, goose_name: []const u8, path: []const u8, fields: []const Field) Error!void {
        try self.w.print(
            \\
            \\// The size of m's wire encoding, in bytes.
            \\{s} {s}(m: {s}&) -> i64 {{
            \\    var n: i64 = 0;
            \\
        , .{ self.fn_kw, try generatedName(self.a, path, "size_of"), goose_name });
        for (fields) |f| {
            const x = try std.fmt.allocPrint(self.a, "m.{s}", .{f.name});
            const ts = varintSize(f.tag());
            if (f.sub) |sub| {
                try self.w.print("    let pb_f{d} = {s}.m;\n", .{ f.number(), x });
                try self.w.print("    if pb_f{d} {{ n += {d} + pb_len_size({s}(pb_f{d})); }}\n", .{
                    f.number(), ts, try self.subName(sub, "size_of"), f.number(),
                });
                continue;
            }
            try self.w.print("    if {f} {{ n += ", .{f.isSet(x)});
            switch (f.sc.size) {
                .varint => try self.w.print("{d} + pb_varint_size({f});", .{ ts, Subst{ .t = f.sc.write_value, .x = x } }),
                .fixed => |k| try self.w.print("{d};", .{ts + k}),
                .bytes => try self.w.print("{d} + pb_bytes_size({s});", .{ ts, x }),
                .message => unreachable,
            }
            try self.w.writeAll(" }\n");
        }
        try self.w.writeAll("    n += m.pb_unknown.len;\n    return n;\n}\n");
    }

    fn emitClear(self: *FileEmitter, goose_name: []const u8, path: []const u8, fields: []const Field, has_words: u32) Error!void {
        try self.w.print(
            \\
            \\// Frees what m owns and resets it to the empty message.
            \\{s} {s}(m: {s}&) {{
            \\
        , .{ self.fn_kw, try generatedName(self.a, path, "clear"), goose_name });
        for (fields) |f| {
            const x = try std.fmt.allocPrint(self.a, "m.{s}", .{f.name});
            if (f.sub != null) {
                try self.w.print("    {s}(m);\n", .{try accessorName(self.a, path, f.fd.name orelse "", clear_acc)});
                continue;
            }
            try self.w.print("    {f};\n", .{Subst{ .t = f.sc.clear, .x = x }});
        }
        for (0..has_words) |i| try self.w.print("    m.pb_has{d} = 0;\n", .{i});
        try self.w.writeAll("    m.pb_unknown = pb_bytes_free(m.pb_unknown);\n}\n");
    }

    /// Decision 0001: copying a record shares what its spans and links
    /// reach, so M_copy duplicates that too.
    fn emitCopy(self: *FileEmitter, goose_name: []const u8, path: []const u8, fields: []const Field, has_words: u32) Error!void {
        try self.w.print(
            \\
            \\// Makes dst a deep copy of src, freeing what dst owned. The two share
            \\// nothing afterwards. Neither may be a sub-message of the other.
            \\{s} {s}(dst: {s}&, src: {s}&) {{
            \\    if dst .== src {{ return; }}
            \\    {s}(dst);
            \\
        , .{ self.fn_kw, try generatedName(self.a, path, "copy"), goose_name, goose_name, try generatedName(self.a, path, "clear") });
        for (fields) |f| {
            if (f.sub) |sub| {
                try self.w.print(
                    \\    let pb_f{d} = src.{s}.m;
                    \\    if pb_f{d} {{ {s}({s}(dst), pb_f{d}); }}
                    \\
                , .{
                    f.number(), f.name, f.number(),
                    try self.subName(sub, "copy"),
                    try accessorName(self.a, path, f.fd.name orelse "", mutable_acc),
                    f.number(),
                });
            } else if (f.sc.size == .bytes) {
                try self.w.print("    dst.{s} = pb_bytes_copy(src.{s});\n", .{ f.name, f.name });
            } else {
                try self.w.print("    dst.{s} = src.{s};\n", .{ f.name, f.name });
            }
        }
        for (0..has_words) |i| try self.w.print("    dst.pb_has{d} = src.pb_has{d};\n", .{ i, i });
        try self.w.writeAll("    dst.pb_unknown = pb_bytes_copy(src.pb_unknown);\n}\n");
    }

    /// The accessors of a stored field, per fieldAccessors: the getter
    /// and set_ of strings and bytes, and set_, has_ and clear_ of fields
    /// with presence; a sub-message has its own (emitSubMessageAccessors).
    fn emitAccessors(self: *FileEmitter, goose_name: []const u8, path: []const u8, f: Field) Error!void {
        if (f.sub) |sub| return self.emitSubMessageAccessors(goose_name, path, f, sub);
        const fname = f.fd.name orelse "";
        const x = try std.fmt.allocPrint(self.a, "m.{s}", .{f.name});
        const is_bytes = f.sc.size == .bytes;
        if (is_bytes) {
            try self.w.print(
                \\
                \\// The contents of {s}, in pb_bytes: valid until it is next set or m
                \\// is cleared.
                \\fn {s}(m: {s}&) -> u8[:] {{ return pb_run(pb_bytes, {s}); }}
                \\
            , .{ fname, try accessorName(self.a, path, fname, get_acc), goose_name, x });
        }
        if (!is_bytes and f.bit == null) return;
        try self.w.print("\n// Sets {s}", .{fname});
        if (is_bytes) try self.w.writeAll(" to a copy of v");
        if (f.bit != null) try self.w.print(" and marks it present:\n// it is encoded even when {s}", .{if (is_bytes) "empty" else "0"});
        try self.w.print(
            \\.
            \\fn {s}(m: {s}&, v: {s}) {{
            \\    {f};
            \\
        , .{ try accessorName(self.a, path, fname, set_acc), goose_name, f.sc.setType(), Subst{ .t = f.sc.set, .x = x } });
        const b = f.bit orelse {
            try self.w.writeAll("}\n");
            return;
        };
        try self.w.print(
            \\    m.pb_has{d} |= 0x{x:0>8};
            \\}}
            \\
            \\fn {s}(m: {s}&) -> bool {{ return (m.pb_has{d} & 0x{x:0>8}) != 0; }}
            \\
            \\fn {s}(m: {s}&) {{
            \\    {f};
            \\    m.pb_has{d} &= 0x{x:0>8};
            \\}}
            \\
        , .{
            b / 32, bitMask(b),
            try accessorName(self.a, path, fname, has_acc), goose_name, b / 32, bitMask(b),
            try accessorName(self.a, path, fname, clear_acc), goose_name,
            Subst{ .t = f.sc.clear, .x = x },
            b / 32, ~bitMask(b),
        });
    }

    /// The getter, mutable_, has_ and clear_ of a sub-message. Its slot in
    /// the pool is the sub-message's own, so a reference to it stays valid
    /// until the field is cleared.
    fn emitSubMessageAccessors(self: *FileEmitter, goose_name: []const u8, path: []const u8, f: Field, sub: MessageInfo) Error!void {
        const fname = f.fd.name orelse "";
        const pool = try self.subName(sub, "pool");
        try self.w.print(
            \\
            \\// The sub-message {s}, or null if it is not set. Valid until it or m is
            \\// cleared.
            \\fn {s}(m: {s}&) -> {s}&? {{ return m.{s}.m; }}
            \\
            \\// The sub-message {s}, set to an empty one first if it is not set.
            \\fn {s}(m: {s}&) -> {s}& {{
            \\    let pb_sub = m.{s}.m;
            \\    if pb_sub {{ return pb_sub; }}
            \\    let pb_new .= {s}.alloc_ref({s} {{ .. }});
            \\    m.{s}.m .= pb_new;
            \\    return pb_new;
            \\}}
            \\
            \\fn {s}(m: {s}&) -> bool {{ return m.{s}.m != null; }}
            \\
            \\// Frees the sub-message {s} and everything it owns.
            \\fn {s}(m: {s}&) {{
            \\    let pb_sub = m.{s}.m;
            \\    guard pb_sub else {{ return; }}
            \\    {s}(pb_sub);
            \\    {s}.free({s}.index_of(pb_sub));
            \\    m.{s}.m .= null;
            \\}}
            \\
        , .{
            fname,
            try accessorName(self.a, path, fname, get_acc), goose_name, sub.goose_name, f.name,
            fname,
            try accessorName(self.a, path, fname, mutable_acc), goose_name, sub.goose_name,
            f.name,
            pool, sub.goose_name,
            f.name,
            try accessorName(self.a, path, fname, has_acc), goose_name, f.name,
            fname,
            try accessorName(self.a, path, fname, clear_acc), goose_name,
            f.name,
            try self.subName(sub, "clear"),
            pool, pool,
            f.name,
        });
    }
};

/// The header comment of every generated file: the user-facing API
/// (decisions 0001, 0004, 0006).
const api_comment =
    \\// API, for each message M (Outer.Inner is Outer_Inner):
    \\//   var m = M { .. };            an empty message: any local, global or
    \\//                                array element the caller owns
    \\//   m.f, m.f = v                 scalar fields without presence
    \\//   M_set_f(m, v), M_has_f(m),   scalar fields with presence (proto3
    \\//   M_clear_f(m)                 optional); m.f reads them
    \\//   M_f(m) -> u8[:]              string and bytes fields: a view into
    \\//   M_set_f(m, v)                pb_bytes, and a copying setter
    \\//   M_f(m) -> S&?                sub-message fields: null if not set;
    \\//   M_mutable_f(m) -> S&         mutable_ first sets an empty one
    \\//   M_has_f(m), M_clear_f(m)
    \\//   M_encode(m, out)             appends M_size_of(m) bytes to out
    \\//   M_decode(buf, m) -> i32      merges buf into m: PB_OK, or a
    \\//                                PB_ERR_* code and a partial m
    \\//                                (PB_ERR_UTF8: a bad proto3 string)
    \\//   M_clear(m)                   frees what m owns, empties it
    \\//   M_copy(dst, src)             makes dst a deep copy of src
    \\// Enum values are i32 constants E_VALUE. Variable-size parts (unknown
    \\// fields, strings and bytes, sub-messages, later repeated fields)
    \\// live in global pools (pb_bytes, M_pool, M_links): clear a message
    \\// to free them. Assigning a record copies spans, not their contents:
    \\// use M_copy.
    \\
    \\
;

/// A message declared in the file being generated.
const MessageInfo = struct {
    desc: *const descriptor.DescriptorProto,
    /// The unescaped path generated names are built from.
    path: []const u8,
    /// Its Goose name, as the file being generated writes it.
    goose_name: []const u8,
    /// What its names are written with: `ns::`, or nothing in its own
    /// namespace.
    ns: []const u8 = "",
    /// How the file being generated imports it, if it is in another file.
    import_path: []const u8 = "",
};

fn stringLess(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

/// A field stored in the record.
const Field = struct {
    fd: *const descriptor.FieldDescriptorProto,
    sc: *const Scalar,
    /// The record field name, escaped.
    name: []const u8,
    /// The has-bit of a field with presence: bit bit % 32 of pb_has<bit / 32>.
    bit: ?u32 = null,
    /// The message of a sub-message field, whose presence is its link.
    sub: ?MessageInfo = null,

    /// The condition under which the field, whose value is `x`, is encoded.
    fn isSet(f: Field, x: []const u8) Cond {
        return .{ .f = f, .x = x };
    }

    fn number(f: Field) u32 {
        return @intCast(f.fd.number orelse 0);
    }

    fn tag(f: Field) u64 {
        return (@as(u64, f.number()) << 3) | f.sc.wire;
    }

    fn lessThan(_: void, a: Field, b: Field) bool {
        return a.number() < b.number();
    }
};

/// Formats the encode condition of a field: its has-bit if it has
/// presence, else a value other than the default.
const Cond = struct {
    f: Field,
    x: []const u8,

    pub fn format(c: Cond, w: *std.Io.Writer) std.Io.Writer.Error!void {
        if (c.f.bit) |b| {
            try w.print("(m.pb_has{d} & 0x{x:0>8}) != 0", .{ b / 32, bitMask(b) });
        } else {
            try (Subst{ .t = c.f.sc.nonzero, .x = c.x }).format(w);
        }
    }
};

fn bitMask(b: u32) u32 {
    return @as(u32, 1) << @intCast(b % 32);
}

/// How one scalar type is stored, read, written and sized. In the
/// templates, `$` stands for the value (`m.<field>`).
const Scalar = struct {
    goose: []const u8,
    wire: u3,
    /// Statement resetting the value to the default, freeing what it owns.
    clear: []const u8,
    /// Decode expression, reading from `r` (`$` is the old value).
    read: []const u8,
    /// Encode statement, writing the value (tag already written) to `out`.
    write: []const u8,
    /// True if the value is not the default (implicit presence: only then
    /// is it encoded). Floats compare bits, so -0.0 is encoded.
    nonzero: []const u8,
    size: union(enum) { varint, fixed: u64, bytes, message },
    /// For varints: the u64 written, whose pb_varint_size is the size.
    write_value: []const u8 = "",
    /// The parameter type of set_, and its statement storing `v`.
    set_type: []const u8 = "",
    set: []const u8 = "$ = v",

    fn setType(sc: *const Scalar) []const u8 {
        return if (sc.set_type.len > 0) sc.set_type else sc.goose;
    }
};

fn varintScalar(goose: []const u8, read: []const u8, value: []const u8) Scalar {
    return .{
        .goose = goose,
        .wire = 0,
        .clear = "$ = 0",
        .read = read,
        .write = "pb_write_varint(out, " ++ value ++ ")",
        .nonzero = "$ != 0",
        .size = .varint,
        .write_value = value,
    };
}

const sc_int32 = varintScalar("i32", "pb_u64_to_int32(pb_read_varint(r))", "pb_int32_to_u64($)");
const sc_int64 = varintScalar("i64", "pb_u64_to_int64(pb_read_varint(r))", "pb_int64_to_u64($)");
const sc_uint32 = varintScalar("u32", "pb_read_varint(r) as! u32", "$");
const sc_uint64 = varintScalar("u64", "pb_read_varint(r)", "$");
const sc_sint32 = varintScalar("i32", "pb_unzigzag32(pb_read_varint(r) as! u32)", "pb_zigzag32($)");
const sc_sint64 = varintScalar("i64", "pb_unzigzag64(pb_read_varint(r))", "pb_zigzag64($)");
const sc_bool: Scalar = .{
    .goose = "bool",
    .wire = 0,
    .clear = "$ = false",
    .read = "pb_read_varint(r) != 0",
    .write = "pb_write_varint(out, pb_bool_to_u64($))",
    .nonzero = "$",
    .size = .{ .fixed = 1 },
};
const sc_fixed32: Scalar = .{ .goose = "u32", .wire = 5, .clear = "$ = 0", .read = "pb_read_fixed32(r)", .write = "pb_write_fixed32(out, $)", .nonzero = "$ != 0", .size = .{ .fixed = 4 } };
const sc_sfixed32: Scalar = .{ .goose = "i32", .wire = 5, .clear = "$ = 0", .read = "pb_read_fixed32(r) as! i32", .write = "pb_write_fixed32(out, $ as! u32)", .nonzero = "$ != 0", .size = .{ .fixed = 4 } };
const sc_float: Scalar = .{ .goose = "f32", .wire = 5, .clear = "$ = 0.0", .read = "pb_read_float(r)", .write = "pb_write_float(out, $)", .nonzero = "pb_f32_to_bits($) != 0", .size = .{ .fixed = 4 } };
const sc_fixed64: Scalar = .{ .goose = "u64", .wire = 1, .clear = "$ = 0", .read = "pb_read_fixed64(r)", .write = "pb_write_fixed64(out, $)", .nonzero = "$ != 0", .size = .{ .fixed = 8 } };
const sc_sfixed64: Scalar = .{ .goose = "i64", .wire = 1, .clear = "$ = 0", .read = "pb_read_fixed64(r) as! i64", .write = "pb_write_fixed64(out, $ as! u64)", .nonzero = "$ != 0", .size = .{ .fixed = 8 } };
const sc_double: Scalar = .{ .goose = "f64", .wire = 1, .clear = "$ = 0.0", .read = "pb_read_double(r)", .write = "pb_write_double(out, $)", .nonzero = "pb_f64_to_bits($) != 0", .size = .{ .fixed = 8 } };

const sc_bytes: Scalar = .{
    .goose = "pb_Span",
    .wire = 2,
    .clear = "$ = pb_bytes_free($)",
    .read = "pb_read_bytes(r, $)",
    .write = "pb_write_bytes(out, $)",
    .nonzero = "$.len > 0",
    .size = .bytes,
    .set_type = "const u8[:]",
    .set = "$ = pb_bytes_set($, v)",
};
/// proto3 strings must be valid UTF-8 (validated on decode).
const sc_string: Scalar = blk: {
    var sc = sc_bytes;
    sc.read = "pb_read_string(r, $)";
    break :blk sc;
};

/// True if this generator stores fields like `fd` yet: only singular fields
/// of proto3, with implicit presence or `optional`, are stored (repeated
/// fields, oneofs and proto2 come with later tasks).
fn isStorable(file: *const descriptor.FileDescriptorProto, fd: *const descriptor.FieldDescriptorProto) bool {
    if (fd.label == .LABEL_REPEATED) return false;
    if (!std.mem.eql(u8, file.syntax orelse "proto2", "proto3")) return false;
    // A proto3 optional is in a synthetic oneof, which is not an ADT: its
    // field is stored like any other.
    return fd.oneof_index == null or (fd.proto3_optional orelse false);
}

/// The scalar storage of `fd`, or null if it is not a stored numeric, bool,
/// enum, string or bytes field.
fn scalarOf(file: *const descriptor.FileDescriptorProto, fd: *const descriptor.FieldDescriptorProto) ?*const Scalar {
    if (!isStorable(file, fd)) return null;
    return switch (fd.type orelse return null) {
        .TYPE_INT32, .TYPE_ENUM => &sc_int32,
        .TYPE_INT64 => &sc_int64,
        .TYPE_UINT32 => &sc_uint32,
        .TYPE_UINT64 => &sc_uint64,
        .TYPE_SINT32 => &sc_sint32,
        .TYPE_SINT64 => &sc_sint64,
        .TYPE_BOOL => &sc_bool,
        .TYPE_FIXED32 => &sc_fixed32,
        .TYPE_SFIXED32 => &sc_sfixed32,
        .TYPE_FLOAT => &sc_float,
        .TYPE_FIXED64 => &sc_fixed64,
        .TYPE_SFIXED64 => &sc_sfixed64,
        .TYPE_DOUBLE => &sc_double,
        .TYPE_STRING => &sc_string,
        .TYPE_BYTES => &sc_bytes,
        else => null,
    };
}

fn varintSize(v: u64) u64 {
    var n: u64 = 1;
    var x = v;
    while (x >= 0x80) : (x >>= 7) n += 1;
    return n;
}

/// Formats template `t` with every `$` replaced by `x`.
const Subst = struct {
    t: []const u8,
    x: []const u8,

    pub fn format(s: Subst, w: *std.Io.Writer) std.Io.Writer.Error!void {
        for (s.t) |c| {
            if (c == '$') try w.writeAll(s.x) else try w.writeByte(c);
        }
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
    files: []const descriptor.FileDescriptorProto,
    w: *std.Io.Writer,
    diag: *[]const u8,
) Error!void {
    var fe: FileEmitter = .{ .a = a, .w = w, .file = file, .files = files };
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
    try std.testing.expectEqualStrings("api/foo_v1.goose", try outputName(a, "api/foo.v1.proto"));
    try std.testing.expectEqualStrings("my_api.goose", try outputName(a, "my-api.proto"));
    try std.testing.expectEqualStrings("my_api/v_2/x.goose", try outputName(a, "my-api/v.2/x.proto"));
    // Every segment is escaped, directories too.
    try std.testing.expectEqualStrings("recursive_.goose", try outputName(a, "recursive.proto"));
    try std.testing.expectEqualStrings("type_/fn_/str_.goose", try outputName(a, "type/fn/str.proto"));
    try std.testing.expectEqualStrings("pb_wire_.goose", try outputName(a, "pb_wire.proto"));
    // Anything else an import path cannot hold.
    try std.testing.expectEqualStrings("a_b_c.goose", try outputName(a, "a b+c.proto"));
    try std.testing.expectEqualStrings("_3d/_1.goose", try outputName(a, "3d/1.proto"));
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
    try std.testing.expectError(error.NameCollision, generateFile(a, &file, &.{}, &out.writer, &diag));
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
    try generateFile(a, file, &.{}, &out.writer, diag);
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
    try std.testing.expect(std.mem.indexOf(u8, out, "struct Node_decode_ {\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "struct Node_set_name_ {\n") != null);
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

test "accessors depend on kind and presence" {
    try std.testing.expectEqual(@as(usize, 0), fieldAccessors(.scalar, false).len);
    const p = fieldAccessors(.scalar, true);
    try std.testing.expectEqual(@as(usize, 3), p.len);
    try std.testing.expectEqualStrings("set_", p[0].prefix);
    try std.testing.expectEqualStrings("has_", p[1].prefix);
    try std.testing.expectEqualStrings("clear_", p[2].prefix);
    try std.testing.expectEqual(@as(usize, 4), fieldAccessors(.string, true).len);
    try std.testing.expectEqual(@as(usize, 4), fieldAccessors(.message, true).len);
}

test "proto3 optional is stored with a has-bit; real oneofs and proto2 are not" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m: descriptor.DescriptorProto = .{ .name = "M" };
    try m.field.append(a, .{ .name = "o", .number = 1, .label = .LABEL_OPTIONAL, .type = .TYPE_INT32, .oneof_index = 0, .proto3_optional = true });
    try m.field.append(a, .{ .name = "u", .number = 2, .label = .LABEL_OPTIONAL, .type = .TYPE_INT32, .oneof_index = 1 });
    var file: descriptor.FileDescriptorProto = .{ .name = "t.proto", .syntax = "proto3" };
    try file.message_type.append(a, m);
    var diag: []const u8 = "";
    const out = try generateForTest(a, &file, &diag);
    try std.testing.expect(std.mem.indexOf(u8, out, "    o: i32,\n    pb_has0: u32,") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "fn M_set_o(m: M&, v: i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "    u: i32,") == null);

    const p2: descriptor.FileDescriptorProto = .{ .syntax = "proto2" };
    try std.testing.expectEqual(@as(?*const Scalar, null), scalarOf(&p2, &m.field.items[0]));
}

test "proto3 strings are validated, bytes are not" {
    const p3: descriptor.FileDescriptorProto = .{ .syntax = "proto3" };
    const s: descriptor.FieldDescriptorProto = .{ .name = "s", .label = .LABEL_OPTIONAL, .type = .TYPE_STRING };
    const b: descriptor.FieldDescriptorProto = .{ .name = "b", .label = .LABEL_OPTIONAL, .type = .TYPE_BYTES };
    try std.testing.expectEqualStrings("pb_read_string(r, $)", scalarOf(&p3, &s).?.read);
    try std.testing.expectEqualStrings("pb_read_bytes(r, $)", scalarOf(&p3, &b).?.read);
    try std.testing.expectEqualStrings("const u8[:]", scalarOf(&p3, &b).?.setType());
    try std.testing.expectEqualStrings("i32", sc_int32.setType());
}

test "sub-message fields of the same file are stored; cycles make functions recursive" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m: descriptor.DescriptorProto = .{ .name = "M" };
    try m.field.append(a, .{ .name = "later", .number = 1, .label = .LABEL_OPTIONAL, .type = .TYPE_MESSAGE, .type_name = ".p.Later" });
    try m.field.append(a, .{ .name = "co", .number = 2, .label = .LABEL_OPTIONAL, .type = .TYPE_MESSAGE, .type_name = ".p.Co" });
    try m.field.append(a, .{ .name = "other", .number = 3, .label = .LABEL_OPTIONAL, .type = .TYPE_MESSAGE, .type_name = ".q.Other" });
    var co: descriptor.DescriptorProto = .{ .name = "Co" };
    try co.field.append(a, .{ .name = "back", .number = 1, .label = .LABEL_OPTIONAL, .type = .TYPE_MESSAGE, .type_name = ".p.M" });
    var self_rec: descriptor.DescriptorProto = .{ .name = "Self" };
    try self_rec.field.append(a, .{ .name = "next", .number = 1, .label = .LABEL_OPTIONAL, .type = .TYPE_MESSAGE, .type_name = ".p.Self" });
    var holder: descriptor.DescriptorProto = .{ .name = "Holder" };
    try holder.field.append(a, .{ .name = "self_", .number = 1, .label = .LABEL_OPTIONAL, .type = .TYPE_MESSAGE, .type_name = ".p.Self" });
    var file: descriptor.FileDescriptorProto = .{ .name = "t.proto", .package = "p", .syntax = "proto3" };
    try file.message_type.append(a, m);
    try file.message_type.append(a, co);
    try file.message_type.append(a, self_rec);
    try file.message_type.append(a, holder);
    try file.message_type.append(a, .{ .name = "Later" });
    var diag: []const u8 = "";
    const out = try generateForTest(a, &file, &diag);
    try std.testing.expect(std.mem.indexOf(u8, out, "    later: Later_Ref,\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "fn M_mutable_later(m: M&) -> Later& {") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "    other: ") == null);
    for ([_][]const u8{ "M", "Co", "Self" }) |name| {
        try std.testing.expect(std.mem.indexOf(u8, out, try std.fmt.allocPrint(a, "recursive fn {s}_decode_from(", .{name})) != null);
        try std.testing.expect(std.mem.indexOf(u8, out, try std.fmt.allocPrint(a, "recursive fn {s}_encode(", .{name})) != null);
        try std.testing.expect(std.mem.indexOf(u8, out, try std.fmt.allocPrint(a, "recursive fn {s}_size_of(", .{name})) != null);
        try std.testing.expect(std.mem.indexOf(u8, out, try std.fmt.allocPrint(a, "recursive fn {s}_clear(", .{name})) != null);
    }
    try std.testing.expect(std.mem.indexOf(u8, out, "\nfn Holder_decode_from(") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\nfn Later_clear(") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "recursive fn Self_copy(dst: Self&, src: Self&) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\nfn Later_copy(dst: Later&, src: Later&) {") != null);
}

test "fields of an imported type are qualified and import its file" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m: descriptor.DescriptorProto = .{ .name = "M" };
    try m.field.append(a, .{ .name = "other", .number = 1, .label = .LABEL_OPTIONAL, .type = .TYPE_MESSAGE, .type_name = ".q.r.Other.In" });
    try m.field.append(a, .{ .name = "bare", .number = 2, .label = .LABEL_OPTIONAL, .type = .TYPE_MESSAGE, .type_name = ".Bare" });
    try m.field.append(a, .{ .name = "same", .number = 3, .label = .LABEL_OPTIONAL, .type = .TYPE_MESSAGE, .type_name = ".p.Same" });
    var file: descriptor.FileDescriptorProto = .{ .name = "t.proto", .package = "p", .syntax = "proto3" };
    try file.message_type.append(a, m);

    var other_msg: descriptor.DescriptorProto = .{ .name = "Other" };
    try other_msg.nested_type.append(a, .{ .name = "In" });
    var q: descriptor.FileDescriptorProto = .{ .name = "z/q.v1.proto", .package = "q.r", .syntax = "proto3" };
    try q.message_type.append(a, other_msg);
    var bare: descriptor.FileDescriptorProto = .{ .name = "bare.proto", .syntax = "proto3" };
    try bare.message_type.append(a, .{ .name = "Bare" });
    var same: descriptor.FileDescriptorProto = .{ .name = "same.proto", .package = "p", .syntax = "proto3" };
    try same.message_type.append(a, .{ .name = "Same" });
    var unused: descriptor.FileDescriptorProto = .{ .name = "unused.proto", .syntax = "proto3" };
    try unused.message_type.append(a, .{ .name = "Unused" });

    var buf: std.Io.Writer.Allocating = .init(a);
    var diag: []const u8 = "";
    try generateFile(a, &file, &.{ q, bare, same, unused, file }, &buf.writer, &diag);
    const out = buf.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "import pb_wire;\nimport bare;\nimport same;\nimport z.q_v1;\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "import unused") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "    other: q_r::Other_In_Ref,\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "    bare: ::Bare_Ref,\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "    same: Same_Ref,\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "fn M_other(m: M&) -> q_r::Other_In&?") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "q_r::Other_In_decode_from(r, M_mutable_other(m));") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "q_r::Other_In_pool.alloc_ref(q_r::Other_In { .. })") != null);
}
