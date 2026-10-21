# AGENTS.md — portable-launcher

> 本文件是任何 AI 编码代理进入本仓库时的**必读**工作说明书，约定目录结构、技术栈、代码规范、配置契约、文档维护与提交流程。任何对脚本、配置、行为的改动都必须同时遵守本文的规则。
>
> 适用项目：Windows 批处理脚本仓库（`cmd.exe` + `WSH/VBScript`），无构建、无依赖、无测试框架。
>
> **来源**：本文件以 [agent-templates](https://github.com/XTsat/agent-templates) 的 `templates/generic/AGENTS.md` 为基线，占位内容已按本项目实际回填。用户说「更新 AGENTS」时按此流程：① 拉取来源模板最新版 → ② 与本地逐节比对 → ③ 合并（**保留本项目已回填的技术栈、目录结构与项目特有约定，禁止把已填内容改回 `{{ 占位 }}`**）→ ④ 展示 diff 与改动清单，等用户确认后再落盘。**禁止整文件覆盖。**

---

## 1. 项目概览

一个**通用**的「把软件的全部运行环境收进子文件夹」Windows 启动器：不改软件本体，只给子进程换一套 `USERPROFILE` / `APPDATA` / `LOCALAPPDATA` / `TEMP` / `PROGRAMDATA` / `HOMEDRIVE` / `HOMEPATH`，让软件把配置、缓存、下载内容都写进本目录，从而实现「拷到 U 盘换台机器继续用」。安装包处理与注册表痕迹另外用 `InstallMode` / `RegBackupKeys` 泛化。

- **项目类型**：命令行脚本仓库（便携化启动器引擎 + 一份配置）
- **主语言与环境**：Windows Batch（`cmd.exe`，Windows 10/11 自带命令集）+ VBScript（`wscript.exe`）
- **包管理 / 构建**：无。脚本零依赖、零编译，拷进目录即可运行

核心文件清单（新增文件时按此表归位）：

| 文件 | 必选 | 职责 |
|------|------|------|
| `README.md` | ✅ | 用户文档：功能、快速开始、配置表、目录结构、安装包来源与 `InstallMode` 选型、常见问题 |
| `AGENTS.md` | ✅ | 本文件：agent 工作说明书 |
| `CHANGELOG.md` | ⚠️ 待补 | 变更日志（格式见第 7 章） |
| `LICENSE` | ⚠️ 待补 | 许可证（发版前必须有） |
| `PortableLauncher.bat` | ✅ | 引擎：读配置 → 重定向环境 → 安装 → 应用补丁 → 启动 |
| `portable.cfg` | ✅ | 一份配置对应一个软件，随仓库分发的是示例值（`MyApp`） |
| `Launch.vbs` | ✅ | 无控制台窗口启动 `PortableLauncher.bat`，失败弹窗并给退出码 |
| `CreateShortcut.vbs` | ✅ | 生成桌面 / 开始菜单快捷方式（指向 `wscript.exe Launch.vbs`） |
| `.gitattributes` | ✅ | 换行锁：`*.bat/*.cmd/*.cfg/*.vbs` 强制 CRLF，其余 LF |
| `.gitignore` | ✅ | 屏蔽 `App/*`、`Installer/*`、运行时伪用户目录 |
| `App/.gitkeep`、`Installer/.gitkeep` | ✅ | 占位，保证空目录进仓库 |

---

## 2. 目录结构与架构

### 2.1 仓库目录

```
portable-launcher/
├── PortableLauncher.bat     # 引擎（唯一入口，通用逻辑都在这里）
├── portable.cfg             # 单软件配置（KEY=VALUE）
├── Launch.vbs               # 无窗口启动器
├── CreateShortcut.vbs       # 快捷方式生成器
├── README.md
├── AGENTS.md
├── .gitattributes
├── .gitignore
├── App/.gitkeep             # 程序本体（安装/解包目标，内容不入库）
└── Installer/.gitkeep       # 安装包缓存（内容不入库）
```

### 2.2 运行时目录布局（由引擎创建）

| 目录 | 作用 |
|------|------|
| `App\` | 程序本体，`Exe` 相对此目录 |
| `Installer\` | 安装包缓存（下载/拖入的包落这里） |
| `Profile\` | 伪造的 `USERPROFILE`（内含 `AppData\Roaming`、`AppData\Local`、`AppData\LocalLow`、`Desktop`、`Temp`） |
| `ProgramData\`、`Public\` | 重定向后的 `PROGRAMDATA` / `ALLUSERSPROFILE` 与 `PUBLIC` |
| `RegistryBackup\` | 安装前的注册表快照（临时，安装后还原即失效） |

### 2.3 引擎内部结构（`PortableLauncher.bat`）

主流程按编号分块，**新增逻辑必须落进对应块或子过程，不要插入新的游离段落**：

1. 默认值（`CFG_*` 全量兜底）
2. 读 `portable.cfg`（`for /f` 逐行 `KEY=VALUE`，`#` 为注释）
3. 命令行覆盖（安装包拖到 bat 上 → `CFG_Installer`，`InstallMode=none` 时按扩展名推断）
4. 目录布局 + 环境重定向（`Redirect=1` 时生效）+ 建目录 + `Env` 附加变量
5. 安装（`Exe` 不存在且 `InstallMode` 非 `none` 才触发）
6. 应用专属补丁（`call :hook_before`）
7. 启动（`Wait` 决定是否 `/wait`）

子过程清单（改行为先定位到这里的标签）：

| 标签 | 职责 |
|------|------|
| `:install` | 定位安装包 → 可选 SHA256 校验 → 备份注册表 → 按 `InstallMode` 静默安装 → 还原注册表 |
| `:resolveInstaller` | 安装包定位优先级链：`Installer` 显式路径 > `InstallerUrl` 下载 > 扫描 `Installer\` |
| `:download` | `curl.exe` 优先、`powershell` 兜底，先写 `.part` 再 `move` 原子落盘，已有缓存跳过 |
| `:scanInstaller` | 取 `Installer\` 下 `*.exe/*.msi/*.7z` 按名称排序最后一个 |
| `:verifyHash` | `InstallerSha256` 非空时用 `certutil` 校验，不符则中止 |
| `:regBackup` / `:regRestore` | 按 `RegBackupKeys` 逐键 `reg export` / `reg delete` + `reg import` |
| `:hook_before` | 应用专属补丁的唯一合法落点（写指针文件、改 json、拉依赖） |
| `:resolve` | 相对路径 → 绝对路径，支持 `{{ROOT}}` 占位符 |
| `:noapp` | 找不到可执行文件时的诊断输出与退出 |

### 2.4 架构原则

- **引擎只做通用动作**：任何「某个软件专属」的处理一律写进 `:hook_before`，禁止污染主流程与其它子过程。
- **配置驱动优先**：新能力先看能否用 `portable.cfg` 的新 key 表达；只有无法配置化的才改引擎。
- **零依赖**：只用 Windows 自带命令（`reg`、`certutil`、`curl`、`powershell`、`msiexec`）；7z 由用户显式配置 `SevenZip=` 路径（不附带、不下载第三方工具）。
- **幂等**：重复运行不得重复安装、不得重复下载（已有 `Exe` 检测、下载缓存、`.part` 原子替换）。
- 保持「双击即用」：所有提示是中文、可读、`pause` 前给结论。

---

## 3. 技术栈与依赖

- **运行时**：Windows 10/11 的 `cmd.exe`（内置命令 + `for /f`、延迟展开）+ `wscript.exe`（VBScript）。
- **依赖声明**：无依赖清单；新增外部程序即视为破坏「零依赖」约定，须先与用户确认。
- **构建**：无。
- **验证**：见第 9 章（静态自检 + 用户在 Windows 上冒烟；本仓库开发机为 Linux，无法执行 `.bat`）。
- **禁止引入**：任何需要安装的运行时（Python/Node/.NET 工具）、任何随仓库分发的第三方二进制、任何联网自更新逻辑（下载仅限用户在 cfg 里主动填的 `InstallerUrl`）。

---

## 4. 代码规范

### 4.1 命名约定

| 元素 | 约定 |
|------|------|
| 标签 | 小写单词、可带下划线：`:install`、`:regBackup`、`:hook_before` |
| 配置变量 | `CFG_<CfgKey>`，与 `portable.cfg` 的 key 一一对应（`CFG_InstallMode` ↔ `InstallMode`） |
| 内部变量 | `PascalCase` 表路径/对象（`Root`、`AppDir`、`ExeFull`、`InstallerFull`、`UserProfile`），小写短名仅用于临时循环变量（`k`、`v`、`p`、`kv`、`i`） |
| 文件 | 仓库根平铺：引擎 `PortableLauncher.bat`，其它 PascalCase 工具脚本，配置 `portable.cfg` |

### 4.2 语法与格式（batch 专项，硬约束）

- **换行必须是 CRLF**：`.gitattributes` 已锁定，禁止改成 LF（`cmd.exe` 解析会出错）。改完文件用 `file`/`git diff --stat` 确认未出现整文件重写。
- **编码 UTF-8（无 BOM）**，第 2 行 `chcp 65001 >nul 2>&1` 是中文提示的前提，不要删。
- `.vbs` 文件**故意保持纯 ASCII**（含注释），避免 WSH 猜测编码；改 `.vbs` 时不得引入中文。
- 变量赋值统一带引号形式：`set "K=V"`，禁止 `set K=V` 裸写。
- 主流程开头 `setlocal EnableDelayedExpansion`；子过程需要局部变量时 `setlocal` + `endlocal & set "%~1=..."` 回传，禁止泄漏局部状态。
- `echo` 输出含 `(` `)` `&` `|` 时用 `echo(` 前缀形式；**在 `if`/`for` 块内**的裸括号必须转义为 `^(` `^)`，否则提前闭合块。
- 判断统一 `if /i`（大小写无关）+ 引号包裹两侧；比较文件存在用 `if exist`。
- 子过程的成功/失败用 `exit /b <code>` 表达，主流程用 `exit /b 0` 正常结束。

### 4.3 注释规范

- 只写 **non-obvious reason**：为什么这么绕、为什么必须这个参数，而不是复述代码在做什么。
- 块注释用 `rem ---- 小节名 ----` 与 `rem ====` 分隔线，保持现有视觉层次。
- **禁止残留中间状态**：不留被注释掉的旧代码、不留调试输出、不留 TODO 空壳。

### 4.4 日志

- 统一用一套输出分级，不另造第二套：`[*]` 常规进度、`[!]` 可恢复问题（继续尝试其它来源）、`[x]` 失败（中止并给下一步建议）、`[reg]` 注册表操作。
- 分级前缀后面直接跟人话结论，一条一行；不留 `DEBUG:` 之类的临时标记与调试输出。
- 输出一律中文；第 2 行的 `chcp 65001` 是中文提示的前提（见 4.2），新增输出不得假定别的代码页。
- 安装、下载这类长流程要报当前阶段与关键入参（安装包路径、`InstallMode`、目标目录），失败时同一行给退出码。

### 4.5 错误处理与防御性编程

- 失败信息必须给出**可执行的下一步**（放哪个目录、改哪个 cfg key、怎么拖安装包），不能只报「失败」。
- 外部调用（安装包、`reg`、`certutil`、`curl`、`powershell`）失败后不得静默继续：要么换兜底方案（下载：curl → powershell），要么中止并提示。
- 每个配置项都必须有兜底默认值，脚本不假定 cfg 存在、也不假定某个 key 已填。
- 先排除「空值 / 文件不存在 / 目录缺失」再执行动作，不靠事后 `errorlevel` 补救。
- `pause` 只在交互场景（找不到程序时的 `:noapp`）出现，且必须尊重 `PORTABLE_NO_PAUSE`（设为任意值时无人值守直接退出）。
- 子过程的成败用 `exit /b <code>` 表达；退出码：`0` 成功；`1` 失败（安装包缺失、哈希不符、`Exe` 找不到、7z 模式缺 `SevenZip`）。

### 4.6 并发

- 不适用：脚本是单线程顺序执行。涉及长任务时只靠「先写 `.part` 再 `move`」保证不产生半截文件；同一目录重复运行不得留下竞态残留。

### 4.7 数据与文件

- 路径统一用 `%Root%` 绝对化后再用；相对路径一律经 `:resolve` 处理（支持 `{{ROOT}}`）。
- 写文件的原子做法：写临时名（`.part` / `.new`）→ `move /y` 覆盖。
- 用户数据只落在 `%Root%` 子目录内，禁止往真实用户目录或系统盘散写。
- 运行时目录的职责见 2.2；新增持久化数据必须有明确归属，不新增游离目录（新增目录要同时改 `.gitignore` 与 2.2 表格）。

---

## 5. 配置契约（`portable.cfg`）

- 格式：`KEY=VALUE`，`#` 起注释，**等号两侧不留空格**（值首部单个空格会被 trim，其余原样保留）；未知 key 会被读进 `CFG_<key>` 但不生效——新增 key 时必须同时在引擎里读它。
- **单一默认值来源**：引擎第 1 节的 `CFG_*` 默认值；`portable.cfg` 是随仓库分发的示例（因此 `Name=MyApp`、`InstallMode=nsis` 与引擎兜底 `App` / `none` 不同是正常的，不要「对齐」掉）。
- 新增/修改配置项必须三处同步：引擎默认值 + `portable.cfg` 示例与注释 + `README.md` 配置表；缺一视为未完成。
- `ShowConsole` 由 `Launch.vbs` 读取（引擎不读），改动时三处（`Launch.vbs`、cfg 注释、README）同步。

当前配置项（13 项）：

| key | 默认（示例） | 说明 |
|-----|------|------|
| `Name` | `MyApp` | 显示名、`start` 窗口标题 |
| `Exe` | `App\MyApp.exe` | 相对 `Root` 的可执行文件路径 |
| `Args` | 空 | 启动参数 |
| `Wait` | `0` | `1` = 等程序退出后窗口才关 |
| `InstallMode` | `nsis` | `none` / `nsis` / `inno` / `msi-admin` / `msi-install` / `7z` |
| `Installer` | `Installer\setup.exe` | 显式安装包路径（相对/绝对/UNC/`{{ROOT}}`） |
| `InstallerUrl` | 空 | 下载地址，缓存到 `Installer\` |
| `InstallerSha256` | 空 | 安装包校验值，非空即校验 |
| `SevenZip` | 空 | `7z` 模式下的 `7z.exe` 路径 |
| `RegBackupKeys` | 空 | 逗号分隔的注册表键：安装前备份、安装后删净再还原 |
| `Env` | 空 | 分号分隔的附加环境变量（`K=V;K2=V2`） |
| `Redirect` | `1` | `0` = 不重定向用户目录（只做安装/启动） |
| `ShowConsole` | `0` | `Launch.vbs` 是否保留控制台窗口 |

---

## 6. 对外接口

| 入口 | 行为 |
|------|------|
| 双击 `PortableLauncher.bat` | 保留控制台，完整输出；安装 + 启动 |
| 把安装包拖到 `PortableLauncher.bat` | 命令行参数覆盖 `Installer`；`InstallMode=none` 时按扩展名推断（`.msi`→`msi-admin`、`.7z`→`7z`、其它→`nsis`） |
| 双击 `Launch.vbs` | 无窗口启动；失败弹窗 + 退出码；拖安装包到它上面会强制显示控制台 |
| `cscript CreateShortcut.vbs [/startmenu]` | 生成桌面快捷方式（带 `/startmenu` 时加开始菜单项），图标取 `Exe` |
| 环境变量 `PORTABLE_NO_PAUSE=1` | 出错时不 `pause`（无人值守） |

接口变更（新增入口、改参数、改退出码语义）必须同步 `README.md` 与 CHANGELOG，并先与用户确认。

---

## 7. 文档维护规范（强制）

> 任何改动在合并前必须同步维护 `README.md` 与 `CHANGELOG.md`。未同步文档 = 任务未完成。

### 7.1 CHANGELOG

- 日常改动先记在顶部 `## [Unreleased]`；**发版时**才把内容移入 `## vX.Y.Z (YYYY-MM-DD)`（日期取发版当天）。
- **先记后合**：同一工作周期内的改动先各记一条，提交/发版前统一整理，把描述同一件事的多条合并成一条。
- 格式为分组式 `### 新增 / 修复 / 变更 / 移除 / 性能`（无内容的分类不写空标题）；条目写「标题 + 冒号 + 说明」。
- **只对重点改动用 `**加粗**`**（核心新能力、重要修复、破坏性变更），其余不加粗。
- **面向使用者书写**：只写使用者能感知的变化（能做什么、行为有什么不同、配置项与默认值怎么变）；不写内部实现（子过程拆分、变量名、行号），不出现文件名与标签名（`Exe`、`InstallMode` 这类使用者直接接触的 key 除外）。
- **无使用者感知的改动不记**：纯注释整理、格式统一、变量改名。
- 更新前必须先读现有文件，保留他人（其它会话）已写入的条目，**严禁整文件覆盖**。

### 7.2 README

- 章节顺序固定为 scaffold 顺序：功能 → 快速开始（安装 / 使用，含「这些操作会绕过 bat」）→ 配置（表格含「类型」列）→ 目录结构 → 安装包怎么传进来 → `InstallMode` 选型 → 常见问题 → 许可证；新增章节要插进这条链里，不要另起游离段落。
- **面向使用者**：写能做什么、怎么配、怎么用、出问题怎么办；不写实现原理与内部流程。
- **版本徽章**：标题下只保留一个 `version` 徽章（版本唯一显式位置，见 8.3），不加其它徽章；发版时只改它的数字，不新增其它版本字样。
- 「常见问题」章节只写「什么情况会穿透、怎么兜底」，不写历史修复记录、旧实现细节与内部变量名。
- 长句不人为软换行（一段一行，靠 Markdown 折行）；空行只用于分隔标题/表格/列表/代码块。
- 涉及用户可见变更（新能力、命令/入口变化、配置项变化、安装包来源变化、已知问题）时，必须同步更新对应章节。

### 7.3 PR 描述

- 只写最终行为，不写尝试过又放弃的方案、不写中间状态；只写 diff 看不出的取舍理由。

---

## 8. 提交与发布

### 8.1 提交规范（Conventional Commits）

- 格式 `<type>(<scope>): <subject>`；`type` 取 `feat` / `fix` / `docs` / `refactor` / `perf` / `test` / `build` / `ci` / `chore` / `style`。
- `subject` 用**中文短句式**描述最终行为，不带句号；可选 `scope`（如 `cfg`、`vbs`）。
- 文档更新与代码改动放在**同一提交**里，不单独拆「补文档」提交。
- 禁止把未完成功能、多轮迭代中间状态写进提交信息。

### 8.2 提交前必须展示并取得确认

展示内容缺一不可：待提交文件清单、`git diff --stat`、**2–3 个候选提交标题**（逐条注明侧重：做了什么 / 为什么改 / 是否带 scope，标出推荐项）。用户选定（或自拟）标题后才 commit。

- **授权一次性**：用户上一轮说过「提交 / 推送」不算本轮授权；展示后又改了任何一行，原确认立即失效，必须重新展示确认。
- 确认 commit ≠ 授权 push；确认推送 ≠ 授权后续继续提交或推送；确认一个提交 ≠ 授权 `--amend`。
- 只有用户明确要求时才 commit / push。

### 8.3 版本号与发布

- SemVer；**只在准备发版时递增一次**，日常任务不碰版本号。
- **版本号的唯一显式位置**：`README.md` 标题下的 `version` 徽章（`https://img.shields.io/badge/version-vX.Y.Z-<color>.svg`，点击跳 `CHANGELOG.md`）。本项目**不建 `VERSION` 文件**，正文与脚注里也不手写版本号——要展示/更新版本只改这一个徽章。
- 发版时三处一致：README `version` 徽章 = CHANGELOG 最新版本段号 = `git tag vX.Y.Z`（tag 与推送同样需用户确认）。
- 徽章只许出现一处；若某处确实需要显示版本（如安装提示），从徽章值派生或直接省略，不要另写一份。

---

## 9. 验证（本机为 Linux，无法运行 `.bat`）

提交前至少跑完静态自检，能跑通的都要跑：

```sh
# 1) 换行保持 CRLF（.bat/.cfg/.vbs 应显示 CRLF，README/AGENTS 应为 LF）
file PortableLauncher.bat portable.cfg Launch.vbs CreateShortcut.vbs README.md AGENTS.md

# 2) 每个 call :label 都有对应标签，无悬空标签
grep -oE 'call :[A-Za-z_]+' PortableLauncher.bat | sort -u
grep -oE '^:[A-Za-z_]+' PortableLauncher.bat | sort -u

# 3) cfg 的 key 与引擎 CFG_ 默认值一一对应（两份列表应相等，唯一允许的差集是 ShowConsole：
#    它只被 Launch.vbs 读取）
grep -oE '^set "CFG_[A-Za-z0-9]+' PortableLauncher.bat | sed 's/set "//' | sort -u > /tmp/cfg-vars
grep -oE '^[A-Za-z0-9]+=' portable.cfg | sed 's/=//;s/^/CFG_/' | sort -u > /tmp/cfg-keys
diff /tmp/cfg-vars /tmp/cfg-keys
```

- 需要真机确认的行为（重定向生效、静默安装参数、`Launch.vbs` 无窗口、快捷方式图标）由用户在 Windows 上双击冒烟；改完要明确告诉用户「哪几步需要在 Windows 上验，预期看到什么」。
- 任何 `cmd` 语法改动都应给出「正常路径 + 失败路径（安装包缺失 / 哈希不符 / 7z 未配置）」的手工验证点。

---

## 10. 最终检查清单（每次任务完成前）

- [ ] 换行与编码：`.bat/.cfg/.vbs` 仍为 CRLF；`.vbs` 仍为纯 ASCII；文件仍为 UTF-8 无 BOM
- [ ] batch 语法：块内括号已转义、`echo(` 用法正确、`set "K=V"` 带引号、`goto`/`call` 目标标签存在
- [ ] 配置：新增 key 已在「引擎默认值 + `portable.cfg` + README 配置表」三处同步
- [ ] 幂等：重复运行不重复安装/下载；写文件走 `.part`/`.new` + `move`
- [ ] 日志与错误处理：`[*]/[!]/[x]/[reg]` 前缀一致，失败信息给出可执行下一步，`PORTABLE_NO_PAUSE` 仍生效
- [ ] 文档：README 与 CHANGELOG（`[Unreleased]`）已同步且面向使用者，未覆盖他人条目
- [ ] 版本号：本次未递增（除非是发版任务；发版时只改 README 的 `version` 徽章，并与 CHANGELOG 版本段、tag 对齐）
- [ ] 提交：已展示文件清单 + `git diff --stat` + 2–3 个候选标题并取得本轮明确确认
- [ ] 验证：第 9 章静态自检跑完，并说明需在 Windows 上冒烟的验证点
