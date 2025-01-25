const std = @import("std");
const logic = @import("logic.zig");
const nn = @import("nn.zig");
const thread_list = @import("Thread_ArrayList.zig");
const tpool = @import("thread_pool.zig");

const mem = std.mem;

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = general_purpose_allocator.allocator();
const board_evaluation = struct { board: logic.Board_s, value: f32 };

pub const train_network = struct {
    train_data: thread_list.Thread_ArrayList(board_evaluation),
    network: *nn.Network(f32),
    games: u32,
    score: f32,
    mutex_ressources: std.Thread.Mutex = .{},

    pub fn add_score(self: *train_network, score: f32) void {
        self.mutex_ressources.lock();
        self.games += 1;

        if (score == 0) {
            self.score += 0.5;
        }

        if (score == 1) {
            self.score += 1;
        }

        if (self.games > 1000) {
            self.score -= self.score * 0.001;
        }

        self.mutex_ressources.unlock();
    }

    pub fn init(network: *nn.Network(f32)) train_network {
        return train_network{ .train_data = thread_list.Thread_ArrayList(board_evaluation).init(gpa), .network = network, .games = 0, .score = 0 };
    }
};

pub fn create_random_net(seed: u32) *nn.Network(f32) {
    const T: type = f32;
    var model = nn.Network(T).init(gpa, true);
    try model.add_LinearLayer(768, 64, seed);
    try model.add_ReLU(64);
    try model.add_LinearLayer(64, 32, seed);
    try model.add_ReLU(32);
    try model.add_LinearLayer(32, 1, seed);
    try model.add_MSE(1);

    const cpy: *nn.Network(T) = try gpa.create(nn.Network(T));
    try model.copy(cpy);
    return cpy;
}

pub fn train(networks: []train_network, games_until_training: u32, threads: u32) !void {
    var rnd = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    var rand = rnd.random();

    var p: tpool.Pool = undefined;
    p.init(gpa, threads);

    for (0..networks.len * games_until_training / 2) |_| {
        const idx_w = rand.intRangeAtMost(usize, 0, networks.len - 1);
        const idx_b = rand.intRangeAtMost(usize, 0, networks.len - 1);

        const cpy_w: *nn.Network(f32) = gpa.create(nn.Network(f32)) catch return;
        const cpy_b: *nn.Network(f32) = gpa.create(nn.Network(f32)) catch return;

        try networks[idx_w].network.copy(cpy_w);
        try networks[idx_b].network.copy(cpy_b);

        try p.spawn(play_eve_single_eval, .{ gpa, cpy_w, &networks[idx_w], cpy_b, &networks[idx_b], 0.01 });
    }
    p.finish();

    std.debug.print("\n", .{});
    std.debug.print("{}\n", .{networks[0].games});
    std.debug.print("{}\n", .{networks[1].games});
    std.debug.print("{}\n", .{networks[2].games});

    std.debug.print("{}\n", .{networks[0].score});
    std.debug.print("{}\n", .{networks[1].score});
    std.debug.print("{}\n", .{networks[2].score});
}

fn play_eve_single_eval(allocator: std.mem.Allocator, network_w: *nn.Network(f32), w_tn: *train_network, network_b: *nn.Network(f32), b_tn: *train_network, randomness: f32) void {
    var num_move: i32 = 0;
    var board = logic.Board_s.init();

    var rnd = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    var rand = rnd.random();

    var result: i32 = undefined;

    var moves = std.ArrayList(board_evaluation).init(gpa);
    defer moves.deinit();

    while (true) {
        var pos_moves = std.ArrayList(logic.move).init(gpa);
        defer pos_moves.deinit();
        board.possible_moves(&pos_moves) catch break;

        const mate = board.check_mate() catch break;
        if (board.check_repetition() or pos_moves.items.len == 0) {
            if (pos_moves.items.len == 0 and mate) {
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
                    const ev = eval_board(move_to_eval, network_b) catch {
                        network_w.free();
                        network_b.free();
                        allocator.destroy(network_w);
                        allocator.destroy(network_b);
                        return;
                    };
                    val = rnd_num + ev;
                } else {
                    const ev = eval_board(move_to_eval, network_w) catch {
                        network_w.free();
                        network_b.free();
                        allocator.destroy(network_w);
                        allocator.destroy(network_b);
                        return;
                    };
                    val = rnd_num + ev;
                }
            }

            if (val < min_value) {
                min_value = val;
                min = i;
            }
        }

        board.make_move_m(pos_moves.items[min]);
        num_move += 1;
        moves.append(board_evaluation{ .board = board.copy(), .value = 0 }) catch break;
    }

    std.debug.print("{}   ", .{result});
    if (result != 0) {
        w_tn.add_score(@floatFromInt(result));
        b_tn.add_score(@floatFromInt(result * -1));

        for (0..moves.items.len) |i| {
            // start with black eval
            moves.items[i].value = @floatFromInt(result * -1);
            result *= -1;

            if (@mod(i, 2) == 0) {
                b_tn.train_data.append(moves.items[i]) catch break;
            } else {
                w_tn.train_data.append(moves.items[i]) catch break;
            }
        }
    }

    network_w.free();
    network_b.free();
    allocator.destroy(network_w);
    allocator.destroy(network_b);
}

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
