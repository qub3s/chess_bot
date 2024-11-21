const std = @import("std");
const print = std.debug.print;

fn vector_d(comptime T: type) type {
    return struct {
        const Self = @This();
        const type_ = T;
        alloc_size: usize,
        size: usize,
        scaling_factor: f32,
        arr: []T,
        allocator: std.mem.Allocator,
        auto_resize: bool,

        pub fn init(allocator: std.mem.Allocator, alloc_size: usize) !Self {
            const arr = try allocator.alloc(T, alloc_size);
            return Self{ .alloc_size = alloc_size, .size = 0, .scaling_factor = 2.0, .arr = arr, .allocator = allocator, .auto_resize = true };
        }

        pub fn get() void {}
        pub fn set() void {}

        // increases / decreases size of array
        pub fn append() void {}
        pub fn push() void {}

        // increases / decreases size of array
        pub fn remove_back() void {}
        pub fn pop() void {}

        // might be runtime intensive for large arrays
        pub fn insert_at() void {}
        // might be runtime intensive for large arrays
        pub fn remove_at() void {}

        // resizes the array
        pub fn resize() void {}

        // sets vector content to array
        pub fn set_array() void {}
        // appends array to vector
        pub fn append_array() void {}
    };
}

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();

    const d = try vector_d(f32).init(gpa, 1000);

    print("{}\n", .{d.size});
    print("{}\n", .{d.alloc_size});
}
