const std = @import("std");
const builtin = @import("builtin");

/// helper function that returns a structure definition, with the fields
/// given by the comptime `flags` anonymous structure members.
/// This is only guaranteed to work for zig version `0.14.0`!
fn Flag(comptime flags: anytype) type {
    var fields: [flags.len]std.builtin.Type.StructField = undefined;

    for (flags, 0..) |f, i| {
        const fieldName: []const u8 = f[0][0..];
        const fieldType: type = f[1];

        fields[i] = .{
            .name = @ptrCast(fieldName),
            .type = fieldType,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = 0,
        };
    }

    return @Type(.{
        .@"struct" = .{
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
fn findFlag(comptime flag: anytype, arena: *std.heap.ArenaAllocator, args: [][:0]u8) !?flag[1] {
    var i: usize = 0;
    const name = flag[0];

    while (i < args.len) : (i += 1) {
        if (!std.mem.startsWith(u8, args[i], "-")) {
            // TODO: handle arguments which are not flags
            continue;
        }
        var option = std.mem.splitScalar(u8, std.mem.trimLeft(u8, args[i], "-"), '=');
        const param = option.first();
        if (std.mem.eql(u8, param, name)) {
            if (option.peek()) |val| {
                return switch (flag[1]) {
                    bool, ?bool => std.mem.eql(u8, val, "true"),
                    i16, u16, i32, i64, u32, u64 => std.fmt.parseInt(flag[1], val, 10) catch std.debug.panic("Invalid integer for option '{s}'", .{name}),
                    []u8, []const u8, ?[]u8, ?[]const u8 => try arena.allocator().dupe(u8, val),
                    else => error.InvalidFlagType,
                };
            } else if (args.len > (i + 1) and !std.mem.startsWith(u8, args[i + 1], "-")) {
                return switch (flag[1]) {
                    bool, ?bool => std.mem.eql(u8, args[i + 1], "true"),
                    i16, u16, i32, i64, u32, u64 => std.fmt.parseInt(flag[1], args[i + 1], 10) catch std.debug.panic("Invalid integer for option '{s}'", .{name}),
                    []u8, []const u8, ?[]u8, ?[]const u8 => try arena.allocator().dupe(u8, args[i + 1]),
                    else => error.InvalidFlagType,
                };
            } else if (flag[1] == bool) {
                return if (flag.len > 2) !flag[2] else true;
            }
        }
    }
    return null;
}

const path_separator = if (builtin.os.tag == .windows) '\\' else '/';

fn Parsed(comptime options: anytype) type {
    const T = Flag(options);
    return struct {
        const Self = @This();

        prog: []const u8,
        args: [][]u8,
        flags: T,
        allocator: std.heap.ArenaAllocator,

        pub fn init(flags: T, arena: std.heap.ArenaAllocator, arglist: [][]u8) !Self {
            var args = try std.process.ArgIterator.initWithAllocator(arena.child_allocator);
            defer args.deinit();
            const prog = if (args.next()) |arg0|
                (if (std.mem.lastIndexOfScalar(u8, arg0, path_separator)) |i| arg0[i + 1 ..] else arg0)
            else
                unreachable;
            return .{
                .prog = try arena.child_allocator.dupe(u8, prog),
                .args = arglist,
                .flags = flags,
                .allocator = arena,
            };
        }

        pub fn deinit(self: Self) void {
            self.allocator.deinit();
            self.allocator.child_allocator.free(self.prog);
            self.allocator.child_allocator.free(self.args);
        }

        pub fn writeHelp(self: Self, writer: anytype) !void {
            _ = self;
            const nameWidth = comptime largest: {
                var w = 0;
                for (options) |flag| {
                    if (flag[0].len > w) w = flag[0].len;
                }
                break :largest w;
            };

            inline for (options) |flag| {
                const flagName = flag[0];
                const flagHelp = if (flag.len > 3) flag[3] else "";
                const flagType = switch (flag[1]) {
                    bool, ?bool => "boolean",
                    i16, u16, i32, i64, u32, u64 => "integer",
                    []u8, []const u8, ?[]u8, ?[]const u8 => "string",
                    else => "unknown",
                };
                const spacing1 = " " ** (nameWidth + 4 - flagName.len);
                const spacing2 = " " ** (nameWidth + 4 - flagType.len);
                try std.fmt.format(writer, "--{s}{s}{s}{s}{s}\n", .{ flagName, spacing1, flagType, spacing2, flagHelp });
            }
        }
    };
}

/// **Parse command line arguments**, returning a Parsed struct.
/// `flags` is a comptime anonymous structure, where each element defines an option to be parsed.
/// Each element has the fields `name`, `type`, `default` and `description`, in this order.
/// Example:
/// const flags = try parseFlags(.{
///     .{ "help", bool, false, "show help message" },
///     .{ "input", ?[]u8, null, "input filename" },
///     .{ "threads", u32, 1, "number of threads" },
/// }, allocator);
pub fn parse(comptime options: anytype, allocator: std.mem.Allocator) !Parsed(options) {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var flags: Flag(options) = undefined;
    var arena = std.heap.ArenaAllocator.init(allocator);
    var arguments = std.ArrayList([]u8).init(allocator);
    defer arguments.deinit();

    inline for (options) |f| {
        if (f.len > 2 and @typeInfo(@TypeOf(f[2])) != .null) {
            @field(flags, f[0]) = f[2];
        } else if (@typeInfo(f[1]) == .optional) {
            @field(flags, f[0]) = null;
        }
    }

    var i: usize = 1;

    while (i < args.len) {
        if (!std.mem.startsWith(u8, args[i], "-")) {
            try arguments.append(try arena.allocator().dupe(u8, args[i]));
            i += 1;
            continue;
        }

        var valid: bool = false;

        var option = std.mem.splitScalar(u8, std.mem.trimLeft(u8, args[i], "-"), '=');
        const param = option.first();

        inline for (options) |flag| {
            const name = flag[0];
            if (std.mem.eql(u8, param, name)) {
                valid = true;
                if (option.peek()) |val| {
                    @field(flags, name) = switch (flag[1]) {
                        bool, ?bool => std.mem.eql(u8, val, "true"),
                        i16, u16, i32, i64, u32, u64 => std.fmt.parseInt(flag[1], val, 10) catch std.debug.panic("Invalid integer for option '{s}'", .{name}),
                        []u8, []const u8, ?[]u8, ?[]const u8 => try arena.allocator().dupe(u8, val),
                        else => return error.InvalidFlagType,
                    };
                } else if (flag[1] == bool) {
                    @field(flags, name) = if (flag.len > 2) !flag[2] else true;
                } else if (args.len > (i + 1) and !std.mem.startsWith(u8, args[i + 1], "-")) {
                    @field(flags, name) = switch (flag[1]) {
                        i16, u16, i32, i64, u32, u64 => std.fmt.parseInt(flag[1], args[i + 1], 10) catch std.debug.panic("Invalid integer for option '{s}'", .{name}),
                        []u8, []const u8, ?[]u8, ?[]const u8 => try arena.allocator().dupe(u8, args[i + 1]),
                        else => return error.InvalidFlagType,
                    };
                    i += 1;
                }
            }
        }

        if (!valid) {
            try arguments.append(try arena.allocator().dupe(u8, args[i]));
        }

        i += 1;
    }

    return try Parsed(options).init(flags, arena, try arguments.toOwnedSlice());
}
