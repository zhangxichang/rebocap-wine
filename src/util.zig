const std = @import("std");
const win = @import("win32.zig");
const c = @import("constants.zig");

pub fn readUtf16(p: ?[*:0]const u16, max: usize) []const u16 {
    const ptr = p orelse return &.{};
    var len: usize = 0;
    while (len < max and ptr[len] != 0) : (len += 1) {}
    return ptr[0..len];
}

pub fn eqlWideAscii(p: []const u16, comptime s: []const u8) bool {
    if (p.len != s.len) return false;
    inline for (s, 0..) |ch, i| {
        if (p[i] != ch) return false;
    }
    return true;
}

pub fn isPortsGuid(p: ?*const anyopaque) bool {
    const b: [*]const u8 = @ptrCast(p orelse return false);
    if (std.mem.readInt(u32, b[0..4], .little) != c.PORTS_D1) return false;
    if (std.mem.readInt(u16, b[4..6], .little) != c.PORTS_D2) return false;
    if (std.mem.readInt(u16, b[6..8], .little) != c.PORTS_D3) return false;
    inline for (c.PORTS_D4, 0..) |x, i| {
        if (b[8 + i] != x) return false;
    }
    return true;
}

pub fn writePortsGuid(dst: [*]u8) void {
    std.mem.writeInt(u32, dst[0..4], c.PORTS_D1, .little);
    std.mem.writeInt(u16, dst[4..6], c.PORTS_D2, .little);
    std.mem.writeInt(u16, dst[6..8], c.PORTS_D3, .little);
    inline for (c.PORTS_D4, 0..) |x, i| {
        dst[8 + i] = x;
    }
}

pub fn fillFakeDevInfo(p: ?*anyopaque) void {
    const b: [*]u8 = @ptrCast(p orelse return);
    const cb_size = std.mem.readInt(u32, b[0..4], .little);
    if (cb_size >= 20) {
        std.mem.writeInt(u32, b[4..8], c.PORTS_D1, .little);
        std.mem.writeInt(u16, b[8..10], c.PORTS_D2, .little);
        std.mem.writeInt(u16, b[10..12], c.PORTS_D3, .little);
        inline for (c.PORTS_D4, 0..) |x, i| {
            b[12 + i] = x;
        }
    }
    if (cb_size >= 24) {
        std.mem.writeInt(u32, b[20..24], c.FAKE_DEVINST, .little);
    }
    if (cb_size >= 32) {
        std.mem.writeInt(usize, b[24..32], 0, .little);
    }
}

fn writeUnit(dst: [*]u8, index: usize, unit: u16) void {
    std.mem.writeInt(u16, dst[index * 2 ..][0..2], unit, .little);
}

pub fn provideStringBytes(buf: ?[*]u8, size: u32, required: ?*u32, s: []const u16) c_int {
    const want: u32 = @intCast((s.len + 1) * 2);
    if (buf == null or size < want) {
        if (required) |r| r.* = want;
        win.SetLastError(c.ERROR_INSUFFICIENT_BUFFER);
        return 0;
    }
    const dst = buf.?;
    for (s, 0..) |unit, i| writeUnit(dst, i, unit);
    writeUnit(dst, s.len, 0);
    if (required) |r| r.* = want;
    win.SetLastError(0);
    return 1;
}

pub fn provideStringChars(buf: ?[*]u16, size: u32, required: ?*u32, s: []const u16) c_int {
    const want: u32 = @intCast(s.len + 1);
    if (buf == null or size < want) {
        if (required) |r| r.* = want;
        win.SetLastError(c.ERROR_INSUFFICIENT_BUFFER);
        return 0;
    }
    const dst = buf.?;
    for (s, 0..) |unit, i| dst[i] = unit;
    dst[s.len] = 0;
    if (required) |r| r.* = want;
    win.SetLastError(0);
    return 1;
}

pub fn provideMultiSz(buf: ?[*]u8, size: u32, required: ?*u32, s1: []const u16, s2: []const u16) c_int {
    const w1 = s1.len + 1;
    const w2 = s2.len + 1;
    const want: u32 = @intCast((w1 + w2 + 1) * 2);
    if (buf == null or size < want) {
        if (required) |r| r.* = want;
        win.SetLastError(c.ERROR_INSUFFICIENT_BUFFER);
        return 0;
    }
    const dst = buf.?;
    for (s1, 0..) |unit, i| writeUnit(dst, i, unit);
    writeUnit(dst, s1.len, 0);
    for (s2, 0..) |unit, i| writeUnit(dst, w1 + i, unit);
    writeUnit(dst, w1 + s2.len, 0);
    writeUnit(dst, w1 + w2, 0);
    if (required) |r| r.* = want;
    win.SetLastError(0);
    return 1;
}
