const std = @import("std");
const mem = @import("../std.zig").mem;

const testing = std.testing;
const debug = std.debug;

pub fn ArrayList(comptime T: type) type {
    return ArrayListCustomAllocator(mem.Allocator, T);
}

pub fn AlignedArrayList(comptime T: type, comptime A: u29) type {
    return AlignedArrayListCustomAllocator(mem.Allocator, T, A);
}

pub fn ArrayListCustomAllocator(comptime Allocator: type, comptime T: type) type {
    return AlignedArrayListCustomAllocator(Allocator, T, @alignOf(T));
}

pub fn AlignedArrayListCustomAllocator(comptime Allocator: type, comptime T: type, comptime A: u29) type {
    return struct {
        const Self = @This();
        const Inner = AlignedArrayListNoAllocator(T, A);

        inner: Inner = Inner{},
        allocator: Allocator,

        pub fn deinit(self: *Self) void {
            self.inner.deinit(self.allocator);
        }

        pub fn count(self: Self) usize {
            return self.inner.count();
        }

        pub fn capacity(self: Self) usize {
            return self.inner.capacity();
        }

        pub fn append(self: *Self, item: T) !void {
            try self.inner.append(self.allocator, item);
        }

        pub fn addOne(self: *Self) !*T {
            return try self.inner.addOne(self.allocator);
        }

        pub fn addOneAssumeCapacity(self: *Self) *T {
            return self.inner.addOneAssumeCapacity();
        }

        pub fn ensureCapacity(self: *Self, new_capacity: usize) !void {
            return self.inner.ensureCapacity(self.allocator, new_capacity);
        }
    };
}

pub fn ArrayListNoAllocator(comptime T: type) type {
    return AlignedArrayListNoAllocator(T, @alignOf(T));
}

pub fn AlignedArrayListNoAllocator(comptime T: type, comptime A: u29) type {
    return struct {
        const Self = @This();

        items: []align(A) T = &[_]T{},
        len: usize = 0,

        pub fn deinit(self: *Self, allocator: var) void {
            mem.free(allocator, self.items);
            self.* = undefined;
        }

        pub fn count(self: Self) usize {
            return self.len;
        }

        pub fn capacity(self: Self) usize {
            return self.items.len;
        }

        pub fn append(self: *Self, allocator: var, item: T) !void {
            const new_item_ptr = try self.addOne(allocator);
            new_item_ptr.* = item;
        }

        pub fn addOne(self: *Self, allocator: var) !*T {
            const new_length = self.len + 1;
            try self.ensureCapacity(allocator, new_length);
            return self.addOneAssumeCapacity();
        }

        pub fn addOneAssumeCapacity(self: *Self) *T {
            debug.assert(self.count() < self.capacity());
            defer self.len += 1;
            return &self.items[self.len];
        }

        pub fn ensureCapacity(self: *Self, allocator: var, new_capacity: usize) !void {
            var better_capacity = self.capacity();
            if (better_capacity >= new_capacity)
                return;

            while (true) {
                better_capacity += better_capacity / 2 + 8;
                if (better_capacity >= new_capacity)
                    break;
            }
            self.items = try mem.alignedRealloc(allocator, T, A, self.items, better_capacity);
        }
    };
}

test "std.ArrayList.init" {
    var bytes: [1024]u8 = undefined;
    var fba = mem.FixedBufferAllocator{ .buffer = bytes[0..] };

    var list = ArrayList(i32){ .allocator = mem.Allocator.init(&fba) };
    defer list.deinit();

    testing.expectEqual(@as(usize, 0), list.count());
    testing.expectEqual(@as(usize, 0), list.capacity());
}

test "std.ArrayList.basic" {
    var bytes: [1024]u8 = undefined;
    var fba = mem.FixedBufferAllocator{ .buffer = bytes[0..] };

    var list = ArrayList(i32){ .allocator = mem.Allocator.init(&fba) };
    defer list.deinit();

    {
        var i: usize = 0;
        while (i < 10) : (i += 1) {
            list.append(@intCast(i32, i + 1)) catch @panic("");
        }
    }

    {
        var i: usize = 0;
        while (i < 10) : (i += 1) {
            testing.expectEqual(@intCast(i32, i + 1), list.inner.items[i]);
        }
    }
}
