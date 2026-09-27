const std = @import("std");

const IMPLEMENTED = [_][]const u8{
    "SetupDiClassGuidsFromNameW",
    "SetupDiGetClassDevsW",
    "SetupDiEnumDeviceInfo",
    "SetupDiGetDeviceInstanceIdW",
    "SetupDiOpenDevRegKey",
    "SetupDiGetDeviceRegistryPropertyW",
    "SetupDiDestroyDeviceInfoList",
};

const TARGET = "C:\\windows\\system32\\setupapi.dll";

const ParseError = error{ NotPe, Truncated, BadRva, BadExport };

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 3) {
        std.debug.print("用法: {s} <setupapi.dll> <setupapi.def>\n", .{args[0]});
        return error.MissingInput;
    }
    const dll_data = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], arena, .unlimited);
    const ref_file = try std.Io.Dir.cwd().createFile(init.io, args[2], .{});
    defer ref_file.close(init.io);
    var ref_file_buf: [1 << 16]u8 = undefined;
    var ref_file_writer = ref_file.writer(init.io, &ref_file_buf);
    try dll_to_ref(arena, &ref_file_writer.interface, dll_data);
    try ref_file_writer.interface.flush();
}

fn dll_to_ref(allocator: std.mem.Allocator, writer: *std.Io.Writer, data: []const u8) !void {
    if (data.len < 0x40 or !std.mem.eql(u8, data[0..2], "MZ")) return error.NotPe;
    const pe_off: usize = try rd32(data, 0x3c);
    if (pe_off + 24 > data.len) return error.NotPe;
    if (!std.mem.eql(u8, data[pe_off..][0..4], "PE\x00\x00")) return error.NotPe;

    const nsec = try rd16(data, pe_off + 6);
    const opt_size = try rd16(data, pe_off + 20);
    const opt_off = pe_off + 24;
    const magic = try rd16(data, opt_off);
    const dd_off: usize = opt_off + (if (magic == 0x20b) @as(usize, 112) else 96);
    const export_rva = try rd32(data, dd_off);
    if (export_rva == 0) return error.BadExport;
    const sec_off = opt_off + opt_size;

    const ed = try rvaToOff(data, nsec, sec_off, export_rva);
    const base = try rd32(data, ed + 16);
    const nfunc = try rd32(data, ed + 20);
    const nnames = try rd32(data, ed + 24);
    const names_rva = try rd32(data, ed + 32);
    const ords_rva = try rd32(data, ed + 36);
    const names_tbl = try rvaToOff(data, nsec, sec_off, names_rva);
    const ords_tbl = try rvaToOff(data, nsec, sec_off, ords_rva);

    var named = std.ArrayList([]const u8).empty;
    var named_ord = std.ArrayList(u32).empty;
    var i: usize = 0;
    while (i < nnames) : (i += 1) {
        const name_rva = try rd32(data, names_tbl + i * 4);
        const ord_idx = try rd16(data, ords_tbl + i * 2);
        try named.append(allocator, try cstr(data, try rvaToOff(data, nsec, sec_off, name_rva)));
        try named_ord.append(allocator, ord_idx);
    }
    const Ctx = struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    };
    std.mem.sort([]const u8, named.items, {}, Ctx.lessThan);

    try writer.writeAll("EXPORTS\n");
    for (IMPLEMENTED) |n| try writer.print("    {s}\n", .{n});
    outer: for (named.items) |n| {
        for (IMPLEMENTED) |impl| if (std.mem.eql(u8, n, impl)) continue :outer;
        try writer.print("    {s} = {s}.{s}\n", .{ n, TARGET, n });
    }
    const covered = try allocator.alloc(bool, nfunc);
    @memset(covered, false);
    for (named_ord.items) |oi| if (oi < nfunc) {
        covered[oi] = true;
    };
    var k: usize = 0;
    while (k < nfunc) : (k += 1) {
        if (!covered[k]) {
            const ord = base + @as(u32, @intCast(k));
            try writer.print("    #{d} = {s}.#{d}\n", .{ ord, TARGET, ord });
        }
    }
}

fn rd16(d: []const u8, off: usize) ParseError!u16 {
    if (off + 2 > d.len) return error.Truncated;
    return std.mem.readInt(u16, d[off..][0..2], .little);
}
fn rd32(d: []const u8, off: usize) ParseError!u32 {
    if (off + 4 > d.len) return error.Truncated;
    return std.mem.readInt(u32, d[off..][0..4], .little);
}
fn rvaToOff(d: []const u8, nsec: u16, sec_off: usize, rva: u32) ParseError!usize {
    var i: usize = 0;
    while (i < nsec) : (i += 1) {
        const b = sec_off + i * 40;
        const vsize = try rd32(d, b + 8);
        const va = try rd32(d, b + 12);
        const raw_size = try rd32(d, b + 16);
        const raw = try rd32(d, b + 20);
        const span: u64 = @max(vsize, raw_size);
        if (rva >= va and @as(u64, rva) < @as(u64, va) + span)
            return @as(usize, raw) + (@as(usize, rva) - va);
    }
    return error.BadRva;
}
fn cstr(d: []const u8, off: usize) ParseError![]const u8 {
    if (off >= d.len) return error.Truncated;
    const end = std.mem.indexOfScalar(u8, d[off..], 0) orelse return error.Truncated;
    return d[off .. off + end];
}
