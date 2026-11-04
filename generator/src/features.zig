//! Resolved protobuf features: what proto2, proto3 and editions all come down
//! to, per element. protoc passes a file's features unresolved, as it wrote them,
//! so the plugin resolves them as protobuf's descriptor.cc does: the defaults of
//! the file's edition, overridden by the file, then each enclosing element.

const std = @import("std");
const pb_plugin = @import("pb_plugin");
const descriptor = pb_plugin.descriptor;
const FeatureSet = descriptor.FeatureSet;

pub const Presence = enum { explicit, implicit, required };

/// The features this generator acts on. json_format and the naming and limit
/// features say nothing about the binary wire format.
pub const Features = struct {
    presence: Presence,
    closed_enum: bool,
    packed_repeated: bool,
    verify_utf8: bool,
    delimited: bool,

    /// What an element whose parent has these features has, with its own
    /// overrides from its options, if any.
    pub fn child(parent: Features, set: ?FeatureSet) Features {
        var f = parent;
        const s = set orelse return f;
        if (s.field_presence) |v| switch (v) {
            .EXPLICIT => f.presence = .explicit,
            .IMPLICIT => f.presence = .implicit,
            .LEGACY_REQUIRED => f.presence = .required,
            else => {},
        };
        if (s.enum_type) |v| switch (v) {
            .OPEN => f.closed_enum = false,
            .CLOSED => f.closed_enum = true,
            else => {},
        };
        if (s.repeated_field_encoding) |v| switch (v) {
            .PACKED => f.packed_repeated = true,
            .EXPANDED => f.packed_repeated = false,
            else => {},
        };
        if (s.utf8_validation) |v| switch (v) {
            .VERIFY => f.verify_utf8 = true,
            .NONE => f.verify_utf8 = false,
            else => {},
        };
        if (s.message_encoding) |v| switch (v) {
            .LENGTH_PREFIXED => f.delimited = false,
            .DELIMITED => f.delimited = true,
            else => {},
        };
        return f;
    }
};

/// proto2: FeatureSetDefaults' EDITION_LEGACY.
const proto2_defaults: Features = .{
    .presence = .explicit,
    .closed_enum = true,
    .packed_repeated = false,
    .verify_utf8 = false,
    .delimited = false,
};
const proto3_defaults: Features = .{
    .presence = .implicit,
    .closed_enum = false,
    .packed_repeated = true,
    .verify_utf8 = true,
    .delimited = false,
};
const edition_2023_defaults: Features = .{
    .presence = .explicit,
    .closed_enum = false,
    .packed_repeated = true,
    .verify_utf8 = true,
    .delimited = false,
};

/// True for a file of syntax "editions", whose features are its own.
pub fn isEditions(file: *const descriptor.FileDescriptorProto) bool {
    return std.mem.eql(u8, file.syntax orelse "", "editions");
}

fn defaultsOf(file: *const descriptor.FileDescriptorProto) Features {
    if (isEditions(file)) return edition_2023_defaults;
    if (std.mem.eql(u8, file.syntax orelse "proto2", "proto3")) return proto3_defaults;
    return proto2_defaults;
}

/// The features of `file`, which its top-level elements inherit.
pub fn ofFile(file: *const descriptor.FileDescriptorProto) Features {
    const opts = file.options orelse return defaultsOf(file);
    return defaultsOf(file).child(opts.features);
}

/// The features of a message whose parent, a file or a message, has `parent`.
pub fn ofMessage(parent: Features, m: *const descriptor.DescriptorProto) Features {
    const opts = m.options orelse return parent;
    return parent.child(opts.features);
}

/// The features of an enum whose parent, a file or a message, has `parent`.
pub fn ofEnum(parent: Features, e: *const descriptor.EnumDescriptorProto) Features {
    const opts = e.options orelse return parent;
    return parent.child(opts.features);
}

/// The features of a oneof of a message that has `parent`.
pub fn ofOneof(parent: Features, o: *const descriptor.OneofDescriptorProto) Features {
    const opts = o.options orelse return parent;
    return parent.child(opts.features);
}

/// The features of field `fd` of `file`, whose parent, its message or its oneof,
/// has `parent`. In proto2 and proto3, the label, the type and `packed` say what
/// features say elsewhere: descriptor.cc's InferLegacyProtoFeatures.
pub fn ofField(
    file: *const descriptor.FileDescriptorProto,
    parent: Features,
    fd: *const descriptor.FieldDescriptorProto,
) Features {
    var f = parent;
    const opts = fd.options;
    if (opts) |o| f = f.child(o.features);
    if (isEditions(file)) return f;
    if (fd.label == .LABEL_REQUIRED) f.presence = .required;
    if (fd.type == .TYPE_GROUP) f.delimited = true;
    if (opts) |o| {
        if (o.@"packed") |p| f.packed_repeated = p;
    }
    return f;
}

