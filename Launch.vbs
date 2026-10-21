' Launch.vbs - start PortableLauncher.bat without a console window
'
' Notes (see README.md):
'   * double-click this file, or use the shortcut made by CreateShortcut.vbs
'   * if you drag an installer onto this file the console IS shown,
'     so you can watch the installation progress
'   * set ShowConsole=1 in portable.cfg to always keep the console
'   * this file is intentionally pure ASCII so Windows Script Host
'     never has to guess an encoding
Option Explicit

Dim fso, sh, env, root, bat, cfgPath, cfg, showConsole, style, cmd, rc, i

Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")

root = fso.GetParentFolderName(WScript.ScriptFullName)
bat = fso.BuildPath(root, "PortableLauncher.bat")
cfgPath = fso.BuildPath(root, "portable.cfg")

If Not fso.FileExists(bat) Then
   MsgBox "PortableLauncher.bat was not found next to this script:" & vbCrLf & root, _
          vbCritical, "Portable Launcher"
   WScript.Quit 1
End If

cfg = ReadUtf8(cfgPath)
showConsole = GetCfg(cfg, "ShowConsole", "0")

' dragging an installer onto this file always needs a visible console
If WScript.Arguments.Count > 0 Then showConsole = "1"

If showConsole = "1" Then
   style = 1
Else
   style = 0
End If

' tell the batch script not to sit on a "pause" that nobody can see
Set env = sh.Environment("PROCESS")
env("PORTABLE_NO_PAUSE") = "1"

cmd = """" & bat & """"
For i = 0 To WScript.Arguments.Count - 1
   cmd = cmd & " """ & WScript.Arguments(i) & """"
Next

rc = sh.Run(cmd, style, True)

If rc <> 0 Then
   MsgBox "Launch failed (exit code " & rc & ")." & vbCrLf & vbCrLf & _
          "Run PortableLauncher.bat directly to see the full output.", _
          vbExclamation, "Portable Launcher"
End If


' ---------------------------------------------------------------- helpers ---
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
