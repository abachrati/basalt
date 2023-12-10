const std = @import("std");
const unicode = std.unicode;
const math = std.math;
const mem = std.mem;

const fixedBufferStream = std.io.fixedBufferStream;
const Allocator = mem.Allocator;

// zig fmt: off
pub const State = enum(u3) {
    Handshake  = 0,
    Status     = 1,
    Login      = 2,
    Config     = 3,
    Play       = 4,
    Disconnect = 5,
};
// zig fmt: on

pub fn Codec(comptime R: type, comptime W: type) type {
    return struct {
        const Self = @This();

        state: State = .Handshake,
        reader: R,
        writer: W,

        pub fn read(self: *Self, alloc: Allocator) !*Packet {
            var length = math.cast(usize, try readVarInt(self.reader)) orelse return error.InvalidLength;
            var id = try readVarInt(self.reader);
            const data = try alloc.alloc(u8, length - sizeOfVarInt(id));
            try self.reader.readNoEof(data);
            return try Packet.init(alloc, id, data);
        }

        pub fn write(self: *Self, packet: *Packet) !void {
            var length = packet.data.len + sizeOfVarInt(packet.id);
            try writeVarInt(@intCast(length), self.writer);
            try writeVarInt(packet.id, self.writer);
            try self.writer.writeAll(packet.data);
        }

        pub fn deinit(_: *Self) void {}
    };
}

pub const Packet = struct {
    const Self = @This();

    id: i32,
    data: []u8,

    pub fn init(alloc: Allocator, id: i32, data: []u8) !*Self {
        const self = try alloc.create(Self);
        self.id = id;
        self.data = data;
        return self;
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        alloc.free(self.data);
        alloc.destroy(self);
    }
};

// Packets =======================================================================================//

pub const HandshakeC2S = struct {
    const Self = @This();
    pub const id = 0x00;

    protocol_version: i32,
    server_address: []const u8,
    server_port: u16,
    next_state: State,

    pub fn decode(alloc: Allocator, packet: *Packet) !Self {
        var stream = fixedBufferStream(packet.data);
        var reader = stream.reader();
        return .{
            .protocol_version = try readVarInt(reader),
            .server_address = try readString(alloc, reader), // Unnecessary malloc & memcpy
            .server_port = try reader.readIntBig(u16),
            .next_state = @enumFromInt(try readVarInt(reader)),
        };
    }

    pub fn deinit(self: *const Self, alloc: Allocator) void {
        alloc.free(self.server_address);
    }
};

pub const StatusRequestC2S = struct {
    pub const id = 0x00;
};

pub const StatusResponseS2C = struct {
    const Self = @This();
    pub const id = 0x00;

    response: []const u8,

    pub fn encode(self: *const Self, alloc: Allocator) !*Packet {
        const data = try alloc.alloc(u8, sizeOfString(self.response));
        errdefer alloc.free(data);

        var stream = fixedBufferStream(data);
        try writeString(self.response, stream.writer());

        return try Packet.init(alloc, id, data);
    }
};

pub const PingRequestC2S = struct {
    const Self = @This();
    pub const id = 0x01;

    payload: i64,

    pub fn decode(packet: *Packet) !Self {
        var stream = fixedBufferStream(packet.data);
        var reader = stream.reader();
        return .{
            .payload = try reader.readIntBig(i64),
        };
    }
};

pub const PingResponseS2C = struct {
    const Self = @This();
    pub const id = 0x01;

    payload: i64,

    pub fn encode(self: *const Self, alloc: Allocator) !*Packet {
        const data = try alloc.alloc(u8, @sizeOf(i64));
        errdefer alloc.free(data);

        var stream = fixedBufferStream(data);
        try stream.writer().writeIntBig(i64, self.payload);

        return try Packet.init(alloc, id, data);
    }
};

// Data ==========================================================================================//

fn readVarInt(reader: anytype) !i32 {
    var value: u32 = 0;
    var offset: u5 = 0;
    return while (offset < 32) : (offset += 7) {
        const byte = try reader.readByte();
        value |= @as(u32, byte & 0x7f) << offset;
        if (byte & 0x80 == 0) break @bitCast(value);
    } else error.VarIntOversized;
}