const testing = std.testing;

test "the defaults are protoc's" {
    // generator/src/edition_defaults.binpb is what protoc computes; see
    // scripts/edition_defaults.sh.
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var reader: std.Io.Reader = .fixed(@embedFile("edition_defaults.binpb"));
    const defaults: descriptor.FeatureSetDefaults = try .decode(&reader, a);
    try testing.expectEqual(descriptor.Edition.EDITION_PROTO2, defaults.minimum_edition.?);
    try testing.expectEqual(descriptor.Edition.EDITION_2023, defaults.maximum_edition.?);
    var seen: usize = 0;
    for (defaults.defaults.items) |d| {
        const edition = d.edition.?;
        const want: Features = switch (edition) {
            .EDITION_LEGACY => proto2_defaults,
            .EDITION_PROTO3 => proto3_defaults,
            .EDITION_2023 => edition_2023_defaults,
            else => return error.TestUnexpectedResult,
        };
        // Each feature is set in exactly one of the two: start from what cannot
        // match, so that a feature protoc leaves out fails.
        const opposite: Features = .{
            .presence = if (want.presence == .implicit) .explicit else .implicit,
            .closed_enum = !want.closed_enum,
            .packed_repeated = !want.packed_repeated,
            .verify_utf8 = !want.verify_utf8,
            .delimited = !want.delimited,
        };
        try testing.expectEqual(want, opposite.child(d.overridable_features).child(d.fixed_features));
        seen += 1;
    }
    try testing.expectEqual(@as(usize, 3), seen);
}

test "syntax picks the defaults" {
    const none: descriptor.FileDescriptorProto = .{};
    const p2: descriptor.FileDescriptorProto = .{ .syntax = "proto2" };
    const p3: descriptor.FileDescriptorProto = .{ .syntax = "proto3" };
    const ed: descriptor.FileDescriptorProto = .{ .syntax = "editions", .edition = .EDITION_2023 };
    try testing.expectEqual(proto2_defaults, ofFile(&none));
    try testing.expectEqual(proto2_defaults, ofFile(&p2));
    try testing.expectEqual(proto3_defaults, ofFile(&p3));
    try testing.expectEqual(edition_2023_defaults, ofFile(&ed));
    try testing.expect(isEditions(&ed));
    try testing.expect(!isEditions(&p3));
}

test "each feature resolves through each value" {
    const base = edition_2023_defaults;
    try testing.expectEqual(Presence.implicit, base.child(.{ .field_presence = .IMPLICIT }).presence);
    try testing.expectEqual(Presence.required, base.child(.{ .field_presence = .LEGACY_REQUIRED }).presence);
    try testing.expectEqual(Presence.explicit, proto3_defaults.child(.{ .field_presence = .EXPLICIT }).presence);
    try testing.expect(base.child(.{ .enum_type = .CLOSED }).closed_enum);
    try testing.expect(!proto2_defaults.child(.{ .enum_type = .OPEN }).closed_enum);
    try testing.expect(!base.child(.{ .repeated_field_encoding = .EXPANDED }).packed_repeated);
    try testing.expect(proto2_defaults.child(.{ .repeated_field_encoding = .PACKED }).packed_repeated);
    try testing.expect(!base.child(.{ .utf8_validation = .NONE }).verify_utf8);
    try testing.expect(proto2_defaults.child(.{ .utf8_validation = .VERIFY }).verify_utf8);
    try testing.expect(base.child(.{ .message_encoding = .DELIMITED }).delimited);
    try testing.expect(!base.child(.{ .message_encoding = .DELIMITED }).child(.{ .message_encoding = .LENGTH_PREFIXED }).delimited);
    // An element with no overrides, or the unknown values, changes nothing.
    try testing.expectEqual(base, base.child(null));
    try testing.expectEqual(base, base.child(.{}));
    try testing.expectEqual(base, base.child(.{
        .field_presence = .FIELD_PRESENCE_UNKNOWN,
        .enum_type = .ENUM_TYPE_UNKNOWN,
        .repeated_field_encoding = .REPEATED_FIELD_ENCODING_UNKNOWN,
        .utf8_validation = .UTF8_VALIDATION_UNKNOWN,
        .message_encoding = .MESSAGE_ENCODING_UNKNOWN,
    }));
}

