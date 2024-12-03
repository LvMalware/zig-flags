const std = @import("std");
const flag = @import("flag.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const flags = try flag.parseFlags(.{
        .{ "help", bool, false },
        .{ "threads", u32, 1 },
        .{ "filename", ?[]u8 },
        // ensure the third element has the right type to be a default value
        .{ "output", []u8, @as([]u8, @constCast("output.txt")) },
    }, allocator);

    inline for (@typeInfo(@TypeOf(flags)).Struct.fields) |field| {
        std.debug.print("Option '{s}' has type {} and value: ", .{ field.name, field.type });
        std.debug.print(switch (field.type) {
            []u8, []const u8, ?[]u8, ?[]const u8 => "{?s}\n",
            else => "{any}\n",
        }, .{@field(flags, field.name)});
    }
}

test "flag parser" {
    try main();
}
