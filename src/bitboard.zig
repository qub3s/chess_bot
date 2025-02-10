const std = @import("std");

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = general_purpose_allocator.allocator();

pub var knight_moves: [64]u64 = std.mem.zeroes([64]u64);
pub var king_moves: [64]u64 = std.mem.zeroes([64]u64);

pub var pawn_attacks_white: [64]u64 = std.mem.zeroes([64]u64);
pub var pawn_moves_white: [64]u64 = std.mem.zeroes([64]u64);
pub var pawn_attacks_black: [64]u64 = std.mem.zeroes([64]u64);
pub var pawn_moves_black: [64]u64 = std.mem.zeroes([64]u64);

pub const bitboard = struct {
    // black       - white
    // k q r b k p - K Q R B K P
    board: [12]u64,
    white_to_move: bool,

    // create attack maps
    // create move maps
    // export to
    // get game result
    // get possible moves

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

        return bitboard{ .board = board, .white_to_move = true };
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
                    break;
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

    inline fn create_new_bitboards(self: *bitboard, store: *std.ArrayList(bitboard), piece: u32, moves: u64, piece_pos: u64) !void {
        var pos: u64 = 1;

        std.debug.print("\n", .{});
        display_u64(moves);
        std.debug.print("\n", .{});

        for (0..64) |_| {
            if (pos & moves != 0) {
                var new_board: [12]u64 = undefined;

                // copy and remove from original and new position
                for (0..12) |i| {
                    new_board[i] = self.board[i] ^ piece_pos ^ pos;
                }

                new_board[piece] |= pos;

                try store.append(bitboard{ .board = new_board, .white_to_move = !self.white_to_move });
            }
            pos = pos << 1;
        }
    }

    inline fn double_push() void {}

    pub fn gen_moves(self: *bitboard, store: *std.ArrayList(bitboard)) !void {
        var all_pieces: u64 = 0;
        var own_pieces: u64 = 0;
        var other_pieces: u64 = 0;

        for (0..6) |i| {
            own_pieces |= self.board[i];
        }

        for (6..12) |i| {
            other_pieces |= self.board[i];
        }

        if (!self.white_to_move) {
            const tmp: u64 = 0;
            own_pieces = tmp;
            own_pieces = other_pieces;
            other_pieces = tmp;
        }

        all_pieces = own_pieces | other_pieces;

        var pos: u64 = 1;
        // over all tiles
        for (0..64) |i| {
            if (own_pieces & pos != 0) {
                // if tile non empty check what piece
                // TODO only for the own piece intervall
                for (0..12) |j| {
                    if (self.board[j] & pos != 0) {
                        switch (j) {
                            0 => try self.create_new_bitboards(store, 0, king_moves[i] ^ (king_moves[i] & own_pieces), pos),
                            4 => try self.create_new_bitboards(store, 4, knight_moves[i] ^ (knight_moves[i] & own_pieces), pos),
                            5 => try self.create_new_bitboards(store, 5, (pawn_attacks_white[i] & other_pieces) | (pawn_moves_white[i] ^ (pawn_moves_white[i] & all_pieces)), pos),
                            6 => try self.create_new_bitboards(store, 6, king_moves[i] ^ (king_moves[i] & own_pieces), pos),
                            10 => try self.create_new_bitboards(store, 10, knight_moves[i] ^ (knight_moves[i] & own_pieces), pos),
                            else => {},
                        }
                    }
                }
            }
            pos = pos << 1;
        }
        std.debug.print("Store: {}\n", .{store.items.len});
    }
};

pub fn generate_attackmaps() void {
    generate_knight_moves();
    generate_king_moves();
    generate_pawn_attacks();
    generate_pawn_moves();
}

