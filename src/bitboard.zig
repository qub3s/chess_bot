const std = @import("std");

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = general_purpose_allocator.allocator();

pub const bitboard = struct {
    // black       - white
    // k q r b k p - K Q R B K P
    board: [12]u64,

    // create attack maps
    // create move maps
    // export to
    // get game result
    // get possible moves
    // inverse board

    pub fn init() bitboard {
        var board = std.mem.zeroes([12]u64);

        board[0] = 0b00010000;
        board[1] = 0b00001000;
        board[2] = 0b10000001;
        board[3] = 0b00100100;
        board[4] = 0b01000010;
        board[5] = 0b11111111 << 8;

        board[6] = 0b00010000 << 56;
        board[7] = 0b00001000 << 56;
        board[8] = 0b10000001 << 56;
        board[9] = 0b00100100 << 56;
        board[10] = 0b01000010 << 56;
        board[11] = 0b11111111 << 48;

        return bitboard{ .board = board };
    }

    pub fn inverse(self: *bitboard) void {
        for (0..6) |i| {
            var tmp: u64 = undefined;

            tmp = self.board[i];
            self.board[i] = self.board[i + 6];
            self.board[i + 6] = tmp;
        }
    }

    pub fn display(self: bitboard) void {
        const pieces = "kqrbkpKQRBKP";
        var printed: bool = false;

        var tmp: u64 = 1;
        for (0..64) |pos| {
            if (pos != 0 and pos % 8 == 0) {
                std.debug.print("\n", .{});
            }

            for (0..12) |piece| {
                if (tmp & self.board[piece] != 0) {
                    std.debug.print("{c} ", .{pieces[piece]});
                    printed = true;
                }
            }

            if (printed) {
                printed = false;
            } else {
                std.debug.print(". ", .{});
            }

            tmp = tmp << 1;
        }
        std.debug.print("\n", .{});
    }
};
