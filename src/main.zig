const std = @import("std");
const ray = @cImport({
    @cInclude("raylib.h");
});
const print = std.debug.print;
const mem = @import("std").mem;

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
        var self = Board_s{ .white_castled = false, .black_castled = false, .pieces = mem.zeroes([64]i32) };

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
};

fn load_piece_textures() !void {
    //const piece_path = "";
    const names: [12][]const u8 = .{ "../images/pieces/kl.png", "../images/pieces/ql.png", "../images/pieces/rl.png", "../images/pieces/bl.png", "../images/pieces/nl.png", "../images/pieces/pl.png", "../images/pieces/kd.png", "../images/pieces/qd.png", "../images/pieces/rd.png", "../images/pieces/bd.png", "../images/pieces/nd.png", "../images/pieces/pd.png" };

    for (0..names.len) |x| {
        textures_pieces[x] = ray.LoadTexture(names[x].ptr);
    }
}

inline fn valid_move(board: Board_s, x: i32, y: i32, white: bool) bool {
    if (x >= 8 or x < 0 or y >= 8 or y < 0) {
        return false;
    }

    const piece = board.pieces[@intCast(y * 8 + x)];

    if (piece == 0) {
        return true;
    }

    if (white) {
        if (piece > 6 and piece < 12) {
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
// TODO add castling
fn possible_moves(board: Board_s) !void {
    var list = std.ArrayList(move).init(gpa);

    for (0..64) |i| {
        if (board.pieces[i] != 0) {
            const x: i32 = @intCast(i % 8);
            const y: i32 = @intCast(i / 8);
            const white = board.pieces[i] < 7;

            // king moves
            if (board.pieces[i] == 1 or board.pieces[i] == 7) {
                const x_change = [_]i32{ 1, -1, 0, 0, 1, 0, -1, 0 };
                const y_change = [_]i32{ 0, 0, 1, -1, 0, 1, 0, -1 };

                for (x_change, y_change) |xc, yc| {
                    if (valid_move(board, x + xc, y + yc, white)) {
                        try list.append(move{ .x1 = x, .y1 = y, .x2 = x + xc, .y2 = y + yc });
                    }
                }
            }

            // add queen moves
            else if (board.pieces[i] == 2 or board.pieces[i] == 8) {
                const x_change = [_]i32{ 1, -1, 0, 0, 1, 0, -1, 0 };
                const y_change = [_]i32{ 0, 0, 1, -1, 0, 1, 0, -1 };

                for (x_change, y_change) |xc, yc| {
                    var x2 = x + xc;
                    var y2 = y + yc;

                    while (valid_move(board, x2, y2, white)) {
                        try list.append(move{ .x1 = x, .y1 = y, .x2 = x2, .y2 = y2 });
                        x2 = x2 + xc;
                        y2 = y2 + yc;
                    }
                }
            }

            // add rook moves
            else if (board.pieces[i] == 3 or board.pieces[i] == 9) {}
            // add bishop moves
            else if (board.pieces[i] == 4 or board.pieces[i] == 10) {}
            // add knight moves
            else if (board.pieces[i] == 5 or board.pieces[i] == 11) {}
            // add pawn white moves
            else if (board.pieces[i] == 6) {}
            // add pawn black moves
            else if (board.pieces[i] == 12) {}
        }
    }
    print("{}\n", .{list.items.len});
    for (0..list.items.len) |i| {
        const x = list.items[i];
        print("{},{} - {},{} | ", .{ x.x1, x.y1, x.x2, x.y2 });
    }
}
fn draw_board(size: i32, board: Board_s, tiles: [64]i32) void {
    const white_board_tile_color = ray.GetColor(white_color);
    const black_board_tile_color = ray.GetColor(black_color);

    var x: i32 = 0;
    var y: i32 = 0;
    while (x < 8) : (x += 1) {
        y = 0;
        while (y < 8) : (y += 1) {
            const xmin = size * (7 - x);
            const ymin = size * (7 - y);

            if (tiles[@intCast(x + y * 8)] == 1) {
                ray.DrawRectangle(xmin, ymin, size, size, ray.SKYBLUE);
            } else if (@mod(x + y, 2) == 0) {
                ray.DrawRectangle(xmin, ymin, size, size, white_board_tile_color);
            } else {
                ray.DrawRectangle(xmin, ymin, size, size, black_board_tile_color);
            }

            const field_value = board.get(@intCast(x), @intCast(y));
            if (field_value != 0) {
                ray.DrawTextureEx(textures_pieces[@intCast(field_value - 1)], ray.Vector2{ .x = @floatFromInt(xmin), .y = @floatFromInt(ymin) }, 0, 0.15, ray.WHITE);
            }
        }
    }
}

// TODO write view
// field 0|0 is bottom left
fn visualize(){}

pub fn main() !void {
    const screenWidth = 1000;
    const screenHeight = 1000;
    const tile_size = 70;

    // declare allocator
    var board = Board_s.init();
    ray.InitWindow(screenWidth, screenHeight, "");
    defer ray.CloseWindow();

    ray.SetTargetFPS(30);

    try load_piece_textures();

    var tiles = mem.zeroes([64]i32);
    var last_pos = tile_pos{ .x = 255, .y = 255 };
    var empty_click = true;

    while (!ray.WindowShouldClose()) {
        if (ray.IsMouseButtonPressed(ray.MOUSE_BUTTON_LEFT) or ray.IsMouseButtonPressed(ray.MOUSE_BUTTON_RIGHT)) {
            // reset board
            tiles = mem.zeroes([64]i32);

            const mouse_pos = ray.GetMousePosition();
            var x: i32 = 0;
            var y: i32 = 0;

            try possible_moves(board);

            while (x < 8) : (x += 1) {
                y = 0;
                while (y < 8) : (y += 1) {
                    const xmin: f32 = @floatFromInt(tile_size * x);
                    const ymin: f32 = @floatFromInt(tile_size * y);

                    if (xmin < mouse_pos.x and xmin + tile_size > mouse_pos.x and ymin < mouse_pos.y and ymin + tile_size > mouse_pos.y) {
                        const p1 = board.get(x, y);

                        if (!empty_click) {
                            const p2 = board.get(last_pos.x, last_pos.y);

                            board.set(x, y, p2);
                            board.set(last_pos.x, last_pos.y, 0);
                            empty_click = true;
                        } else {
                            empty_click = (p1 == 0);
                        }
                        print("tile: {} {}", .{ x, y });
                        tiles[@intCast(x + 8 * y)] = 1;
                        last_pos.x = @intCast(x);
                        last_pos.y = @intCast(y);
                    }
                }
            }
        }

        // start drawing
        ray.BeginDrawing();
        defer ray.EndDrawing();

        ray.ClearBackground(ray.RAYWHITE);
        draw_board(tile_size, board, tiles);
    }
}
