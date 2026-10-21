@echo off
rem 中文提示按 UTF-8 输出；如果显示乱码，把这行删掉或改成 GBK 保存本文件
chcp 65001 >nul 2>&1
setlocal EnableDelayedExpansion
rem ==========================================================================
rem  PortableLauncher.bat  --  通用「把软件的全部运行环境收进子文件夹」启动器
rem  配套 portable.cfg，用法见 README.md
rem
rem  原理：这套做法不是"改软件"，而是给子进程换一套
rem        USERPROFILE / APPDATA / LOCALAPPDATA / TEMP / PROGRAMDATA /
rem        HOMEDRIVE / HOMEPATH，软件自己去"用户目录"写东西时就写进了
rem        本目录的子文件夹。所以这套做法对任何软件都通用，只差一个配置。
rem        剩下两件事（安装包、注册表痕迹）用下面的 InstallMode / RegBackupKeys
rem        泛化处理。
rem ==========================================================================

cd /d "%~dp0"
set "Root=%CD%"
set "RealUserProfile=%USERPROFILE%"

rem ---------------------------- 1. 默认值 -----------------------------------
set "CFG_Name=App"
set "CFG_Exe=App\App.exe"
set "CFG_Args="
set "CFG_Wait=0"
set "CFG_Redirect=1"
set "CFG_InstallMode=none"
set "CFG_Installer="
set "CFG_InstallerUrl="
set "CFG_InstallerSha256="
set "CFG_SevenZip="
set "CFG_RegBackupKeys="
set "CFG_Env="

rem ------------------- 2. 读取 portable.cfg（KEY=VALUE，# 为注释） -----------
if exist "%Root%\portable.cfg" for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%Root%\portable.cfg") do (
   set "k=%%A"
   set "v=%%B"
   if "!v:~0,1!"==" " set "v=!v:~1!"
   if not "!k!"=="" set "CFG_!k!=!v!"
)

rem ---------------- 3. 命令行覆盖：把安装包直接拖到本 bat 上 ----------------
rem   PortableLauncher.bat "D:\下载\setup.exe"
if not "%~1"=="" (
   echo [*] 命令行指定安装包: "%~1"
   set "CFG_Installer=%~1"
   if /i "%CFG_InstallMode%"=="none" (
      set "CFG_InstallMode=nsis"
      if /i "%~x1"==".msi" set "CFG_InstallMode=msi-admin"
      if /i "%~x1"==".7z"  set "CFG_InstallMode=7z"
      echo [*] 未配置 InstallMode, 按扩展名推断为 !CFG_InstallMode!
   )
)

rem ---------------------------- 4. 目录布局 ---------------------------------
set "AppDir=%Root%\App"
set "UserProfile=%Root%\Profile"
set "AppData=%UserProfile%\AppData\Roaming"
set "LocalAppData=%UserProfile%\AppData\Local"
set "LocalLowAppData=%UserProfile%\AppData\LocalLow"
set "Temp=%LocalAppData%\Temp"
set "Tmp=%Temp%"
set "ProgramDataDir=%Root%\ProgramData"
set "PublicDir=%Root%\Public"
set "HomeDrive=%~d0"
set "HomePath=%Root:~2%"

if "%CFG_Redirect%"=="1" (
   set "USERPROFILE=%UserProfile%"
   set "APPDATA=%AppData%"
   set "LOCALAPPDATA=%LocalAppData%"
   set "TEMP=%Temp%"
   set "TMP=%Tmp%"
   set "HOMEDRIVE=%HomeDrive%"
   set "HOMEPATH=%HomePath%"
   set "PROGRAMDATA=%ProgramDataDir%"
   set "ALLUSERSPROFILE=%ProgramDataDir%"
   set "PUBLIC=%PublicDir%"
)

for %%D in ("%AppDir%" "%UserProfile%\Desktop" "%AppData%" "%LocalAppData%" "%LocalLowAppData%" "%Temp%" "%ProgramDataDir%" "%PublicDir%") do (
   if not exist "%%~D" mkdir "%%~D" >nul 2>&1
)

rem 额外的任意环境变量，如 Env=CUDA_VISIBLE_DEVICES=1;HF_HOME=D:\hf
if not "%CFG_Env%"=="" (
   set "pairs=%CFG_Env:;=" "%"
   for %%E in ("%pairs%") do (
      set "kv=%%~E"
      if not "!kv!"=="" set "!kv!"
   )
)

