const std = @import("std");
const zcsv = @import("zcsv");
const blas = @import("blas.zig");

const print = std.debug.print;

const NN_Error = error{
    ErrorDimensionsNotMatch,
    ErrorUnionWronglySet,
    ErrorLogic,
};

const LayerTypeTag = enum { linear, activfunc, lossfunc };

pub fn LayerType(comptime T: type) type {
    return union(LayerTypeTag) {
        linear: LinearLayer(T),
        activfunc: ActivationFunction(T),
        lossfunc: LossFunction(T),
    };
}

pub fn LinearLayer(comptime T: type) type {
    _ = switch (T) {
        f32 => 0,
        f64 => 0,
        else => @compileError("Types outside of f32 and f64 are not supported"),
    };

    return struct {
        indim: usize,
        outdim: usize,
        weight: []T,
        bias: []T,
        bias_cpy: []T, // saves additional allocation
        Allocator: std.mem.Allocator,

        input_activations: []T,
        grad_weight: AdamsOptimizer(T),
        grad_bias: AdamsOptimizer(T),

        // randomly initialize
        pub fn init_rand(indim: usize, outdim: usize, Allocator: std.mem.Allocator, rnd: u64) !LinearLayer(T) {
            // allocate memory
            const weight = try Allocator.alloc(T, indim * outdim);
            const bias = try Allocator.alloc(T, outdim);
            const bias_cpy = try Allocator.alloc(T, outdim);
            const input_activations = try Allocator.alloc(T, indim);

            const grad_weight = try AdamsOptimizer(T).init(indim * outdim, Allocator);
            const grad_bias = try AdamsOptimizer(T).init(outdim, Allocator);

            var rand = std.rand.DefaultPrng.init(rnd);

            for (0..weight.len) |i| {
                weight[i] = (rand.random().float(T) - 0.5) * 2 / @as(T, @floatFromInt(indim * outdim));
            }

            for (0..bias.len) |i| {
                bias[i] = (rand.random().float(T) - 0.5) * 2;
            }

            @memcpy(bias_cpy, bias);

            return LinearLayer(T){ .indim = indim, .outdim = outdim, .weight = weight, .bias = bias, .bias_cpy = bias_cpy, .input_activations = input_activations, .Allocator = Allocator, .grad_weight = grad_weight, .grad_bias = grad_bias };
        }

        pub fn deinit(self: @This()) void {
            self.Allocator.free(self.weight);
            self.Allocator.free(self.bias);
            self.Allocator.free(self.bias_cpy);
        }

        // foreward pass
        pub fn fp(self: *@This(), input: []T, result: []T, eval: bool) !void {
            if (input.len != self.indim) {
                return NN_Error.ErrorDimensionsNotMatch;
            }

            if (!eval) {
                @memcpy(self.input_activations, input);
            }

            blas.gemv(T, self.outdim, self.indim, self.weight, false, input, self.bias_cpy, 1, 1);

            @memcpy(result, self.bias_cpy);
            @memcpy(self.bias_cpy, self.bias);
        }

        pub fn bp(self: *@This(), input: []T, result: []T) !void {
            // create bias
            self.grad_weight.num_stored_grad += 1;
            self.grad_bias.num_stored_grad += 1;
            const sbias = self.grad_bias.grad;
            const sweight = self.grad_weight.grad;

            for (0..sbias.len) |i| {
                sbias[i] += input[i];
            }

            for (0..self.input_activations.len) |act| {
                for (0..input.len) |inp| {
                    sweight[act * input.len + inp] += self.input_activations[act] * input[inp];
                }
            }

            @memset(result, 0);
            blas.gemv(T, self.outdim, self.indim, self.weight, true, input, result, 1, 1);
        }

        pub fn step(self: *@This(), lr: T) !void {
            try self.grad_bias.step(lr, self.bias);
            try self.grad_weight.step(lr, self.weight);
        }

        pub fn print(self: @This()) void {
            std.debug.print("Weight: {}x{}: {any}", .{ self.indim, self.outdim, self.weight });
        }

        pub fn println(self: @This()) void {
            std.debug.print("Weight: {}x{}\n", .{ self.indim, self.outdim });
        }
    };
}

pub fn ActivationFunction(comptime T: type) type {
    return struct {
        type_: usize,
        s: []T,
        Allocator: std.mem.Allocator,

        pub fn relu_fp(self: *@This(), input: []T, eval: bool) !void {
            if (!eval) {
                @memcpy(self.s, input);
            }

            for (0..input.len) |i| {
                input[i] = @max(input[i], 0);
            }
        }

        pub fn relu_bp(self: @This(), input: []T) void {
            for (0..input.len) |i| {
                if (self.s[i] < 0) {
                    input[i] = 0;
                }
            }
        }

        pub fn fp(self: *@This(), input: []T, eval: bool) !void {
            switch (self.type_) {
                0 => return try relu_fp(self, input, eval),
                else => return NN_Error.ErrorUnionWronglySet,
            }
        }

        pub fn bp(self: @This(), input: []T) !void {
            switch (self.type_) {
                0 => return relu_bp(self, input),
                else => return NN_Error.ErrorUnionWronglySet,
            }
        }
    };
}

