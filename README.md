# Rebocap Wine 兼容补丁

让 Windows 版 ReboCap 客户端在 Wine（Bottles / 原生 Wine / 其他 Wine 前端）下识别
RebornBodyCap USB 接收器：界面绿灯、追踪器实时读数、双固件版本、零弹窗。

> 仅适用于 Wine。真实 Windows 上设备原生就能枚举，**不需要**本补丁。

## 交付文件

```
setupapi.dll                  运行时唯一的补丁文件（构建产物）
rebocap-wine-install.sh       安装脚本（Linux 侧运行）
rebocap-wine-uninstall.sh     卸载脚本
README.md                     本说明
```

## 前置条件

- 接收器：USB `248a:8002`（RebornBodyCap / RebornRX）；
- prefix 的 `dosdevices/com34` 模板存在（Bottles 的 Wine 模板自带；USB 串口固定使用 COM33+）；
- **Linux 用户对接收器串口有读写权限**（`/dev/ttyACM*`，权限通常为 `root:uucp 0660`）。
  没有权限时：补丁已生效（不再报 `-3`），但打开串口失败，日志循环报 `-2 IO连接错误`；
  修复见「串口权限」一节。
- 本补丁只作用于放置它的那个 wine prefix，不影响其他程序。

## 串口权限（必须）

应用枚举到设备后，需要以当前 Linux 用户打开 `/dev/ttyACM*`（经 `com34` 映射）。
若权限不足，表现为：界面不绿、`rebocap.log` 循环出现 `-2 IO连接错误`。

两种修复方式（选一）：

**方式 A：把用户加入 `uucp` 组（标准做法，需要重新登录）**

```bash
sudo usermod -aG uucp "$USER"
# 注销并重新登录桌面会话后生效
```

**方式 B：udev 规则（不需要重新登录）**

```bash
echo 'SUBSYSTEM=="tty", ATTRS{idVendor}=="248a", ATTRS{idProduct}=="8002", MODE="0666"' | \
  sudo tee /etc/udev/rules.d/99-rebocap.rules
sudo udevadm control --reload-rules && sudo udevadm trigger
# 拔插一次接收器使其生效
```

自查（能读写即可，例如权限为 `0666`，或你的用户已在 `uucp` 组）：

```bash
ls -l /dev/ttyACM*
```

## 安装

1. 把上面四个文件放到 `rebocap.exe` 所在目录，例如：

   ```
   <prefix>/drive_c/Program Files (x86)/Rebocap/
   ```

2. 赋执行权限并运行安装脚本：

   ```bash
   cd "<prefix>/drive_c/Program Files (x86)/Rebocap"
   chmod +x rebocap-wine-install.sh rebocap-wine-uninstall.sh
   ./rebocap-wine-install.sh
   ```

3. 安装脚本做三件事：定位并校验环境、删除 `KnownDLLs\setupapi`、
   设置 `HKCU\Software\Wine\DllOverrides\setupapi = native,builtin`。

4. **生效时机（重要）**：需要 wine 会话重启——

   - 关闭该 prefix 里所有程序后重新启动（推荐）；
   - 或执行 `WINEPREFIX="<prefix>" <wine目录>/wineserver -k` 立即结束会话
     （注意：会强制关闭瓶内所有程序）。

   只写入注册表、不重启会话的话，运行中的程序（及 wineserver 会话）仍用旧配置。

## 日常使用

用你喜欢的方式启动 `rebocap.exe`（Bottles 快捷方式、`bottles-cli run`、原生 `wine` 均可）。
安装脚本不参与启动，也不会限制前端选择。

## 端口与 USB 插拔

- 端口名（`PortName`）由补丁保证存在于真实注册表：首次打开设备注册表键时自动建键；
  缺省写入 `COM34`（幂等——已有值不覆盖）。
- `COM34` 在该 prefix 里映射到真实的 USB 串口（`dosdevices/com34`）。
- **重插注意**：接收器重新插拔后，内核串口节点会重新编号（ttyACM0/ACM1…），
  `com34` 映射可能悬空；此时重启程序不会恢复，需要：

  - 让 `com34` 重新指向当前 `ttyACM*`（即修正 `dosdevices/com34` 软链），再启动程序；
  - 追踪器开关不影响"已连接/绿灯/固件"，只影响是否有实时读数。

## 验收标准

1. `rebocap.log` 中零 `-3`；
2. 界面绿"已连接"、零弹窗；
3. 追踪器开机后有实时读数；
4. 配置页双固件 `v_15 / v_7`。

## 排障

