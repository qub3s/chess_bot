const std = @import("std");
const mem = @import("std").mem;
const nn = @import("src/nn.zig");
const logic = @import("src/logic.zig");
const vis = @import("src/visualize.zig");
const tpool = @import("src/thread_pool.zig");
const train = @import("src/train.zig");
const static = @import("src/static_eval.zig");
const play = @import("src/play.zig");
const bench = @import("src/benchmark.zig");
const bb = @import("src/bitboard.zig");

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

fn vis_board(board: *logic.Board_s) void {
    const screenWidth = 1000;
    const screenHeight = 1000;
    const tile_size = 125;

    vis.ray.InitWindow(screenWidth, screenHeight, "");
    defer vis.ray.CloseWindow();
    vis.load_piece_textures() catch return;
    vis.ray.SetTargetFPS(30);

    while (!vis.ray.WindowShouldClose()) {
        vis.ray.BeginDrawing();
        defer vis.ray.EndDrawing();
        vis.visualize(board, tile_size) catch return;
    }
}

fn v_play_hvh() !void {
    var s = static.static_analysis.init();

    var board = logic.Board_s.init();

    const thread = try std.Thread.spawn(.{}, vis_board, .{&board});

    print("{}\n", .{vis.vis_thread});
    while (!vis.vis_thread) {
        const res = (try play.eval_position_move_pv(&board, &s, 1));

        print("{}\n", .{res});
    }

    thread.join();
    print("{}\n", .{try board.get_result()});
}

fn v_play_eve() !void {
    play.add_rand = true;
    var s = static.static_analysis.init();

    var board = logic.Board_s.init();

    const thread = try std.Thread.spawn(.{}, vis_board, .{&board});

    print("{}\n", .{vis.vis_thread});
    while (!vis.vis_thread) {
        print("{}\n", .{board.white_to_move});
        const res = (try play.play_best_move_pv(&board, &s, 4));
        print("{d}\n", .{res});
    }

    thread.join();
    print("{}\n", .{try board.get_result()});
}

pub fn main() !void {
    print("compiles...\n", .{});
    ray.SetTraceLogLevel(5);
    //try bench.benchmark_move_gen();

    var x = bb.bitboard.init();
    x.display();
    x.inverse();

    bb.generate_attackmaps();

    std.debug.print("\n", .{});
    for (0..16) |i| {
        std.debug.print("{}\n", .{i});
        bb.display_u64(bb.rook_masks_h[i]);
        std.debug.print("\n\n", .{});
    }

    //try v_play_hvh();
    //try v_play_eve();

    //try v_play_eve_static_pv();

    //const T: type = f32;
    //const seed = 33;
    //var model = nn.Network(T).init(gpa, true);
    //try model.add_LinearLayer(768, 64, seed);
    //try model.add_ReLU(64);
    //try model.add_LinearLayer(64, 32, seed);
    //try model.add_ReLU(32);
    //try model.add_LinearLayer(32, 1, seed);
    //try model.add_MSE(1);

    //const a: *nn.Network(T) = try gpa.create(nn.Network(T));
    //try model.copy(a);
    //try a.load("0");

    //const b: *nn.Network(T) = try gpa.create(nn.Network(T));
    //try model.copy(b);

    //const c: *nn.Network(T) = try gpa.create(nn.Network(T));
    //try model.copy(c);

    //const d: *nn.Network(T) = try gpa.create(nn.Network(T));
    //try model.copy(d);

    //const e: *nn.Network(T) = try gpa.create(nn.Network(T));
    //try model.copy(e);

    //const f: *nn.Network(T) = try gpa.create(nn.Network(T));
    //try model.copy(f);

    //const g: *nn.Network(T) = try gpa.create(nn.Network(T));
    //try model.copy(g);

    //var networks: [3]train.train_network = undefined;
    //networks[0] = train.train_network.init(a);
    //networks[1] = train.train_network.init(b);
    //networks[2] = train.train_network.init(c);
    //networks[3] = train.train_network.init(d);
    //networks[4] = train.train_network.init(e);
    //networks[5] = train.train_network.init(d);
    //networks[6] = train.train_network.init(e);

    //var eval: [1]static.static_analysis = undefined;
    //eval[0] = static.static_analysis.init();

    //try train.train_static(&eval, 6, 10, 10);
    //try v_play_hvh();
    //_ = try v_play_eve_minimax(networks[0].network, networks[1].network, 0);
    //try train.train(gpa, &networks, 4096, 12, 0.01, 0.01, 10000);
    //train.compete_eve_single_eval(a, b, 100, 0.01);
    //std.debug.print("{}\n", .{try v_play_eve_single_eval(a, b, 0.01)});
    //for (0..100) |_| {
    //    std.debug.print("{}\n", .{try v_play_eve_single_eval(a, b, 0.01)});
    //}
}
