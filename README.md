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

    const flags = try flag.parseFlags(.{
        .{ "help", bool, false },
        .{ "filename", ?[]u8 },
    }, allocator);

    std.debug.print("Filename: {?s}\n", .{ flags.filename });

    if (flags.help) {
        std.debug.print("help message\n", .{});
    }
    // ...
}

```
