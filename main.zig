const std = @import("std");
const mem = @import("std").mem;

const nn = @import("src/nn.zig");
const logic = @import("src/logic.zig");
const vis = @import("src/visualize.zig");
const tpool = @import("src/thread_pool.zig");
const Thread_ArrayList = @import("src/Thread_ArrayList.zig");

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = general_purpose_allocator.allocator();

const print = std.debug.print;

const Error = error{
    ErrorLogic,
};

var rnd = std.rand.DefaultPrng.init(0);
var rand = rnd.random();

const max_game_len: usize = 300;

// piece_graphices
const tile_pos = struct { x: i32, y: i32 };
const board_evaluation = struct { board: logic.Board_s, value: f32 };

// empty = 0, wking = 1, wqueen = 2, wrook = 3, wbishop = 4, wknight = 5, wpawn = 6, bking = 7 ...

fn eval_board(board: logic.Board_s, model: *nn.Network(f32)) !f32 {
    var input = mem.zeroes([768]f32);
    var sol = mem.zeroes([1]f32);
    var result = mem.zeroes([1]f32);
    var err = mem.zeroes([1]f32);

    const res: f32 = @floatFromInt(board.check_win());
    if (res != 0) {
        return std.math.inf(f32);
    }

    board.get_input(&input);
    try model.fp(&input, &sol, &result, &err);
    return result[0];
}

fn two_mm_calc_min_move(engine: *nn.Network(f32), board: *logic.Board_s) !f32 {
    var pos_moves = std.ArrayList(logic.move).init(gpa);
    defer pos_moves.deinit();
    try board.possible_moves(&pos_moves);

    var min: usize = 0;
    var min_value: f32 = std.math.inf(f32);

    for (0..pos_moves.items.len) |i| {
        var val: f32 = undefined;
        var move_to_eval = board.copy();
        move_to_eval.make_move_m(pos_moves.items[i]);

        if (move_to_eval.check_win() != 0) {
            val = -std.math.inf(f32);
        } else {
            val = try eval_board(move_to_eval, engine);
        }

        if (val < min_value) {
            min_value = val;
            min = i;
        }
    }

    return min_value;
}

fn two_mm_play_move_single_eval(engine: *nn.Network(f32), board: *logic.Board_s) !logic.Board_s {
    var pos_moves = try std.ArrayList(logic.move).initCapacity(gpa, 100);
    defer pos_moves.deinit();
    try board.possible_moves(&pos_moves);

    var max: usize = 0;
    var max_value: f32 = -std.math.inf(f32);

    for (0..pos_moves.items.len) |i| {
        var val: f32 = undefined;
        var move_to_eval = board.copy();
        move_to_eval.make_move_m(pos_moves.items[i]);

        if (move_to_eval.check_win() != 0) {
            val = std.math.inf(f32);
        } else {
            val = try two_mm_calc_min_move(engine, &move_to_eval);
        }

        if (val > max_value) {
            max_value = val;
            max = i;
        }
    }

    board.make_move_m(pos_moves.items[max]);

    return board.*;
}

fn two_mm_make_random_move(board: *logic.Board_s) !void {
    var pos_moves = std.ArrayList(logic.move).init(gpa);
    defer pos_moves.deinit();
    try board.possible_moves(&pos_moves);

    for (0..100) |_| {
        var newboard = board.copy();
        const rnd_i = rand.intRangeAtMost(usize, 0, pos_moves.items.len - 1);
        newboard.make_move_m(pos_moves.items[rnd_i]);

        if (!try newboard.checkmate_next_move()) {
            board.make_move_m(pos_moves.items[rnd_i]);
            return;
        }
    }

    const rnd_i = rand.intRangeAtMost(usize, 0, pos_moves.items.len - 1);
    board.make_move_m(pos_moves.items[rnd_i]);
}

fn two_mm_play_engine_game(engine: *nn.Network(f32), random: f32, result: *std.ArrayList(board_evaluation), network_stack: *Thread_ArrayList.Thread_ArrayList(*nn.Network(f32))) void {
    var num_move: i32 = 0;
    var board = logic.Board_s.init();
    var errb = false;

    while (board.check_win() == 0 and num_move < 550) {
        //print("{any}\n", .{board.pieces});
        const rnd_num = rand.float(f32);

        if (rnd_num <= random) {
            board = two_mm_play_move_single_eval(engine, &board) catch |err| {
                print("Error: {}\n", .{err});
                errb = true;
                break;
            };
        } else {
            print("random", .{});
            two_mm_make_random_move(&board) catch |err| {
                print("Error: {}\n", .{err});
                errb = true;
                break;
            };
        }

        if (board.white_to_move) {
            result.append(board_evaluation{ .board = board.copy(), .value = @floatFromInt(num_move) }) catch |err| {
                print("Error: {}\n", .{err});
                errb = true;
                break;
            };
        } else {
            result.append(board_evaluation{ .board = board.copy(), .value = @floatFromInt(-num_move) }) catch |err| {
                print("Error: {}\n", .{err});
                errb = true;
                break;
            };
        }

        num_move += 1;
    }

    print("{}\n", .{num_move});

    const res: f32 = @floatFromInt(board.check_win());

    for (0..@intCast(num_move)) |i| {
        if (i % 2 == 0) {
            result.items[i].value = res;
        } else {
            result.items[i].value = -res;
        }
    }
    network_stack.append(engine) catch return;
}

