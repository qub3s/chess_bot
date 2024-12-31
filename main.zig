const std = @import("std");
const ray = @cImport({
    @cInclude("raylib.h");
});
const print = std.debug.print;
const mem = @import("std").mem;
const nn = @import("src/nn.zig");
const nn_type = f32;

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = general_purpose_allocator.allocator();

// board colors
const black_color: u32 = 0xf0d9b5ff;
const white_color: u32 = 0xb58863ff;

// piece_graphices
var textures_pieces: [12]ray.Texture = undefined;
const tile_pos = struct { x: i32, y: i32 };
const move = struct { x1: i32, y1: i32, x2: i32, y2: i32 };

// empty = 0, wking = 1, wqueen = 2, wrook = 3, wbishop = 4, wknight = 5, wpawn = 6, bking = 7 ...
const Board_s = struct {
    white_castled: bool,
    black_castled: bool,
    pieces: [64]i32,
    white_to_move: bool,

    pub fn nothing(self: Board_s) Board_s {
        return self;
    }

    pub fn set(self: *Board_s, x: i32, y: i32, value: i32) void {
        self.pieces[@intCast(y * 8 + x)] = value;
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
        self.set(3, 0, 2);
        self.set(4, 0, 1);
        self.set(5, 0, 4);
        self.set(6, 0, 5);
        self.set(7, 0, 3);

        // black pieces
        self.set(0, 7, 9);
        self.set(1, 7, 11);
        self.set(2, 7, 10);
        self.set(3, 7, 8);
        self.set(4, 7, 7);
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
        const copy_pieces = mem.zeroes([64]i32);
        @memcpy(copy_pieces, self.pieces);

        return Board_s{ .white_castled = self.white_castled, .black_castled = self.black_castled, .pieces = copy_pieces, .white_to_move = self.white_to_move };
    }
};

fn load_piece_textures() !void {
    const names: [12][]const u8 = .{ "images/pieces/kl.png", "images/pieces/ql.png", "images/pieces/rl.png", "images/pieces/bl.png", "images/pieces/nl.png", "images/pieces/pl.png", "images/pieces/kd.png", "images/pieces/qd.png", "images/pieces/rd.png", "images/pieces/bd.png", "images/pieces/nd.png", "images/pieces/pd.png" };

    for (0..names.len) |x| {
        textures_pieces[x] = ray.LoadTexture(names[x].ptr);
    }
}

inline fn valid_move(board: *Board_s, x: i32, y: i32, white: bool) bool {
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

// create list of all possible moves
// TODO
// add castling
// add en pason
// add promoting
fn possible_moves(board: *Board_s, list: *std.ArrayList(move)) !void {
    for (0..64) |i| {
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
                        try list.append(move{ .x1 = x, .y1 = y, .x2 = x + xc, .y2 = y + yc });
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
                        try list.append(move{ .x1 = x, .y1 = y, .x2 = x2, .y2 = y2 });

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
                        try list.append(move{ .x1 = x, .y1 = y, .x2 = x2, .y2 = y2 });

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
                        try list.append(move{ .x1 = x, .y1 = y, .x2 = x2, .y2 = y2 });

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
                        try list.append(move{ .x1 = x, .y1 = y, .x2 = x2, .y2 = y2 });
                    }
                }
            }
            // add pawn white moves
            else if (board.pieces[i] == 6) {
                const capr = board.pieces[@intCast(x - 1 + (y + 1) * 8)];
                const capl = board.pieces[@intCast(x + 1 + (y + 1) * 8)];
                const push = board.pieces[@intCast(x + (y + 1) * 8)];

                // capture left
                if (capr > 6 and valid_move(board, x - 1, y + 1, white)) {
                    try list.append(move{ .x1 = x, .y1 = y, .x2 = x - 1, .y2 = y + 1 });
                }

                // capture right
                if (capl > 6 and valid_move(board, x + 1, y + 1, white)) {
                    try list.append(move{ .x1 = x, .y1 = y, .x2 = x + 1, .y2 = y + 1 });
                }

                // push
                if (valid_move(board, x, y + 1, white) and push == 0) {
                    try list.append(move{ .x1 = x, .y1 = y, .x2 = x, .y2 = y + 1 });
                }

                // double push
                if (y == 1) {
                    const fpush = board.pieces[@intCast(x + (y + 2) * 8)];
                    if (valid_move(board, x, y + 2, white) and fpush == 0) {
                        try list.append(move{ .x1 = x, .y1 = y, .x2 = x, .y2 = y + 2 });
                    }
                }
            }
            // add pawn black moves
            else if (board.pieces[i] == 12) {
                const capr = board.pieces[@intCast(x - 1 + (y - 1) * 8)];
                const capl = board.pieces[@intCast(x + 1 + (y - 1) * 8)];
                const push = board.pieces[@intCast(x + (y - 1) * 8)];

                // capture left
                if (capr < 7 and capr != 0 and valid_move(board, x - 1, y - 1, white)) {
                    try list.append(move{ .x1 = x, .y1 = y, .x2 = x - 1, .y2 = y - 1 });
                }

                // capture right
                if (capl < 7 and capl != 0 and valid_move(board, x + 1, y - 1, white)) {
                    try list.append(move{ .x1 = x, .y1 = y, .x2 = x + 1, .y2 = y - 1 });
                }

                // push
                if (valid_move(board, x, y - 1, white) and push == 0) {
                    try list.append(move{ .x1 = x, .y1 = y, .x2 = x, .y2 = y - 1 });
                }

                // double push
                if (y == 6) {
                    const fpush = board.pieces[@intCast(x + (y - 2) * 8)];
                    if (valid_move(board, x, y - 2, white) and fpush == 0) {
                        try list.append(move{ .x1 = x, .y1 = y, .x2 = x, .y2 = y - 2 });
                    }
                }
            }
        }
    }
}

