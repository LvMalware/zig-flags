const std = @import("std");
const flag = @import("flag.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const parsed = try flag.parseFlags(.{
        .{ "help", bool, false, "Show help message and exit" },
        .{ "threads", u32, 1, "Number of threads" },
        .{ "filename", ?[]u8, null, "Input filename" },
        // ensure the third element has the right type to be a default value
        .{ "output", []u8, @as([]u8, @constCast("output.txt")), "Output filename" },
    }, allocator);

    defer parsed.deinit();

    if (parsed.flags.help) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("Usage: {s} [Options]\n\nOptions:\n\n", .{parsed.prog});
        try parsed.writeHelp(stdout);
        try stdout.print("\n", .{});
    }

    inline for (@typeInfo(@TypeOf(parsed.flags)).@"struct".fields) |field| {
        std.debug.print("Option '{s}' has type {} and value: ", .{ field.name, field.type });
        std.debug.print(switch (field.type) {
            []u8, []const u8, ?[]u8, ?[]const u8 => "{?s}\n",
            else => "{any}\n",
        }, .{@field(parsed.flags, field.name)});
    }
}

test "flag parser" {
    try main();
}
