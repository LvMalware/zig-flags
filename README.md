## zig flags

A command line flags parser for zig.

Works only with Zig `0.14.0`!

Example:

```zig

const std = @import("std");
const flag = @import("flag.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const parsed = try flag.parse(.{
        .{ "help", bool, false, "Show help" },
        .{ "filename", ?[]u8, null, "Input filename" },
    }, allocator);

    defer parsed.deinit();

    std.debug.print("Filename: {?s}\n", .{ parsed.flags.filename });

    if (parsed.flags.help) {
        std.debug.print("help message\n", .{});
    }
    // ...
}

```
