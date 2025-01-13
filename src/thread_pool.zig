const std = @import("std");
const print = std.debug.print;
const stdout = std.io.getStdOut().writer();

pub const Pool = @This();

// This code is influenced by the zig std, especially in the "fn spawn"
// It uses FIFO scheduling and agressivly spawns workers whenever there is work to do
// workers are not stored in list but ended whenever there is not more work to do:w

allocator: std.mem.Allocator,
mutex_ressources: std.Thread.Mutex = .{},
sem_running: std.Thread.Semaphore = .{},

max_number_of_workers: u32,
number_of_workers: u32,

process_list: std.ArrayList(*fnstruct),
spawn_config: std.Thread.SpawnConfig,

const fnstruct = struct {
    fnpointer: *const fn (*fnstruct) void,
};

inline fn wating_process(comptime func: anytype, args: anytype) void {
    @call(.auto, func, args);
}

pub fn init(pool: *Pool, allocator: std.mem.Allocator, max_number_of_workers: u32) void {
    pool.allocator = allocator;
    pool.max_number_of_workers = max_number_of_workers;
    pool.number_of_workers = 0;
    pool.sem_running.permits = 1;
    pool.process_list = std.ArrayList(*fnstruct).init(allocator);
    pool.spawn_config = std.Thread.SpawnConfig{ .stack_size = 100 * 1024 * 1024, .allocator = allocator };
}

// this function needs to be always under a mutex lock
fn run_control(pool: *Pool) void {
    if (pool.number_of_workers == 0) {
        pool.sem_running.post();
    } else {
        pool.sem_running.permits = 0;
    }
}

pub fn finish(pool: *Pool) void {
    pool.sem_running.wait();
}

pub fn spawn(pool: *Pool, comptime func: anytype, args: anytype) !void {
    const process_container = struct {
        arguments: @TypeOf(args),
        pools: *Pool,
        run_field: fnstruct = .{ .fnpointer = runFn },

        pub fn runFn(fnp: *fnstruct) void {
            const self: *@This() = @fieldParentPtr("run_field", fnp);
            @call(.auto, func, self.arguments);
            self.pools.allocator.destroy(self);
        }
    };

    pool.mutex_ressources.lock();

    const process: *process_container = try pool.allocator.create(process_container);
    process.* = .{ .arguments = args, .pools = pool };
    try pool.process_list.append(&process.run_field);

    if (pool.number_of_workers < pool.max_number_of_workers) {
        const w_thread = try std.Thread.spawn(pool.spawn_config, worker, .{pool});
        //print("created worker thread \n", .{});
        w_thread.detach();
        pool.number_of_workers += 1;
        pool.run_control();
    }

    pool.mutex_ressources.unlock();
}

fn worker(pool: *Pool) void {
    while (true) {
        pool.mutex_ressources.lock();

        // kill worker
        if (pool.process_list.items.len == 0) {
            pool.number_of_workers -= 1;
            pool.run_control();
            pool.mutex_ressources.unlock();
            return;
        }

        // secure the process
        const process = pool.process_list.pop();

        // spawn more workers
        if (pool.process_list.items.len != 0) {
            for (0..pool.process_list.items.len) |_| {
                if (pool.number_of_workers < pool.max_number_of_workers) {
                    const w_thread = std.Thread.spawn(pool.spawn_config, worker, .{pool}) catch |err| {
                        print("Failed to create thread: {}\n", .{err});
                        pool.process_list.append(process) catch break;
                        break;
                    };
                    w_thread.detach();
                    pool.number_of_workers += 1;
                } else {
                    break;
                }
            }
        }
        pool.mutex_ressources.unlock();
        @call(.auto, process.fnpointer, .{process});
    }
}

fn add(a: i32, b: i32) void {
    stdout.print("{}\n", .{a + b}) catch return;
    return;
}

pub fn main() !void {
    print("compiles...\n", .{});

    var general_purpose_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_alloc.allocator();

    var p: Pool = undefined;
    p.init(gpa, 3);
    try p.spawn(add, .{ 7, 2 });
    try p.spawn(add, .{ 9, 2 });
    print("before finish \n", .{});
    p.finish();
    //@call(.auto, p.process_list.items[0], .{});
}
