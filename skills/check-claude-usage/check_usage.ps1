<#
.SYNOPSIS
  Opens claude.ai's usage settings page in a real, visible, foreground browser
  window, screenshots it, and closes the window again — without disturbing any
  other browser windows that may already be open.

.DESCRIPTION
  Designed for the "check-claude-usage" skill. Crops the settings panel out
  of the screenshot, upscales it, runs it through local Tesseract OCR, and
  regex-extracts the numbers, printing:
    Current session: NN% used, resets in Xh Ym
    Weekly limits: NN% used, resets <day> <time>
  No LLM ever reads the image — these numbers are not available through any
  API or programmatic call, but plain OCR is enough once the page is open.

.PARAMETER Url
  Defaults to the usage settings page.

.PARAMETER OutDir
  Directory to save the screenshot/crop/OCR intermediates into. Defaults to
  a temp folder.
#>
param(
  [string]$Url = "https://claude.ai/new#settings/usage",
  [string]$OutDir = "$env:TEMP\claude-usage-check",
  [int]$MaxCacheAgeMinutes = 15
)

$ErrorActionPreference = "Stop"

# One account, four agents sharing $HOME: a reading from any of them is valid
# for all. The cache also keeps the injected input events (which reset the OS
# idle timer) spaced out past the display's 5-minute timeout.
$cacheFile = "$HOME\.claude\skills\check-claude-usage\state\last-check.json"
if (Test-Path $cacheFile) {
  try {
    $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json
    $ageMin = ((Get-Date) - [datetime]$cache.timestamp).TotalMinutes
    if ($ageMin -lt $MaxCacheAgeMinutes) {
      Write-Output $cache.sessionLine
      Write-Output $cache.weeklyLine
      return
    }
  } catch {
    # unreadable/corrupt cache -- fall through to a real check
  }
}

# MUST run before System.Windows.Forms is loaded. This desktop is 1920x1080 at
# 150% scaling: a DPI-unaware process reads Screen.PrimaryScreen.Bounds as
# 1280x720 while CopyFromScreen still works in physical pixels, so the capture
# silently becomes the top-left two thirds of the screen.
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public class DpiAware{[DllImport("user32.dll")]public static extern bool SetProcessDPIAware();}'
[DpiAware]::SetProcessDPIAware() | Out-Null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---- locate the browser -----------------------------------------------
$bravePaths = @(
  "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe",
  "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe",
  "C:\Program Files (x86)\BraveSoftware\Brave-Browser\Application\brave.exe"
)
$browserExe = $bravePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $browserExe) {
  Write-Error "Could not find brave.exe in any known install location. Update `$bravePaths in this script if the browser or its path changed."
}
$procName = [System.IO.Path]::GetFileNameWithoutExtension($browserExe)  # "brave"

# ---- locate tesseract (OCR, not vision — plain text recognition on the
# cropped settings panel, so no image ever needs to reach an LLM) ---------
$tesseractPaths = @(
  "C:\Program Files\Tesseract-OCR\tesseract.exe",
  "C:\Program Files (x86)\Tesseract-OCR\tesseract.exe"
)
$tesseractExe = $tesseractPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $tesseractExe) {
  Write-Error "Could not find tesseract.exe. Install it (winget install UB-Mannheim.TesseractOCR) or update `$tesseractPaths in this script."
}

# ---- Win32 interop for foreground/maximize -----------------------------
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32Focus {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
}
"@
$SW_MAXIMIZE = 3
$SW_RESTORE  = 9

function Get-BraveWindow {
  Get-Process -Name $procName -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.MainWindowTitle -ne "" } |
    Sort-Object StartTime -Descending | Select-Object -First 1
}

function Focus-Window([System.Diagnostics.Process]$proc) {
  if ($proc.MainWindowHandle -eq [IntPtr]::Zero) { return $false }
  if ([Win32Focus]::IsIconic($proc.MainWindowHandle)) {
    [Win32Focus]::ShowWindowAsync($proc.MainWindowHandle, $SW_RESTORE) | Out-Null
    Start-Sleep -Milliseconds 300
  }
  [Win32Focus]::ShowWindowAsync($proc.MainWindowHandle, $SW_MAXIMIZE) | Out-Null
  [Win32Focus]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null
  return $true
}

# ---- launch, forcing a genuinely new top-level window ------------------
# --new-window guarantees a fresh window even if the browser is already
# running (Chromium's single-instance forwarding would otherwise just open a
# background tab in whatever window state already existed).
# --hide-crash-restore-bubble suppresses the "Restore pages?" popover, which
# renders in the top-right corner directly above the usage percentages.
Start-Process -FilePath $browserExe -ArgumentList @(
  "--hide-crash-restore-bubble", "--new-window", $Url) | Out-Null

# ---- find that new window: newest brave process with a real title ------
$deadline = (Get-Date).AddSeconds(15)
$target = $null
while ((Get-Date) -lt $deadline) {
  $target = Get-Process -Name $procName -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.MainWindowTitle -ne "" } |
    Sort-Object StartTime -Descending |
    Select-Object -First 1
  if ($target) { break }
  Start-Sleep -Milliseconds 400
}
if (-not $target) {
  Write-Error "Timed out waiting for the browser window to appear."
}

Focus-Window $target | Out-Null

