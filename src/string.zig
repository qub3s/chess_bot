const std = @import("std");
const print = std.debug.print;

var general_purpose_alloc = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = general_purpose_alloc.allocator();

pub const String = struct {
    str: []u8,
    pub var String_alloc: std.mem.Allocator = undefined;

    pub fn init_s(s: []const u8) !String {
        const ns = try String_alloc.alloc(u8, s.len);
        @memcpy(ns, s);
        return String{ .str = ns };
    }

    pub fn init(s: []u8) !String {
        const ns = try String_alloc.alloc(u8, s.len);
        @memcpy(ns, s);
        return String{ .str = ns };
    }

    // print string content
    pub fn print(self: *const String) void {
        std.debug.print("{s}", .{self.str});
    }

    // print string and write new line
    pub fn println(self: *const String) void {
        std.debug.print("{s}\n", .{self.str});
    }

    // remove all occurences
    pub fn remove(self: *const String, remove_string: String) !void {
        var results = std.ArrayList(u32).init(String_alloc);
        defer results.deinit();

        try self.find(remove_string, &results);

        if (results.items.len == 0) {
            return;
        }

        var new_string = try String_alloc.alloc(u8, self.str.len - remove_string.str.len * results.items.len);

        var sc: usize = 0;
        var rc: usize = 0;
        var nstc: usize = 0;

        while (sc < self.str.len) {
            if (results.items[rc] == sc) {
                if (rc + 1 < results.items.len) {
                    rc += 1;
                }
                sc += remove_string.str.len;
            } else {
                new_string[nstc] = self.str[sc];
                nstc += 1;
                sc += 1;
            }
        }

        @constCast(self).str = new_string;
    }

    // remove the string and returns arraylist
    pub fn split(self: *const String, remove_string: String, results: *std.ArrayList(String)) !void {
        var res = std.ArrayList(u32).init(String_alloc);
        defer res.deinit();

        try self.find(remove_string, &res);

        try results.append(try String.init(self.str[0..res.items[0]]));

        var i: usize = 1;
        while (i < res.items.len) {
            try results.append(try String.init(self.str[res.items[i - 1] + remove_string.str.len .. res.items[i]]));
            i += 1;
        }

        try results.append(try String.init(self.str[res.items[i - 1] + remove_string.str.len .. self.str.len]));
    }

    // replace the strings
    pub fn replace(self: *const String, remove_string: String, replace_string: String) !void {
        var results = std.ArrayList(u32).init(String_alloc);
        defer results.deinit();

        try self.find(remove_string, &results);

        var new_string = try String_alloc.alloc(u8, self.str.len - (replace_string.str.len - remove_string.str.len) * results.items.len);

        var sc: usize = 0;
        var rc: usize = 0;
        var nstc: usize = 0;

        while (sc < self.str.len) {
            if (results.items[rc] == sc) {
                if (rc + 1 < results.items.len) {
                    rc += 1;
                }

                for (replace_string) |c| {
                    new_string[nstc] = c;
                    nstc += 1;
                }
                sc += remove_string.str.len;
            } else {
                new_string[nstc] = self.str[sc];
                nstc += 1;
                sc += 1;
            }
        }

        @constCast(self).str = new_string;
    }
    // KMP Algorithm
    pub fn find(self: *const String, search_string: String, results: *std.ArrayList(u32)) !void {
        // pre processing jumps
        var ppj = try String_alloc.alloc(i32, search_string.str.len + 1);
        defer String_alloc.free(ppj);

        var i: i32 = 0;
        var j: i32 = -1;

        ppj[0] = -1;

        while (i < search_string.str.len) {
            while (j >= 0 and search_string.str[@intCast(i)] != search_string.str[@intCast(j)]) {
                j = ppj[@intCast(j)];
            }

            i = i + 1;
            j = j + 1;
            ppj[@intCast(i)] = j;
        }

        j = 0;
        i = 0;

        while (i < self.str.len) {
            while (j >= 0 and self.str[@intCast(i)] != search_string.str[@intCast(j)]) {
                j = ppj[@intCast(j)];
            }

            i += 1;
            j += 1;

            if (j == search_string.str.len) {
                try results.append(@intCast(i - @as(i32, @intCast(search_string.str.len))));
                j = ppj[@intCast(j)];
            }
        }
    }

    pub fn deinit(self: *const String) void {
        String_alloc.free(self.str);
    }
};

pub fn main() !void {
    String.String_alloc = gpa;
    const s = try String.init_s("dasa bcist abcon eabcea de");

    defer s.deinit();

    const search = try String.init_s(" ");
    defer search.deinit();

    var results = std.ArrayList(u32).init(gpa);
    defer results.deinit();

    var list = std.ArrayList(String).init(gpa);
    defer list.deinit();

    try s.split(search, &list);
    try s.find(search, &results);

    s.println();
    try s.remove(search);
    s.println();

    for (results.items) |x| {
        std.debug.print("{}\n", .{x});
    }

    std.debug.print("split list:\n", .{});

    for (list.items) |x| {
        std.debug.print("String: ", .{});
        x.pln();
    }
}
