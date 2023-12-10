const std = @import("std");
const log = std.log;
const net = std.net;
const mem = std.mem;

const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const StreamServer = net.StreamServer;
const Stream = net.Stream;
const Connection = StreamServer.Connection;
const Address = net.Address;
const Allocator = mem.Allocator;
const Thread = std.Thread;

const protocol = @import("protocol.zig");

const Codec = protocol.Codec;
const Packet = protocol.Packet;
const HandshakeC2S = protocol.HandshakeC2S;
const StatusRequestC2S = protocol.StatusRequestC2S;
const StatusResponseS2C = protocol.StatusResponseS2C;
const PingRequestC2S = protocol.PingRequestC2S;
const PingResponseS2C = protocol.PingResponseS2C;

const json_response =
    \\{
    \\    "version": {
    \\        "name": "1.20.2",
    \\        "protocol": 764
    \\    },
    \\    "players": {
    \\        "max": 100,
    \\        "online": 5,
    \\        "sample": [
    \\            {
    \\                "name": "thinkofdeath",
    \\                "id": "4566e69f-c907-48ee-8d71-d7ba5aa00d20"
    \\            }
    \\        ]
    \\    },
    \\    "description": {
    \\        "text": "Hello world"
    \\    },
    \\    "favicon": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAMAAACdt4HsAAAAM1BMVEU9Oj1cXFwsKiwzMzN0dHQ1NUArLDUXGiFHR0gbJjIfIChPS08LEhokJS1BP0GJiYk9PkzjPy/JAAAC5klEQVRYw5STC46DMAxE7ZSkAZMs9z/t2ri2IcCu+qRKU8Q88gVCYTqBDGWmzEzRZGRhDxtTYduiHWC+0lzhYSMC/hFqCT0xNQsTsweSx/OZTgwQI0UkTx8oow1Hw1khTRWMoBETmpzetN5y/Qgy3SuiM9jI1nVXVJCxGJ2cU31QZANw26CoSmSnhFYPxg1C+QeaK5fGpPVREV9XH7gsK6UVDR2vxPcJTTChD9cPXJEXgusUyB8gTAfIz9ht38gYsOCHiTWf/1TECBzg+r2iwJ2CIAtQB8HkM9zs4sVCUCQ7Q53IBFXqwyaxomlCxhPZfYY4sAlqJTQI/DDkD0TjdY5rQPWVRFCh014Xui0R5Ui+v3YNoMurwH0VMEiGL0+NlGcjG/XFHATdhnXaNM8wGlK6CJhTW0GDzNCK1O8FYZgcn0ZxQ0qPAgCvD4p5qD8IJHg9wBJ1798LhKqKGIqvwLKY4HkECtrcI0Dj/v8Co+GFdflK0HLFA72tLliOgteTQCDfwve6mmB5v00g/CkA0H5qqwm4/pVALk1KJpD2dwIhueBtRP9Z8FtJHe42DINAAJ6owBEafv/HHRRx9toxp/cjUSrdVxrSyBGgAyDSAnprgggXoBuAJ+EEFEGxOABK6LcAC4AgzGs7gPRA1AQZ7wDq3AKCGQDgBmYdieoCCECeAWADq87PI0WZAZhJAUUMZAGIX+QtZwBOAPA8gZq/loivB+BhAAYgwl4HoETNBJH5CmSwgLWBbL4AEe6B+B0E4PcbaToAogW+C4ASIdV4Dmpj0aM3AEFznTWB3Fj1uAWyBoAAVA29WwB1QISPwKMBKoP+AeJ4BMawDoicgYgUMD4DuAATDmAoANuAwP4EyAyACA/VAsw/qn5ILeABIApAxwJUqYB5E/DrAsgUgHljngHEsgYg/43XCVgCLSD7CVzXPAOvE5ApgBDsgwmQDfgyuzdBD3gWIHJ7gmtOALYBYs0EpDvw+AH6OFMg2VOvNQAAAABJRU5ErkJggg==",
    \\    "enforcesSecureChat": false,
    \\    "previewsChat": true
    \\}
;

pub fn handleHandshake(alloc: Allocator, codec: anytype, packet: *Packet) !void {
    switch (packet.id) {
        HandshakeC2S.id => {
            const handshake = try HandshakeC2S.decode(alloc, packet);
            defer handshake.deinit(alloc);
            if (handshake.protocol_version != 764) return error.UnknownProtocol;
            codec.state = handshake.next_state;
        },
        else => return error.UnknownPacket,
    }
}

pub fn handleStatus(alloc: Allocator, codec: anytype, packet: *Packet) !void {
    switch (packet.id) {
        StatusRequestC2S.id => {
            const response = StatusResponseS2C{ .response = json_response };
            const pkt = response.encode(alloc);
            defer pkt.deinit();
            try codec.write(pkt);
        },
        PingRequestC2S.id => {
            const request = try PingRequestC2S.decode(packet);
            const response = PingResponseS2C{ .payload = request.payload };
            const pkt = response.encode(alloc);
            defer pkt.deinit();
            try codec.write(pkt);
            codec.state = .Disconnect;
        },
        else => return error.UnknownPacket,
    }
}

pub fn handleConnection(alloc: Allocator, conn: Connection) !void {
    defer conn.stream.close();

    log.info("Client {} connected", .{conn.address});

    var codec = Codec(Stream.Reader, Stream.Writer){
        .reader = conn.stream.reader(),
        .writer = conn.stream.writer(),
    };

    while (codec.state != .Disconnect) {
        const packet = try codec.read(alloc);
        defer packet.deinit(alloc);

        switch (codec.state) {
            .Handshake => try handleHandshake(alloc, &codec, packet),
            .Status => try handleStatus(alloc, &codec, packet),
            else => break,
        }
    }
}

pub fn main() !void {
    const address = try Address.parseIp("0.0.0.0", 25565);
    var server = StreamServer.init(.{ .reuse_address = true });
    try server.listen(address);

    log.info("Listening on {}", .{address});

    var gpa = GeneralPurposeAllocator(.{}){};
    var alloc = gpa.allocator();

    while (server.accept()) |conn| {
        _ = try Thread.spawn(.{}, handleConnection, .{ alloc, conn });
    } else |_| {}
}