fn writeVarInt(self: i32, writer: anytype) !void {
    var value: u32 = @bitCast(self);
    while (value & ~@as(u32, 0x7f) != 0) : (value >>= 7) {
        try writer.writeByte((@as(u8, @truncate(value)) & 0x7f) | 0x80);
    }
    try writer.writeByte(@truncate(value));
}

fn sizeOfVarInt(self: i32) usize {
    var value: u32 = @bitCast(self);
    var size: usize = 0;
    return while (true) {
        size += 1;
        value >>= 7;
        if (value == 0) break size;
    };
}

fn readString(alloc: Allocator, reader: anytype) ![]const u8 {
    const length = math.cast(usize, try readVarInt(reader)) orelse return error.InvalidLength;
    const string = try alloc.alloc(u8, length);
    try reader.readNoEof(string);
    if (!unicode.utf8ValidateSlice(string)) return error.InvalidUTF8;
    return string;
}

fn writeString(self: []const u8, writer: anytype) !void {
    try writeVarInt(@intCast(self.len), writer);
    try writer.writeAll(self);
}

fn sizeOfString(self: []const u8) usize {
    return sizeOfVarInt(@intCast(self.len)) + self.len;
}

// Tests =========================================================================================//

const testing = std.testing;

// zig fmt: off
const varInt_test_data = [_]struct { value: i32, bytes: []const u8 }{
    .{ .value = 0,           .bytes = &.{ 0x00                         }},
    .{ .value = 1,           .bytes = &.{ 0x01                         }},
    .{ .value = 2,           .bytes = &.{ 0x02                         }},
    .{ .value = 127,         .bytes = &.{ 0x7f                         }},
    .{ .value = 128,         .bytes = &.{ 0x80, 0x01                   }},
    .{ .value = 255,         .bytes = &.{ 0xff, 0x01                   }},
    .{ .value = 25565,       .bytes = &.{ 0xdd, 0xc7, 0x01             }},
    .{ .value = 2097151,     .bytes = &.{ 0xff, 0xff, 0x7f             }},
    .{ .value = 2147483647,  .bytes = &.{ 0xff, 0xff, 0xff, 0xff, 0x07 }},
    .{ .value = -1,          .bytes = &.{ 0xff, 0xff, 0xff, 0xff, 0x0f }},
    .{ .value = -2147483648, .bytes = &.{ 0x80, 0x80, 0x80, 0x80, 0x08 }},
};
// zig fmt: on

test "readVarInt" {
    for (varInt_test_data) |data| {
        var stream = fixedBufferStream(data.bytes);
        var reader = stream.reader();
        try testing.expectEqual(data.value, try readVarInt(reader));
    }
}

test "writeVarInt" {
    for (varInt_test_data) |data| {
        var buf: [5]u8 = .{};
        var stream = fixedBufferStream(buf);
        var writer = stream.writer();
        try writeVarInt(data.value, writer);
        try testing.expectEqualSlices(u8, data.bytes, stream.getWritten());
    }
}

test "sizeOfVarInt" {
    for (varInt_test_data) |data| {
        try testing.expectEqual(data.bytes.len, sizeOfVarInt(data.value));
    }
}

// zig fmt: off
// const varlong_test_data = [_]struct { value: i64, bytes: []const u8 }{
//     .{ .value = 0,                    .bytes = &.{ 0x00                                                       }},
//     .{ .value = 1,                    .bytes = &.{ 0x01                                                       }},
//     .{ .value = 2,                    .bytes = &.{ 0x02                                                       }},
//     .{ .value = 127,                  .bytes = &.{ 0x7f                                                       }},
//     .{ .value = 128,                  .bytes = &.{ 0x80, 0x01                                                 }},
//     .{ .value = 255,                  .bytes = &.{ 0xff, 0x01                                                 }},
//     .{ .value = 2147483647,           .bytes = &.{ 0xff, 0xff, 0xff, 0xff, 0x07                               }},
//     .{ .value = 9223372036854775807,  .bytes = &.{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f       }},
//     .{ .value = -1,                   .bytes = &.{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01 }},
//     .{ .value = -2147483648,          .bytes = &.{ 0x80, 0x80, 0x80, 0x80, 0xf8, 0xff, 0xff, 0xff, 0xff, 0x01 }},
//     .{ .value = -9223372036854775808, .bytes = &.{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 }},
// };
// zig fmt: on
