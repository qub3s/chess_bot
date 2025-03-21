const std = @import("std");
const nn = @import("nn.zig");
const thread_list = @import("Thread_ArrayList.zig");
const tpool = @import("thread_pool.zig");
const static = @import("static_eval.zig");
const bb = @import("bb.zig");

const mem = std.mem;

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = general_purpose_allocator.allocator();

const board_evaluation = struct { board: bb.bitboard, value: f32 };

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
