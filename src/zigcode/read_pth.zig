const std = @import("std");
const string = @import("string.zig");
const print = std.debug.print;

var general_purpose_alloc = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = general_purpose_alloc.allocator();

pub fn read_pth_file(path: []const u8) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    // 2^30 (1GB)
    const buf_size = 50000;
    var buf: [buf_size]u8 = std.mem.zeroes([buf_size]u8);

    const buf_len = try in_stream.readAll(@constCast(&buf));

    if (buf_len == buf_size) {
        print("Buffer too small file not read correctly", .{});
    }

    const written_buffer = buf[0..buf_len];
    const string_buf = try string.String.init(written_buffer);

    // splitting
    var res = std.ArrayList(string.String).init(gpa);
    defer res.deinit();
    const split = try string.String.init_s("\n");

    try string_buf.split(split, &res);

    for (0..res.items.len) |i| {
        print("{s}\n", .{res.items[i].str});
        }
    }
}

pub fn main() !void {
    print("compile...\n", .{});
    string.String.String_alloc = gpa;

    _ = std.ArrayList([]u8).init(gpa);
    try read_pth_file("transfer/model_files/model.csv");

    print("done...\n", .{});
}
