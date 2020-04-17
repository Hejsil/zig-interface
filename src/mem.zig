const std = @import("std");
const builtin = @import("builtin");
const vtable = @import("vtable.zig");

const testing = std.testing;
const math = std.math;
const debug = std.debug;
const mem = @This();

const TypeInfo = builtin.TypeInfo;

pub const AllocError = error{OutOfMemory};

pub const Allocator = struct {
    const VTable = struct {
        pub const Impl = @OpaqueType();

        /// Allocate byte_count bytes and return them in a slice, with the
        /// slice's pointer aligned at least to alignment bytes.
        /// The returned newly allocated memory is undefined.
        /// `alignment` is guaranteed to be >= 1
        /// `alignment` is guaranteed to be a power of 2
        alloc: fn (allocator: *Impl, byte_count: usize, alignment: u29) AllocError![]u8,

        /// If `new_byte_count > old_mem.len`:
        /// * `old_mem.len` is the same as what was returned from allocFn or reallocFn.
        /// * alignment >= alignment of old_mem.ptr
        ///
        /// If `new_byte_count <= old_mem.len`:
        /// * this function must return successfully.
        /// * alignment <= alignment of old_mem.ptr
        ///
        /// When `reallocFn` returns,
        /// `return_value[0..min(old_mem.len, new_byte_count)]` must be the same
        /// as `old_mem` was when `reallocFn` is called. The bytes of
        /// `return_value[old_mem.len..]` have undefined values.
        /// `alignment` is guaranteed to be >= 1
        /// `alignment` is guaranteed to be a power of 2
        realloc: fn (allocator: *Impl, old_mem: []u8, new_byte_count: usize, alignment: u29) AllocError![]u8,

        /// Guaranteed: `old_mem.len` is the same as what was returned from `allocFn` or `reallocFn`
        free: fn (allocator: *Impl, old_mem: []u8) void,
    };

    vtable: *const VTable,
    impl: *VTable.Impl,

    pub fn init(allocator: var) Allocator {
        const T = @TypeOf(allocator).Child;
        return Allocator{
            .vtable = comptime vtable.populate(VTable, T, T),
            .impl = @ptrCast(*VTable.Impl, allocator),
        };
    }

    pub fn alloc(allocator: Allocator, n: usize, alignment: u29) AllocError![]u8 {
        return allocator.vtable.alloc(allocator.impl, n, alignment);
    }

    pub fn realloc(allocator: Allocator, old_mem: []u8, new_size: usize, alignment: u29) AllocError![]u8 {
        return allocator.vtable.realloc(allocator.impl, old_mem, new_size, alignment);
    }

    pub fn free(allocator: Allocator, bytes: []u8) void {
        return allocator.vtable.free(allocator.impl, bytes);
    }
};

test "mem.Allocator" {
    var buf: [1024]u8 = undefined;
    var fba = FixedBufferAllocator{ .buffer = buf[0..] };
    const allocator = Allocator.init(&fba);

    var t = try mem.alloc(allocator, u8, 10);
    testing.expectEqual(@as(usize, 10), t.len);
    testing.expectEqual(@as(usize, 10), fba.end_index);

    t = try mem.realloc(allocator, u8, t, 5);
    testing.expectEqual(@as(usize, 5), t.len);
    testing.expectEqual(@as(usize, 10), fba.end_index);

    t = try mem.realloc(allocator, u8, t, 20);
    testing.expectEqual(@as(usize, 20), t.len);
    testing.expectEqual(@as(usize, 30), fba.end_index);

    mem.free(allocator, t);
    testing.expectEqual(@as(usize, 20), t.len);
    testing.expectEqual(@as(usize, 30), fba.end_index);
}

