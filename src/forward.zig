const std = @import("std");

extern "kernel32" fn LoadLibraryW(lpLibFileName: [*:0]const u16) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GetProcAddress(hModule: *anyopaque, lpProcName: [*:0]const u8) callconv(.winapi) ?*const anyopaque;

const system_setupapi = std.unicode.utf8ToUtf16LeStringLiteral("C:\\windows\\system32\\setupapi.dll");

pub const FnClassGuids = *const fn (?[*:0]const u16, ?[*]u8, u32, ?*u32) callconv(.winapi) c_int;
pub const FnGetDevs = *const fn (?*const anyopaque, ?[*:0]const u16, ?*anyopaque, u32) callconv(.winapi) ?*anyopaque;
pub const FnEnumInfo = *const fn (?*anyopaque, u32, ?*anyopaque) callconv(.winapi) c_int;
pub const FnInstId = *const fn (?*anyopaque, ?*anyopaque, ?[*]u16, u32, ?*u32) callconv(.winapi) c_int;
pub const FnGetProp = *const fn (?*anyopaque, ?*anyopaque, u32, ?*u32, ?[*]u8, u32, ?*u32) callconv(.winapi) c_int;
pub const FnOpenKey = *const fn (?*anyopaque, ?*anyopaque, u32, u32, u32, u32) callconv(.winapi) ?*anyopaque;
pub const FnDestroy = *const fn (?*anyopaque) callconv(.winapi) c_int;

pub const Orig = struct {
    class_guids: FnClassGuids,
    get_devs: FnGetDevs,
    enum_info: FnEnumInfo,
    inst_id: FnInstId,
    get_prop: FnGetProp,
    open_key: FnOpenKey,
    destroy: FnDestroy,
};

var state: std.atomic.Value(u32) = .init(0);
var orig: Orig = undefined;

pub fn get() *const Orig {
    if (state.load(.acquire) != 2) {
        if (state.cmpxchgStrong(0, 1, .acq_rel, .acquire) == null) {
            orig = resolve();
            state.store(2, .release);
        } else {
            while (state.load(.acquire) != 2) std.atomic.spinLoopHint();
        }
    }
    return &orig;
}

fn resolve() Orig {
    const module = LoadLibraryW(system_setupapi).?;
    return .{
        .class_guids = sym(module, "SetupDiClassGuidsFromNameW", FnClassGuids),
        .get_devs = sym(module, "SetupDiGetClassDevsW", FnGetDevs),
        .enum_info = sym(module, "SetupDiEnumDeviceInfo", FnEnumInfo),
        .inst_id = sym(module, "SetupDiGetDeviceInstanceIdW", FnInstId),
        .get_prop = sym(module, "SetupDiGetDeviceRegistryPropertyW", FnGetProp),
        .open_key = sym(module, "SetupDiOpenDevRegKey", FnOpenKey),
        .destroy = sym(module, "SetupDiDestroyDeviceInfoList", FnDestroy),
    };
}

fn sym(module: *anyopaque, name: [*:0]const u8, comptime T: type) T {
    return @ptrCast(GetProcAddress(module, name).?);
}
