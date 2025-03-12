const std = @import("std");
const logic = @import("logic.zig");

pub const static_analysis = struct {
    piece_square_tables: [768]f32,
    gradient: [768]f32,
    gradient_values: u32,
    gradient_mutex: std.Thread.Mutex = .{},
    piece_values: [6]f32,

    pub fn init() static_analysis {
        const piece_square_tables = std.mem.zeroes([768]f32);
        const gradient = std.mem.zeroes([768]f32);
        const piece_values = .{ 100000, 10, 5.25, 3.5, 3.5, 1 };

        return static_analysis{ .piece_square_tables = piece_square_tables, .gradient = gradient, .gradient_values = 0, .piece_values = piece_values };
    }

    pub fn step(self: *static_analysis) void {
        self.gradient_mutex.lock();

        for (0..self.piece_square_tables.len) |i| {
            self.piece_square_tables[i] = self.gradient[i] / @as(f32, @floatFromInt(self.gradient_values));
        }
        self.gradient_values = 0;

        self.gradient_mutex.unlock();
    }

    pub fn copy(self: *static_analysis) static_analysis {
        self.gradient_mutex.lock();
        var piece_square_tables = std.mem.zeroes([768]f32);
        var gradient = std.mem.zeroes([768]f32);

        @memcpy(&piece_square_tables, &self.piece_square_tables);
        @memcpy(&gradient, &self.gradient);

        self.gradient_mutex.unlock();

        return static_analysis{ .piece_square_tables = piece_square_tables, .gradient = gradient, .gradient_values = self.gradient_values };
    }

    pub fn add(self: *static_analysis, adding: static_analysis) void {
        self.gradient_mutex.lock();

        for (0..self.piece_square_tables.len) |i| {
            self.gradient[i] += adding.piece_square_tables[i];
        }
        self.gradient_values += 1;

        self.gradient_mutex.unlock();
    }

    pub fn mutate(self: *static_analysis, strength: f32) void {
        var rnd = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
        var rand = rnd.random();

        for (0..self.piece_square_tables.len) |i| {
            self.piece_square_tables[i] += (rand.float(f32) - 1) * 2 * strength;
        }
    }

    pub fn eval_pv(self: *static_analysis, board: [64]i32) f32 {
        var val: f32 = 0;
        for (0..self.piece_values.len) |i| {
            for (0..64) |j| {
                if (board[j] == i + 1) {
                    val += self.piece_values[i];
                }

                if (board[j] == i + 7) {
                    val -= self.piece_values[i];
                }
            }
        }

        return val;
    }

    pub fn eval(self: *static_analysis, board: [768]f32) f32 {
        var result: f32 = 0;

        for (0..768) |i| {
            result += self.piece_square_tables[i] * board[i];
        }

        return result;
    }

    pub fn save(self: *@This(), fileName: []const u8) !void {
        self.gradient_mutex.lock();
        const file = try std.fs.cwd().createFile(fileName, .{ .read = false });
        const writer = file.writer();

        const data = std.mem.bytesAsSlice(u8, &self.piece_square_tables);
        try writer.writeAll(data);
        self.gradient_mutex.unlock();
    }

    pub fn load(self: *@This(), fileName: []const u8) !void {
        self.gradient_mutex.lock();
        const file = try std.fs.cwd().openFile(fileName, .{ .mode = .read_only });
        const reader = file.reader();

        const data = std.mem.bytesAsSlice(u8, &self.piece_square_tables);
        _ = try reader.readAll(data);
        self.gradient_mutex.unlock();
    }
};
