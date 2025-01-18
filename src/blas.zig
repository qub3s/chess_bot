const std = @import("std");
const blas = @cImport(@cInclude("flexiblas/cblas.h"));
const mvmultc = @cImport(@cInclude("vm_mul.h"));

const print = std.debug.print;

var general_purpose_alloc = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = general_purpose_alloc.allocator();

// generalised matrix vector
// A is matrix, V, Y are Vectors
// alpha and beta are scalars
// Y = aAV + bY
// Stride is set to 1 see function call
pub fn gemv(T: type, A_rows: usize, A_cols: usize, A: []T, trans_a: bool, V: []T, Y: []T, alpha: T, beta: T) void {
    const transpose_a = if (trans_a) blas.CblasTrans else blas.CblasNoTrans;

    switch (T) {
        f32 => blas.cblas_sgemv(blas.CblasColMajor, @intCast(transpose_a), @intCast(A_rows), @intCast(A_cols), alpha, A.ptr, @intCast(A_rows), V.ptr, 1, beta, Y.ptr, 1),
        f64 => blas.cblas_dgemv(blas.CblasColMajor, @intCast(transpose_a), @intCast(A_rows), @intCast(A_cols), alpha, A.ptr, @intCast(A_rows), V.ptr, 1, beta, Y.ptr, 1),
        else => @compileError("Types outside of f32 and f64 are not supported"),
    }
}

// res = mat*x + b
pub fn mvmult(rows: usize, cols: usize, mat: []f32, x: []f32, b: []f32, res: []f32) void {
    if (cols % 8 == 0 or rows % 8 == 0) {
        mvmultc.naive_algo(@intCast(cols), @intCast(rows), mat.ptr, b.ptr, x.ptr, res.ptr);
    } else {
        mvmultc.mat_vec_AVX2(@intCast(cols), @intCast(rows), mat.ptr, b.ptr, x.ptr, res.ptr);
    }
}

pub fn main() !void {
    print("comiles...\n", .{});
    var rnd = std.rand.DefaultPrng.init(0);

    const row = 800;
    const col = 250;

    const A = try gpa.alloc(f32, row * col);
    const V = try gpa.alloc(f32, row);
    const Y = try gpa.alloc(f32, row);

    for (0..A.len) |x| {
        A[x] = @rem(rnd.random().float(f32), 100);
    }

    for (0..V.len) |x| {
        V[x] = @rem(rnd.random().float(f32), 100);
    }

    for (0..Y.len) |x| {
        Y[x] = @rem(rnd.random().float(f32), 100);
    }

    for (0..1000000) |_| {
        gemv(f32, row, col, A, false, V, Y, 1, 1);
    }

    print("Check if imported: {}\n", .{blas.CBLAS_LAYOUT});
}
