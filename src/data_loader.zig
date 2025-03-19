const std = @import("std");
const string = @import("string.zig");

var general_purpose_alloc = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = general_purpose_alloc.allocator();

//pub fn parseFile(fileName: []const u8, alloc: std.mem.Allocator) !std.ArrayList([]u8) {
//    var result = std.ArrayList([]u8).init(alloc);
//
//    const file = try std.fs.cwd().openFile(fileName, .{});
//    defer file.close();
//
//    var parser = zcsv.allocs.column.init(alloc, file.reader(), .{});
//
//    _ = parser.next();
//    while (parser.next()) |row| {
//        defer row.deinit();
//
//        var cnt: usize = 0;
//        var arr = try alloc.alloc(u8, 28 * 28 + 1);
//
//        var fieldIter = row.iter();
//        while (fieldIter.next()) |field| {
//            arr[cnt] = try std.fmt.parseInt(u8, field.data(), 10);
//            cnt += 1;
//        }
//
//        try result.append(arr);
//    }
//    return result;
//}

pub fn fen_to_bb() void {}

pub fn parse_games(path: []const u8, number_positions: usize) !void {
    string.String.String_alloc = gpa;

    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    const reader = buf_reader.reader();

    var line = std.ArrayList(u8).init(gpa);
    defer line.deinit();

    const writer = line.writer();

    var line_num: usize = 0;

    while (line_num < number_positions) {
        try reader.streamUntilDelimiter(writer, '\n', null);
        defer line.clearRetainingCapacity();

        line_num += 1;

        const s = try string.String.init(line.items);
        var quotes: std.ArrayList(u32) = std.ArrayList(u32).init(gpa);

        try s.find(try string.String.init_s("\""), &quotes);

        std.debug.print("{s}\n", .{line.items[quotes.items[2] + 1 .. quotes.items[3]]});
        std.debug.print("{s}\n", .{line.items[quotes.items[9] + 2 .. quotes.items[10] - 1]});
    }
}

pub fn main() !void {
    std.debug.print("start:\n", .{});
    try parse_games("/home/qub3/Downloads/lichess_db_eval.jsonl", 30);
}
