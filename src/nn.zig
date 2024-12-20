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
        store_result: []T,
        //grad_weight: []T,
        //grad_bias: []T,

        // randomly initialize
        pub fn init_rand(indim: usize, outdim: usize, Allocator: std.mem.Allocator, rnd: u64) !LinearLayer(T) {
            const weight = try Allocator.alloc(T, indim * outdim);
            const bias = try Allocator.alloc(T, outdim);
            const bias_cpy = try Allocator.alloc(T, outdim);

            const store_result = try Allocator.alloc(T, outdim);

            var rand = std.rand.DefaultPrng.init(rnd);

            for (0..weight.len) |i| {
                weight[i] = rand.random().float(T) - 0.5;
            }
            for (0..bias.len) |i| {
                bias[i] = rand.random().float(T) - 0.5;
            }

            @memcpy(bias_cpy, bias);

            return LinearLayer(T){ .indim = indim, .outdim = outdim, .weight = weight, .bias = bias, .bias_cpy = bias_cpy, .Allocator = Allocator, .store_result = store_result, .eval = true };
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

            blas.gemv(T, self.outdim, self.indim, self.weight, false, input, self.bias_cpy, 1, 1);

            const result = try self.Allocator.alloc(T, self.outdim);
            @memcpy(result, self.bias_cpy);
            @memcpy(self.bias_cpy, self.bias);

            if (!self.eval) {
                self.Allocator.free(self.store_result);
                self.store_result = try self.Allocator.alloc(T, self.bias.len);
                @memcpy(self.store_result, result);
            }

            return result;
        }

        pub fn bp(self: @This(), input: []T, Allocator: std.mem.Allocator) ![]T {
            if (input.len != self.indim) {
                return NN_Error.ErrorDimensionsNotMatch;
            }

            blas.gemv(T, self.outdim, self.indim, self.weight, true, input, self.bias_cpy, 1, 1);

            const result = try Allocator.alloc(T, self.outdim);
            @memcpy(result, self.bias_cpy);
            @memcpy(self.bias_cpy, self.bias);

            return result;
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

        pub fn fp(self: *@This(), res: []T, sol: []T) ![]T {
            if (!self.eval) {
                self.Allocator.free(self.s);
                self.s = try self.Allocator.alloc(T, res.len);
                print("{}\n", .{self.s.len});
                @memcpy(self.s, res);
            }

            for (0..res.len) |i| {
                res[i] = (res[i] - sol[i]) * (res[i] - sol[i]);
            }

            return res;
        }

        pub fn bp(self: @This(), sol: []T) ![]T {
            for (0..self.s.len) |i| {
                sol[i] = 2 * (self.s[i] - sol[i]);
            }
            return sol;
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
            input[i] = 1;
        } else {
            input[i] = 0;
        }
    }
    return input;
}

pub fn main() !void {
    print("compiles... \n", .{});

    var general_purpose_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_alloc.allocator();

    const T: type = f32;
    const inp1 = 15;
    const out1 = 5;

    const inp2 = 5;
    const out2 = 1;

    // init X
    var y = try gpa.alloc(T, out2);
    y[0] = 3;

    var X = try gpa.alloc(T, inp1);
    defer gpa.free(X);
    for (0..inp1) |i| {
        X[i] = @floatFromInt(i);
    }

    const random = try gpa.alloc(T, inp1);

    // init layers
    var l1 = try LinearLayer(T).init_rand(inp1, out1, gpa, 42);
    var l2 = try LinearLayer(T).init_rand(inp2, out2, gpa, 42);
    var mse = MSE(T){ .eval = false, .s = random, .Allocator = gpa };

    var y1 = try l1.fp(X);
    defer gpa.free(y1);
    y1 = relu_fp(T, y1);

    var y2 = try l2.fp(y1);
    defer gpa.free(y2);

    y2 = try mse.fp(y2, y);

    for (0..y2.len) |i| {
        print("{}\n", .{y2[i]});
    }

    y2 = try mse.bp(y);

    for (0..y2.len) |i| {
        print("{}\n", .{y2[i]});
    }

    print("done... \n", .{});
}
