const std = @import("std");
const c = @import("constants.zig");
const win = @import("win32.zig");
const util = @import("util.zig");
const reg = @import("reg.zig");
const forward = @import("forward.zig");

/// 按类名获取类 GUID 列表。
///
/// 接管：类名为 "Ports" 时写入 Ports 类 GUID
/// {4D36E978-E325-11CE-BFC1-08002BE10318}，*RequiredSize = 1，返回 1；
/// 输出缓冲为空或容量不足时仅回填 *RequiredSize = 1 并返回 0。
/// 其他类名转发系统原版。
export fn SetupDiClassGuidsFromNameW(
    class_name: ?[*:0]const u16,
    guid_out: ?[*]u8,
    guid_count: u32,
    required: ?*u32,
) callconv(.winapi) c_int {
    const name = util.readUtf16(class_name, 256);
    if (util.eqlWideAscii(name, c.CLASS_NAME)) {
        if (required) |r| r.* = 1;
        if (guid_out == null or guid_count < 1) return 0;
        util.writePortsGuid(guid_out.?);
        win.SetLastError(0);
        return 1;
    }
    return forward.get().class_guids(class_name, guid_out, guid_count, required);
}

/// 按类 GUID 获取设备信息集句柄。
///
/// 接管：类 GUID 为 Ports 类时返回假 HDEVINFO（0x52454342）；
/// 该句柄是后续 5 个接管分支的凭据。
/// 其他 GUID 或枚举器转发系统原版。
export fn SetupDiGetClassDevsW(
    class_guid: ?*const anyopaque,
    enumerator: ?[*:0]const u16,
    hwnd_parent: ?*anyopaque,
    flags: u32,
) callconv(.winapi) ?*anyopaque {
    if (util.isPortsGuid(class_guid)) {
        win.SetLastError(0);
        return @ptrFromInt(c.FAKE_HDEVINFO);
    }
    return forward.get().get_devs(class_guid, enumerator, hwnd_parent, flags);
}

/// 按索引枚举设备信息。
///
/// 接管：假句柄且 index == 0 时按调用方给出的 cbSize 填充 SP_DEVINFO_DATA
/// （Ports 类 GUID、DevInst = 0xB07AB、Reserved = 0），返回 1；
/// index > 0 时 SetLastError(259 = ERROR_NO_MORE_ITEMS) 并返回 0。
/// 其他句柄转发系统原版。
export fn SetupDiEnumDeviceInfo(
    dev_info_set: ?*anyopaque,
    member_index: u32,
    dev_info_data: ?*anyopaque,
) callconv(.winapi) c_int {
    if (isFake(dev_info_set)) {
        if (member_index != 0) {
            win.SetLastError(c.ERROR_NO_MORE_ITEMS);
            return 0;
        }
        if (dev_info_data == null) {
            win.SetLastError(c.ERROR_INVALID_PARAMETER);
            return 0;
        }
        util.fillFakeDevInfo(dev_info_data);
        win.SetLastError(0);
        return 1;
    }
    return forward.get().enum_info(dev_info_set, member_index, dev_info_data);
}

/// 获取设备实例 ID。
///
/// 接管：假句柄时返回 "USB\VID_248A&PID_8002\REBORNRX"。
/// 单位约定：DeviceInstanceIdSize / *RequiredSize 为字符数（WCHAR 个数，含结尾 0），
/// 与属性接口的字节语义不同。
/// 缓冲为空或字符容量不足时回填 *RequiredSize 并 SetLastError(122)，返回 0。
/// 其他句柄转发系统原版。
export fn SetupDiGetDeviceInstanceIdW(
    dev_info_set: ?*anyopaque,
    dev_info_data: ?*anyopaque,
    device_instance_id: ?[*]u16,
    device_instance_id_size: u32,
    required_size: ?*u32,
) callconv(.winapi) c_int {
    if (isFake(dev_info_set)) {
        const s = std.unicode.utf8ToUtf16LeStringLiteral(c.INSTANCE_ID);
        return util.provideStringChars(device_instance_id, device_instance_id_size, required_size, s);
    }
    return forward.get().inst_id(dev_info_set, dev_info_data, device_instance_id, device_instance_id_size, required_size);
}

