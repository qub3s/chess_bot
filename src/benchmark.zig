const std = @import("std");
const logic = @import("logic.zig");
const play = @import("play.zig");
const static = @import("static_eval.zig");

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = general_purpose_allocator.allocator();

pub fn benchmark_move_gen() !void {
    var s = static.static_analysis.init();

    var board = logic.Board_s.init();

    for (0..10) |_| {
        _ = try play.play_best_move_pv(&board, &s, 2);
    }

    const start = std.time.milliTimestamp();
    var stop: i64 = 0;
    var counter: u32 = 0;

    while (stop - start < 1000) {
        var pos_moves = try std.ArrayList(logic.move).initCapacity(gpa, 256);
        defer pos_moves.deinit();
        try board.possible_moves(&pos_moves);

        counter += 1;
        stop = std.time.milliTimestamp();
    }

    std.debug.print("Counter: {}\n", .{counter});
}
