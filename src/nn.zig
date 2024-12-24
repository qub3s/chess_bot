const std = @import("std");
const zcsv = @import("zcsv");
const blas = @import("blas.zig");

const print = std.debug.print;

const NN_Error = error{
    ErrorDimensionsNotMatch,
};

const LayerType = union {
    linear: *LinearLayer,
    activfunc: *ActivationFunction,
    lossfunc: *LossFunction,
};

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

        eval: bool,
        input_activations: []T,
        grad_weight: []T,
        grad_bias: []T,

        // randomly initialize
        pub fn init_rand(indim: usize, outdim: usize, Allocator: std.mem.Allocator, rnd: u64) !LinearLayer(T) {
            // allocate memory
            const weight = try Allocator.alloc(T, indim * outdim);
            const bias = try Allocator.alloc(T, outdim);
            const bias_cpy = try Allocator.alloc(T, outdim);
            const input_activations = try Allocator.alloc(T, indim);
            const grad_weight = try Allocator.alloc(T, indim * outdim);
            const grad_bias = try Allocator.alloc(T, outdim);
            @memset(grad_weight, 0);
            @memset(grad_bias, 0);

            var rand = std.rand.DefaultPrng.init(rnd);

            for (0..weight.len) |i| {
                weight[i] = (rand.random().float(T) - 0.5) * 2 / @as(T, @floatFromInt(indim * outdim));
            }

            for (0..bias.len) |i| {
                bias[i] = (rand.random().float(T) - 0.5) * 2;
            }

            @memcpy(bias_cpy, bias);

            return LinearLayer(T){ .indim = indim, .outdim = outdim, .weight = weight, .bias = bias, .bias_cpy = bias_cpy, .input_activations = input_activations, .Allocator = Allocator, .grad_weight = grad_weight, .grad_bias = grad_bias, .eval = false };
        }

        pub fn deinit(self: @This()) void {
            self.Allocator.free(self.weight);
            self.Allocator.free(self.bias);
            self.Allocator.free(self.bias_cpy);
        }

        // foreward pass
        pub fn fp(self: *@This(), input: []T) ![]T {
            if (input.len != self.indim) {
                return NN_Error.ErrorDimensionsNotMatch;
            }

            if (!self.eval) {
                @memcpy(self.input_activations, input);
            }

            blas.gemv(T, self.outdim, self.indim, self.weight, false, input, self.bias_cpy, 1, 1);

            const result = try self.Allocator.alloc(T, self.outdim);
            @memcpy(result, self.bias_cpy);
            @memcpy(self.bias_cpy, self.bias);

            return result;
        }

        pub fn bp(self: *@This(), input: []T, result: []T) ![]T {
            // create bias
            for (0..self.grad_bias.len) |i| {
                self.grad_bias[i] += input[i];
            }

            // create weight matrix
            for (0..self.input_activations.len) |act| {
                for (0..input.len) |inp| {
                    //self.grad_weight[act * input.len + inp] += self.input_activations[act] * input[inp];
                    self.grad_weight[inp * self.input_activations.len + act] += self.input_activations[act] * input[inp];
                }
            }

            @memset(result, 0);
            blas.gemv(T, self.outdim, self.indim, self.weight, true, input, result, 1, 1);

            return result;
        }

        pub fn step(self: *@This(), lr: T, batchsize: T) void {
            for (0..self.weight.len) |w| {
                self.weight[w] += self.grad_weight[w] / batchsize * lr;
            }

            for (0..self.bias.len) |b| {
                self.bias[b] += self.grad_bias[b] / batchsize * lr;
            }

            //std.debug.print("{any}\n", .{self.grad_weight});

            @memset(self.grad_weight, 0);
            @memset(self.grad_bias, 0);
        }

        pub fn print(self: @This()) void {
            std.debug.print("Weight: {}x{}", .{ self.indim, self.outdim });
        }

        pub fn println(self: @This()) void {
            std.debug.print("Weight: {}x{}\n", .{ self.indim, self.outdim });
        }
    };
}

