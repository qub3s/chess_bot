const std = @import("std");
const nn = @import("nn.zig");
const thread_list = @import("Thread_ArrayList.zig");
const tpool = @import("thread_pool.zig");
const static = @import("static_eval.zig");
const bb = @import("bitboard.zig");
const dl = @import("data_loader.zig");

const mem = std.mem;

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = general_purpose_allocator.allocator();

const board_evaluation = struct { board: bb.bitboard, value: f32 };

pub fn create_random_net(seed: u32) !*nn.Network(f32) {
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

pub fn train_network(network: *nn.Network(f32), lr: f32, batches: usize, batch_size: usize, Xs: *std.ArrayList([768]f32), ys: *std.ArrayList(i32)) !void {
    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rnd = prng.random();

    for (0..batches) |_| {
        var res: [1]f32 = .{0};
        var err: [1]f32 = .{0};
        var cumulative_error: f32 = 0;

        for (0..batch_size) |_| {
            const idx = std.Random.intRangeAtMost(rnd, usize, 0, Xs.items.len - 1);
            var X = std.mem.zeroes([768]f32);
            @memcpy(&X, &Xs.items[idx]);

            var y = std.mem.zeroes([1]f32);
            @memset(&y, @floatFromInt(ys.items[idx]));

            network.fp(&X, &y, &res, &err) catch return;
            network.bp(&y) catch return;

            cumulative_error += err[0];
        }
        std.debug.print("Error: {}\n", .{cumulative_error / @as(f32, @floatFromInt(batch_size))});

        network.step(lr) catch return;
        network.eval = true;
    }
}

pub fn main() !void {
    const net = try create_random_net(32);

    var board = std.ArrayList([768]f32).init(gpa);
    var evals = std.ArrayList(i32).init(gpa);

    try dl.parse_games("/home/qub3/downloads/lichess_db_eval.jsonl", 5, &evals, &board);

    try train_network(net, 0.001, 100, 10, &board, &evals);
}
