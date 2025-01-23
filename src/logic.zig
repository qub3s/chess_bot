const std = @import("std");
const mem = @import("std").mem;

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = general_purpose_allocator.allocator();

const Error = error{OutOfMemory};

pub const move = struct { x1: i32, y1: i32, x2: i32, y2: i32 };

pub const Board_s = struct {
    white_castled: bool,
    black_castled: bool,
    pieces: [64]i32,
    white_to_move: bool,

    pub fn possible_moves(board: *Board_s, list: *std.ArrayList(move)) !void {
        return board.get_move(list, true);
    }

    fn get_move(board: *Board_s, list: *std.ArrayList(move), check_checkmate: bool) Error!void {
        for (0..64) |i| {
            var mov: move = undefined;

            if (board.pieces[i] != 0 and ((board.white_to_move and board.pieces[i] < 7) or (!board.white_to_move and board.pieces[i] > 6))) {
                const x: i32 = @intCast(i % 8);
                const y: i32 = @intCast(i / 8);
                const white = board.pieces[i] < 7;

                // king moves
                if (board.pieces[i] == 1 or board.pieces[i] == 7) {
                    const x_change = [_]i32{ 1, -1, 0, 0, 1, 1, -1, -1 };
                    const y_change = [_]i32{ 0, 0, 1, -1, 1, -1, -1, 1 };

                    for (x_change, y_change) |xc, yc| {
                        if (valid_move(board, x + xc, y + yc, white)) {
                            mov = move{ .x1 = x, .y1 = y, .x2 = x + xc, .y2 = y + yc };
                            if (!try board.move_results_checkmate(mov, check_checkmate)) {
                                try list.append(mov);
                            }
                        }
                    }
                }

                // add queen moves
                else if (board.pieces[i] == 2 or board.pieces[i] == 8) {
                    const x_change = [_]i32{ 1, -1, 0, 0, 1, 1, -1, -1 };
                    const y_change = [_]i32{ 0, 0, 1, -1, 1, -1, -1, 1 };

                    for (x_change, y_change) |xc, yc| {
                        var x2 = x + xc;
                        var y2 = y + yc;

                        while (valid_move(board, x2, y2, white)) {
                            mov = move{ .x1 = x, .y1 = y, .x2 = x2, .y2 = y2 };
                            if (!try board.move_results_checkmate(mov, check_checkmate)) {
                                try list.append(mov);
                            }

                            if (board.pieces[@intCast(x2 + y2 * 8)] != 0) {
                                break;
                            }
                            x2 = x2 + xc;
                            y2 = y2 + yc;
                        }
                    }
                }

                // add rook moves
                else if (board.pieces[i] == 3 or board.pieces[i] == 9) {
                    const x_change = [_]i32{ 1, -1, 0, 0 };
                    const y_change = [_]i32{ 0, 0, 1, -1 };

                    for (x_change, y_change) |xc, yc| {
                        var x2 = x + xc;
                        var y2 = y + yc;

                        while (valid_move(board, x2, y2, white)) {
                            mov = move{ .x1 = x, .y1 = y, .x2 = x2, .y2 = y2 };
                            if (!try board.move_results_checkmate(mov, check_checkmate)) {
                                try list.append(mov);
                            }

                            if (board.pieces[@intCast(x2 + y2 * 8)] != 0) {
                                break;
                            }
                            x2 = x2 + xc;
                            y2 = y2 + yc;
                        }
                    }
                }
                // add bishop moves
                else if (board.pieces[i] == 4 or board.pieces[i] == 10) {
                    const x_change = [_]i32{ 1, 1, -1, -1 };
                    const y_change = [_]i32{ 1, -1, 1, -1 };

                    for (x_change, y_change) |xc, yc| {
                        var x2 = x + xc;
                        var y2 = y + yc;

                        while (valid_move(board, x2, y2, white)) {
                            mov = move{ .x1 = x, .y1 = y, .x2 = x2, .y2 = y2 };
                            if (!try board.move_results_checkmate(mov, check_checkmate)) {
                                try list.append(mov);
                            }

                            if (board.pieces[@intCast(x2 + y2 * 8)] != 0) {
                                break;
                            }
                            x2 = x2 + xc;
                            y2 = y2 + yc;
                        }
                    }
                }
                // add knight moves
                else if (board.pieces[i] == 5 or board.pieces[i] == 11) {
                    const x_change = [_]i32{ 2, 2, -2, -2, 1, 1, -1, -1 };
                    const y_change = [_]i32{ 1, -1, 1, -1, 2, -2, 2, -2 };

                    for (x_change, y_change) |xc, yc| {
                        const x2 = x + xc;
                        const y2 = y + yc;

                        if (valid_move(board, x2, y2, white)) {
                            mov = move{ .x1 = x, .y1 = y, .x2 = x2, .y2 = y2 };
                            if (!try board.move_results_checkmate(mov, check_checkmate)) {
                                try list.append(mov);
                            }
                        }
                    }
                }
                // add pawn white moves
                else if (board.pieces[i] == 6) {
                    const capr = board.pieces[@intCast(x - 1 + (y + 1) * 8)];
                    var capl: i32 = 0;
                    if (x != 7) {
                        capl = board.pieces[@intCast(x + 1 + (y + 1) * 8)];
                    } else {
                        capl = 0;
                    }
                    const push = board.pieces[@intCast(x + (y + 1) * 8)];

                    // capture left
                    if (capr > 6 and valid_move(board, x - 1, y + 1, white)) {
                        mov = move{ .x1 = x, .y1 = y, .x2 = x - 1, .y2 = y + 1 };
                        if (!try board.move_results_checkmate(mov, check_checkmate)) {
                            try list.append(mov);
                        }
                    }

                    // capture right
                    if (capl > 6 and valid_move(board, x + 1, y + 1, white)) {
                        mov = move{ .x1 = x, .y1 = y, .x2 = x + 1, .y2 = y + 1 };
                        if (!try board.move_results_checkmate(mov, check_checkmate)) {
                            try list.append(mov);
                        }
                    }

                    // push
                    if (valid_move(board, x, y + 1, white) and push == 0) {
                        mov = move{ .x1 = x, .y1 = y, .x2 = x, .y2 = y + 1 };
                        if (!try board.move_results_checkmate(mov, check_checkmate)) {
                            try list.append(mov);
                        }
                    }

                    // double push
                    if (y == 1) {
                        const fpush = board.pieces[@intCast(x + (y + 2) * 8)];
                        if (valid_move(board, x, y + 2, white) and fpush == 0) {
                            mov = move{ .x1 = x, .y1 = y, .x2 = x, .y2 = y + 2 };
                            if (!try board.move_results_checkmate(mov, check_checkmate)) {
                                try list.append(mov);
                            }
                        }
                    }
                }
                // add pawn black moves
                else if (board.pieces[i] == 12) {
                    var capr: i32 = 0;
                    if (x != 0) {
                        capr = board.pieces[@intCast(x - 1 + (y - 1) * 8)];
                    } else {
                        capr = 0;
                    }
                    const capl = board.pieces[@intCast(x + 1 + (y - 1) * 8)];
                    const push = board.pieces[@intCast(x + (y - 1) * 8)];

                    // capture left
                    if (capr < 7 and capr != 0 and valid_move(board, x - 1, y - 1, white)) {
                        mov = move{ .x1 = x, .y1 = y, .x2 = x - 1, .y2 = y - 1 };
                        if (!try board.move_results_checkmate(mov, check_checkmate)) {
                            try list.append(mov);
                        }
                    }

                    // capture right
                    if (capl < 7 and capl != 0 and valid_move(board, x + 1, y - 1, white)) {
                        mov = move{ .x1 = x, .y1 = y, .x2 = x + 1, .y2 = y - 1 };
                        if (!try board.move_results_checkmate(mov, check_checkmate)) {
                            try list.append(mov);
                        }
                    }

                    // push
                    if (valid_move(board, x, y - 1, white) and push == 0) {
                        mov = move{ .x1 = x, .y1 = y, .x2 = x, .y2 = y - 1 };
                        if (!try board.move_results_checkmate(mov, check_checkmate)) {
                            try list.append(mov);
                        }
                    }

                    // double push
                    if (y == 6) {
                        const fpush = board.pieces[@intCast(x + (y - 2) * 8)];
                        if (valid_move(board, x, y - 2, white) and fpush == 0) {
                            mov = move{ .x1 = x, .y1 = y, .x2 = x, .y2 = y - 2 };
                            if (!try board.move_results_checkmate(mov, check_checkmate)) {
                                try list.append(mov);
                            }
                        }
                    }
                }
            }
        }
    }

    pub fn move_results_checkmate(self: *Board_s, m: move, rec: bool) !bool {
        var cpy = self.copy();
        cpy.make_move_m(m);
        return try cpy.checkmate_next_move(rec);
    }

    pub fn set(self: *Board_s, x: i32, y: i32, value: i32) void {
        self.pieces[@intCast(y * 8 + x)] = value;
    }

    pub fn checkmate_next_move(self: *Board_s, recursive: bool) !bool {
        if (recursive == false) {
            return false;
        }

        var pos_moves = std.ArrayList(move).init(gpa);
        defer pos_moves.deinit();
        try self.get_move(&pos_moves, false);

        for (0..pos_moves.items.len) |i| {
            var move_to_eval = self.copy();
            move_to_eval.make_move_m(pos_moves.items[i]);
            if (move_to_eval.check_win() != 0) {
                return true;
            }
        }
        return false;
    }

    pub fn get(self: *const Board_s, x: i32, y: i32) i32 {
        return self.pieces[@intCast(y * 8 + x)];
    }

    pub fn init() Board_s {
        var self = Board_s{ .white_castled = false, .black_castled = false, .pieces = mem.zeroes([64]i32), .white_to_move = true };

        // white pieces
        self.set(0, 0, 3);
        self.set(1, 0, 5);
        self.set(2, 0, 4);
        self.set(3, 0, 1);
        self.set(4, 0, 2);
        self.set(5, 0, 4);
        self.set(6, 0, 5);
        self.set(7, 0, 3);

        // black pieces
        self.set(0, 7, 9);
        self.set(1, 7, 11);
        self.set(2, 7, 10);
        self.set(3, 7, 7);
        self.set(4, 7, 8);
        self.set(5, 7, 10);
        self.set(6, 7, 11);
        self.set(7, 7, 9);

        // pawns
        for (0..8) |x| {
            self.set(@intCast(x), 1, 6);
            self.set(@intCast(x), 6, 12);
        }
        return self;
    }

    pub fn copy(self: Board_s) Board_s {
        var copy_pieces: [64]i32 = undefined;
        copy_pieces[0] = 0;
        @memcpy(copy_pieces[0..64], self.pieces[0..64]);

        return Board_s{ .white_castled = self.white_castled, .black_castled = self.black_castled, .pieces = copy_pieces, .white_to_move = self.white_to_move };
    }

    fn get_board_768(p64: [64]i32, p768: *[768]f32) void {
        for (0..768) |i| {
            if (p64[i % 64] == 1 + i / 64) {
                p768[i] = 1;
            } else {
                p768[i] = 0;
            }
        }
    }

    pub fn get_input(self: Board_s, p768: *[768]f32) void {
        var flipped_board = mem.zeroes([64]i32);

        if (self.white_to_move) {
            for (0..self.pieces.len) |i| {
                flipped_board[i] = self.pieces[i];
            }
        } else {
            self.inverse_board(&flipped_board);
        }

        get_board_768(flipped_board, p768);
    }

    //TODO change the value of the pieces
    pub fn inverse_board(board: Board_s, result: *[64]i32) void {
        for (0..8) |x| {
            for (0..8) |y| {
                const val = board.pieces[x + y * 8];

                if (val == 0) {
                    result[x + (7 - y) * 8] = 0;
                } else if (val > 6) {
                    result[x + (7 - y) * 8] = val - 6;
                } else if (val <= 6) {
                    result[x + (7 - y) * 8] = val + 6;
                }
            }
        }
    }

    pub fn valid_move(board: *Board_s, x: i32, y: i32, white: bool) bool {
        // check if in bounds
        if (x > 7 or x < 0 or y > 7 or y < 0) {
            return false;
        }

        const piece = board.pieces[@intCast(y * 8 + x)];

        // check if empty
        if (piece == 0) {
            return true;
        }

        if (white) {
            if (piece > 6 and piece < 13) {
                return true;
            } else {
                return false;
            }
        } else {
            if (piece > 0 and piece < 7) {
                return true;
            } else {
                return false;
            }
        }
    }

    pub fn check_win(board: Board_s) i32 {
        var res: i32 = 0;
        for (0..64) |i| {
            if (board.pieces[i] == 1) {
                res += 1;
            } else if (board.pieces[i] == 7) {
                res -= 1;
            }
        }
        return res;
    }

    pub fn make_move_m(board: *Board_s, pos: move) void {
        make_move(board, @intCast(pos.x1 + pos.y1 * 8), @intCast(pos.x2 + pos.y2 * 8));
    }

    pub fn make_move(board: *Board_s, pos: usize, move_to: usize) void {
        //const mt_x: i32 = @intCast(move_to % 8);
        const mt_y: i32 = @intCast(move_to / 8);

        if (board.pieces[pos] == 6 and mt_y == 7) {
            board.pieces[pos] = 0;
            board.pieces[move_to] = 2;
        } else if (board.pieces[pos] == 12 and mt_y == 0) {
            board.pieces[pos] = 0;
            board.pieces[move_to] = 8;
        } else {
            board.pieces[move_to] = board.pieces[pos];
            board.pieces[pos] = 0;
        }
        board.white_to_move = board.white_to_move == false;
    }
};