pub fn ActivationFunction(comptime T: type) type {
    return struct {
        type_: usize,

        pub fn relu_fp(input: []T) []T {
            for (0..input.len) |i| {
                input[i] = @max(input[i], 0);
            }
            return input;
        }

        pub fn relu_bp(input: []T) []T {
            for (0..input.len) |i| {
                if (input[i] > 0) {
                    input[i] *= 1;
                } else {
                    input[i] = 0;
                }
            }
            return input;
        }

        pub fn fp(self: *@This(), input: []T) []T {
            switch (self.type_) {
                0 => return self.relu_fp(input),
                else => @compileError("This value is wrongly set !!!"),
            }
        }

        pub fn bp(self: *@This(), input: []T) []T {
            switch (self.type_) {
                0 => return self.relu_bp(input),
                else => @compileError("This value is wrongly set !!!"),
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
            if (eval) {
                self.Allocator.free(self.s);
                self.s = try self.Allocator.alloc(T, res.len);
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
            switch (self.type_) {
                0 => self.mse_fp(res, sol, eval),
                else => @compileError("This value is wrongly set !!!"),
            }
        }

        pub fn bp(self: *@This(), res: []T, sol: []T, eval: bool) !void {
            switch (self.type_) {
                0 => self.mse_bp(res, sol, eval),
                else => @compileError("This value is wrongly set !!!"),
            }
        }
    };
}

pub fn Network(comptime T: type) type {
    return struct {
        layer: std.ArrayList(LayerType),
        Allocator: std.mem.Allocator,

        pub fn add_LinearLayer(self: @This(), indim: usize, outdim: usize, rnd: u64) !LinearLayer(T) {
            self.layer.append(try LinearLayer(T).init_rand(indim, outdim, self.Allocator, rnd));
        }

        pub fn add_mse(self: @This()) void {
            self.layer.append(try LossFunction(T).mse_init(self.Allocator));
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

pub fn overfit_linear_layer(gpa: std.mem.Allocator) !void {
    const num_batches = 10000;
    const batchsize = 100;
    const lr = 0.001;

    const T: type = f32;
    const inp1 = 784;
    const out1 = 1;
    const train_data = try parseFile("src/mnist_test.csv", gpa);

    var l1 = try LinearLayer(T).init_rand(inp1, out1, gpa, 22);
    //const random = try gpa.alloc(T, inp1);
    //var mse = MSE(T){ .eval = false, .s = random, .Allocator = gpa };

    var rnd = std.rand.DefaultPrng.init(0);
    var rand = rnd.random();
    var mse_x: f32 = 0;

    for (0..batchsize * num_batches) |data| {
        const sample = rand.intRangeAtMost(usize, 0, 10); //train_data.items.len - 1);

        var y = try gpa.alloc(T, 1);
        var X = try gpa.alloc(T, inp1);
        defer gpa.free(X);
        defer gpa.free(y);

        for (0..X.len - 1) |i| {
            X[i] = @floatFromInt(train_data.items[sample][i + 1] / 255);
        }

        y[0] = @floatFromInt(train_data.items[sample][0]);
        //if (train_data.items[sample][0] > 5) {
        //    y[0] = 0;
        //} else {
        //    y[0] = 1;
        //}

        const y1 = try l1.fp(X);
        defer gpa.free(y1);

        y1[0] = y1[0];

        //try mse.fp(y1, y);

        const e = y1[0];
        if (std.math.isNan(e) or std.math.isInf(e)) {
            print("break", .{});
            break;
        }

        //mse_x += y1[0];

        //print("MSE: {any}\n", .{y1});
        //try mse.bp(y);

        X = try l1.bp(y, X);

        if (data % batchsize == 0 and data != 0) {
            print("{}\n", .{mse_x / batchsize});
            mse_x = 0;
            l1.step(lr, batchsize);
        }
    }
}

pub fn main() !void {
    print("compiles... \n", .{});

    var general_purpose_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_alloc.allocator();
    //try overfit_linear_layer(gpa);

    var net = Network(f32){ .layer = std.ArrayList(LayerType).init(gpa), .Allocator = gpa };
    net.add_LinearLayer(10 * 10, 1, 4);

    print("done... \n", .{});
}
