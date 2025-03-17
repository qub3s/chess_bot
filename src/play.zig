const std = @import("std");
const nn = @import("nn.zig");
const thread_list = @import("Thread_ArrayList.zig");
const static = @import("static_eval.zig");
const bb = @import("bitboard.zig");

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = general_purpose_allocator.allocator();

pub var add_rand = false;
pub var analyzed_positions: u32 = 0;

fn nega_max_static_pv(board: *bb.bitboard, model: *static.static_analysis, level: u32, alpha: f32, beta: f32) !f32 {
    if (level == 0) {
        return static_eval_pv(board, model);
    }

    var max = alpha;
    var val: f32 = undefined;

    var moves: [256]bb.bitboard = undefined;
    var number_of_moves: usize = 0;
    try board.gen_moves(&moves, &number_of_moves);

    for (0..number_of_moves) |i| {
        var move_to_eval = moves[i];

        val = -1 * (try nega_max_static_pv(&move_to_eval, model, level - 1, -beta, -max));

        if (val > max) {
            max = val;
            if (max >= beta) {
                return std.math.inf(f32);
            }
        }
    }

    return max;
}

pub fn static_eval_pv(board: *bb.bitboard, model: *static.static_analysis) !f32 {
    var rnd = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    var rand = rnd.random();

    var res = std.mem.zeroes([64]i32);
    board.to_num_board(&res);

    var ret: f32 = 0;
    if (add_rand) {
        ret = model.eval_pv(res) + rand.float(f32) * 0.0001;
    } else {
        ret = model.eval_pv(res);
    }

    //for (0..64) |i| {
    //    if (i % 8 == 0 and i != 0) {
    //        std.debug.print("\n", .{});
    //    }
    //    std.debug.print("{}   ", .{res[i]});
    //}
    //std.debug.print("\n\n\n", .{});

    analyzed_positions += 1;

    if (board.white_to_move) {
        return ret;
    } else {
        return -ret;
    }
}

pub fn play_best_move_pv(board: *bb.bitboard, model: *static.static_analysis, level: u32) !f32 {
    var moves: [256]bb.bitboard = undefined;
    var number_of_moves: usize = 0;

    try board.gen_moves(&moves, &number_of_moves);

    var max = -std.math.inf(f32);
    var indx: i32 = 0;

    if (number_of_moves == 0) {
        std.debug.print("game over!\n", .{});
        return 0;
    }

    for (0..number_of_moves) |i| {
        var val: f32 = 0;
        var move_to_eval = moves[i];

        var moves_2: [256]bb.bitboard = undefined;
        var number_of_moves_2: usize = 0;
        try board.gen_moves(&moves_2, &number_of_moves_2);

        val = -1 * (try nega_max_static_pv(&move_to_eval, model, level - 1, -std.math.inf(f32), std.math.inf(f32)));

        if (val > max) {
            max = val;
            indx = @intCast(i);
        }
    }

    board.* = (moves[@intCast(indx)]);
    std.debug.print("Analyzed Positions: {}\n", .{analyzed_positions});
    analyzed_positions = 0;
    return max;
}