pub const FixedBufferAllocator = struct {
    buffer: []u8,
    end_index: usize = 0,

    pub fn alloc(allocator: *FixedBufferAllocator, n: usize, alignment: u29) AllocError![]u8 {
        const addr = @ptrToInt(allocator.buffer.ptr) + allocator.end_index;
        const rem = @rem(addr, alignment);
        const march_forward_bytes = if (rem == 0) 0 else (alignment - rem);
        const adjusted_index = allocator.end_index + march_forward_bytes;
        const new_end_index = adjusted_index + n;
        if (new_end_index > allocator.buffer.len)
            return error.OutOfMemory;

        const result = allocator.buffer[adjusted_index..new_end_index];
        allocator.end_index = new_end_index;

        return result;
    }

    pub fn realloc(allocator: *FixedBufferAllocator, old_mem: []u8, new_size: usize, alignment: u29) AllocError![]u8 {
        debug.assert(old_mem.len <= allocator.end_index);
        if (new_size <= old_mem.len) {
            return old_mem[0..new_size];
        } else if (old_mem.ptr == allocator.buffer.ptr + allocator.end_index - old_mem.len) {
            const start_index = allocator.end_index - old_mem.len;
            const new_end_index = start_index + new_size;
            if (new_end_index > allocator.buffer.len) return error.OutOfMemory;
            const result = allocator.buffer[start_index..new_end_index];
            allocator.end_index = new_end_index;
            return result;
        } else {
            const result = try alloc(allocator, new_size, alignment);
            std.mem.copy(u8, result, old_mem);
            return result;
        }
    }

    pub fn free(allocator: *FixedBufferAllocator, bytes: []u8) void {}
};

test "mem.FixedBufferAllocator" {
    var buf: [1024]u8 = undefined;
    var fba = FixedBufferAllocator{ .buffer = buf[0..] };

    var t = try fba.alloc(10, 1);
    testing.expectEqual(@as(usize, 10), t.len);
    testing.expectEqual(@as(usize, 10), fba.end_index);

    t = try fba.realloc(t, 5, 1);
    testing.expectEqual(@as(usize, 5), t.len);
    testing.expectEqual(@as(usize, 10), fba.end_index);

    t = try fba.realloc(t, 20, 1);
    testing.expectEqual(@as(usize, 20), t.len);
    testing.expectEqual(@as(usize, 30), fba.end_index);

    fba.free(t);
    testing.expectEqual(@as(usize, 20), t.len);
    testing.expectEqual(@as(usize, 30), fba.end_index);
}

pub fn create(allocator: var, init: var) AllocError!*@TypeOf(init) {
    const T = @TypeOf(init);
    if (@sizeOf(T) == 0)
        return &(T{});

    const slice = try mem.alloc(allocator, T, 1);
    slice[0] = init;
    return &slice[0];
}

test "mem.create" {
    var buf: [@sizeOf(u16)]u8 = undefined;
    var fba = FixedBufferAllocator{ .buffer = buf[0..] };

    testing.expectEqual(@as(u16, 99), (try mem.create(&fba, @as(u16, 99))).*);
    testing.expectError(AllocError.OutOfMemory, mem.create(&fba, @as(u16, 100)));
}

pub fn alloc(allocator: var, comptime T: type, n: usize) AllocError![]T {
    return mem.alignedAlloc(allocator, T, @alignOf(T), n);
}

test "mem.alloc" {
    var buf: [@sizeOf(u16) * 4]u8 = undefined;
    var fba = FixedBufferAllocator{ .buffer = buf[0..] };

    const t = try mem.alloc(&fba, u16, 4);
    testing.expectEqual(@as(usize, 4), t.len);
    testing.expectError(AllocError.OutOfMemory, mem.alloc(&fba, u8, 1));
}

pub fn alignedAlloc(allocator: var, comptime T: type, comptime alignment: u29, n: usize) AllocError![]align(alignment) T {
    if (n == 0)
        return &[_]T{};

    const byte_count = math.mul(usize, @sizeOf(T), n) catch return AllocError.OutOfMemory;
    const byte_slice = try allocator.alloc(byte_count, alignment);
    debug.assert(byte_slice.len == byte_count);

    // This loop gets optimized out in ReleaseFast mode
    for (byte_slice) |*byte|
        byte.* = undefined;

    return std.mem.bytesAsSlice(T, @alignCast(alignment, byte_slice));
}