/// 读取设备注册表属性。
///
/// 接管：假句柄时按属性号返回：
///   1  → HARDWAREID（MULTI_SZ，双串 + 双零结尾，PropertyRegDataType = 7）
///   12 → FRIENDLYNAME（"USB 串行设备 (<PortName>)"；PortName 读真注册表，缺省回退 "COM34"）
///   11 → MFG；35 → LOCPATH；13 → LOCINFO；0 → DEVICEDESC；4 → SERVICE
///   7  → CLASS_NAME；8 → CLASSGUID；9 → DRIVER（字符串型 PropertyRegDataType = 1）
///   其他属性号返回 0。
/// 单位约定：PropertyBufferSize / *RequiredSize 为字节数；
/// 缓冲为空或不足时回填 *RequiredSize 并 SetLastError(122)。
/// 其他句柄转发系统原版。
export fn SetupDiGetDeviceRegistryPropertyW(
    dev_info_set: ?*anyopaque,
    dev_info_data: ?*anyopaque,
    property: u32,
    property_reg_data_type: ?*u32,
    property_buffer: ?[*]u8,
    property_buffer_size: u32,
    required_size: ?*u32,
) callconv(.winapi) c_int {
    if (isFake(dev_info_set)) {
        if (property == 1) {
            const s1 = std.unicode.utf8ToUtf16LeStringLiteral(c.HWID1);
            const s2 = std.unicode.utf8ToUtf16LeStringLiteral(c.HWID2);
            const rc = util.provideMultiSz(property_buffer, property_buffer_size, required_size, s1, s2);
            if (rc == 1 and property_reg_data_type != null) property_reg_data_type.?.* = 7;
            return rc;
        }
        var name_buf: [128]u16 = undefined;
        const s: ?[]const u16 = switch (property) {
            12 => friendlyName(name_buf[0..]),
            11 => std.unicode.utf8ToUtf16LeStringLiteral(c.MFG),
            35 => std.unicode.utf8ToUtf16LeStringLiteral(c.LOCPATH),
            13 => std.unicode.utf8ToUtf16LeStringLiteral(c.LOCINFO),
            0 => std.unicode.utf8ToUtf16LeStringLiteral(c.DEVICEDESC),
            4 => std.unicode.utf8ToUtf16LeStringLiteral(c.SERVICE),
            7 => std.unicode.utf8ToUtf16LeStringLiteral(c.CLASS_NAME),
            8 => std.unicode.utf8ToUtf16LeStringLiteral(c.CLASSGUID),
            9 => std.unicode.utf8ToUtf16LeStringLiteral(c.DRIVER),
            else => null,
        };
        const str = s orelse return 0;
        const rc = util.provideStringBytes(property_buffer, property_buffer_size, required_size, str);
        if (rc == 1 and property_reg_data_type != null) property_reg_data_type.?.* = 1;
        return rc;
    }
    return forward.get().get_prop(dev_info_set, dev_info_data, property, property_reg_data_type, property_buffer, property_buffer_size, required_size);
}

/// 打开设备注册表键。
///
/// 接管：假句柄时打开（不存在则创建）真注册表键
/// HKLM\SYSTEM\CurrentControlSet\Enum\USB\VID_248A&PID_8002\REBORNRX\Device Parameters，
/// 并确保 PortName 值存在（缺省写入 "COM34"），返回真 HKEY。
/// 失败时 SetLastError(2 = ERROR_FILE_NOT_FOUND) 并返回 INVALID_HANDLE_VALUE。
/// 其他句柄转发系统原版。
export fn SetupDiOpenDevRegKey(
    dev_info_set: ?*anyopaque,
    dev_info_data: ?*anyopaque,
    scope: u32,
    hw_profile: u32,
    key_type: u32,
    sam_desired: u32,
) callconv(.winapi) ?*anyopaque {
    if (isFake(dev_info_set)) {
        const hkey = reg.ensurePortKey() orelse {
            win.SetLastError(c.ERROR_FILE_NOT_FOUND);
            return @ptrFromInt(std.math.maxInt(usize));
        };
        win.SetLastError(0);
        return hkey;
    }
    return forward.get().open_key(dev_info_set, dev_info_data, scope, hw_profile, key_type, sam_desired);
}

/// 释放设备信息集。
///
/// 接管：假句柄时 SetLastError(0) 并返回 1（假句柄无实际资源）。
/// 其他句柄转发系统原版。
export fn SetupDiDestroyDeviceInfoList(dev_info_set: ?*anyopaque) callconv(.winapi) c_int {
    if (isFake(dev_info_set)) {
        win.SetLastError(0);
        return 1;
    }
    return forward.get().destroy(dev_info_set);
}

fn isFake(p: ?*anyopaque) bool {
    return p != null and @intFromPtr(p.?) == c.FAKE_HDEVINFO;
}

fn friendlyName(out: []u16) ?[]const u16 {
    var port_buf: [64]u16 = undefined;
    const port: []const u16 = reg.readPortName(port_buf[0..]) orelse std.unicode.utf8ToUtf16LeStringLiteral(c.PORT_NAME);
    const prefix = std.unicode.utf8ToUtf16LeStringLiteral(c.FRIENDLY_PREFIX);
    if (out.len < prefix.len + port.len + 1) return null;
    @memcpy(out[0..prefix.len], prefix);
    @memcpy(out[prefix.len..][0..port.len], port);
    out[prefix.len + port.len] = ')';
    return out[0 .. prefix.len + port.len + 1];
}