rem ---------------------------- 5. 安装（如需要） ----------------------------
call :resolve ExeFull "%CFG_Exe%"
if "%CFG_Exe%"=="" goto :noapp
if not exist "%ExeFull%" if /i not "%CFG_InstallMode%"=="none" call :install
if not exist "%ExeFull%" goto :noapp

rem ---------------------------- 6. 应用专属补丁 ------------------------------
call :hook_before

rem ---------------------------- 7. 启动 -------------------------------------
echo [*] 启动 %CFG_Name%
if "%CFG_Wait%"=="1" (
   start "%CFG_Name%" /wait /D "%Root%" "%ExeFull%" %CFG_Args%
) else (
   start "%CFG_Name%" /D "%Root%" "%ExeFull%" %CFG_Args%
)
exit /b 0


rem ==========================================================================
rem  子过程
rem ==========================================================================

:install
call :resolveInstaller
if not exist "%InstallerFull%" (
   echo [x] 找不到安装包。
   echo     可用的传递方式:
   echo       1. 把安装包放进 "%Root%\Installer\" ^(文件名任意, 自动取最新一个^)
   echo       2. portable.cfg 里写 Installer=D:\path\setup.exe 或 \\nas\share\setup.exe
   echo       3. portable.cfg 里写 InstallerUrl=https://... 自动下载并缓存
   echo       4. 直接把安装包拖到 PortableLauncher.bat 图标上
   exit /b 1
)
call :verifyHash
if errorlevel 1 exit /b 1
echo [*] 安装模式 %CFG_InstallMode%: "%InstallerFull%"
call :regBackup
if /i "%CFG_InstallMode%"=="nsis"        "%InstallerFull%" /S /D="%AppDir%"
if /i "%CFG_InstallMode%"=="inno"        "%InstallerFull%" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /CURRENTUSER /DIR="%AppDir%"
if /i "%CFG_InstallMode%"=="msi-admin"   msiexec /a "%InstallerFull%" /qn TARGETDIR="%AppDir%"
if /i "%CFG_InstallMode%"=="msi-install" msiexec /i "%InstallerFull%" /qn INSTALLDIR="%AppDir%"
if /i "%CFG_InstallMode%"=="7z" (
   if "%CFG_SevenZip%"=="" ( echo [x] 7z 模式需要配置 SevenZip= ; exit /b 1 )
   "%CFG_SevenZip%" x "%InstallerFull%" -o"%AppDir%" -y >nul
)
call :regRestore
exit /b 0

rem ==========================================================================
rem  安装包定位：优先级 命令行拖入 > 显式路径 > URL 下载 > 自动扫描 Installer\
rem ==========================================================================
:resolveInstaller
set "InstallerFull="
rem 0) 指针文件/URL 直接塞进 Installer 的情况
if /i "!CFG_Installer:~0,4!"=="http" (
   set "CFG_InstallerUrl=%CFG_Installer%"
   set "CFG_Installer="
)
rem 1) 显式路径（相对 / 绝对 / UNC / {{ROOT}}）
if not "%CFG_Installer%"=="" (
   call :resolve InstallerFull "%CFG_Installer%"
   if not exist "!InstallerFull!" (
      echo [!] 配置的安装包不存在, 继续尝试其它来源: "!InstallerFull!"
      set "InstallerFull="
   )
)
rem 2) 下载（已有同名缓存则直接用，不重复下）
if "%InstallerFull%"=="" if not "%CFG_InstallerUrl%"=="" call :download
rem 3) 自动扫描 Installer\ 下的 exe/msi/7z，取名字排序最后的（通常是最新）
if "%InstallerFull%"=="" call :scanInstaller
exit /b 0

:download
set "url=%CFG_InstallerUrl%"
set "fname="
for %%U in ("%url%") do set "fname=%%~nxU"
if "%fname%"=="" set "fname=installer.tmp"
if not exist "%Root%\Installer" mkdir "%Root%\Installer" >nul 2>&1
set "dest=%Root%\Installer\%fname%"
if exist "%dest%" (
   echo [*] 已存在缓存, 跳过下载: "%dest%"
   set "InstallerFull=%dest%"
   exit /b 0
)
echo [*] 下载 "%url%"
set "got=0"
where curl.exe >nul 2>&1
if %errorlevel% equ 0 (
   curl.exe -L --fail --retry 2 -o "%dest%.part" "%url%"
   if exist "%dest%.part" set "got=1"
)
if "%got%"=="0" (
   powershell -NoProfile -Command "try{Invoke-WebRequest -UseBasicParsing -Uri '%url%' -OutFile '%dest%.part'}catch{exit 1}"
   if exist "%dest%.part" set "got=1"
)
if "%got%"=="1" move /y "%dest%.part" "%dest%" >nul
if exist "%dest%" (set "InstallerFull=%dest%") else (echo [x] 下载失败)
exit /b 0

