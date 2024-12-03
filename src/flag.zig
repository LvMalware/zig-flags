const std = @import("std");

/// helper function that returns a structure definition, with the fields
/// given by the comptime `flags` anonymous structure members.
/// This is only guaranteed to work for zig version `0.13.0`!
fn Flag(comptime flags: anytype) type {
    var fields: [flags.len]std.builtin.Type.StructField = undefined;

    for (flags, 0..) |f, i| {
        const fieldName: []const u8 = f[0][0..];
        const fieldType: type = f[1];

        fields[i] = .{
            .name = @ptrCast(fieldName),
            .type = fieldType,
            .default_value = null,
            .is_comptime = false,
            .alignment = 0,
        };
    }

    return @Type(.{
        .Struct = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        },
    });
}

/// helper function to parse the command line arguments and find the option
/// associated with a flag definition. This will return an error-optional value
/// of type `flag[1]`.
fn findFlag(comptime flag: anytype, allocator: std.mem.Allocator, args: [][:0]u8) !?flag[1] {
    var i: usize = 0;
    const name = flag[0];

    while (i < args.len) : (i += 1) {
        if (!std.mem.startsWith(u8, args[i], "-"))
            continue;
        var option = std.mem.splitScalar(u8, std.mem.trimLeft(u8, args[i], "-"), '=');
        const param = option.first();
        if (std.mem.eql(u8, param, name)) {
            if (option.peek()) |val| {
                return switch (flag[1]) {
                    bool, ?bool => std.mem.eql(u8, val, "true"),
                    i16, u16, i32, i64, u32, u64 => std.fmt.parseInt(flag[1], val, 10) catch std.debug.panic("Invalid integer for option '{s}'", .{name}),
                    []u8, []const u8, ?[]u8, ?[]const u8 => try allocator.dupe(u8, val),
                    else => error.InvalidFlagType,
                };
            } else if (args.len > (i + 1) and !std.mem.startsWith(u8, args[i + 1], "--")) {
                return switch (flag[1]) {
                    bool, ?bool => std.mem.eql(u8, args[i + 1], "true"),
                    i16, u16, i32, i64, u32, u64 => std.fmt.parseInt(flag[1], args[i + 1], 10) catch std.debug.panic("Invalid integer for option '{s}'", .{name}),
                    []u8, []const u8, ?[]u8, ?[]const u8 => try allocator.dupe(u8, args[i + 1]),
                    else => error.InvalidFlagType,
                };
            } else if (flag[1] == bool) {
                return if (flag.len > 2) !flag[2] else true;
            }
        }
    }
    return null;
}

/// **Parse command line arguments**, returning a struct where each field is a command line option.
/// `flags` is a comptime anonymous structure, where each element defines an option to be parsed.
/// Each element has the fields `name`, `type` and (optionally) `default`, in this order.
/// Example:
/// const flags = try parseFlags(.{
///     .{ "help", bool, false },
///     .{ "input", ?[]u8 },
///     .{ "threads", u32, 1 },
/// }, allocator);
pub fn parseFlags(comptime flags: anytype, allocator: std.mem.Allocator) !Flag(flags) {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var flag: Flag(flags) = undefined;

    inline for (flags) |f| {
        @field(flag, f[0]) = if (try findFlag(f, allocator, args)) |value| value else if (f.len > 2) f[2] else if (@typeInfo(f[1]) == .Optional) null else std.debug.panic("Missing option {s}", .{f[0]});
    }
    return flag;
}
