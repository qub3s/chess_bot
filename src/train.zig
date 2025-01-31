const std = @import("std");
const logic = @import("logic.zig");
const nn = @import("nn.zig");
const thread_list = @import("Thread_ArrayList.zig");
const tpool = @import("thread_pool.zig");
const static = @import("static_eval.zig");

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
        if (!self.mutex_ressources.tryLock()) {
            self.mutex_ressources.lock();
        }
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

    pub fn reset_score(self: *train_network) void {
        if (!self.mutex_ressources.tryLock()) {
            std.debug.print("lock failed\n", .{});
            self.mutex_ressources.lock();
        }
        self.score = 0;
        self.games = 0;
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

fn train_batch(network: *train_network, lr: f32) void {
    var res: [1]f32 = .{0};
    var err: [1]f32 = .{0};
    network.network.eval = false;

    while (network.train_data.list.items.len != 0) {
        const X_raw = network.train_data.pop() catch return;
        var X: [768]f32 = mem.zeroes([768]f32);
        X_raw.board.get_input(&X);

        var y: [1]f32 = undefined;
        y[0] = X_raw.value;

        network.network.fp(&X, &y, &res, &err) catch return;
        network.network.bp(&y) catch return;
    }
    network.network.step(lr) catch return;
    network.network.eval = true;
}

pub fn train(allocator: std.mem.Allocator, networks: []train_network, games_until_training: u32, threads: u32, lr: f32, rng: f32, epochs: u32) !void {
    var rnd = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    var rand = rnd.random();

    var p: tpool.Pool = undefined;
    p.init(gpa, threads);

    for (0..epochs) |ep| {
        std.debug.print("{}\n", .{ep});

        // play games
        for (0..networks.len * games_until_training / 2) |_| {
            const idx_w = rand.intRangeAtMost(usize, 0, networks.len - 1);
            const idx_b = rand.intRangeAtMost(usize, 0, networks.len - 1);

            const cpy_w: *nn.Network(f32) = allocator.create(nn.Network(f32)) catch return;
            const cpy_b: *nn.Network(f32) = allocator.create(nn.Network(f32)) catch return;

            try networks[idx_w].network.copy(cpy_w);
            try networks[idx_b].network.copy(cpy_b);

            try p.spawn(play_eve_single_eval, .{ allocator, cpy_w, &networks[idx_w], cpy_b, &networks[idx_b], rng });
        }
        p.finish();

        // gradient descent
        std.debug.print("train\n", .{});
        for (0..networks.len) |i| {
            try p.spawn(train_batch, .{ &networks[i], lr });
        }
        p.finish();

        // save networks
        for (0..networks.len) |i| {
            var file_name: [2]u8 = undefined;
            try networks[i].network.save(try std.fmt.bufPrint(&file_name, "{d}", .{i}));
        }

        // check if model should be replaced
        //for (0..networks.len) |i| {
        //    if (networks[i].score / @as(f32, @floatFromInt(networks[i].games)) < 0.25) {
        //        // memory leak here that is ignored
        //        const new: *nn.Network(f32) = gpa.create(nn.Network(f32)) catch return;
        //        if (i != 0) {
        //            networks[i - 1].network.copy(new) catch return;
        //        } else {
        //            networks[networks.len - 1].network.copy(new) catch return;
        //        }

        //        networks[i].network.free();
        //        //allocator.destroy(networks[i].network.free());
        //        networks[i].network = new;
        //        std.debug.print("replaced model\n", .{});
        //    }
        //    networks[i].reset_score();
        //}
    }
}

fn play_eve_single_eval(allocator: std.mem.Allocator, network_w: *nn.Network(f32), w_tn: *train_network, network_b: *nn.Network(f32), b_tn: *train_network, randomness: f32) void {
    var num_move: i32 = 0;
    var board = logic.Board_s.init();

    var rnd = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    var rand = rnd.random();

    var general_purpose_allocators = std.heap.GeneralPurposeAllocator(.{}){};
    const gpas = general_purpose_allocators.allocator();

    var result: i32 = undefined;

    var moves = std.ArrayList(board_evaluation).initCapacity(gpas, 512) catch {
        network_w.free();
        network_b.free();
        allocator.destroy(network_w);
        allocator.destroy(network_b);
        return;
    };
    defer moves.deinit();

    while (true) {
        var pos_moves = std.ArrayList(logic.move).initCapacity(gpas, 64) catch {
            network_w.free();
            network_b.free();
            allocator.destroy(network_w);
            allocator.destroy(network_b);
            std.debug.print("free\n", .{});
            return;
        };
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
                    const ev = eval_board(&move_to_eval, network_b) catch {
                        network_w.free();
                        network_b.free();
                        allocator.destroy(network_w);
                        allocator.destroy(network_b);
                        std.debug.print("free\n", .{});
                        return;
                    };
                    val = ev + rnd_num;
                } else {
                    const ev = eval_board(&move_to_eval, network_w) catch {
                        network_w.free();
                        network_b.free();
                        allocator.destroy(network_w);
                        allocator.destroy(network_b);
                        std.debug.print("free\n", .{});
                        return;
                    };
                    val = ev + rnd_num;
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

    if (true) {
        w_tn.add_score(@floatFromInt(result));
        b_tn.add_score(@floatFromInt(result * -1));

        for (0..moves.items.len) |i| {
            // start with black eval
            result *= -1;
            moves.items[i].value = @floatFromInt(result);

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

pub fn compete_eve_single_eval(network_A: *nn.Network(f32), network_B: *nn.Network(f32), games: u32, randomness: f32) void {
    var network_w: *nn.Network(f32) = undefined;
    var network_b: *nn.Network(f32) = undefined;
    var score: i32 = 0;

    var rnd = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    var rand = rnd.random();

    for (0..games) |g| {
        var board = logic.Board_s.init();
        var result: i32 = undefined;
        var num_move: i32 = 0;

        if (g % 2 == 0) {
            network_w = network_A;
            network_b = network_B;
        } else {
            network_w = network_B;
            network_b = network_A;
        }

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
                        const ev = minimax(&move_to_eval, network_w, 1) catch return;
                        val = rnd_num + ev;
                    } else {
                        const ev = minimax(&move_to_eval, network_b, 1) catch return;
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
        }

        if (g % 2 == 0) {
            score += result;
        } else {
            score -= result;
        }
        std.debug.print("{}\n", .{score});
    }
}

pub fn minimax(board: *logic.Board_s, model: *nn.Network(f32), level: u32) !f32 {
    if (level == 0) {
        return eval_board(board, model);
    }

    var pos_moves = std.ArrayList(logic.move).init(gpa);
    defer pos_moves.deinit();
    try board.possible_moves(&pos_moves);

    // check for checkmate
    const mate = try board.check_mate();

    if (board.check_repetition() or pos_moves.items.len == 0) {
        if (pos_moves.items.len == 0 and mate) {
            return std.math.inf(f32) * @as(f32, @floatFromInt(board.get_winner()));
        } else {
            return 0;
        }
    }

    if (level % 2 == 0) {
        var value: f32 = -std.math.inf(f32);
        // maximize
        for (0..pos_moves.items.len) |i| {
            var cpy = board.copy();
            cpy.make_move_m(pos_moves.items[i]);
            const res = try minimax(&cpy, model, level - 1);

            if (res > value) {
                value = res;
            }
        }
        return value;
    } else {
        // minimize
        var value: f32 = std.math.inf(f32);

        for (0..pos_moves.items.len) |i| {
            var cpy = board.copy();
            cpy.make_move_m(pos_moves.items[i]);
            const res = try minimax(&cpy, model, level - 1);

            if (res < value) {
                value = res;
            }
        }
        return value;
    }
}

pub fn eval_board(board: *logic.Board_s, model: *nn.Network(f32)) !f32 {
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

// handles the inversion
pub fn static_eval(board: *logic.Board_s, model: static.static_analysis) f32 {
    var res = std.mem.zeroes([64]f32);

    if (!board.white_to_move) {
        board.inverse_board(&res);
    } else {
        @memcpy(res, board.pieces);
    }

    var large = std.mem.zeroes([768]f32);
    logic.Board_s.get_board_768(res, &large);

    return model.eval(large);
}

// doesnt work nega max
pub fn static_alpha_beta_max(board: *logic.Board_s, model: static.static_analysis, depth: u32, alpha: f32, beta: f32) f32 {
    if (depth == 0) {
        return static_eval(board, model);
    }

    var max = alpha;

    var pos_moves = std.ArrayList(logic.move).initCapacity(gpa, 64) catch return max;
    defer pos_moves.deinit();
    board.possible_moves(&pos_moves) catch return max;

    const mate = board.check_mate() catch return max;

    if (board.check_repetition() or pos_moves.items.len == 0) {
        if (pos_moves.items.len == 0 and mate) {
            if (board.white_to_move) {
                return std.math.inf(f32) * board.get_winner();
            } else {
                return std.math.inf(f32) * board.get_winner();
            }
        } else {
            return 0;
        }
    }

    for (0..pos_moves.items.len) |i| {
        var move_to_eval = board.copy();
        move_to_eval.make_move_m(pos_moves.items[i]);

        const val = static_alpha_beta_max(board, model, depth - 1, max, beta);

        if (val < max) {
            max = val;
            if (max >= beta) {
                break;
            }
        }
    }
    return max;
}

// doesnt work nega max
pub fn static_alpha_beta_min(board: *logic.Board_s, model: static.static_analysis, depth: u32, alpha: f32, beta: f32) f32 {
    if (depth == 0) {
        return static_eval(board, model);
    }

    var min = beta;

    var pos_moves = std.ArrayList(logic.move).initCapacity(gpa, 64) catch return min;
    defer pos_moves.deinit();
    board.possible_moves(&pos_moves) catch return min;

    const mate = board.check_mate() catch return min;

    if (board.check_repetition() or pos_moves.items.len == 0) {
        if (pos_moves.items.len == 0 and mate) {
            if (board.white_to_move) {
                return std.math.inf(f32) * board.get_winner();
            } else {
                return std.math.inf(f32) * board.get_winner();
            }
        } else {
            return 0;
        }
    }

    for (0..pos_moves.items.len) |i| {
        var move_to_eval = board.copy();
        move_to_eval.make_move_m(pos_moves.items[i]);

        const val = static_alpha_beta_max(board, model, depth - 1, alpha, min);

        if (val < min) {
            min = val;
            if (min <= alpha) {
                break;
            }
        }
    }
    return min;
}

pub fn negaMax(board: *logic.Board_s, model: static.static_analysis, depth: u32){
    if (depth == 0) {
        return static_eval(board, model);
    }

    var max = -std.math.inf(f32);

    var pos_moves = std.ArrayList(logic.move).initCapacity(gpa, 64) catch return min;
    defer pos_moves.deinit();
    board.possible_moves(&pos_moves) catch return min;

    const mate = board.check_mate() catch return min;
    if (board.check_repetition() or pos_moves.items.len == 0) {
        if (pos_moves.items.len == 0 and mate) {
                return -std.math.inf(f32); 
        }
        return 0;
    }

    for(0..pos_moves.items.len) |i| {
        var move_to_eval = board.copy();
        move_to_eval.make_move_m(pos_moves.items[i]);

        var val = -negaMax(move_to_eval, model, depth-1);

        if( val > max ){
            max = val;
        }
    }

    return max;
}

pub fn play_static(model_a: static.static_analysis, model_b: static.static_analysis, save_a: *static.static_analysis, save_b: *static.static_analysis) void {
    var num_move: i32 = 0;
    var board = logic.Board_s.init();

    var result: i32 = undefined;

    while (true) {
        var pos_moves = std.ArrayList(logic.move).initCapacity(gpa, 64) catch return;
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
                if (@mod(num_move, 2) == 0) {
                    val = negaMax(move_to_eval, model_a, 3);
                } else {
                    val = negaMax(move_to_eval, model_b, 3); 
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

    if (result == 1) {
        save_a.add(model_a);
    }

    if (result == -1) {
        save_b.add(model_b);
    }
}

pub fn train_static(eval: []static.static_analysis, threads: u32, epochs: u32, runs_before_step: u32) !void {
    var rnd = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    var rand = rnd.random();

    var p: tpool.Pool = undefined;
    p.init(gpa, threads);

    for (0..epochs) |_| {
        for (0..eval.len * runs_before_step / 2) |_| {
            const idx_w = rand.intRangeAtMost(usize, 0, eval.len - 1);
            const idx_b = rand.intRangeAtMost(usize, 0, eval.len - 1);

            _ = eval[idx_w].copy();
            _ = eval[idx_b].copy();

            //try p.spawn(play_eve_single_eval, .{ allocator, cpy_w, &networks[idx_w], cpy_b, &networks[idx_b], rng });
        }

        for (0..eval.len) |i| {
            eval[i].step();
        }
    }
}
