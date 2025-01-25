const std = @import("std");
const mem = @import("std").mem;

const nn = @import("src/nn.zig");
const logic = @import("src/logic.zig");
const vis = @import("src/visualize.zig");
const tpool = @import("src/thread_pool.zig");
const train = @import("src/train.zig");

const Thread_ArrayList = @import("src/Thread_ArrayList.zig");

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = general_purpose_allocator.allocator();

const print = std.debug.print;

const Error = error{
    ErrorLogic,
};

const max_game_len: usize = 300;

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
            val = try train.eval_board(move_to_eval, engine);
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

//fn train(engine: *nn.Network(f32), result: *std.ArrayList(board_evaluation), epochs: usize, lr: f32) !void {
//    const batchsize = result.items.len;
//    var err = std.mem.zeroes([1]f32);
//    var res = std.mem.zeroes([1]f32);
//
//    for (0..batchsize * epochs) |i| {
//        const sample = rand.intRangeAtMost(usize, 0, batchsize - 1);
//        var X = std.mem.zeroes([768]f32);
//        result.items[sample].board.get_input(&X);
//
//        var y: [1]f32 = undefined;
//        y[0] = result.items[sample].value;
//
//        try engine.fp(&X, &y, &res, &err);
//
//        const e = res[0];
//        try engine.bp(&y);
//
//        if (i % batchsize == 0 and i != 0) {
//            try engine.step(lr);
//        }
//
//        if (std.math.isNan(e) or std.math.isInf(e)) {
//            print("break\n", .{});
//            break;
//        }
//    }
//}

//fn two_mm_train(T: type, allocator: std.mem.Allocator, engine: *nn.Network(f32), threads: u32, train_runs: u32, games_per_train_run: u32) !void {
//    var network_stack = Thread_ArrayList.Thread_ArrayList(*nn.Network(T)).init(allocator);
//
//    var p: tpool.Pool = undefined;
//    p.init(allocator, threads);
//
//    // create model copies
//    for (0..threads * 2) |_| {
//        const append: *nn.Network(T) = try allocator.create(nn.Network(T));
//        try engine.copy(append);
//
//        std.debug.print("append: {*}\n", .{append});
//        try network_stack.append(append);
//    }
//
//    for (0..train_runs) |_| {
//        var results = std.ArrayList(*std.ArrayList(board_evaluation)).init(allocator);
//        defer results.deinit();
//
//        // collect the games
//        for (0..games_per_train_run) |_| {
//            const res = try allocator.create(std.ArrayList(board_evaluation));
//            res.* = try std.ArrayList(board_evaluation).initCapacity(allocator, max_game_len);
//            try results.append(res);
//
//            //const mod = try network_stack.pop();
//            //try p.spawn(two_mm_play_engine_game, .{ mod, 1, results.items[results.items.len - 1], &network_stack });
//        }
//        p.finish();
//
//        // delete the model copies
//        while (network_stack.list.items.len != 0) {
//            const deinit = network_stack.list.items[network_stack.list.items.len - 1];
//            deinit.free();
//        }
//
//        var unify = std.ArrayList(board_evaluation).init(allocator);
//
//        for (results.items) |res| {
//            try unify.appendSlice(res.items);
//            res.deinit();
//        }
//
//        // train
//    }
//
//    return;
//}

fn v_play_hvh() !void {
    const screenWidth = 1000;
    const screenHeight = 1000;
    const tile_size = 125;

    var board = logic.Board_s.init();

    vis.ray.InitWindow(screenWidth, screenHeight, "");
    defer vis.ray.CloseWindow();
    try vis.load_piece_textures();
    vis.ray.SetTargetFPS(30);
    var result: i32 = 0;

    while (!vis.ray.WindowShouldClose()) {
        vis.ray.BeginDrawing();
        defer vis.ray.EndDrawing();
        try vis.visualize(&board, tile_size);

        var pos_moves = std.ArrayList(logic.move).init(gpa);
        defer pos_moves.deinit();
        try board.possible_moves(&pos_moves);

        if (board.check_repetition() or (pos_moves.items.len == 0 and try board.check_mate())) {
            if (pos_moves.items.len == 0 and try board.check_mate()) {
                result = board.get_winner();
            } else {
                result = 0;
            }
        }

        std.debug.print("{}\n", .{result});
    }
}

fn v_play_eve_single_eval(engine_w: *nn.Network(f32), engine_b: *nn.Network(f32), randomness: f32) !i32 {
    var num_move: i32 = 0;
    var board = logic.Board_s.init();

    var rnd = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    var rand = rnd.random();

    const screenWidth = 1000;
    const screenHeight = 1000;

    vis.ray.InitWindow(screenWidth, screenHeight, "");
    defer vis.ray.CloseWindow();
    try vis.load_piece_textures();
    vis.ray.SetTargetFPS(10);

    var result: i32 = undefined;

    while (true) {
        vis.ray.BeginDrawing();
        defer vis.ray.EndDrawing();
        try vis.visualize(&board, 125);

        var pos_moves = std.ArrayList(logic.move).init(gpa);
        defer pos_moves.deinit();
        try board.possible_moves(&pos_moves);

        if (board.check_repetition() or (pos_moves.items.len == 0 and try board.check_mate())) {
            if (pos_moves.items.len == 0 and try board.check_mate()) {
                result = board.get_winner();
            } else {
                result = 0;
            }
            break;
        }

        var min: usize = 0;
        var min_value: f32 = std.math.inf(f32);

        for (0..pos_moves.items.len) |i| {
            var val: f32 = undefined;

            var move_to_eval = board.copy();
            move_to_eval.make_move_m(pos_moves.items[i]);

            if (move_to_eval.check_win() != 0) {
                val = -std.math.inf(f32);
            } else {
                const rnd_num = rand.float(f32) * randomness;
                if (@mod(num_move, 2) == 0) {
                    val = try train.eval_board(move_to_eval, engine_b) + rnd_num;
                } else {
                    val = try train.eval_board(move_to_eval, engine_w) + rnd_num;
                }
            }

            if (val < min_value) {
                min_value = val;
                min = i;
            }
        }

        board.make_move_m(pos_moves.items[min]);
        num_move += 1;
    }
    return result;
}

pub fn main() !void {
    print("compiles...\n", .{});
    //try v_play_hvh();

    const T: type = f32;
    const seed = 33;
    var model = nn.Network(T).init(gpa, true);
    try model.add_LinearLayer(768, 64, seed);
    try model.add_ReLU(64);
    try model.add_LinearLayer(64, 32, seed);
    try model.add_ReLU(32);
    try model.add_LinearLayer(32, 1, seed);
    try model.add_MSE(1);

    const a: *nn.Network(T) = try gpa.create(nn.Network(T));
    try model.copy(a);

    const b: *nn.Network(T) = try gpa.create(nn.Network(T));
    try model.copy(b);

    const c: *nn.Network(T) = try gpa.create(nn.Network(T));
    try model.copy(c);

    var networks: [3]train.train_network = undefined;
    networks[0] = train.train_network.init(a);
    networks[1] = train.train_network.init(b);
    networks[2] = train.train_network.init(c);

    try train.train(&networks, 100, 12);

    //try v_play_eve_single_eval(&model, cpy, 0.1);

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