pub fn LossFunction(comptime T: type) type {
    return struct {
        type_: usize,
        s: []T,
        Allocator: std.mem.Allocator,

        pub fn mse_init(Allocator: std.mem.Allocator) LossFunction(T) {
            const s = Allocator.alloc(T, 1);

            return struct { .type_ = 0, .s = s, .Allocator = Allocator };
        }

        pub fn mse_fp(self: *@This(), res: []T, sol: []T, eval: bool) !void {
            if (!eval) {
                @memcpy(self.s, res);
            }

            for (0..res.len) |i| {
                res[i] = (sol[i] - res[i]) * (sol[i] - res[i]);
            }
        }

        pub fn mse_bp(self: @This(), sol: []T) !void {
            for (0..self.s.len) |i| {
                sol[i] = 2 * (sol[i] - self.s[i]);
            }
        }

        pub fn fp(self: *@This(), res: []T, sol: []T, eval: bool) !void {
            try switch (self.type_) {
                0 => self.mse_fp(res, sol, eval),
                else => return NN_Error.ErrorUnionWronglySet,
            };
        }

        pub fn bp(self: *@This(), sol: []T) !void {
            try switch (self.type_) {
                0 => self.mse_bp(sol),
                else => return NN_Error.ErrorUnionWronglySet,
            };
        }
    };
}

pub fn AdamsOptimizer(comptime T: type) type {
    return struct {
        grad: []T,
        m: []T,
        v: []T,
        t: T,
        num_stored_grad: T,
        Allocator: std.mem.Allocator,

        var eps: f32 = 10e-8;
        var b1: f32 = 0.9;
        var b2: f32 = 0.999;

        pub fn init(dim: usize, Allocator: std.mem.Allocator) !AdamsOptimizer(T) {
            const t = 0;
            const num_stored_grad = 0;

            const grad = try Allocator.alloc(T, dim);
            const m = try Allocator.alloc(T, dim);
            const v = try Allocator.alloc(T, dim);

            @memset(grad, 0);
            @memset(m, 0);
            @memset(v, 0);

            return AdamsOptimizer(T){ .grad = grad, .m = m, .v = v, .t = t, .num_stored_grad = num_stored_grad, .Allocator = Allocator };
        }

        pub fn deinit(self: *@This()) void {
            self.Allocator.free(self.grad);
            self.Allocator.free(self.m);
            self.Allocator.free(self.v);
        }

        pub fn step(self: *@This(), lr: T, params: []T) !void {
            self.t += 1;

            if (self.num_stored_grad == 0) {
                return NN_Error.ErrorLogic;
            }

            for (0..self.grad.len) |i| {
                self.grad[i] /= self.num_stored_grad;
            }

            for (0..self.grad.len) |i| {
                self.m[i] = AdamsOptimizer(T).b1 * self.m[i] + (1 - AdamsOptimizer(T).b1) * self.grad[i];
                self.v[i] = AdamsOptimizer(T).b2 * self.v[i] + (1 - AdamsOptimizer(T).b2) * self.grad[i] * self.grad[i];

                const mhat = self.m[i] / (1 - std.math.pow(T, AdamsOptimizer(T).b1, self.t));
                const vhat = self.v[i] / (1 - std.math.pow(T, AdamsOptimizer(T).b2, self.t));

                params[i] += lr * mhat / (@sqrt(vhat) + AdamsOptimizer(T).eps);
            }

            @memset(self.grad, 0);
            self.num_stored_grad = 0;
        }
    };
}