fn train(engine: *nn.Network(f32), result: *std.ArrayList(board_evaluation), epochs: usize, lr: f32) !void {
    const batchsize = result.items.len;
    var err = std.mem.zeroes([1]f32);
    var res = std.mem.zeroes([1]f32);

    for (0..batchsize * epochs) |i| {
        const sample = rand.intRangeAtMost(usize, 0, batchsize - 1);
        var X = std.mem.zeroes([768]f32);
        result.items[sample].board.get_input(&X);

        var y: [1]f32 = undefined;
        y[0] = result.items[sample].value;

        try engine.fp(&X, &y, &res, &err);

        const e = res[0];
        try engine.bp(&y);

        if (i % batchsize == 0 and i != 0) {
            try engine.step(lr);
        }

        if (std.math.isNan(e) or std.math.isInf(e)) {
            print("break\n", .{});
            break;
        }
    }
}

fn two_mm_train(T: type, allocator: std.mem.Allocator, engine: *nn.Network(f32), threads: u32, train_runs: u32, games_per_train_run: u32) !void {
    var network_stack = Thread_ArrayList.Thread_ArrayList(*nn.Network(T)).init(allocator);

    var p: tpool.Pool = undefined;
    p.init(allocator, threads);

    // create model copies
    for (0..threads * 2) |_| {
        const append: *nn.Network(T) = try allocator.create(nn.Network(T));

        try engine.copy(append);

        std.debug.print("append: {*}\n", .{append});
        try network_stack.append(append);
    }

    for (0..train_runs) |_| {
        var results = std.ArrayList(*std.ArrayList(board_evaluation)).init(allocator);
        defer results.deinit();

        // collect the games
        for (0..games_per_train_run) |_| {
            const res = try allocator.create(std.ArrayList(board_evaluation));
            res.* = try std.ArrayList(board_evaluation).initCapacity(allocator, max_game_len);
            try results.append(res);

            const mod = try network_stack.pop();
            try p.spawn(two_mm_play_engine_game, .{ mod, 1, results.items[results.items.len - 1], &network_stack });
        }
        p.finish();

        // delete the model copies
        while (network_stack.list.items.len != 0) {
            const deinit = network_stack.list.items[network_stack.list.items.len - 1];
            deinit.free();
        }

        var unify = std.ArrayList(board_evaluation).init(allocator);

        for (results.items) |res| {
            try unify.appendSlice(res.items);
            res.deinit();
        }

        // train
    }

    return;
}

fn play_hvh() !void {
    const screenWidth = 1000;
    const screenHeight = 1000;
    const tile_size = 125;

    var board = logic.Board_s.init();

    vis.ray.InitWindow(screenWidth, screenHeight, "");
    defer vis.ray.CloseWindow();
    try vis.load_piece_textures();
    vis.ray.SetTargetFPS(30);
    while (!vis.ray.WindowShouldClose()) {
        vis.ray.BeginDrawing();
        defer vis.ray.EndDrawing();

        try vis.visualize(&board, tile_size);
    }
}

pub fn main() !void {
    print("compiles...\n", .{});
    try play_hvh();

    //const T: type = f32;
    //const seed = 22;
    //var model = nn.Network(T).init(gpa, true);
    //try model.add_LinearLayer(768, 64, seed);
    //try model.add_ReLu(64);
    //try model.add_LinearLayer(64, 32, seed);
    //try model.add_ReLu(32);
    //try model.add_LinearLayer(32, 1, seed);
    //try model.add_MSE(1);

    //const threads = 6;
    //try two_mm_train(T, gpa, &model, threads, 1, 1000);

    // declare allocator

    //try stage_one_train(gpa);

    //var model1 = nn.Network(T){ .layer = std.ArrayList(nn.LayerType(T)).init(gpa), .Allocator = gpa, .eval = true };
    //try model1.add_LinearLayer(768, 64, seed);
    //try model1.add_ReLu(64);
    //try model1.add_LinearLayer(64, 32, seed);
    //try model1.add_ReLu(32);
    //try model1.add_LinearLayer(32, 1, seed);
    //try model1.add_MSE(1);

    //try model_competition(&model, &model1, 10, 0.9);

}
