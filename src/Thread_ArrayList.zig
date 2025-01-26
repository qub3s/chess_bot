const std = @import("std");

const print = std.debug.print;

pub fn Thread_ArrayList(comptime T: type) type {
    return struct {
        list: std.ArrayList(T),
        mutex_ressources: std.Thread.Mutex = .{},
        sem: std.Thread.Semaphore = .{},

        pub fn init(allocator: std.mem.Allocator) Thread_ArrayList(T) {
            return Thread_ArrayList(T){ .list = std.ArrayList(T).init(allocator) };
        }

        pub fn deinit(self: *@This()) Thread_ArrayList(T) {
            self.list.deinit();
        }

        pub fn append(self: *@This(), inp: T) !void {
            if (!self.mutex_ressources.tryLock()) {
                self.mutex_ressources.lock();
                std.debug.print("failed lock\n", .{});
            }
            try self.list.append(inp);
            self.mutex_ressources.unlock();
            self.sem.post();
        }

        pub fn pop(self: *@This()) !T {
            self.sem.wait();
            if (!self.mutex_ressources.tryLock()) {
                self.mutex_ressources.lock();
                std.debug.print("failed lock\n", .{});
            }

            const ret = self.list.pop();
            self.mutex_ressources.unlock();

            return ret;
        }
    };
}
