const std = @import("std");
const print = std.debug.print;

const Pool = @This();

// This code is influenced by the zig std, especially in the "fn spawn"
// It uses FIFO scheduling and agressivly spawns workers whenever there is work to do
// workers are not stored in list but ended whenever there is not more work to do:w

allocator: std.mem.Allocator,
mutex: std.Thread.Mutex = .{},
is_running: bool = false,

max_number_of_workers: u32,
number_of_workers: u32,

process_list: std.ArrayList(runFn),
spawn_config: std.Thread.SpawnConfig = std.Thread.SpawnConfig{ .stacksize = 16 * 1024 * 1024, .allocator = Pool.allocator },

const runFn = *const fn () void;

inline fn wating_process(comptime func: anytype, args: anytype) void {
    @call(.auto, func, args);
}

pub fn init(pool: *Pool, allocator: std.mem.Allocator, max_parralel_jobs: u32) void {
    pool.allocator = allocator;
    pool.max_number_of_workers = max_parralel_jobs;
    pool.process_list = std.ArrayList(runFn).init(allocator);
}

pub fn spawn(pool: *Pool, comptime func: anytype, args: anytype) !void {
    const process_container = struct {
        //pool: *Pool,
        arguments: @TypeOf(args),
        run_field: *const fn () void = runFnx, // This field is needed, because otherwise the function pointer is not extractable after initialization (not a member function)

        pub fn runFnx() void {
            @call(.auto, func, args);
        }
    };

    pool.mutex.lock();
    const process = process_container{ .arguments = args };
    try pool.process_list.append(process.run_field);

    if (pool.number_of_workers < pool.max_number_of_workers) {
        const w_thread = try std.Thread.spawn(pool.spawn_config, worker, .{pool});
        w_thread.detach();
    }
    pool.mutex.unlock();
}

fn worker(pool: *Pool) !void {
    while (true) {
        pool.mutex.lock();

        // kill worker
        if (pool.process_list.items.len == 0) {
            pool.number_of_workers -= 1;
            pool.mutex.unlock();
            return;
        }

        // secure the process
        const process = pool.process_list.pop();

        // spawn more workers
        if (pool.process_list.items.len != 0) {
            for (0..pool.process_list.items.len) |_| {
                if (pool.number_of_workers < pool.max_number_of_workers) {
                    const w_thread = try std.Thread.spawn(pool.spawn_config, worker, .{pool});
                    w_thread.detach();
                    pool.number_of_workers += 1;
                } else {
                    break;
                }
            }
        }

        pool.mutex.unlock();
        @call(.auto, process, .{});
    }
}

fn add(a: i32, b: i32) void {
    print("{}\n", .{a + b});
    return;
}

pub fn main() !void {
    print("compiles...\n", .{});

    var general_purpose_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_alloc.allocator();

    print("{}\n", .{@TypeOf(init)});

    var p: Pool = undefined;
    p.init(gpa, 2);
    try p.spawn(add, .{ 7, 2 });
    //std.time.sleep(10000000000);
    @call(.auto, p.process_list.items[0], .{});
}
