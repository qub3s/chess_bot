const std = @import("std");
const zcsv = @import("zcsv");
const blas = @import("blas.zig");

const tpool = @import("thread_pool.zig");
const Thread_ArrayList = @import("Thread_ArrayList.zig");

const print = std.debug.print;

const NN_Error = error{
    ErrorDimensionsNotMatch,
    ErrorUnionWronglySet,
    ErrorLogic,
    NetworkParametersNotConsistent,
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

        pub fn copy(self: *@This()) !LinearLayer(T) {
            const weight = try self.Allocator.alloc(T, self.indim * self.outdim);
            @memcpy(weight, self.weight);

            const bias = try self.Allocator.alloc(T, self.outdim);
            @memcpy(bias, self.bias);

            const bias_cpy = try self.Allocator.alloc(T, self.outdim);
            @memcpy(bias_cpy, self.bias_cpy);

            const input_activations = try self.Allocator.alloc(T, self.indim);
            @memcpy(input_activations, self.input_activations);

            const grad_weight = try self.grad_weight.copy();
            const grad_bias = try self.grad_bias.copy();

            return LinearLayer(T){ .indim = self.indim, .outdim = self.outdim, .weight = weight, .bias = bias, .bias_cpy = bias_cpy, .input_activations = input_activations, .grad_weight = grad_weight, .grad_bias = grad_bias, .Allocator = self.Allocator };
        }

        pub fn free(self: *@This()) void {
            self.Allocator.free(self.weight);
            self.Allocator.free(self.bias);
            self.Allocator.free(self.bias_cpy);
            self.Allocator.free(self.input_activations);

            self.grad_weight.free();
            self.grad_bias.free();
        }

        // foreward pass
        pub fn fp(self: *@This(), input: []T, result: []T, eval: bool) !void {
            if (input.len != self.indim) {
                return NN_Error.ErrorDimensionsNotMatch;
            }

            if (!eval) {
                @memcpy(self.input_activations, input);
            }

            blas.mvmult(self.outdim, self.indim, false, self.weight, input, self.bias, self.bias_cpy);
            //blas.gemv(T, self.outdim, self.indim, self.weight, false, input, self.bias_cpy, 1, 1);

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

            for (0..input.len) |inp| {
                for (0..self.input_activations.len) |act| {
                    sweight[inp * self.input_activations.len + act] += self.input_activations[act] * input[inp];
                }
            }

            @memset(result, 0);

            // das hier funktioniert noch nicht
            //blas.mvmult(self.outdim, self.indim, true, self.weight, input, result, result);
            blas.gemv(T, self.outdim, self.indim, self.weight, true, input, result, 1, 1);
        }

        pub fn step(self: *@This(), lr: T) !void {
            try self.grad_bias.step(lr, self.bias);
            try self.grad_weight.step(lr, self.weight);
        }
    };
}

