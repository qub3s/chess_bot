const std = @import("std");
const logic = @import("logic.zig");
const nn = @import("nn.zig");
const thread_list = @import("Thread_ArrayList.zig");
const static = @import("static_eval.zig");
const bb = @import("bitboard.zig");

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = general_purpose_allocator.allocator();

pub var add_rand = false;
var analyzed_positions: u32 = 0;

fn nega_max_static_pv(board: *bb.bitboard, model: *static.static_analysis, level: u32, alpha: f32, beta: f32) !f32 {
    if (level == 0) {
        return static_eval_pv(board, model);
    }

    var max = alpha;
    var val: f32 = undefined;

    var moves = std.ArrayList(bb.bitboard).init(gpa);
    defer moves.deinit();
    try board.gen_moves(&moves);

    for (0..moves.items.len) |i| {
        var move_to_eval = moves.items[i];

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
    res = board.to_num_board(&res);

    if (!board.white_to_move) {
        for (0..64) |i| {
            if (res[i] != 0 and res[i] <= 7) {
                res[i] = res[i] + 6;
            } else if (res[i] != 0 and res[i] > 7) {
                res[i] = res[i] - 6;
            }
        }
    }

    //for (0..64) |i| {
    //    if (i % 8 == 0 and i != 0) {
    //        std.debug.print("\n", .{});
    //    }
    //    std.debug.print("{}   ", .{res[i]});
    //}
    //std.debug.print("\n\n\n", .{});

    analyzed_positions += 1;
    if (add_rand) {
        return model.eval_pv(res) + rand.float(f32) * 0.0001;
    } else {
        return model.eval_pv(res);
    }
}

pub fn play_best_move_pv(board: *bb.bitboard, model: *static.static_analysis, level: u32) !f32 {
    var moves = std.ArrayList(bb.bitboard).init(gpa);
    defer moves.deinit();
    try board.gen_moves(&moves);

    var max = -std.math.inf(f32);
    var indx: i32 = 0;

    if (moves.items.len == 0) {
        std.debug.print("game over!\n", .{});
        return 0;
    }

    for (0..moves.items.len) |i| {
        var val: f32 = 0;
        var move_to_eval = moves.items[i];

        var pos_moves = std.ArrayList(bb.bitboard).init(gpa);
        defer pos_moves.deinit();
        try board.gen_moves(&pos_moves);

        val = -1 * (try nega_max_static_pv(&move_to_eval, model, level - 1, -std.math.inf(f32), std.math.inf(f32)));

        if (val > max) {
            max = val;
            indx = @intCast(i);
        }
    }

    board.* = (moves.items[@intCast(indx)]);
    //std.debug.print("Analyzed Positions: {}\n", .{analyzed_positions});
    analyzed_positions = 0;
    return max;
}

pub fn eval_position_move_pv(board: *logic.Board_s, model: *static.static_analysis, level: u32) !f32 {
    var cpy = board.copy();
    return play_best_move_pv(&cpy, model, level);
}