fn generate_pawn_attacks() void {
    const one: u64 = 1;

    for (0..64) |i| {
        const x: i32 = @mod(@as(i32, @intCast(i)), 8);
        const y: i32 = @divTrunc(@as(i32, @intCast(i)), 8);

        const x_change = [_]i32{ 1, -1 };
        const y_change = [_]i32{ -1, -1 };

        for (x_change, y_change) |xc, yc| {
            const x2 = x + xc;
            const y2 = y + yc;

            if (x2 >= 0 and x2 < 8 and y2 >= 0 and y2 < 8) {
                pawn_attacks_white[i] |= one << @intCast(x2 + y2 * 8);
            }
        }
    }

    for (0..64) |i| {
        const x: i32 = @mod(@as(i32, @intCast(i)), 8);
        const y: i32 = @divTrunc(@as(i32, @intCast(i)), 8);

        const x_change = [_]i32{ 1, -1 };
        const y_change = [_]i32{ 1, 1 };

        for (x_change, y_change) |xc, yc| {
            const x2 = x + xc;
            const y2 = y + yc;

            if (x2 >= 0 and x2 < 8 and y2 >= 0 and y2 < 8) {
                pawn_attacks_black[i] |= one << @intCast(x2 + y2 * 8);
            }
        }
    }
}

fn generate_pawn_moves() void {
    const one: u64 = 1;

    for (0..64) |i| {
        const x: i32 = @mod(@as(i32, @intCast(i)), 8);
        const y: i32 = @divTrunc(@as(i32, @intCast(i)), 8);

        const x_change = [_]i32{0};
        const y_change = [_]i32{-1};

        for (x_change, y_change) |xc, yc| {
            const x2 = x + xc;
            const y2 = y + yc;

            if (x2 >= 0 and x2 < 8 and y2 >= 0 and y2 < 8) {
                pawn_moves_white[i] |= one << @intCast(x2 + y2 * 8);
            }
        }
    }

    for (0..64) |i| {
        const x: i32 = @mod(@as(i32, @intCast(i)), 8);
        const y: i32 = @divTrunc(@as(i32, @intCast(i)), 8);

        const x_change = [_]i32{0};
        const y_change = [_]i32{1};

        for (x_change, y_change) |xc, yc| {
            const x2 = x + xc;
            const y2 = y + yc;

            if (x2 >= 0 and x2 < 8 and y2 >= 0 and y2 < 8) {
                pawn_moves_black[i] |= one << @intCast(x2 + y2 * 8);
            }
        }
    }
}

fn generate_king_moves() void {
    const one: u64 = 1;

    for (0..64) |i| {
        const x: i32 = @mod(@as(i32, @intCast(i)), 8);
        const y: i32 = @divTrunc(@as(i32, @intCast(i)), 8);

        const x_change = [_]i32{ 1, -1, 0, 0, 1, 1, -1, -1 };
        const y_change = [_]i32{ 0, 0, 1, -1, 1, -1, -1, 1 };

        for (x_change, y_change) |xc, yc| {
            const x2 = x + xc;
            const y2 = y + yc;

            if (x2 >= 0 and x2 < 8 and y2 >= 0 and y2 < 8) {
                king_moves[i] |= one << @intCast(x2 + y2 * 8);
            }
        }
    }
}

fn generate_knight_moves() void {
    const one: u64 = 1;

    for (0..64) |i| {
        const x: i32 = @mod(@as(i32, @intCast(i)), 8);
        const y: i32 = @divTrunc(@as(i32, @intCast(i)), 8);

        const x_change = [_]i32{ 2, 2, -2, -2, 1, 1, -1, -1 };
        const y_change = [_]i32{ 1, -1, 1, -1, 2, -2, 2, -2 };

        for (x_change, y_change) |xc, yc| {
            const x2 = x + xc;
            const y2 = y + yc;

            if (x2 >= 0 and x2 < 8 and y2 >= 0 and y2 < 8) {
                knight_moves[i] |= one << @intCast(x2 + y2 * 8);
            }
        }
    }
}

pub fn display_u64(b: u64) void {
    var tmp: u64 = 1;

    for (0..64) |i| {
        if (i % 8 == 0 and i != 0) {
            std.debug.print("\n", .{});
        }

        if (tmp & b != 0) {
            std.debug.print("X ", .{});
        } else {
            std.debug.print(". ", .{});
        }
        tmp = tmp << 1;
    }
}
