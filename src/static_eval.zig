const std = @import("std");

pub const static_analysis = struct {
    piece_values: [6]f32,

    pub fn init() static_analysis {
        const piece_values = .{ 100000, 10, 5.25, 3.5, 3.5, 1 };

        return static_analysis{ .piece_values = piece_values };
    }

    pub fn add(self: *static_analysis, adding: static_analysis) void {
        self.gradient_mutex.lock();

        for (0..self.piece_square_tables.len) |i| {
            self.gradient[i] += adding.piece_square_tables[i];
        }
        self.gradient_values += 1;

        self.gradient_mutex.unlock();
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
};