日志位置：`<Rebocap>/log/rebocap.log`（关注 `-3` 与 `finish update device info`）。

自查注册表（`<prefix>` 与 `<wine>` 换成实际值）：

```bash
# 应提示找不到 setupapi 值
WINEPREFIX="<prefix>" "<wine>" reg query \
  "HKLM\System\CurrentControlSet\Control\Session Manager\KnownDLLs" /v setupapi

# 应显示 native,builtin
WINEPREFIX="<prefix>" "<wine>" reg query \
  "HKCU\Software\Wine\DllOverrides" /v setupapi
```

| 现象                               | 可能原因                                 | 处理                                                       |
| ---------------------------------- | ---------------------------------------- | ---------------------------------------------------------- |
| 界面不绿、`rebocap.log` 刷 `-3`    | DllOverrides 没生效                      | 核验注册表；确认已做会话重启（关闭程序或 `wineserver -k`） |
| 同上                               | KnownDLLs 没删掉                         | 重跑安装脚本；确认查询结果为空                             |
| 完全没有变化                       | `setupapi.dll` 不在 `rebocap.exe` 同目录 | 放对位置后重跑安装脚本并重启会话                           |
| 绿但无读数                         | 追踪器没开机                             | 打开追踪器（连接/绿灯/固件不依赖它，读数需要它）           |
| 界面不绿、日志循环 `-2 IO连接错误` | 串口权限不足                             | 见「串口权限」一节                                         |
| 重插后不识别                       | `com34` 映射悬空                         | 修正 `com34` 指向当前 `ttyACM*`/重启 prefix 后再启动程序   |

## 卸载

```bash
./rebocap-wine-uninstall.sh
```

脚本会还原 `KnownDLLs\setupapi = "setupapi.dll"`、删除 `DllOverrides\setupapi`、
删除运行期创建的设备键 `REBORNRX`；同样**需要会话重启**生效。
要彻底移除，再手动删除 `setupapi.dll`、两个脚本与本 README 即可。

## 原理（简版）

- **枚举层（假）**：补丁提供一个同名 `setupapi.dll`（放在应用目录，优先于系统版加载）。
  其中 7 个 `SetupDi*` 函数由补丁实现，返回已验证的设备参数（Ports 类 GUID、
  实例 ID `USB\VID_248A&PID_8002\REBORNRX`、设备属性等）；
  其余 ~610 个导出通过链接期"转发条目"交给系统原版，补丁不含它们的代码。
- **数据层（真）**：`SetupDiOpenDevRegKey` 返回**真实**注册表键，应用经真 `advapi32`
  读出 `PortName`；端口打开后走的是真实 Wine 串口，数据链完全真实。
- **部署**：只新增一个 DLL，加两处注册表设置（KnownDLLs / DllOverrides）；
  不修改系统文件、不挂钩任何函数；删文件 + 跑卸载脚本即完全回滚。

## 从源码构建

- 工具链：Zig 0.16（交叉编译内置，无需安装 mingw）
- 构建：

  ```bash
  zig build --release      # 产物：zig-out/bin/setupapi.dll
  ```

- 构建期自动执行 `scripts/gen_def.zig`：读取仓库根目录的 `system-setupapi.dll`
  （Wine builtin，构建输入），生成"7 个真实现 + 610 条转发"的导出清单并交给链接器。
- 目录说明：

  ```
  src/lib.zig           7 个覆盖函数（枚举层）
  src/constants.zig     已验证真值表（GUID/设备 ID/属性字符串）
  src/util.zig          UTF-16、GUID、探针协议等工具
  src/reg.zig           真注册表键：建键/自愈 PortName/读取
  src/forward.zig       运行时转发助手（其余参数→系统原版）
  src/win32.zig         手写 Win32 绑定（零 cImport）
  scripts/gen_def.zig   导出清单生成器（构建期运行）
  system-setupapi.dll   Wine builtin（构建输入；原料，不是补丁产物）
  ```

- 构建产物是 `zig-out/bin/setupapi.dll`——**别把仓库根的 Wine builtin 当补丁拷进瓶子**
  （它只是构建原料，没有任何代理逻辑）。
- 更换 Wine runner 时：用新 runner 的 `lib/wine/x86_64-windows/setupapi.dll`
  替换仓库根目录的 `system-setupapi.dll`，重新 `zig build --release` 即可。

## 许可说明

仓库根目录的 `system-setupapi.dll` 来自 Wine
（`lib/wine/x86_64-windows/setupapi.dll`），许可为 LGPL-2.1-or-later
（https://wiki.winehq.org/Licensing）。
