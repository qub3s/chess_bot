const std = @import("std");
const mem = @import("std").mem;

const nn = @import("src/nn.zig");
const logic = @import("src/logic.zig");
const vis = @import("src/visualize.zig");
const tpool = @import("src/thread_pool.zig");
const train = @import("src/train.zig");

pub const ray = @cImport({
    @cInclude("raylib.h");
});

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

        if (board.check_repetition() or (pos_moves.items.len == 0)) {
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
                    val = try train.minimax(&move_to_eval, engine_w, 1);
                    val += rnd_num;
                } else {
                    val = try train.minimax(&move_to_eval, engine_b, 1);
                    val += rnd_num;
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
    ray.SetTraceLogLevel(5);
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

    const d: *nn.Network(T) = try gpa.create(nn.Network(T));
    try model.copy(d);

    const e: *nn.Network(T) = try gpa.create(nn.Network(T));
    try model.copy(e);

    const f: *nn.Network(T) = try gpa.create(nn.Network(T));
    try model.copy(f);

    const g: *nn.Network(T) = try gpa.create(nn.Network(T));
    try model.copy(g);

    var networks: [3]train.train_network = undefined;
    networks[0] = train.train_network.init(a);
    networks[1] = train.train_network.init(b);
    networks[2] = train.train_network.init(c);
    //networks[3] = train.train_network.init(d);
    //networks[4] = train.train_network.init(e);
    //networks[5] = train.train_network.init(d);
    //networks[6] = train.train_network.init(e);

    try train.train(&networks, 1000, 4, 0.01, 0.01, 10000);
    //try train.compete_eve_single_eval(a, b, 100, 0.01);
    //std.debug.print("{}\n", .{try v_play_eve_single_eval(a, b, 0.01)});
    //for (0..100) |_| {
    //    std.debug.print("{}\n", .{try v_play_eve_single_eval(a, b, 0.01)});
    //}
}