:scanInstaller
if not exist "%Root%\Installer" exit /b 0
for /f "delims=" %%A in ('dir /b /a-d /o-n "%Root%\Installer"\*.exe "%Root%\Installer"\*.msi "%Root%\Installer"\*.7z 2^>nul') do (
   if not defined InstallerFull set "InstallerFull=%Root%\Installer\%%A"
)
exit /b 0

rem 可选：InstallerSha256= 校验，防止下载/拷贝被换包
:verifyHash
if "%CFG_InstallerSha256%"=="" exit /b 0
certutil -hashfile "%InstallerFull%" SHA256 | findstr /i /c:"%CFG_InstallerSha256%" >nul
if errorlevel 1 (
   echo [x] SHA256 校验失败, 已中止安装: "%InstallerFull%"
   exit /b 1
)
echo [*] SHA256 校验通过
exit /b 0

rem ---- 安装前备份注册表键（逗号分隔），安装后还原，抹掉安装痕迹 ----
:regBackup
if "%CFG_RegBackupKeys%"=="" exit /b 0
if not exist "%Root%\RegistryBackup" mkdir "%Root%\RegistryBackup" >nul 2>&1
set "i=0"
set "list=%CFG_RegBackupKeys:,=" "%"
for %%K in ("%list%") do (
   set "key=%%~K"
   set /a i+=1
   if "!key:~0,1!"==" " set "key=!key:~1!"
   set "f=%Root%\RegistryBackup\bk_!i!.reg"
   if exist "!f!" del "!f!" >nul 2>&1
   reg export "!key!" "!f!" /y >nul 2>&1
   set "sz=0"
   for %%F in ("!f!") do set "sz=%%~zF"
   if !sz! GTR 0 (echo [reg] 已备份 !key!) else (echo [reg] !key! 安装前不存在)
)
exit /b 0

:regRestore
if "%CFG_RegBackupKeys%"=="" exit /b 0
set "i=0"
set "list=%CFG_RegBackupKeys:,=" "%"
for %%K in ("%list%") do (
   set "key=%%~K"
   set /a i+=1
   if "!key:~0,1!"==" " set "key=!key:~1!"
   reg delete "!key!" /f >nul 2>&1
   set "f=%Root%\RegistryBackup\bk_!i!.reg"
   set "sz=0"
   for %%F in ("!f!") do set "sz=%%~zF"
   if !sz! GTR 0 reg import "!f!" >nul 2>&1
   echo [reg] 已还原 !key!
)
exit /b 0

rem ---- 应用专属补丁（改配置、写指针文件、下载依赖等）都放这里 ----
:hook_before
rem 例 1: 写一个 home 指针文件，让程序把数据放到本目录
rem   > "%Root%\.myapp-home" echo %Root%\data
rem
rem 例 2: 改程序 JSON 配置里的某个路径（这里假设键名是 dataPath）
rem   set "f=%AppData%\MyApp\settings.json"
rem   if exist "!f!" (
rem      (for /f "usebackq delims=" %%L in ("!f!") do (
rem          set "l=%%L"
rem          echo(!l! | findstr /c:"dataPath" >nul
rem          if !errorlevel! equ 0 (echo   "dataPath": "%Root:\=\\%\\data",) else (echo(!l!)
rem       )) > "!f!.new"
rem      move /y "!f!.new" "!f!" >nul
rem   )
exit /b 0

rem ---- 把相对路径解析成绝对路径，支持 {{ROOT}} 占位符 ----
:resolve
setlocal EnableDelayedExpansion
set "p=%~2"
set "p=!p:{{ROOT}}=%Root%!"
if not "!p:~1,1!"==":" set "p=%Root%\!p!"
endlocal & set "%~1=%p%"
exit /b 0

:noapp
echo [x] 找不到可执行文件 "%ExeFull%"
echo     请把程序解包/安装到 "%AppDir%"，或检查 portable.cfg 里的 Exe / InstallMode / Installer
if /i "%CFG_InstallMode%"=="none" (
   echo     提示: 也可以设 InstallMode=7z 自动解包, 或 nsis / inno / msi-admin 静默安装
   echo     或者把安装包直接拖到本文件图标上
)
if not defined PORTABLE_NO_PAUSE pause
exit /b 1
