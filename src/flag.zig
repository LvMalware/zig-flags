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
        if (!std.mem.startsWith(u8, args[i], "-"))
            // TODO: handle arguments which are not flags
            continue;
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
            } else if (args.len > (i + 1) and !std.mem.startsWith(u8, args[i + 1], "--")) {
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

fn Parsed(comptime options: anytype) type {
    const T = Flag(options);
    return struct {
        const Self = @This();

        flags: T,
        allocator: std.heap.ArenaAllocator,

        pub fn init(flags: T, allocator: std.heap.ArenaAllocator) Self {
            return .{
                .flags = flags,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: Self) void {
            self.allocator.deinit();
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

/// **Parse command line arguments**, returning a struct where each field is a command line option.
/// `flags` is a comptime anonymous structure, where each element defines an option to be parsed.
/// Each element has the fields `name`, `type` and (optionally) `default`, in this order.
/// Example:
/// const flags = try parseFlags(.{
///     .{ "help", bool, false },
///     .{ "input", ?[]u8 },
///     .{ "threads", u32, 1 },
/// }, allocator);
pub fn parseFlags(comptime options: anytype, allocator: std.mem.Allocator) !Parsed(options) {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var flags: Flag(options) = undefined;

    var arena = std.heap.ArenaAllocator.init(allocator);

    inline for (options) |f| {
        @field(flags, f[0]) = if (try findFlag(f, &arena, args)) |value| value else if (f.len > 2 and @typeInfo(@TypeOf(f[2])) != .null) f[2] else if (@typeInfo(f[1]) == .optional) null else std.debug.panic("Missing option {s}", .{f[0]});
    }
    return Parsed(options).init(flags, arena);
}