pub fn realloc(allocator: var, comptime T: type, old_mem: []T, n: usize) AllocError![]T {
    return mem.alignedRealloc(allocator, T, @alignOf(T), @alignCast(@alignOf(T), old_mem), n);
}

test "mem.realloc" {
    var buf: [@sizeOf(u16) * 4]u8 = undefined;
    var fba = FixedBufferAllocator{ .buffer = buf[0..] };

    var t = try mem.alloc(&fba, u8, 4);
    testing.expectEqual(@as(usize, 4), t.len);

    t = try mem.realloc(&fba, u8, t, 2);
    testing.expectEqual(@as(usize, 2), t.len);
    testing.expectError(AllocError.OutOfMemory, mem.realloc(&fba, u8, t, 5));
}

pub fn alignedRealloc(allocator: var, comptime T: type, comptime alignment: u29, old_mem: []align(alignment) T, n: usize) AllocError![]align(alignment) T {
    if (old_mem.len == 0)
        return mem.alignedAlloc(allocator, T, alignment, n);
    if (n == 0) {
        mem.free(allocator, old_mem);
        return &[_]T{};
    }

    const old_byte_slice = std.mem.sliceAsBytes(old_mem);
    const byte_count = math.mul(usize, @sizeOf(T), n) catch return AllocError.OutOfMemory;
    const byte_slice = try allocator.realloc(old_byte_slice, byte_count, alignment);
    debug.assert(byte_slice.len == byte_count);
    if (n > old_mem.len) {
        // This loop gets optimized out in ReleaseFast mode
        for (byte_slice[old_byte_slice.len..]) |*byte|
            byte.* = undefined;
    }

    return std.mem.bytesAsSlice(T, @alignCast(alignment, byte_slice));
}

/// Reallocate, but `n` must be less than or equal to `old_mem.len`.
/// Unlike `realloc`, this function cannot fail.
/// Shrinking to 0 is the same as calling `free`.
pub fn shrink(allocator: var, comptime T: type, old_mem: []T, n: usize) []T {
    return mem.alignedShrink(allocator, T, @alignOf(T), @alignCast(@alignOf(T), old_mem), n);
}

test "mem.shrink" {
    var buf: [@sizeOf(u16) * 4]u8 = undefined;
    var fba = FixedBufferAllocator{ .buffer = buf[0..] };

    var t = try mem.alloc(&fba, u16, 4);
    testing.expectEqual(@as(usize, 4), t.len);

    t = mem.shrink(&fba, u16, t, 2);
    testing.expectEqual(@as(usize, 2), t.len);
}

pub fn alignedShrink(allocator: var, comptime T: type, comptime alignment: u29, old_mem: []align(alignment) T, n: usize) []align(alignment) T {
    if (n == 0) {
        mem.free(allocator, old_mem);
        return old_mem[0..0];
    }

    debug.assert(n <= old_mem.len);

    // Here we skip the overflow checking on the multiplication because
    // n <= old_mem.len and the multiplication didn't overflow for that operation.
    const byte_count = @sizeOf(T) * n;

    const byte_slice = allocator.realloc(std.mem.sliceAsBytes(old_mem), byte_count, alignment) catch unreachable;
    debug.assert(byte_slice.len == byte_count);
    return std.mem.bytesAsSlice(T, @alignCast(alignment, byte_slice));
}

pub fn free(allocator: var, memory: var) void {
    const bytes = std.mem.sliceAsBytes(memory);
    if (bytes.len == 0)
        return;

    const non_const_ptr = @ptrCast([*]u8, bytes.ptr);
    allocator.free(non_const_ptr[0..bytes.len]);
}

test "mem.free" {
    var buf: [@sizeOf(u16) * 4]u8 = undefined;
    var fba = FixedBufferAllocator{ .buffer = buf[0..] };

    var t = try mem.alloc(&fba, u16, 4);
    testing.expectEqual(@as(usize, 4), t.len);
    mem.free(&fba, t);
}
