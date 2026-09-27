pub const HKEY = ?*anyopaque;

pub const HKEY_LOCAL_MACHINE: HKEY = @ptrFromInt(0x80000002);

pub const KEY_READ: u32 = 0x00020019;
pub const KEY_WRITE: u32 = 0x00020006;
pub const REG_OPTION_NON_VOLATILE: u32 = 0;
pub const REG_SZ: u32 = 1;

pub extern "kernel32" fn SetLastError(dwErrCode: u32) callconv(.winapi) void;

pub extern "advapi32" fn RegOpenKeyExW(hKey: HKEY, lpSubKey: [*:0]const u16, ulOptions: u32, samDesired: u32, phkResult: *HKEY) callconv(.winapi) c_int;
pub extern "advapi32" fn RegCreateKeyExW(hKey: HKEY, lpSubKey: [*:0]const u16, reserved: u32, lpClass: ?[*:0]u16, dwOptions: u32, samDesired: u32, lpSecurityAttributes: ?*anyopaque, phkResult: *HKEY, lpdwDisposition: ?*u32) callconv(.winapi) c_int;
pub extern "advapi32" fn RegSetValueExW(hKey: HKEY, lpValueName: [*:0]const u16, reserved: u32, dwType: u32, lpData: [*]const u8, cbData: u32) callconv(.winapi) c_int;
pub extern "advapi32" fn RegQueryValueExW(hKey: HKEY, lpValueName: [*:0]const u16, lpReserved: ?*u32, lpType: ?*u32, lpData: ?[*]u8, lpcbData: ?*u32) callconv(.winapi) c_int;
pub extern "advapi32" fn RegCloseKey(hKey: HKEY) callconv(.winapi) c_int;
