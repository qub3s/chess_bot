const std = @import("std");

var general_purpose_allocator = std.heap.GeneralPurposeAllocautor(.{}){};
const gpa = general_purpose_allocator.allocator();

pub var knight_moves: [64]u64 = undefined;
pub var king_moves: [64]u64 = undefined;

pub var pawn_attacks_white: [64]u64 = undefined;
pub var pawn_moves_white: [64]u64 = undefined;

pub var pawn_attacks_black: [64]u64 = undefined;
pub var pawn_moves_black: [64]u64 = undefined;

pub var rook_masks_v: [16]u64 = undefined;
pub var rook_masks_h: [16]u64 = undefined;

pub var magic_rook_v: [16]u64 = undefined;
pub var magic_rook_h: [16]u64 = undefined;

pub var atk_map_rook_v: [16][12]u64 = undefined;
pub var atk_map_rook_h: [16][12]u64 = undefined;

pub var search_table_rook_v: [16][64]u4 = undefined;
pub var search_table_rook_h: [16][64]u4 = undefined;

// 1: rook mask * blockers
// 2: blockers * magic
// 3: search table lookup
// 4: attack map lookup

//pub var bishop_masks_dl: [16]u64 = std.mem.zeroes([16]u64);
//pub var bishop_masks_dr: [16]u64 = std.mem.zeroes([16]u64);

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

    pub fn copy(self: *bitboard) bitboard {
        var new_board: [12]u64 = undefined;
        @memcpy(&new_board, self.board);

        return bitboard{ .board = new_board, .white_to_move = self.white_to_move };
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
        const pieces = "kqrbnpKQRBNP";
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

    pub fn make_hypothetical_moves(self: *bitboard, p1: u32, p2: u32) bitboard {
        var cpy = self.copy();

        const one: u64 = 1;
        for (0..12) |i| {
            if (self.board[i] & one << p2 != 0) {
                cpy.board[i] = self.board[i] ^ one << p2;
            }

            if (self.board[i] & one << p1 != 0) {
                cpy.board[i] = self.board[i] ^ one << p1;
                cpy.board[i] = cpy.board ^ one << p2;
            }
        }
        return cpy;
    }

    inline fn create_new_bitboards(self: *bitboard, store: *std.ArrayList(bitboard), piece: u32, moves: u64, piece_pos: u64) !void {
        var pos: u64 = 1;

        for (0..64) |_| {
            if (pos & moves != 0) {
                var new_board: [12]u64 = undefined;

                // copy and remove from original and new position
                for (0..12) |i| {
                    if (i == piece) {
                        new_board[i] = self.board[i] ^ pos ^ (piece_pos & self.board[i]);
                    } else {
                        new_board[i] = self.board[i] ^ (piece_pos & self.board[i]);
                    }
                }

                new_board[piece] |= pos;

                try store.append(bitboard{ .board = new_board, .white_to_move = !self.white_to_move });
            }
            pos = pos << 1;
        }
    }

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

                            6 => try self.create_new_bitboards(store, 0, king_moves[i] ^ (king_moves[i] & own_pieces), pos),
                            10 => try self.create_new_bitboards(store, 4, knight_moves[i] ^ (knight_moves[i] & own_pieces), pos),
                            11 => try self.create_new_bitboards(store, 5, (pawn_attacks_black[i] & other_pieces) | (pawn_moves_black[i] ^ (pawn_moves_black[i] & all_pieces)), pos),
                            else => {},
                        }
                    }
                }
            }
            pos = pos << 1;
        }
    }
};