# Give the SPA time to hydrate and render the usage panel after the window
# itself is already up. claude.ai is a heavier client-side app; a fixed
# settle delay is simpler and more robust here than trying to detect
# "network idle" from outside the process.
Start-Sleep -Seconds 6
# Re-assert foreground/maximized in case anything (a focus-stealing dialog,
# a slow window manager) knocked it back during the wait.
Focus-Window $target | Out-Null
Start-Sleep -Seconds 1

# Chromium persists zoom per origin in the browser profile across restarts, so
# whatever level claude.ai was last left at would otherwise carry into this
# capture. Reset to 100%, where the settings modal fits the 1920px screen whole.
[System.Windows.Forms.SendKeys]::SendWait("^0")
Start-Sleep -Seconds 2

# ---- screenshot ----------------------------------------------------------
# Captured only as OCR input, never read by an LLM: the settings panel is a
# fixed-layout modal at 1920x1080/100% zoom, so a plain crop + upscale +
# Tesseract pass reads its text reliably without spending a single vision
# token in the production path.
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outPath = Join-Path $OutDir "usage_$stamp.png"

$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
$gfx = [System.Drawing.Graphics]::FromImage($bmp)
$gfx.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
$gfx.Dispose()

# The settings modal's content pane always lands in this region at
# 1920x1080/100% zoom/maximized (see the DPI-aware note above for why that
# combination is guaranteed). 2x upscale before OCR is what gets Tesseract
# from misreading "11%" as "N%" to reading it correctly.
$cropRect = New-Object System.Drawing.Rectangle(485, 140, 1235, 760)
$cropped = $bmp.Clone($cropRect, $bmp.PixelFormat)
$scale = 2
$scaled = New-Object System.Drawing.Bitmap ($cropRect.Width * $scale), ($cropRect.Height * $scale)
$sg = [System.Drawing.Graphics]::FromImage($scaled)
$sg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$sg.DrawImage($cropped, 0, 0, $scaled.Width, $scaled.Height)
$sg.Dispose()
$cropPath = Join-Path $OutDir "usage_${stamp}_crop.png"
$scaled.Save($cropPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
$cropped.Dispose()
$scaled.Dispose()

$ocrBase = Join-Path $OutDir "usage_${stamp}_ocr"
& $tesseractExe $cropPath $ocrBase --psm 6 2>$null | Out-Null
$ocrText = Get-Content "$ocrBase.txt" -Raw

# ---- leave the browser closed and empty ---------------------------------
# The browser on this machine belongs to the agent, so there is never a tab
# worth preserving: close every one of them with Ctrl+W. Leaving any behind
# makes the next launch restore them alongside a fresh tab, so the tab count
# climbs by one per run. Closing the final tab exits the browser, and it exits
# cleanly — a forced kill would mark the profile as an unclean exit, which puts
# a "Restore pages?" popover over the top-right of the page on every later
# launch.
$deadline = (Get-Date).AddSeconds(45)
while ((Get-Date) -lt $deadline) {
  $w = Get-BraveWindow
  if (-not $w) { break }
  Focus-Window $w | Out-Null
  Start-Sleep -Milliseconds 250
  [System.Windows.Forms.SendKeys]::SendWait("^w")
  Start-Sleep -Milliseconds 450
}
# Anything still alive (a window that refused to close, a stray helper
# process) gets cleaned up so the next run starts from nothing.
if (Get-Process -Name $procName -ErrorAction SilentlyContinue) {
  foreach ($p in (Get-Process -Name $procName -ErrorAction SilentlyContinue |
                  Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero })) {
    $p.CloseMainWindow() | Out-Null
  }
  Start-Sleep -Seconds 3
  Stop-Process -Name $procName -Force -ErrorAction SilentlyContinue
}

# ---- extract the numbers from the OCR text -------------------------------
$pctMatches = [regex]::Matches($ocrText, '(\d{1,3})\s*%\s*used')
$resetMatches = [regex]::Matches($ocrText, 'Resets\s+([^\r\n]+)')

if ($ocrText -notmatch 'Current session' -or $ocrText -notmatch 'Weekly limits') {
  Write-Error "Usage panel not recognized in OCR text (login page, Cloudflare check, or layout change). Raw OCR saved at $ocrBase.txt for inspection:`n$ocrText"
}
if ($pctMatches.Count -lt 2 -or $resetMatches.Count -lt 2) {
  Write-Error "Expected 2 usage bars, found $($pctMatches.Count) percentages and $($resetMatches.Count) reset lines. Raw OCR saved at $ocrBase.txt for inspection:`n$ocrText"
}

$sessionLine = "Current session: $($pctMatches[0].Groups[1].Value)% used, resets $($resetMatches[0].Groups[1].Value.Trim())"
$weeklyLine = "Weekly limits: $($pctMatches[1].Groups[1].Value)% used, resets $($resetMatches[1].Groups[1].Value.Trim())"

New-Item -ItemType Directory -Force -Path (Split-Path $cacheFile) | Out-Null
[pscustomobject]@{
  timestamp   = (Get-Date).ToString('o')
  sessionLine = $sessionLine
  weeklyLine  = $weeklyLine
} | ConvertTo-Json | Set-Content -Path $cacheFile -Encoding utf8

Write-Output $sessionLine
Write-Output $weeklyLine
