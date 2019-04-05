const std = @import("std");
const mem = @import("mem.zig");
const vtable = @import("vtable.zig");
const testing = std.testing;
const read = @This();

pub fn Reader(comptime E: type) type {
    return struct {
        pub const Error = E;

        const VTable = struct {
            pub const Impl = @OpaqueType();
            read: fn (reader: *Impl, buf: []u8) Error![]u8,
        };

        vtable: *const VTable,
        impl: *VTable.Impl,

        pub fn init(reader: var) @This() {
            const T = @typeOf(reader).Child;
            return @This(){
                .vtable = comptime vtable.populate(VTable, T, T),
                .impl = @ptrCast(*VTable.Impl, reader),
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

pub fn Writer(comptime E: type) type {
    return struct {
        pub const Error = E;

        const VTable = struct {
            pub const Impl = @OpaqueType();
            write: fn (writer: *Impl, buf: []const u8) Error!usize,
        };

        vtable: *const VTable,
        impl: *VTable.Impl,

        pub fn init(writer: var) @This() {
            const T = @typeOf(writer).Child;
            return @This(){
                .vtable = comptime vtable.populate(VTable, T, T),
                .impl = @ptrCast(*VTable.Impl, writer),
            };
        }

        pub fn write(writer: @This(), buf: []const u8) Error!usize {
            return writer.vtable.write(writer.impl, buf);
        }
    };
}

test "read.Writer" {
    var buf: [2]u8 = undefined;
    const mw = &MemWriter.init(buf[0..]);
    const writer = Writer(MemWriter.Error).init(mw);
    testing.expectEqual(usize(1), try writer.write("a"));
    testing.expectEqualSlices(u8, "a", mw.buffer[0..mw.i]);
    testing.expectEqual(usize(1), try writer.write("b"));
    testing.expectEqualSlices(u8, "ab", mw.buffer[0..mw.i]);
    testing.expectEqual(usize(0), try writer.write("c"));
    testing.expectEqualSlices(u8, "ab", mw.buffer[0..mw.i]);
}

pub fn ReadWriter(comptime ReadErr: type, comptime WriteErr: type) type {
    return struct {
        pub const ReadError = ReadErr;
        pub const WriteError = WriteErr;

        const VTable = struct {
            pub const Impl = @OpaqueType();
            read: fn (reader: *Impl, buf: []u8) ReadError![]u8,
            write: fn (writer: *Impl, buf: []const u8) WriteError!usize,
        };

        vtable: *const VTable,
        impl: *VTable.Impl,

        pub fn init(rw: var) @This() {
            const T = @typeOf(rw).Child;
            return @This(){
                .vtable = comptime vtable.populate(VTable, T, T),
                .impl = @ptrCast(*VTable.Impl, rw),
            };
        }

        pub fn read(rw: @This(), buf: []u8) ReadError![]u8 {
            return rw.vtable.read(rw.impl, buf);
        }

        pub fn write(rw: @This(), buf: []const u8) WriteError!usize {
            return rw.vtable.write(rw.impl, buf);
        }
    };
}

test "read.ReadWriter" {
    var buf: [2]u8 = undefined;
    var buf2: [1]u8 = undefined;
    const mrw = &MemReadWriter.init(buf[0..]);
    const rw = ReadWriter(MemReadWriter.Error, MemReadWriter.Error).init(mrw);
    testing.expectEqual(usize(1), try rw.write("a"));
    testing.expectEqualSlices(u8, "a", mrw.notRead());
    testing.expectEqual(usize(1), try rw.write("b"));
    testing.expectEqualSlices(u8, "ab", mrw.notRead());
    testing.expectEqual(usize(0), try rw.write("c"));
    testing.expectEqualSlices(u8, "ab", mrw.notRead());

    testing.expectEqualSlices(u8, "a", try rw.read(buf2[0..]));
    testing.expectEqualSlices(u8, "b", mrw.notRead());
    testing.expectEqualSlices(u8, "b", try rw.read(buf2[0..]));
    testing.expectEqualSlices(u8, "", mrw.notRead());
    testing.expectEqualSlices(u8, "", try rw.read(buf2[0..]));
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

pub const MemWriter = struct {
    pub const Error = error{};

    buffer: []u8,
    i: usize,

    pub fn init(buffer: []u8) MemWriter {
        return MemWriter{
            .buffer = buffer,
            .i = 0,
        };
    }

    pub fn write(writer: *MemWriter, buf: []const u8) Error!usize {
        const buffer = writer.rest();
        const len = std.math.min(buf.len, buffer.len);
        std.mem.copy(u8, buffer, buf[0..len]);
        writer.i += len;
        return len;
    }

    pub fn rest(writer: MemWriter) []u8 {
        return writer.buffer[writer.i..];
    }
};

test "read.MemWriter" {
    var buf: [2]u8 = undefined;
    const mw = &MemWriter.init(buf[0..]);
    testing.expectEqual(usize(1), try mw.write("a"));
    testing.expectEqualSlices(u8, "a", mw.buffer[0..mw.i]);
    testing.expectEqual(usize(1), try mw.write("b"));
    testing.expectEqualSlices(u8, "ab", mw.buffer[0..mw.i]);
    testing.expectEqual(usize(0), try mw.write("c"));
    testing.expectEqualSlices(u8, "ab", mw.buffer[0..mw.i]);
}

pub const MemReadWriter = struct {
    pub const Error = error{};

    buffer: []u8,
    start: usize,
    end: usize,

    pub fn init(buffer: []u8) MemReadWriter {
        return MemReadWriter{
            .buffer = buffer,
            .start = 0,
            .end = 0,
        };
    }

    pub fn write(mrw: *MemReadWriter, buf: []const u8) Error!usize {
        const buffer = mrw.notWritten();
        const len = std.math.min(buf.len, buffer.len);
        std.mem.copy(u8, buffer, buf[0..len]);
        mrw.end += len;
        return len;
    }

    pub fn read(mrw: *MemReadWriter, buf: []u8) Error![]u8 {
        const buffer = mrw.notRead();
        const len = std.math.min(buf.len, buffer.len);
        std.mem.copy(u8, buf, buffer[0..len]);

        mrw.start += len;
        return buf[0..len];
    }

    pub fn notWritten(mrw: MemReadWriter) []u8 {
        return mrw.buffer[mrw.end..];
    }

    pub fn notRead(mrw: MemReadWriter) []const u8 {
        return mrw.buffer[mrw.start..mrw.end];
    }
};

test "read.MemReadWriter" {
    var buf: [2]u8 = undefined;
    var buf2: [1]u8 = undefined;
    const mrw = &MemReadWriter.init(buf[0..]);
    testing.expectEqual(usize(1), try mrw.write("a"));
    testing.expectEqualSlices(u8, "a", mrw.notRead());
    testing.expectEqual(usize(1), try mrw.write("b"));
    testing.expectEqualSlices(u8, "ab", mrw.notRead());
    testing.expectEqual(usize(0), try mrw.write("c"));
    testing.expectEqualSlices(u8, "ab", mrw.notRead());

    testing.expectEqualSlices(u8, "a", try mrw.read(buf2[0..]));
    testing.expectEqualSlices(u8, "b", mrw.notRead());
    testing.expectEqualSlices(u8, "b", try mrw.read(buf2[0..]));
    testing.expectEqualSlices(u8, "", mrw.notRead());
    testing.expectEqualSlices(u8, "", try mrw.read(buf2[0..]));
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
