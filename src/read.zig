const std = @import("std");
const mem = @import("mem.zig");
const vtable = @import("vtable.zig");
const testing = std.testing;
const read = @This();

pub fn Reader(comptime E: type) type {
    return struct {
        pub const Error = E;

        const VTable = struct {
            read: fn (reader: *c_void, buf: []u8) Error![]u8,
        };

        vtable: *const VTable,
        impl: *c_void,

        pub fn init(reader: var) @This() {
            const T = @typeOf(reader).Child;
            return @This(){
                .vtable = comptime vtable.populate(VTable, T, T),
                .impl = @ptrCast(*c_void, reader),
            };
        }

        pub fn read(reader: @This(), buf: []u8) Error![]u8 {
            return reader.vtable.read(reader.impl, buf);
        }
    };
}

test "read.Reader" {
    var buf: [2]u8 = undefined;
    const mr = &MemReader.init("abc");
    const reader = Reader(MemReader.Error).init(mr);
    testing.expectEqualSlices(u8, "ab", try reader.read(buf[0..]));
    testing.expectEqual(usize(2), mr.i);
    testing.expectEqualSlices(u8, "c", try reader.read(buf[0..]));
    testing.expectEqual(usize(3), mr.i);
    testing.expectEqualSlices(u8, "", try reader.read(buf[0..]));
    testing.expectEqual(usize(3), mr.i);
}


pub const MemReader = struct {
    pub const Error = error{};

    buffer: []const u8,
    i: usize,

    pub fn init(buffer: []const u8) MemReader {
        return MemReader{
            .buffer = buffer,
            .i = 0,
        };
    }

    pub fn read(reader: *MemReader, buf: []u8) Error![]u8 {
        const buffer = reader.rest();
        const len = std.math.min(buf.len, buffer.len);
        std.mem.copy(u8, buf, buffer[0..len]);

        reader.i += len;
        return buf[0..len];
    }

    pub fn rest(reader: MemReader) []const u8 {
        return reader.buffer[reader.i..];
    }
};

test "read.MemReader" {
    var buf: [2]u8 = undefined;
    const mr = &MemReader.init("abc");
    testing.expectEqualSlices(u8, "ab", try mr.read(buf[0..]));
    testing.expectEqual(usize(2), mr.i);
    testing.expectEqualSlices(u8, "c", try mr.read(buf[0..]));
    testing.expectEqual(usize(3), mr.i);
    testing.expectEqualSlices(u8, "", try mr.read(buf[0..]));
    testing.expectEqual(usize(3), mr.i);
}

pub fn byte(reader: var) !u8 {
    var buf: [1]u8 = undefined;
    const bytes = try reader.read(buf[0..]);
    if (bytes.len == 0)
        return error.EndOfStream;

    return bytes[0];
}

test "read.byte" {
    const mr = &MemReader.init("abcd");
    testing.expectEqual(u8('a'), try read.byte(mr));
    testing.expectEqual(u8('b'), try read.byte(mr));
    testing.expectEqual(u8('c'), try read.byte(mr));
    testing.expectEqual(u8('d'), try read.byte(mr));
    testing.expectError(error.EndOfStream, read.byte(mr));
}

pub fn until(reader: var, allocator: var, delim: u8) ![]u8 {
    var res = try mem.alloc(allocator, u8, 4);
    errdefer mem.free(allocator, res);

    var i: usize = 0;
    while (true) : (i += 1) {
        if (res.len <= i)
            res = try mem.realloc(allocator, u8, res, res.len * 2);

        res[i] = try read.byte(reader);
        if (res[i] == delim)
            return mem.shrink(allocator, u8, res, i+1);
    }
}

test "read.until" {
    var buf: [32]u8 = undefined;
    const allocator = &mem.FixedBufferAllocator.init(buf[0..]);
    const mr = &MemReader.init("ab\ncd");

    const line = try read.until(mr, allocator, '\n');
    testing.expectEqualSlices(u8, "ab\n", line);
    testing.expectError(error.EndOfStream, read.until(mr, allocator, '\n'));
}