fn check_win(board: Board_s) i32 {
    var res = 0;
    for (0..64) |i| {
        if (board.pieces[i] == 1) {
            res += 1;
        } else if (board.pieces[i] == 7) {
            res -= 1;
        }
    }
    return res;
}

fn make_move(board: *Board_s, pos: usize, move_to: usize) void {
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

fn visualize(board: *Board_s, size: i32) !void {
    const white_board_tile_color = ray.GetColor(white_color);
    const black_board_tile_color = ray.GetColor(black_color);

    var click_pos: i32 = -1;
    const last_click_pos = struct {
        var v: i32 = -1;
    };

    const first_draw = struct {
        var v: bool = true;
    };

    if (ray.IsMouseButtonPressed(ray.MOUSE_BUTTON_LEFT) or ray.IsMouseButtonPressed(ray.MOUSE_BUTTON_RIGHT)) {
        const mouse_pos = ray.GetMousePosition();
        if (!(@as(i32, @intFromFloat(mouse_pos.x)) > 8 * size) and !(@as(i32, @intFromFloat(mouse_pos.y)) > 8 * size)) {
            click_pos = 63 - @divTrunc(@as(i32, @intFromFloat(mouse_pos.x)), size) - @divTrunc(@as(i32, @intFromFloat(mouse_pos.y)), size) * 8;
        }
    }

    if (click_pos != -1 or first_draw.v) {
        ray.ClearBackground(ray.RAYWHITE);
        first_draw.v = false;

        // get moves
        var all_moves = std.ArrayList(move).init(gpa);
        var visible_moves = std.ArrayList(i32).init(gpa);
        try possible_moves(board, &all_moves);

        // check if move is valid
        if (last_click_pos.v != -1) {
            var temp: i32 = -1;
            for (0..all_moves.items.len) |i| {
                if (all_moves.items[i].x1 + all_moves.items[i].y1 * 8 == last_click_pos.v and all_moves.items[i].x2 + all_moves.items[i].y2 * 8 == click_pos) {
                    temp = click_pos;
                    break;
                }
            }

            if (temp == -1) {
                last_click_pos.v = click_pos;
                click_pos = temp;
            }
            // swap board pieces
            if (click_pos != -1) {
                make_move(board, @intCast(last_click_pos.v), @intCast(click_pos));
                last_click_pos.v = -1;
                click_pos = -1;
            }
        }

        // carry over the last move
        if (click_pos != -1) {
            last_click_pos.v = click_pos;
        }

        // collect moves of selected piece
        for (0..all_moves.items.len) |i| {
            if (last_click_pos.v == all_moves.items[i].x1 + all_moves.items[i].y1 * 8) {
                try visible_moves.append(all_moves.items[i].x2 + all_moves.items[i].y2 * 8);
            }
        }

        // draw pieces and fields
        var x: i32 = 0;
        var y: i32 = 0;
        while (x < 8) : (x += 1) {
            y = 0;
            while (y < 8) : (y += 1) {
                const xmin = size * (7 - x);
                const ymin = size * (7 - y);

                if (last_click_pos.v == y * 8 + x) {
                    ray.DrawRectangle(xmin, ymin, size, size, ray.DARKBLUE);
                } else if (@mod(x + y, 2) == 0) {
                    ray.DrawRectangle(xmin, ymin, size, size, white_board_tile_color);
                } else {
                    ray.DrawRectangle(xmin, ymin, size, size, black_board_tile_color);
                }

                const field_value = board.get(@intCast(x), @intCast(y));
                if (field_value != 0) {
                    ray.DrawTextureEx(textures_pieces[@intCast(field_value - 1)], ray.Vector2{ .x = @floatFromInt(xmin), .y = @floatFromInt(ymin) }, 0, @as(f32, @floatFromInt(size)) / 480.0, ray.WHITE);
                }
            }
        }

        x = 0;
        while (x < 8) : (x += 1) {
            y = 0;
            while (y < 8) : (y += 1) {
                const xmin = size * (7 - x);
                const ymin = size * (7 - y);

                for (0..visible_moves.items.len) |i| {
                    if (visible_moves.items[i] == y * 8 + x) {
                        ray.DrawCircle(xmin + @divTrunc(size, 2), ymin + @divTrunc(size, 2), @floatFromInt(@divTrunc(size, 6)), ray.DARKBLUE);
                    }
                }
            }
        }
    }
}

fn inverse_board(board: Board_s, result: *[64]i32) void {
    for (0..8) |x| {
        for (0..4) |y| {
            result[x + y * 8] = board.pieces[x + (7 - y) * 8];
        }
    }
}

fn get_board_768(p64: [64]i32, p768: *[768]nn_type) void {
    for (0..768) |i| {
        if (p64[i % 64] == i % 64) {
            p768[i] = 1;
        } else {
            p768[i] = 0;
        }
    }
}

fn eval_single_position(board: Board_s, model: *nn.Network(nn_type)) !void {
    var flipped_board = mem.zeroes([64]i32);
    var input = mem.zeroes([768]nn_type);
    const result = mem.zeroes([1]nn_type);

    if (board.white_to_move) {
        for (0..board.pieces.len) |i| {
            flipped_board[i] = board.pieces[i];
        }
    } else {
        inverse_board(board, &flipped_board);
    }
    get_board_768(flipped_board, &input);
    try model.fp(&input, @constCast(&result), @constCast(&result));
}

fn stage_one_train(allocator: std.mem.Allocator) !void {
    // create model
    const T = nn_type;
    var model = nn.Network(T){ .layer = std.ArrayList(nn.LayerType(T)).init(allocator), .Allocator = allocator, .eval = true };
    try model.add_LinearLayer(768, 392, 42);
    try model.add_ReLu(392);
    try model.add_LinearLayer(392, 256, 42);
    try model.add_ReLu(256);
    try model.add_LinearLayer(256, 64, 42);
    try model.add_ReLu(64);
    try model.add_LinearLayer(64, 1, 42);
    try model.add_MSE(1);

    const board = Board_s.init();
    try eval_single_position(board, &model);

    return;
}

pub fn main() !void {
    print("compiles...", .{});
    try stage_one_train(gpa);
    const screenWidth = 1000;
    const screenHeight = 1000;
    const tile_size = 125;

    // declare allocator
    var board = Board_s.init();
    board.white_castled = true;
    ray.InitWindow(screenWidth, screenHeight, "");
    defer ray.CloseWindow();

    ray.SetTargetFPS(30);

    try load_piece_textures();

    while (!ray.WindowShouldClose()) {
        ray.BeginDrawing();
        defer ray.EndDrawing();

        try visualize(&board, tile_size);
    }
}