pub fn Network(comptime T: type) type {
    return struct {
        layer: std.ArrayList(LayerType(T)),
        Allocator: std.mem.Allocator,
        eval: bool,

        pub fn add_LinearLayer(self: *@This(), indim: usize, outdim: usize, rnd: u64) !void {
            try self.layer.append(LayerType(T){ .linear = try LinearLayer(T).init_rand(
                indim,
                outdim,
                self.Allocator,
                rnd,
            ) });
        }

        pub fn add_ReLu(self: *@This(), dim: usize) !void {
            try self.layer.append(LayerType(T){ .activfunc = ActivationFunction(T){ .type_ = 0, .Allocator = self.Allocator, .s = try self.Allocator.alloc(T, dim) } });
        }

        pub fn add_MSE(self: *@This(), dim: usize) !void {
            try self.layer.append(LayerType(T){ .lossfunc = LossFunction(T){ .type_ = 0, .Allocator = self.Allocator, .s = try self.Allocator.alloc(T, dim) } });
        }

        pub fn fp(self: *@This(), input: []T, y: []T, res: []T) !void {
            var fp_v = try self.Allocator.alloc(T, input.len);
            @memcpy(fp_v, input);

            for (0..self.layer.items.len) |i| {
                fp_v = switch (self.layer.items[i]) {
                    .linear => blk: {
                        const result = try self.Allocator.alloc(T, self.layer.items[i].linear.outdim);
                        try self.layer.items[i].linear.fp(fp_v, result, self.eval);
                        self.Allocator.free(fp_v);
                        break :blk result;
                    },
                    .activfunc => blk: {
                        try self.layer.items[i].activfunc.fp(fp_v, self.eval);
                        break :blk fp_v;
                    },
                    .lossfunc => blk: {
                        try self.layer.items[i].lossfunc.fp(fp_v, y, self.eval);
                        break :blk fp_v;
                    },
                };
            }

            @memcpy(res, fp_v);
            self.Allocator.free(fp_v);
        }

        pub fn bp(self: *@This(), input: []T) !void {
            var bp_v = try self.Allocator.alloc(T, input.len);
            @memcpy(bp_v, input);

            const rev = self.layer.items.len - 1;

            for (0..self.layer.items.len) |i| {
                bp_v = switch (self.layer.items[rev - i]) {
                    .linear => blk: {
                        const result = try self.Allocator.alloc(T, self.layer.items[rev - i].linear.indim);
                        try self.layer.items[rev - i].linear.bp(bp_v, result);
                        self.Allocator.free(bp_v);
                        break :blk result;
                    },
                    .activfunc => blk: {
                        try self.layer.items[rev - i].activfunc.bp(bp_v);
                        break :blk bp_v;
                    },
                    .lossfunc => blk: {
                        try self.layer.items[rev - i].lossfunc.bp(bp_v);
                        break :blk bp_v;
                    },
                };
            }
        }

        pub fn step(self: *@This(), lr: T) !void {
            for (0..self.layer.items.len) |i| {
                switch (self.layer.items[i]) {
                    .linear => try self.layer.items[i].linear.step(lr),
                    .activfunc => {},
                    .lossfunc => {},
                }
            }
        }

        pub fn out_num(self: *@This()) !void {
            for (0..self.layer.items.len) |i| {
                switch (self.layer.items[i]) {
                    .linear => self.layer.items[i].linear.print(),
                    .activfunc => print("Activ\n", .{}),
                    .lossfunc => print("Loss\n", .{}),
                }
            }
            print("\n", .{});
        }
    };
}

pub fn parseFile(fileName: []const u8, alloc: std.mem.Allocator) !std.ArrayList([]u8) {
    var result = std.ArrayList([]u8).init(alloc);

    const file = try std.fs.cwd().openFile(fileName, .{});
    defer file.close();

    var parser = zcsv.allocs.column.init(alloc, file.reader(), .{});

    _ = parser.next();
    while (parser.next()) |row| {
        defer row.deinit();

        var cnt: usize = 0;
        var arr = try alloc.alloc(u8, 28 * 28 + 1);

        var fieldIter = row.iter();
        while (fieldIter.next()) |field| {
            arr[cnt] = try std.fmt.parseInt(u8, field.data(), 10);
            cnt += 1;
        }

        try result.append(arr);
    }

    return result;
}

pub fn overfit_linear_layer(T: type, gpa: std.mem.Allocator) !void {
    const num_batches = 200;
    const batchsize = 100;
    //const lr = 0.01;

    const inp1 = 784;
    const inp2 = 50;
    const out1 = 50;
    const out2 = 1;
    const train_data = try parseFile("src/mnist_test.csv", gpa);

    var net = Network(T){ .layer = std.ArrayList(LayerType(T)).init(gpa), .Allocator = gpa, .eval = false };
    try net.add_LinearLayer(inp1, out1, 4);
    try net.add_ReLu(inp2);
    try net.add_LinearLayer(inp2, out2, 5);
    try net.add_MSE(1);

    var rnd = std.rand.DefaultPrng.init(0);
    var rand = rnd.random();
    //var mse_x: f32 = 0;

    var y = try gpa.alloc(T, 1);
    var X = try gpa.alloc(T, inp1);
    defer gpa.free(X);
    defer gpa.free(y);
    const res = try gpa.alloc(T, y.len);

    for (0..batchsize * num_batches) |_| {
        const sample = rand.intRangeAtMost(usize, 0, 100); //train_data.items.len - 1);

        for (0..X.len - 1) |i| {
            X[i] = @as(T, @floatFromInt(train_data.items[sample][i + 1])) / 255;
        }

        y[0] = @floatFromInt(train_data.items[sample][0]);

        try net.fp(X, y, res);

        //const e = res[0];

        //mse_x += res[0];

        //try net.bp(y);

        //if (data % batchsize == 0 and data != 0) {
        //    print("Err: {}\n", .{mse_x / batchsize});
        //    mse_x = 0;
        //    try net.step(lr);
        //}

        //if (std.math.isNan(e) or std.math.isInf(e)) {
        //    print("break\n", .{});
        //    break;
        //}
    }

    //try net.out_num();
}

pub fn main() !void {
    print("compiles... \n", .{});

    var general_purpose_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_alloc.allocator();
    const T = f32;
    try overfit_linear_layer(T, gpa);

    print("done... \n", .{});
}
