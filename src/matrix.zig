const std = @import("std");
const print = std.debug.print;

const Matrix_Errors = error{
    MatrixLogicError,
};

var general_purpose_alloc = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = general_purpose_alloc.allocator();

pub fn Matrix(comptime T: type) type {
    return struct {
        xdim: usize,
        ydim: usize,
        transposed: bool,
        mat: []T,
        Allocator: std.mem.Allocator,

        pub fn init(xdim: usize, ydim: usize, mat: []T, Allocator: std.mem.Allocator) !Matrix(T) {
            const new_mat = try Allocator.alloc(T, mat.len);
            @memcpy(new_mat, mat);
            return Matrix(T){ .xdim = xdim, .ydim = ydim, .mat = new_mat, .Allocator = Allocator, .transposed = false };
        }

        pub fn deinit(self: @This()) void {
            self.Allocator.free(self.mat);
        }

        pub fn add(self: @This(), other: Matrix(T)) !void {
            if (other.xdim != self.xdim or other.ydim != self.ydim) {
                return Matrix_Errors.MatrixLogicError;
            }

            for (0..self.mat.len) |i| {
                self.mat[i] += other.mat[i];
            }
        }

        pub fn mult(self: *@This(), other: Matrix(T)) !void {
            if (self.xdim != other.ydim) {
                return Matrix_Errors.MatrixLogicError;
            }

            const res_mat = try self.Allocator.alloc(T, other.xdim * self.ydim);
            @memset(res_mat, 0);

            for (0..self.ydim) |y| {
                for (0..other.xdim) |x| {
                    for (0..self.xdim) |z| {
                        res_mat[x + y * other.xdim] += self.get(z, y) * other.get(x, z);
                    }
                }
            }

            self.xdim = other.xdim;
            self.Allocator.free(self.mat);
            self.mat = res_mat;
        }

        pub fn transpose(self: *@This()) void {
            _ = @constCast(self);
            const temp = self.xdim;
            self.xdim = self.ydim;
            self.ydim = temp;
            self.transposed = self.transposed == false;
        }

        pub inline fn get(self: @This(), x: usize, y: usize) T {
            if (self.transposed) {
                return self.mat[y + x * self.xdim];
            }
            return self.mat[x + y * self.xdim];
        }

        pub inline fn set(self: @This(), value: T, x: usize, y: usize) void {
            self.mat[x + y * self.xdim] = value;
        }

        pub fn print(self: @This()) void {
            std.debug.print("{}x{}\n", .{ self.xdim, self.ydim });
            for (0..self.ydim) |y| {
                for (0..self.xdim) |x| {
                    std.debug.print("{} ", .{self.get(x, y)});
                }
                std.debug.print("\n", .{});
            }
            std.debug.print("\n", .{});
        }

        pub fn copy(self: @This(), Allocator: std.mem.Allocator) !Matrix(T) {
            const new_mat = try Allocator.alloc(T, self.mat.len);
            @memcpy(new_mat, self.mat);
            return Matrix(T){ .xdim = self.xdim, .ydim = self.ydim, .mat = new_mat, .Allocator = Allocator, .transposed = false };
        }
    };
}

pub fn main() !void {
    print("compiles...\n", .{});

    var rnd = std.rand.DefaultPrng.init(0);

    const matrix_arr = try gpa.alloc(i32, 256 * 800);
    defer gpa.free(matrix_arr);

    const matrix_arr2 = try gpa.alloc(i32, 256);
    defer gpa.free(matrix_arr2);

    for (0..matrix_arr.len) |x| {
        matrix_arr[x] = @rem(rnd.random().int(i32), 100);
    }

    for (0..matrix_arr2.len) |x| {
        matrix_arr2[x] = 1;
    }

    for (0..1000) |_| {
        var t2 = try Matrix(i32).init(256, 800, matrix_arr, gpa);
        const t3 = try Matrix(i32).init(1, 256, matrix_arr2, gpa);
        try t2.mult(t3);
    }

    print("finished running...", .{});
}
