const std = @import("std");
const logic = @import("logic.zig");
const play = @import("play.zig");
const static = @import("static_eval.zig");
const bb = @import("bitboard.zig");

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = general_purpose_allocator.allocator();

// pseudolegal move generation -> target larger than a million a second

pub fn pseudolegal_moves(sec: i64) !void {
    std.debug.print("\nStart Benchmarking Pseudolegal Move Generation ... \n", .{});

    var board = bb.bitboard.init();

    const start: i64 = std.time.milliTimestamp();

    var nps: i64 = 1;

    while (std.time.milliTimestamp() < start + sec * 1000) {
        var list = try std.ArrayList(bb.bitboard).initCapacity(gpa, 100);
        try board.gen_moves(&list);
        nps += 1;
    }

    std.debug.print("Nodes per Second: {d}\n", .{@divTrunc(nps, sec)});
}

// move analysis