pub fn generate_attackmaps() void {
    generate_knight_moves();
    generate_king_moves();
    generate_pawn_attacks();
    generate_pawn_moves();

    generate_rook_masks();
    generate_rook_attacks();
    //generate_bishop_masks();
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

fn generate_rook_masks() void {
    const one: u64 = 1;

    for (0..32) |i| {
        const x: i32 = @mod(@as(i32, @intCast(i)), 8);
        const y: i32 = @divTrunc(@as(i32, @intCast(i)), 8);

        if (x < 4 and y < 4) {
            const y_change = [_]i32{ 1, -1 };

            for (y_change) |yc| {
                const x2 = x;
                var y2 = y + yc;

                while (y2 >= 0 and y2 < 8) {
                    rook_masks_v[@intCast(x + y * 4)] |= one << @intCast(x2 + y2 * 8);

                    y2 += yc;
                }
            }

            if (y != 0) {
                rook_masks_v[@intCast(x + y * 4)] ^= one << @intCast(x);
            }

            if (y != 7) {
                rook_masks_v[@intCast(x + y * 4)] ^= one << @intCast(x + 7 * 8);
            }
        }
    }

    for (0..32) |i| {
        const x: i32 = @mod(@as(i32, @intCast(i)), 8);
        const y: i32 = @divTrunc(@as(i32, @intCast(i)), 8);

        if (x < 4 and y < 4) {
            const x_change = [_]i32{ 1, -1 };

            for (x_change) |xc| {
                var x2 = x + xc;
                const y2 = y;

                while (x2 >= 0 and x2 < 8) {
                    rook_masks_h[@intCast(x + y * 4)] |= one << @intCast(x2 + y2 * 8);

                    x2 += xc;
                }
            }

            if (x != 0) {
                rook_masks_h[@intCast(x + y * 4)] ^= one << @intCast(y * 8);
            }

            if (x != 7) {
                rook_masks_h[@intCast(x + y * 4)] ^= one << @intCast(7 + y * 8);
            }
        }
    }
}

fn generate_rook_attacks() void {
    const one: u64 = 1;
    var atk_map: u64 = undefined;

    for (0..32) |i| {
        const x: i32 = @mod(@as(i32, @intCast(i)), 8);
        const y: i32 = @divTrunc(@as(i32, @intCast(i)), 8);

        if (x < 4 and y < 4) {
            magic_rook_h[@intCast(x + 4 * y)] = std.math.pow(u64, 2, @intCast((7 - y) * 8 + 1));

            for (0..64) |j| {
                const board: u64 = j << @intCast(y * 8 + 1);

                atk_map = 0;

                if (board & one << @intCast(x + y * 8) == 0) {
                    const x_change = [_]i32{ 1, -1 };

                    for (x_change) |xc| {
                        var x2 = x + xc;

                        while (x2 >= 0 and x2 < 8 and board & (one << @intCast(x2 + y * 8)) == 0) {
                            atk_map |= one << @intCast(x2 + y * 8);
                            x2 += xc;
                        }

                        if (x2 >= 0 and x2 < 8 and board & (one << @intCast(x2 + y * 8)) != 0) {
                            atk_map |= one << @intCast(x2 + y * 8);
                        }
                    }

                    for (0..20) |k| {
                        if (atk_map_rook_h[@intCast(x + y * 4)][k] == atk_map) {
                            search_table_rook_h[@intCast(x + y * 4)][j] = @intCast(k);
                            break;
                        }

                        if (atk_map_rook_h[@intCast(x + y * 4)][k] == 0) {
                            search_table_rook_h[@intCast(x + y * 4)][j] = @intCast(k);
                            atk_map_rook_h[@intCast(x + y * 4)][k] = atk_map;
                            break;
                        }
                    }

                    //std.debug.print("\n\n\n\n", .{});
                    //display_u64(board);
                    //std.debug.print("\n\n", .{});
                    //display_u64(atk_map);
                }
            }
        }
    }

    for (0..32) |i| {
        const x: i32 = @mod(@as(i32, @intCast(i)), 8);
        const y: i32 = @divTrunc(@as(i32, @intCast(i)), 8);

        if (x < 4 and y < 4) {
            for (0..8) |j| {
                magic_rook_v[@intCast(x + 4 * y)] |= one << @intCast(x + @as(i32, @intCast(j)) * 8 - @as(i32, @intCast(j)) + 1);
            }

            for (0..64) |j| {
                const board: u64 = transpose_u64(j << @intCast(y * 8 + 1));

                atk_map = 0;

                if (board & one << @intCast(x + y * 8) == 0) {
                    const y_change = [_]i32{ 1, -1 };

                    for (y_change) |yc| {
                        var y2 = y + yc;

                        while (y2 >= 0 and y2 < 8 and board & (one << @intCast(x + y2 * 8)) == 0) {
                            atk_map |= one << @intCast(x + y2 * 8);
                            y2 += yc;
                        }

                        if (y2 >= 0 and y2 < 8 and board & (one << @intCast(x + y2 * 8)) != 0) {
                            atk_map |= one << @intCast(x + y2 * 8);
                        }
                    }

                    for (0..20) |k| {
                        if (atk_map_rook_v[@intCast(x + y * 4)][k] == atk_map) {
                            search_table_rook_v[@intCast(x + y * 4)][j] = @intCast(k);
                            break;
                        }

                        if (atk_map_rook_v[@intCast(x + y * 4)][k] == 0) {
                            search_table_rook_v[@intCast(x + y * 4)][j] = @intCast(k);
                            atk_map_rook_v[@intCast(x + y * 4)][k] = atk_map;
                            break;
                        }
                    }
                }
                atk_map = 0;
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

pub inline fn inverse_horizontal_u64(b: u64) u64 {
    return b << 56 | (0xff00 & b) << 40 | (0xff0000 & b) << 24 | (0xff000000 & b) << 8 | b >> 56 | (0xff000000000000 & b) >> 40 | (0xff000000000000 & b) >> 24 | (0xff0000000 & b) >> 8;
}

pub inline fn inverse_vertical_u64(b: u64) u64 {
    return (0xf0f0f0f0f0f0f0f0 & b) >> 4 | (0x0f0f0f0f0f0f0f & b) << 4;
}

pub inline fn transpose_u64(b: u64) u64 {
    const one: u64 = 1;
    var copy: u64 = 0;

    for (0..64) |i| {
        const x: i32 = @mod(@as(i32, @intCast(i)), 8);
        const y: i32 = @divTrunc(@as(i32, @intCast(i)), 8);

        if (one << @intCast(x + y * 8) & b != 0) {
            copy |= one << @intCast(y + x * 8);
        }
    }

    return copy;
}

//fn generate_bishop_masks() void {
//    const one: u64 = 1;
//    // all bordering bits
//    const remove: u64 = 0xff818181818181ff;
//
//    for (0..64) |i| {
//        const x: i32 = @mod(@as(i32, @intCast(i)), 8);
//        const y: i32 = @divTrunc(@as(i32, @intCast(i)), 8);
//
//        if (x < 4 and y < 4) {
//            const x_change = [_]i32{ -1, -1, 1, 1 };
//            const y_change = [_]i32{ 1, -1, 1, -1 };
//
//            for (x_change, y_change) |xc, yc| {
//                var x2 = x + xc;
//                var y2 = y + yc;
//
//                while (x2 >= 0 and x2 < 8 and y2 >= 0 and y2 < 8) {
//                    bishop_masks_dl[i] |= one << @intCast(x2 + y2 * 8);
//
//                    x2 += xc;
//                    y2 += yc;
//                }
//            }
//
//            bishop_masks_dl[i] ^= (bishop_masks_dl[i] & remove);
//        }
//    }
//}
