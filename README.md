# 通用「环境收进子文件夹」启动器

一个通用引擎 + 一份 `portable.cfg`，换软件只改配置、不用动脚本。

## 它能做什么

| 能做什么 | 怎么控制 |
|---|---|
| 软件把配置、缓存、下载内容都写进本文件夹，不再散落到系统用户目录 | `Redirect=1`（默认开启） |
| 首次运行自动建好目录骨架，不用手动创建 | 自动完成，无需配置 |
| 把安装包静默装进 `App\`，装完即可启动 | `InstallMode` + `Installer` |
| 安装后清掉安装器留下的注册表痕迹，系统保持原状 | `RegBackupKeys` |
| 在指定环境里启动程序，标题、参数、退出行为可控 | `Name` / `Exe` / `Args` / `Wait` |

**关键认知**：这套便携化的本质是**换环境变量**，不是改软件。所以它天然适用于所有「按 `%APPDATA%` / `%USERPROFILE%` 写文件」的程序（绝大多数 Electron / Qt / .NET 桌面程序与绿色软件）。真正需要额外处理的只有两件事：**安装包**和**注册表**。

## 目录结构

```text
PortableLauncher.bat    引擎（基本不用改）
portable.cfg            每个软件一份配置
App\                    程序本体（安装/解包到这里）
Installer\              安装包放这里
Profile\                伪造的 USERPROFILE
  ├─ Desktop\
  └─ AppData\{Roaming,Local,LocalLow}\Temp\
ProgramData\ Public\    伪造的全局目录
RegistryBackup\         安装前注册表快照（临时）
```

把整个文件夹拷到 U 盘 / 别的机器，双击启动器就能继续用。

## 配置项

| 键 | 说明 |
|---|---|
| `Name` | 窗口标题 |
| `Exe` | 可执行文件，相对本目录，如 `App\MyApp.exe`；支持 `{{ROOT}}` 占位符 |
| `Args` | 启动参数 |
| `Wait` | 1 = 等程序退出后再关窗口 |
| `InstallMode` | `none` / `nsis` / `inno` / `msi-admin` / `msi-install` / `7z` |
| `Installer` | 安装包路径（相对 / 绝对 / UNC 均可），如 `Installer\setup.exe` |
| `SevenZip` | `InstallMode=7z` 时的 `7z.exe` 路径 |
| `RegBackupKeys` | 逗号分隔的注册表键：安装前导出，安装后删除并回导 |
| `Env` | 额外环境变量，分号分隔，如 `K=V;K2=V2`（例：`HF_HOME=D:\hf`） |
| `Redirect` | 0 = 不重定向目录，只做安装/启动 |

## 各种安装包怎么选 InstallMode

| 安装包类型 | 推荐模式 | 说明 |
|---|---|---|
| NSIS（7-Zip、VLC 这类常见小工具安装包） | `nsis` | `/S /D=` 静默装到 `App\` |
| Inno Setup（Notepad++、ffmpeg GUI 这类） | `inno` | `/VERYSILENT /DIR=` |
| MSI（Python、Node 这类运行时安装包） | `msi-admin` ✅ | `msiexec /a` 只解包，**不写注册表、不需要管理员** |
| MSI 且必须真注册 | `msi-install` | 会写 HKLM/HKCU，靠 `RegBackupKeys` 擦痕迹 |
| 认不出的 exe / 自解压包 | `7z` | 7z 直接解包，最万能 |
| 官方免安装 zip | `none` | 解压到 `App\` 即可 |

判断类型的方法：用 7z 工具打开看内部结构，出现 `$PLUGINSDIR` 是 NSIS，出现 `app-32.7z` / `embedded` 是 Inno，出现 `.msi` 流是 MSI 套壳。

## 这类软件不听话怎么办

换环境变量只对**读环境变量**的程序有效。以下情况会穿透：

1. **用 Known Folder API**（`SHGetKnownFolderPath`）的程序，如 Office、部分 Adobe 套件——它读注册表 `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders`，不看你给的环境变量。
2. **需要安装服务 / 驱动、写 HKLM** 的程序。
3. **安装包自己弹 UAC**，提权后子进程是新会话，环境变量可能被重置。

三种兜底，从轻到重：

- **只解决配置路径**：程序大多支持命令行或配置文件指定数据目录（`--user-data-dir`、`XDG_CONFIG_HOME`、`-portable` 之类），写进 `Args` 比伪造整个用户目录更可靠。
- **真正的隔离（任意软件通用）**：进程级沙箱工具（自行选择，例如 Sandboxie-Plus）。一个沙箱就是一个文件夹，一次配置长期有效：
  ```bat
  "<沙箱工具目录>\Start.exe" /box:PortableApp /silent "%CD%\Installer\setup.exe"
  ```
  装完再用同一沙箱启动，所有文件与注册表写入都落在沙箱目录里，注册表这一层它也会虚拟化——这是本方案的上位替代。
- **重型隔离**：Windows Sandbox（`wsb` 配置文件 + 映射目录）或整机虚拟机，适合一次性安装包模拟、不可信安装包。

## 快速上手

1. 新建一个空文件夹，放 `PortableLauncher.bat` + `portable.cfg`。
2. 改 cfg 的 `Name` / `Exe` / `InstallMode` / `Installer`。
3. 安装包丢进 `Installer\`，双击 `PortableLauncher.bat`。
4. 检查生成的文件：`Profile\AppData\Roaming` 下应该出现该软件的目录；没出现说明程序不认环境变量，走上面的兜底方案。
5. 调试写入位置：用文件 / 注册表监控工具（如 Procmon）过滤 `Process Name is <程序>.exe` + `Operation is WriteFile/RegSetValue`，一眼看出它往哪写。
