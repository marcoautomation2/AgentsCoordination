---
name: run-manager-gui-tests
description: Execute the Fearless manager's GUI acceptance tests (https://marcoautomation2.github.io/shared-docs/manager-gui-tests.txt) by driving the real fearlessManaged*w.exe with mouse and keyboard, screenshotting each step. Use to run the manager GUI test plan, verify a manager GUI change by hand, or reproduce a manager GUI bug.
---

# Driving the manager GUI

There is no computer-use tool: drive it from PowerShell with Win32 calls —
launch, screenshot, look at the screenshot (Read), click or type,
screenshot again. Do it yourself, not through a subagent.

## Build the manager

Kill any running manager first (it locks `runtime\lib\modules`), then from
`Coordinator\test`:
```powershell
taskkill /F /IM fearlessManaged0_001w.exe
& "C:\Program Files\Java\jdk-26.0.2\bin\java.exe" --module-path ..\..\Commons\Commons.jar --add-modules Commons mainCoordinator\DeployManagedFearless.java
```
Output: `StandardLibrary\fearlessManagedArtefact\fearlessManaged0_001\fearlessManaged0_001w.exe`.

## Test projects

The plan's projects are copies of `StandardLibrary\integrationTests`
projects with one distinctly named marker: `helloWorld` → `01_hello_world`
(marker `hello_world.fearless`), `mainInMethod` → `02_mains_in_methods`
(`mains_in_methods.fearless`), `testGui1` → `09_gui_basics`
(`gui_basics.fearless`). Copy them into the session scratchpad, delete the
copied `*.fearless` marker and write the new one (any text).

## Harness

Paste this at the start of every PowerShell call — shell state does not
persist between calls:

```powershell
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public class DpiAware{[DllImport("user32.dll")]public static extern bool SetProcessDPIAware();}'
[DpiAware]::SetProcessDPIAware() | Out-Null
Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;using System.Runtime.InteropServices;
public class W{[DllImport("user32.dll")]public static extern void mouse_event(uint f,int x,int y,uint d,int e);
[DllImport("user32.dll")]public static extern bool SetCursorPos(int x,int y);
[DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr h);}
"@
function Shot($p){ $b=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds; $bm=New-Object System.Drawing.Bitmap $b.Width,$b.Height; $g=[System.Drawing.Graphics]::FromImage($bm); $g.CopyFromScreen($b.Location,[System.Drawing.Point]::Empty,$b.Size); $bm.Save($p); $g.Dispose(); $bm.Dispose() }
function Click($x,$y){ [W]::SetCursorPos($x,$y)|Out-Null; Start-Sleep -m 100; [W]::mouse_event(2,0,0,0,0); Start-Sleep -m 80; [W]::mouse_event(4,0,0,0,0); Start-Sleep -m 150 }
function Keys($k){ [System.Windows.Forms.SendKeys]::SendWait($k) }
function Launch($exe){ $env:JAVA_TOOL_OPTIONS='-Dsun.java2d.d3d=false -Dsun.java2d.opengl=false -Dsun.java2d.noddraw=true'; Start-Process $exe }
```

Two facts this depends on:
- The screen is 1920x1080 at 150% scaling: without `SetProcessDPIAware()`
  before `System.Windows.Forms` loads, screenshots come back cropped to
  1280x720 and clicks land short.
- Java2D's D3D/OpenGL pipeline paints a blank client area for screen
  capture in this session; `Launch` forces the software pipeline through
  `JAVA_TOOL_OPTIONS`. Every child JVM the manager runs then prints a
  harmless `Picked up JAVA_TOOL_OPTIONS` line to its output.

The manager window lands somewhere different on every launch
(`setLocationByPlatform`): after launching, foreground it
(`[W]::SetForegroundWindow((Get-Process fearlessManaged0_001w).MainWindowHandle)`),
screenshot, and read coordinates off that screenshot. Never reuse
coordinates from an earlier launch. Drag with a run of `SetCursorPos`
calls between `mouse_event(2,...)` and `mouse_event(4,...)`.

JFileChooser ("Add folder..."): clicking a list entry overwrites the
"Folder name" field with that entry. Click the text field, `Keys "^a"`,
`Keys "<full path>"`, screenshot to confirm, then click Open.

## Clean state between tests

```powershell
taskkill /F /IM fearlessManaged0_001w.exe
Remove-Item -Recurse -Force "<managerExeDir>\..\fearless0_001"   # manager data folder
Remove-Item -Recurse -Force "<projectFolder>\.fearless_out"
Remove-Item "HKCU:\Software\Classes\.fearless" -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem "HKCU:\Software\Classes" | Where-Object PSChildName -like "*earless*" | Remove-Item -Recurse -Force
```
The registry lines unclaim `.fearless` (Test 1's setup); open a fresh
Explorer window afterwards, since an open one keeps showing the old icon.

A bug found this way is fixed and PR'd, nothing more: publishing happens
only on an explicit ask.
