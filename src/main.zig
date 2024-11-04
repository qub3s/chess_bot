const std = @import("std");
const ray = @cImport({
    @cInclude("raylib.h");
});
const print = std.debug.print;
const mem = @import("std").mem;

// board colors
const black_color: u32 = 0xf0d9b5ff;
const white_color: u32 = 0xb58863ff;

// piece_graphices
var textures_pieces: [12]ray.Texture = undefined;

// empty = 0, wking = 1, wqueen = 2, wrook = 3, wbishop = 4, wknight = 5, wpawn = 6, bking = 7 ...
const Board_s = struct {
    white_castled: bool,
    black_castled: bool,
    piece_pos: [64]u8,

    pub fn nothing(self: Board_s) Board_s {
        return self;
    }

    pub fn set(self: *Board_s, x: u32, y: u32, value: u8) void {
        self.piece_pos[y * 8 + x] = value;
    }

    pub fn get(self: *const Board_s, x: u32, y: u32) u8 {
        return self.piece_pos[y * 8 + x];
    }

    pub fn init() Board_s {
        var self = Board_s{ .white_castled = false, .black_castled = false, .piece_pos = mem.zeroes([64]u8) };

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

fn draw_board(size: i32, board: Board_s) void {
    const white_board_tile_color = ray.GetColor(white_color);
    const black_board_tile_color = ray.GetColor(black_color);

    var x: i32 = 0;
    var y: i32 = 0;
    while (x < 8) : (x += 1) {
        y = 0;
        while (y < 8) : (y += 1) {
            const xmin = size * x;
            const ymin = size * y;

            if (@mod(x + y, 2) == 0) {
                ray.DrawRectangle(xmin, ymin, size, size, white_board_tile_color);
            } else {
                ray.DrawRectangle(xmin, ymin, size, size, black_board_tile_color);
            }

            const field_value = board.get(@intCast(x), @intCast(y));
            if (field_value != 0) {
                ray.DrawTextureEx(textures_pieces[field_value - 1], ray.Vector2{ .x = @floatFromInt(xmin), .y = @floatFromInt(ymin) }, 0, 0.15, ray.WHITE);
            }
        }
    }
}

pub fn main() !void {
    const screenWidth = 1000;
    const screenHeight = 1000;

    // declare allocator
    //var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    //const gpa = general_purpose_allocator.allocator();

    const board = Board_s.init();
    //board = board.nothing();

    ray.InitWindow(screenWidth, screenHeight, "");
    defer ray.CloseWindow();

    ray.SetTargetFPS(30);

    try load_piece_textures();

    while (!ray.WindowShouldClose()) {
        ray.BeginDrawing();
        defer ray.EndDrawing();

        ray.ClearBackground(ray.RAYWHITE);
        draw_board(70, board);
    }
}
