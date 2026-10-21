' CreateShortcut.vbs - create a desktop shortcut that starts Launch.vbs
'
' Usage:
'   double-click                -> shortcut on the Desktop
'   cscript CreateShortcut.vbs /startmenu
'                               -> Desktop shortcut + Start Menu entry
'
' The shortcut points at wscript.exe with Launch.vbs as argument, and takes
' its icon from the application exe configured in portable.cfg.
' Pure ASCII on purpose.
Option Explicit

Dim fso, sh, root, cfg, appName, exeRel, exeFull, launcher
Dim targets, made, i, arg

Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")

root = fso.GetParentFolderName(WScript.ScriptFullName)
cfg = ReadUtf8(fso.BuildPath(root, "portable.cfg"))

appName = GetCfg(cfg, "Name", "PortableApp")
exeRel = GetCfg(cfg, "Exe", "")

exeFull = exeRel
exeFull = Replace(exeFull, "{{ROOT}}", root)
If Len(exeFull) > 1 Then
   If Mid(exeFull, 2, 1) <> ":" Then exeFull = fso.BuildPath(root, exeFull)
End If

launcher = fso.BuildPath(root, "Launch.vbs")
If Not fso.FileExists(launcher) Then
   MsgBox "Launch.vbs was not found next to this script:" & vbCrLf & root, _
          vbCritical, "Portable Launcher"
   WScript.Quit 1
End If

made = ""
made = made & MakeLnk(fso.BuildPath(sh.SpecialFolders("Desktop"), appName & ".lnk"), _
                      launcher, root, exeFull, appName) & vbCrLf

For i = 0 To WScript.Arguments.Count - 1
   arg = LCase(WScript.Arguments(i))
   If arg = "/startmenu" Or arg = "/sm" Then
      made = made & MakeLnk(fso.BuildPath(sh.SpecialFolders("Programs"), appName & ".lnk"), _
                            launcher, root, exeFull, appName) & vbCrLf
   End If
Next

MsgBox "Shortcut(s) created:" & vbCrLf & vbCrLf & made & vbCrLf & _
       "Always start the app through this shortcut, otherwise it will use" & vbCrLf & _
       "your real user profile instead of the portable folders.", _
       vbInformation, "Portable Launcher"


' ---------------------------------------------------------------- helpers ---
Function MakeLnk(lnkPath, launcherPath, workDir, iconSrc, descr)
   Dim sc, wscriptExe
   wscriptExe = sh.ExpandEnvironmentStrings("%SystemRoot%\System32\wscript.exe")
   Set sc = sh.CreateShortcut(lnkPath)
   sc.TargetPath = wscriptExe
   sc.Arguments = """" & launcherPath & """"
   sc.WorkingDirectory = workDir
   sc.WindowStyle = 1
   sc.Description = descr
   If iconSrc <> "" Then
      If fso.FileExists(iconSrc) Then sc.IconLocation = iconSrc & ",0"
   End If
   sc.Save
   Set sc = Nothing
   MakeLnk = lnkPath
End Function

Function ReadUtf8(path)
   Dim st
   ReadUtf8 = ""
   If Not fso.FileExists(path) Then Exit Function
   On Error Resume Next
   Set st = CreateObject("ADODB.Stream")
   st.Type = 2
   st.Charset = "utf-8"
   st.Open
   st.LoadFromFile path
   ReadUtf8 = st.ReadText
   st.Close
   Set st = Nothing
   On Error GoTo 0
End Function

Function GetCfg(text, key, defaultValue)
   Dim lines, ln, p
   GetCfg = defaultValue
   If text = "" Then Exit Function
   For Each ln In Split(text, vbLf)
      ln = Replace(ln, vbCr, "")
      If Left(ln, 1) <> "#" And InStr(ln, "=") > 0 Then
         p = InStr(ln, "=")
         If Trim(Left(ln, p - 1)) = key Then
            GetCfg = Trim(Mid(ln, p + 1))
            Exit Function
         End If
      End If
   Next
End Function
