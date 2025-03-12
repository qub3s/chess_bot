const std = @import("std");
const mem = @import("std").mem;

pub const ray = @cImport({
    @cInclude("raylib.h");
});

const logic = @import("logic.zig");
const bb = @import("bitboard.zig");

var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = general_purpose_allocator.allocator();

var textures_pieces: [12]ray.Texture = undefined;

// board colors
const black_color: u32 = 0xf0d9b5ff;
const white_color: u32 = 0xb58863ff;

pub var vis_thread: bool = false;

pub fn load_piece_textures() !void {
    const names: [12][]const u8 = .{ "images/pieces/kl.png", "images/pieces/ql.png", "images/pieces/rl.png", "images/pieces/bl.png", "images/pieces/nl.png", "images/pieces/pl.png", "images/pieces/kd.png", "images/pieces/qd.png", "images/pieces/rd.png", "images/pieces/bd.png", "images/pieces/nd.png", "images/pieces/pd.png" };

    for (0..names.len) |x| {
        textures_pieces[x] = ray.LoadTexture(names[x].ptr);
    }
}

pub fn visualize_bb(board: *bb.bitboard, size: i32) !void {
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

    //var visible_moves = std.ArrayList(bb.bitboard).init(gpa);
    var all_moves: [256]bb.bitboard = undefined;
    var number_of_moves: usize = 0;
    try board.gen_moves(&all_moves, &number_of_moves);

    //std.debug.print("{}\n", .{all_moves.items.len});

    if (click_pos != -1 or first_draw.v) {
        first_draw.v = false;

        // check if move is valid
        if (last_click_pos.v != -1) {
            var temp: i32 = -1;
            const new_gamestate = board.make_hypothetical_moves(@intCast(last_click_pos.v), @intCast(click_pos));

            for (0..number_of_moves + 1) |i| {
                if (all_moves[i].equal(new_gamestate)) {
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
                board.* = board.make_hypothetical_moves(@intCast(last_click_pos.v), @intCast(click_pos));
                last_click_pos.v = -1;
                click_pos = -1;
            }
        }

        // carry over the last move
        if (click_pos != -1) {
            last_click_pos.v = click_pos;
        }
    }

    ray.ClearBackground(ray.RAYWHITE);
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
            } else if (@mod(x + y, 2) != 0) {
                ray.DrawRectangle(xmin, ymin, size, size, white_board_tile_color);
            } else {
                ray.DrawRectangle(xmin, ymin, size, size, black_board_tile_color);
            }

            const field_value = board.get_square_value(@intCast(x + y * 8));
            if (field_value != -1) {
                ray.DrawTextureEx(textures_pieces[@intCast(field_value)], ray.Vector2{ .x = @floatFromInt(xmin), .y = @floatFromInt(ymin) }, 0, @as(f32, @floatFromInt(size)) / 480.0, ray.WHITE);
            }
        }
    }

    // collect moves of selected piece
    //for (0..all_moves.items.len) |i| {
    //    if (last_click_pos.v == all_moves.items[i].x1 + all_moves.items[i].y1 * 8) {
    //        try visible_moves.append(all_moves.items[i].x2 + all_moves.items[i].y2 * 8);
    //    }
    //}

    x = 0;
    while (x < 8) : (x += 1) {
        y = 0;
        while (y < 8) : (y += 1) {
            //const xmin = size * (7 - x);
            //const ymin = size * (7 - y);

            //for (0..visible_moves.items.len) |i| {
            //    if (visible_moves.items[i] == y * 8 + x) {
            //        ray.DrawCircle(xmin + @divTrunc(size, 2), ymin + @divTrunc(size, 2), @floatFromInt(@divTrunc(size, 6)), ray.DARKBLUE);
            //    }
            //}
        }
    }
}

pub fn visualize(board: *logic.Board_s, size: i32) !void {
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

    var visible_moves = std.ArrayList(i32).init(gpa);
    var all_moves = std.ArrayList(logic.move).init(gpa);
    try board.possible_moves(&all_moves);

    if (click_pos != -1 or first_draw.v) {
        first_draw.v = false;

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
                board.make_move(@intCast(last_click_pos.v), @intCast(click_pos));
                last_click_pos.v = -1;
                click_pos = -1;
            }
        }

        // carry over the last move
        if (click_pos != -1) {
            last_click_pos.v = click_pos;
        }
    }

    ray.ClearBackground(ray.RAYWHITE);
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
            } else if (@mod(x + y, 2) != 0) {
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

    // collect moves of selected piece
    for (0..all_moves.items.len) |i| {
        if (last_click_pos.v == all_moves.items[i].x1 + all_moves.items[i].y1 * 8) {
            try visible_moves.append(all_moves.items[i].x2 + all_moves.items[i].y2 * 8);
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

fn vis_board_bb(board: *bb.bitboard) void {
    const screenWidth = 1000;
    const screenHeight = 1000;
    const tile_size = 125;

    ray.InitWindow(screenWidth, screenHeight, "");
    defer ray.CloseWindow();
    load_piece_textures() catch return;
    ray.SetTargetFPS(30);

    vis_thread = true;

    while (!ray.WindowShouldClose()) {
        ray.BeginDrawing();
        defer ray.EndDrawing();
        visualize_bb(board, tile_size) catch return;
    }

    vis_thread = false;
}

fn vis_board(board: *logic.Board_s) void {
    const screenWidth = 1000;
    const screenHeight = 1000;
    const tile_size = 125;

    ray.InitWindow(screenWidth, screenHeight, "");
    defer ray.CloseWindow();
    load_piece_textures() catch return;
    ray.SetTargetFPS(30);

    vis_thread = true;

    while (!ray.WindowShouldClose()) {
        ray.BeginDrawing();
        defer ray.EndDrawing();
        visualize(board, tile_size) catch return;
    }

    vis_thread = false;
}
