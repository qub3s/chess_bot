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
const c_texture_raylib = extern struct { id: u32, width: i32, height: i32, mipmaps: i32, format: i32 };
var textures: [12]ray.Texture = undefined;

// empty = 0, wking = 1, wqueen = 2, wrook = 3, wbishop = 4, wknight = 5, wpawn = 6, bking = 7 ...
const board = struct {
    const white_castled = false;
    const black_castled = false;
    const piece_pos = [_]u8{0} ** 10;

    pub inline fn get(self: board, comptime T: type, x: T, y: T) *T {
        return &self.piece_pos[y * 8 + x];
    }

    pub fn init_piece_pos(self: board) void {
        // white pieces
        self.piece_pos.get(i32, 0, 0).* = 3;
        self.piece_pos.get(i32, 1, 0).* = 5;
        self.piece_pos.get(i32, 2, 0).* = 4;
        self.piece_pos.get(i32, 3, 0).* = 2;
        self.piece_pos.get(i32, 4, 0).* = 1;
        self.piece_pos.get(i32, 5, 0).* = 4;
        self.piece_pos.get(i32, 6, 0).* = 5;
        self.piece_pos.get(i32, 7, 0).* = 3;

        // black pieces
        self.piece_pos.get(i32, 0, 7).* = 9;
        self.piece_pos.get(i32, 1, 7).* = 11;
        self.piece_pos.get(i32, 2, 7).* = 10;
        self.piece_pos.get(i32, 3, 7).* = 8;
        self.piece_pos.get(i32, 4, 7).* = 7;
        self.piece_pos.get(i32, 5, 7).* = 10;
        self.piece_pos.get(i32, 6, 7).* = 11;
        self.piece_pos.get(i32, 7, 7).* = 9;

        // pawns
        for (0..7) |x| {
            self.piece_pos.get(usize, x, 0).* = 6;
            self.piece_pos.get(usize, x, 7).* = 12;
        }
    }
};

fn load_piece_textures(gpa: std.mem.Allocator) !void {
    const piece_path = "../images/pieces/";
    const names: [12][]const u8 = .{ "kl.png", "ql.png", "rl.png", "bl.png", "nl.png", "pl.png", "kd.png", "qd.png", "rd.png", "bd.png", "nd.png", "pd.png" };

    // allocator
    for (0..names.len) |x| {
        const path = try gpa.alloc(u8, piece_path.len + names[x].len);
        @memcpy(path[0..piece_path.len], piece_path);
        @memcpy(path[piece_path.len..], names[x]);

        var image: [*]ray.struct_Image = ray.LoadImage(path.ptr);
        image = ray.ImageResize(image, 120, 120);
        textures[x] = ray.LoadTextureFromImage(image);

        gpa.free(path);
    }
}

fn draw_board() void {
    const white_board_tile_color = ray.GetColor(white_color);
    const black_board_tile_color = ray.GetColor(black_color);

    var x: i32 = 0;
    var y: i32 = 0;
    const size: i32 = 50;
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
        }
    }
}

pub fn main() !void {
    const screenWidth = 800;
    const screenHeight = 600;

    //var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    //const gpa = general_purpose_allocator.allocator();

    //try load_piece_textures(gpa);

    ray.InitWindow(screenWidth, screenHeight, "");
    defer ray.CloseWindow();

    ray.SetTargetFPS(30);

    while (!ray.WindowShouldClose()) {
        ray.BeginDrawing();
        defer ray.EndDrawing();
        ray.ClearBackground(ray.RAYWHITE);

        const image = ray.LoadTexture("../images/pieces/kl.png");
        //image = ray.ImageResize(image, 120, 120);
        ray.DrawTexture(image, 200, 200, ray.WHITE);

        draw_board();
    }
}