test "features are inherited through each level" {
    const file: descriptor.FileDescriptorProto = .{
        .syntax = "editions",
        .edition = .EDITION_2023,
        .options = .{ .features = .{ .field_presence = .IMPLICIT, .enum_type = .CLOSED, .utf8_validation = .NONE } },
    };
    const at_file = ofFile(&file);
    try testing.expectEqual(Presence.implicit, at_file.presence);
    try testing.expect(at_file.closed_enum);
    // A message inherits the file, overriding one feature; a nested one both.
    const outer: descriptor.DescriptorProto = .{ .options = .{ .features = .{ .field_presence = .EXPLICIT } } };
    const at_outer = ofMessage(at_file, &outer);
    try testing.expectEqual(Presence.explicit, at_outer.presence);
    try testing.expect(!at_outer.verify_utf8);
    const nested: descriptor.DescriptorProto = .{ .options = .{ .features = .{ .utf8_validation = .VERIFY } } };
    const at_nested = ofMessage(at_outer, &nested);
    try testing.expectEqual(Presence.explicit, at_nested.presence);
    try testing.expect(at_nested.verify_utf8);
    try testing.expect(at_nested.closed_enum);
    const plain: descriptor.DescriptorProto = .{};
    try testing.expectEqual(at_outer, ofMessage(at_outer, &plain));

    // An enum inherits the file or a message, and overrides.
    const open_e: descriptor.EnumDescriptorProto = .{ .options = .{ .features = .{ .enum_type = .OPEN } } };
    const plain_e: descriptor.EnumDescriptorProto = .{};
    try testing.expect(!ofEnum(at_file, &open_e).closed_enum);
    try testing.expect(ofEnum(at_nested, &plain_e).closed_enum);

    // A oneof inherits its message, and a field its oneof or message.
    const oneof: descriptor.OneofDescriptorProto = .{ .options = .{ .features = .{ .message_encoding = .DELIMITED } } };
    const at_oneof = ofOneof(at_outer, &oneof);
    try testing.expect(at_oneof.delimited);
    const plain_f: descriptor.FieldDescriptorProto = .{ .name = "a", .type = .TYPE_MESSAGE };
    try testing.expect(ofField(&file, at_oneof, &plain_f).delimited);
    const own_f: descriptor.FieldDescriptorProto = .{
        .name = "b",
        .type = .TYPE_MESSAGE,
        .options = .{ .features = .{ .message_encoding = .LENGTH_PREFIXED, .field_presence = .LEGACY_REQUIRED, .repeated_field_encoding = .EXPANDED } },
    };
    const at_own = ofField(&file, at_oneof, &own_f);
    try testing.expect(!at_own.delimited);
    try testing.expectEqual(Presence.required, at_own.presence);
    try testing.expect(!at_own.packed_repeated);
}

test "proto2 and proto3 infer features from labels, types and packed" {
    const p2: descriptor.FileDescriptorProto = .{ .syntax = "proto2" };
    const p3: descriptor.FileDescriptorProto = .{ .syntax = "proto3" };
    const ed: descriptor.FileDescriptorProto = .{ .syntax = "editions", .edition = .EDITION_2023 };
    const req: descriptor.FieldDescriptorProto = .{ .name = "r", .label = .LABEL_REQUIRED, .type = .TYPE_INT32 };
    const grp: descriptor.FieldDescriptorProto = .{ .name = "g", .label = .LABEL_OPTIONAL, .type = .TYPE_GROUP };
    const pk: descriptor.FieldDescriptorProto = .{ .name = "p", .label = .LABEL_REPEATED, .type = .TYPE_INT32, .options = .{ .@"packed" = true } };
    const unpk: descriptor.FieldDescriptorProto = .{ .name = "u", .label = .LABEL_REPEATED, .type = .TYPE_INT32, .options = .{ .@"packed" = false } };
    const plain: descriptor.FieldDescriptorProto = .{ .name = "x", .label = .LABEL_REPEATED, .type = .TYPE_INT32 };
    const f2 = ofFile(&p2);
    const f3 = ofFile(&p3);
    try testing.expectEqual(Presence.required, ofField(&p2, f2, &req).presence);
    try testing.expect(ofField(&p2, f2, &grp).delimited);
    try testing.expect(ofField(&p2, f2, &pk).packed_repeated);
    try testing.expect(!ofField(&p2, f2, &plain).packed_repeated);
    try testing.expect(ofField(&p3, f3, &plain).packed_repeated);
    try testing.expect(!ofField(&p3, f3, &unpk).packed_repeated);
    try testing.expectEqual(Presence.implicit, ofField(&p3, f3, &plain).presence);
    // Editions say it with features only.
    try testing.expectEqual(Presence.explicit, ofField(&ed, ofFile(&ed), &req).presence);
    try testing.expect(!ofField(&ed, ofFile(&ed), &grp).delimited);
}
