pub const FAKE_HDEVINFO: usize = 0x52454342;
pub const FAKE_DEVINST: u32 = 0xB07AB;

pub const PORTS_D1: u32 = 0x4D36E978;
pub const PORTS_D2: u16 = 0xE325;
pub const PORTS_D3: u16 = 0x11CE;
pub const PORTS_D4: [8]u8 = .{ 0xBF, 0xC1, 0x08, 0x00, 0x2B, 0xE1, 0x03, 0x18 };

pub const CLASS_NAME = "Ports";
pub const INSTANCE_ID = "USB\\VID_248A&PID_8002\\REBORNRX";
pub const HWID1 = "USB\\VID_248A&PID_8002&REV_0100";
pub const HWID2 = "USB\\VID_248A&PID_8002";
pub const PORT_NAME = "COM34";
pub const FRIENDLY_PREFIX = "USB 串行设备 (";
pub const MFG = "@usbser.inf,%msft%;Microsoft";
pub const DEVICEDESC = "@usbser.inf,%usbserial.devicedesc%;USB 串行设备";
pub const SERVICE = "usbser";
pub const CLASSGUID = "{4d36e978-e325-11ce-bfc1-08002be10318}";
pub const DRIVER = "{4d36e978-e325-11ce-bfc1-08002be10318}\\0002";
pub const LOCPATH = "PCIROOT(0)#PCI(0201)#PCI(0000)#PCI(0C00)#PCI(0000)#USBROOT(0)#USB(8)";
pub const LOCINFO = "Port_#0008.Hub_#0004";

pub const PORT_KEY_PATH = "SYSTEM\\CurrentControlSet\\Enum\\USB\\VID_248A&PID_8002\\REBORNRX\\Device Parameters";

pub const ERROR_INSUFFICIENT_BUFFER: u32 = 122;
pub const ERROR_NO_MORE_ITEMS: u32 = 259;
pub const ERROR_FILE_NOT_FOUND: u32 = 2;
pub const ERROR_INVALID_PARAMETER: u32 = 87;
