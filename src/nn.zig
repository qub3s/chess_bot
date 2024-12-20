const std = @import("std");
const blas = @import("blas.zig");

const print = std.debug.print;

const NN_Error = error{
    ErrorDimensionsNotMatch,
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
        //num_grad: usize,

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
                weight[i] = rand.random().float(T) - 0.5;
            }
            for (0..bias.len) |i| {
                bias[i] = rand.random().float(T) - 0.5;
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
            for (0..input.len) |inp| {
                for (0..self.input_activations.len) |act| {
                    self.grad_weight[inp * self.input_activations.len + act] += self.input_activations[act] * input[inp];
                }
            }

            // calculate the next layer error
            @memset(result, 0);
            blas.gemv(T, self.outdim, self.indim, self.weight, true, input, result, 1, 1);

            return result;
        }

        // divide by number of rounds not implemented
        pub fn step(self: *@This(), lr: T, batchsize: T) void {
            for (0..self.weight.len) |w| {
                self.weight[w] += self.grad_weight[w] / batchsize * lr;
            }

            for (0..self.bias.len) |b| {
                self.bias[b] += self.grad_bias[b] * lr;
            }

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

pub fn MSE(comptime T: type) type {
    return struct {
        eval: bool,
        s: []T,
        Allocator: std.mem.Allocator,

        pub fn fp(self: *@This(), res: []T, sol: []T) !void {
            if (!self.eval) {
                self.Allocator.free(self.s);
                self.s = try self.Allocator.alloc(T, res.len);
                @memcpy(self.s, res);
            }

            for (0..res.len) |i| {
                res[i] = (sol[i] - res[i]) * (sol[i] - res[i]);
            }
        }

        pub fn bp(self: @This(), sol: []T) !void {
            for (0..self.s.len) |i| {
                sol[i] = 2 * (sol[i] - self.s[i]);
            }
        }
    };
}

pub fn relu_fp(comptime T: type, input: []T) []T {
    for (0..input.len) |i| {
        input[i] = @max(input[i], 0);
    }
    return input;
}

pub fn relu_bp(comptime T: type, input: []T) []T {
    for (0..input.len) |i| {
        if (input[i] > 0) {
            input[i] *= 1;
        } else {
            input[i] *= 0;
        }
    }
    return input;
}

pub fn main() !void {
    print("compiles... \n", .{});

    var general_purpose_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_alloc.allocator();

    const T: type = f32;
    const inp1 = 5;
    const out1 = 1;

    // init layers
    var l1 = try LinearLayer(T).init_rand(inp1, out1, gpa, 22);
    const random = try gpa.alloc(T, inp1);
    var mse = MSE(T){ .eval = false, .s = random, .Allocator = gpa };

    //var rand = std.rand.DefaultPrng.init(0);

    for (0..500) |data| {
        var y = try gpa.alloc(T, out1);
        var X = try gpa.alloc(T, inp1);
        defer gpa.free(X);
        defer gpa.free(y);

        if (data % 2 == 0) {
            y[0] = 0;

            for (0..inp1) |i| {
                X[i] = 0; //rand.random().float(f32) * 0.1;
            }
        } else {
            y[0] = 1;

            for (0..inp1) |i| {
                X[i] = 1; //rand.random().float(f32) * 10;
            }
        }

        const y1 = try l1.fp(X);
        defer gpa.free(y1);

        try mse.fp(y1, y);

        try mse.bp(y);

        X = try l1.bp(y, X);

        print("{}\n", .{y1[0]});
        if (data % 4 == 0) {
            l1.step(0.01, 10);
        }
    }
    print("done... \n", .{});
}
