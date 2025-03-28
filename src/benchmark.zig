const std = @import("std");
const play = @import("play.zig");
const static = @import("static_eval.zig");
const bb = @import("bitboard.zig");

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = general_purpose_allocator.allocator();

// pseudolegal move generation -> target larger than a million a second

pub fn pseudolegal_moves(iterations: u64) !void {
    std.debug.print("\nStart Benchmarking Pseudolegal Move Generation ... \n", .{});

    var board = bb.bitboard.init();

    const start: i128 = std.time.nanoTimestamp();

    for (0..iterations) |_| {
        var moves: [256]bb.bitboard = undefined;
        var number_of_moves: usize = 0;

        try board.gen_moves(&moves, &number_of_moves);

        if (number_of_moves == 0) {
            board = bb.bitboard.init();
        } else {
            board = moves[0];
        }
    }

    const factor: f64 = @as(f64, 1000000000) / @as(f64, @floatFromInt(std.time.nanoTimestamp() - start));

    std.debug.print("Mega Nodes per Second: {d} (Mnps) \n", .{@as(f64, @floatFromInt(iterations)) * factor / 1000000});
}

pub fn pv_eval(iterations: u64) !void {
    std.debug.print("\nStart Benchmarking Evaluation Speed ... \n", .{});

    var board = bb.bitboard.init();
    var eval = static.static_analysis.init();

    const start: i128 = std.time.nanoTimestamp();

    for (0..iterations) |_| {
        var moves: [256]bb.bitboard = undefined;
        var number_of_moves: usize = 0;

        try board.gen_moves(&moves, &number_of_moves);

        if (number_of_moves == 0) {
            board = bb.bitboard.init();
        } else {
            for (0..number_of_moves) |i| {
                var board_64 = std.mem.zeroes([64]i32);
                moves[i].to_num_board(&board_64);
                _ = eval.eval_pv(board_64);
            }

            // eval positions
            board = moves[0];
        }
    }

    const factor: f64 = @as(f64, 1000000000) / @as(f64, @floatFromInt(std.time.nanoTimestamp() - start));

    std.debug.print("Mega Nodes per Second: {d} (Mnps) \n", .{@as(f64, @floatFromInt(iterations)) * factor / 1000000});
}

//pub fn move_generation_plus_pv(iterations: u64) !void {}