pub fn ActivationFunction(comptime T: type) type {
    return struct {
        type_: usize,
        s: []T,
        Allocator: std.mem.Allocator,

        pub fn copy(self: *@This()) !ActivationFunction(T) {
            const s = try self.Allocator.alloc(T, self.s.len);
            @memcpy(s, self.s);

            return ActivationFunction(T){ .type_ = self.type_, .s = s, .Allocator = self.Allocator };
        }

        pub fn free(self: *@This()) void {
            self.Allocator.free(self.s);
        }

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

            return LossFunction(T){ .type_ = 0, .s = s, .Allocator = Allocator };
        }

        pub fn copy(self: *@This()) !LossFunction(T) {
            const s = try self.Allocator.alloc(T, self.s.len);
            @memcpy(s, self.s);

            return LossFunction(T){ .type_ = self.type_, .s = s, .Allocator = self.Allocator };
        }

        pub fn free(self: *@This()) void {
            self.Allocator.free(self.s);
        }

        pub fn mse_fp(self: *@This(), res: []T, sol: []T, err: []T, eval: bool) !void {
            if (!eval) {
                @memcpy(self.s, res);
            }

            for (0..res.len) |i| {
                err[i] = (sol[i] - res[i]) * (sol[i] - res[i]);
            }
        }

        pub fn mse_bp(self: @This(), sol: []T) !void {
            for (0..self.s.len) |i| {
                sol[i] = 2 * (sol[i] - self.s[i]);
            }
        }

        pub fn fp(self: *@This(), res: []T, sol: []T, err: []T, eval: bool) !void {
            try switch (self.type_) {
                0 => self.mse_fp(res, sol, err, eval),
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

        pub fn free(self: *@This()) void {
            self.Allocator.free(self.grad);
            self.Allocator.free(self.m);
            self.Allocator.free(self.v);
        }

        pub fn copy(self: *@This()) !AdamsOptimizer(T) {
            const grad = try self.Allocator.alloc(T, self.grad.len);
            @memcpy(grad, self.grad);
            const m = try self.Allocator.alloc(T, self.m.len);
            @memcpy(m, self.m);
            const v = try self.Allocator.alloc(T, self.v.len);
            @memcpy(v, self.v);

            return AdamsOptimizer(T){ .grad = grad, .m = m, .v = v, .t = self.t, .num_stored_grad = self.num_stored_grad, .Allocator = self.Allocator };
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
        // these variables prevent additional allocations
        max_layer_size: u32,
        allocation_field: []T,

        pub fn init(allocator: std.mem.Allocator, eval: bool) Network(T) {
            return Network(T){ .layer = std.ArrayList(LayerType(T)).init(allocator), .Allocator = allocator, .eval = eval, .max_layer_size = 0, .allocation_field = undefined };
        }

        pub fn copy(self: *@This(), net: *Network(T)) !void {
            var layer = std.ArrayList(LayerType(T)).init(self.Allocator);
            const allocation_field = try self.Allocator.alloc(T, self.allocation_field.len);

            for (0..self.layer.items.len) |i| {
                switch (self.layer.items[i]) {
                    .linear => blk: {
                        const append = try self.layer.items[i].linear.copy();
                        try layer.append(LayerType(T){ .linear = append });
                        break :blk;
                    },
                    .activfunc => blk: {
                        const append = try self.layer.items[i].activfunc.copy();
                        try layer.append(LayerType(T){ .activfunc = append });
                        break :blk;
                    },
                    .lossfunc => blk: {
                        const append = try self.layer.items[i].lossfunc.copy();
                        try layer.append(LayerType(T){ .lossfunc = append });
                        break :blk;
                    },
                }
            }

            net.layer = layer;
            net.Allocator = self.Allocator;
            net.eval = self.eval;
            net.max_layer_size = self.max_layer_size;
            net.allocation_field = allocation_field;
            return;
        }

        pub fn free(self: *@This()) void {
            for (0..self.layer.items.len) |i| {
                switch (self.layer.items[i]) {
                    .linear => self.layer.items[i].linear.free(),
                    .lossfunc => self.layer.items[i].lossfunc.free(),
                    .activfunc => self.layer.items[i].activfunc.free(),
                }
            }
            defer self.layer.deinit();
            self.Allocator.free(self.allocation_field);
        }

        pub fn add_LinearLayer(self: *@This(), indim: usize, outdim: usize, rnd: u64) !void {
            try self.layer.append(LayerType(T){ .linear = try LinearLayer(T).init_rand(
                indim,
                outdim,
                self.Allocator,
                rnd,
            ) });

            if (self.max_layer_size < indim) {
                self.max_layer_size = @intCast(indim);
                self.allocation_field = try self.Allocator.alloc(T, self.max_layer_size);
            }

            if (self.max_layer_size < outdim) {
                self.max_layer_size = @intCast(outdim);
                self.allocation_field = try self.Allocator.alloc(T, self.max_layer_size);
            }
        }

        pub fn add_ReLU(self: *@This(), dim: usize) !void {
            try self.layer.append(LayerType(T){ .activfunc = ActivationFunction(T){ .type_ = 0, .Allocator = self.Allocator, .s = try self.Allocator.alloc(T, dim) } });
        }

        pub fn add_MSE(self: *@This(), dim: usize) !void {
            try self.layer.append(LayerType(T){ .lossfunc = LossFunction(T){ .type_ = 0, .Allocator = self.Allocator, .s = try self.Allocator.alloc(T, dim) } });
        }

        pub fn fp(self: *@This(), input: []T, y: []T, res: []T, err: []T) !void {
            var LayerInput = input;

            for (0..self.layer.items.len) |i| {
                LayerInput = switch (self.layer.items[i]) {
                    .linear => blk: {
                        try self.layer.items[i].linear.fp(LayerInput, self.allocation_field[0..self.layer.items[i].linear.outdim], self.eval);
                        //print("{any}\n\n\n", .{self.allocation_field[0..self.layer.items[i].linear.outdim]});
                        break :blk self.allocation_field[0..self.layer.items[i].linear.outdim];
                    },
                    .activfunc => blk: {
                        try self.layer.items[i].activfunc.fp(LayerInput, self.eval);
                        break :blk LayerInput;
                    },
                    .lossfunc => blk: {
                        try self.layer.items[i].lossfunc.fp(LayerInput, y, err, self.eval);
                        break :blk LayerInput;
                    },
                };
            }

            @memcpy(res, LayerInput);
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

        // File Layout:
        // - 1 byte (u8) for how many bytes per weight (f32 -> 4, f64 -> 8)
        // - 4 bytes (u32) (number of layers)
        // for every layer 8 bytes (u64) that show the number of bytes for the weights, followed by 8 bytes (u64) that show the nunber of bytes for the bias
        // then all the data
        pub fn save(self: @This(), fileName: []const u8) !void {
            const size_T: u8 = @sizeOf(T);
            var num_linear_layer: u32 = 0;
            var layerweights = std.ArrayList(u64).init(self.Allocator);
            var layerbias = std.ArrayList(u64).init(self.Allocator);

            for (0..self.layer.items.len) |i| {
                switch (self.layer.items[i]) {
                    .linear => blk: {
                        num_linear_layer += 1;
                        try layerweights.append(self.layer.items[i].linear.outdim * self.layer.items[i].linear.indim);
                        try layerbias.append(self.layer.items[i].linear.outdim);
                        break :blk;
                    },
                    .activfunc => {},
                    .lossfunc => {},
                }
            }

            const file = try std.fs.cwd().createFile(fileName, .{ .read = false });
            const writer = file.writer();

            try writer.writeInt(u8, size_T, std.builtin.Endian.little);
            try writer.writeInt(u32, num_linear_layer, std.builtin.Endian.little);

            for (0..layerweights.items.len) |i| {
                try writer.writeInt(u64, layerweights.items[i], std.builtin.Endian.little);
                try writer.writeInt(u64, layerbias.items[i], std.builtin.Endian.little);
            }

            for (0..self.layer.items.len) |i| {
                switch (self.layer.items[i]) {
                    .linear => blk: {
                        const weights = std.mem.bytesAsSlice(u8, self.layer.items[i].linear.weight);
                        const bias = std.mem.bytesAsSlice(u8, self.layer.items[i].linear.bias);

                        try writer.writeAll(weights);
                        try writer.writeAll(bias);
                        break :blk;
                    },
                    .activfunc => {},
                    .lossfunc => {},
                }
            }
        }

        pub fn load(self: @This(), fileName: []const u8) !void {
            const file = try std.fs.cwd().openFile(fileName, .{ .mode = .read_only });
            const reader = file.reader();

            if (try reader.readInt(u8, std.builtin.Endian.little) != @sizeOf(T)) {
                return NN_Error.NetworkParametersNotConsistent;
            }

            const number_of_layers = try reader.readInt(u32, std.builtin.Endian.little);

            var num_linear_layer: u32 = 0;
            var layerweights = std.ArrayList(u64).init(self.Allocator);
            var layerbias = std.ArrayList(u64).init(self.Allocator);

            for (0..self.layer.items.len) |i| {
                switch (self.layer.items[i]) {
                    .linear => blk: {
                        num_linear_layer += 1;
                        try layerweights.append(self.layer.items[i].linear.outdim * self.layer.items[i].linear.indim);
                        try layerbias.append(self.layer.items[i].linear.outdim);
                        break :blk;
                    },
                    .activfunc => {},
                    .lossfunc => {},
                }
            }

            if (num_linear_layer != number_of_layers) {
                return NN_Error.NetworkParametersNotConsistent;
            }

            for (0..layerweights.items.len) |i| {
                const lw = try reader.readInt(u64, std.builtin.Endian.little);
                const lb = try reader.readInt(u64, std.builtin.Endian.little);

                if (layerweights.items[i] != lw or layerbias.items[i] != lb) {
                    return NN_Error.NetworkParametersNotConsistent;
                }
            }

            for (0..self.layer.items.len) |i| {
                switch (self.layer.items[i]) {
                    .linear => blk: {
                        const weights = std.mem.bytesAsSlice(u8, self.layer.items[i].linear.weight);
                        const bias = std.mem.bytesAsSlice(u8, self.layer.items[i].linear.bias);

                        const lenw = try reader.readAll(weights);
                        const lenb = try reader.readAll(bias);

                        if (lenw != self.layer.items[i].linear.weight.len or lenb != self.layer.items[i].linear.bias.len) {
                            return NN_Error.NetworkParametersNotConsistent;
                        }
                        break :blk;
                    },
                    .activfunc => {},
                    .lossfunc => {},
                }
            }
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
    const num_batches = 100;
    const batchsize = 100;
    const lr = 0.01;

    const inp1 = 784;
    const inp2 = 80;
    const out1 = 80;
    const out2 = 1;
    const train_data = try parseFile("src/mnist_test.csv", gpa);

    var net = Network(T).init(gpa, false);
    try net.add_LinearLayer(inp1, out1, 42);
    //try net.add_ReLU(inp2);
    try net.add_LinearLayer(inp2, out2, 42);
    try net.add_MSE(1);

    var mse_x: f32 = 0;
    var rnd = std.rand.DefaultPrng.init(0);
    var rand = rnd.random();

    var y = try gpa.alloc(T, 1);
    var X = try gpa.alloc(T, inp1);
    var err = try gpa.alloc(T, 1);
    err[0] = 0;

    defer gpa.free(X);
    defer gpa.free(y);
    defer gpa.free(err);

    const res = try gpa.alloc(T, y.len);
    defer gpa.free(res);

    for (0..batchsize * num_batches) |data| {
        const sample = rand.intRangeAtMost(usize, 0, 100); //train_data.items.len - 1);

        for (0..X.len - 1) |i| {
            X[i] = @as(T, @floatFromInt(train_data.items[sample][i + 1])) / 255;
        }

        y[0] = @floatFromInt(train_data.items[sample][0]);

        try net.fp(X, y, res, err);

        const e = res[0];

        mse_x += err[0];

        try net.bp(y);

        if (data % batchsize == 0 and data != 0) {
            print("Err: {}\n", .{mse_x / batchsize});
            mse_x = 0;
            try net.step(lr);
        }

        if (std.math.isNan(e) or std.math.isInf(e)) {
            print("break\n", .{});
            break;
        }
    }
}

fn bench_fn(T: type, model: *Network(T), network_stack: *Thread_ArrayList.Thread_ArrayList(*Network(T))) void {
    var X = std.mem.zeroes([768]T);
    var y = std.mem.zeroes([1]T);
    var res = std.mem.zeroes([1]T);
    var err = std.mem.zeroes([1]T);

    for (0..10000) |_| {
        model.fp(&X, &y, &res, &err) catch return;
    }

    network_stack.append(model) catch return;
}

fn sleep() void {
    std.time.sleep(10000);
    //1 - 20
    //2 - 10
    //3 - 7
    //4 - 5
    //5 - 4
    //6 - 4
    //7 - 3
}

pub fn benchmarking(gpa: std.mem.Allocator) !void {
    const threads = 6;
    const T = f32;

    const seed = 42;
    var model = Network(T).init(gpa, true);
    try model.add_LinearLayer(768, 256, seed);
    try model.add_ReLU(256);
    try model.add_LinearLayer(256, 80, seed);
    try model.add_ReLU(80);
    try model.add_LinearLayer(80, 1, seed);

    var p: tpool.Pool = undefined;
    p.init(gpa, threads);

    var network_stack = Thread_ArrayList.Thread_ArrayList(*Network(T)).init(gpa);

    for (0..threads + 1) |_| {
        const cpy: *Network(f32) = gpa.create(Network(f32)) catch return;
        try model.copy(cpy);
        try network_stack.append(cpy);
    }

    print("start\n", .{});
    const start = std.time.microTimestamp();

    for (0..240) |i| {
        print("{}\n", .{i});
        const mod = try network_stack.pop();
        try p.spawn(bench_fn, .{ T, mod, &network_stack });
        //try p.spawn(sleep, .{});
    }
    p.finish();
    const end = std.time.microTimestamp();
    print("{}\n", .{(end - start)});
}

pub fn main() !void {
    print("compiles... \n", .{});

    var general_purpose_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_alloc.allocator();
    const T = f32;

    try overfit_linear_layer(T, gpa);

    try benchmarking(gpa);

    const seed = 42;
    var model = Network(T).init(gpa, true);
    try model.add_LinearLayer(768, 8, seed);
    try model.add_LinearLayer(8, 8, seed);
    try model.add_LinearLayer(8, 1, seed);

    const append: *Network(T) = try gpa.create(Network(T));
    try model.copy(append);

    var X = std.mem.zeroes([768]T);
    var y = std.mem.zeroes([1]T);
    var res = std.mem.zeroes([1]T);
    var err = std.mem.zeroes([1]T);

    const repeat = 1;

    for (0..repeat) |_| {
        model.fp(&X, &y, &res, &err) catch return;
        print("{any}\n", .{res});
    }

    print("\n\n\n", .{});

    for (0..repeat) |_| {
        append.fp(&X, &y, &res, &err) catch return;
        print("{any}\n", .{res});
    }

    //try benchmarking(T, gpa, 100000);

    //try overfit_linear_layer(T, gpa);

    //print("done... \n", .{});
}
