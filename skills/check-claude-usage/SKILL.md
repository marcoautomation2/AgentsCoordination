---
name: check-claude-usage
description: Read Marco's current Anthropic usage limits — the rolling ~5-hour "Current session" and the "Weekly limits" percentages and reset times shown at claude.ai/settings/usage — by opening the page in the logged-in browser on this machine, screenshotting it and OCRing the numbers. Use before deciding how hard to run a long or scheduled task.
---

# Checking claude.ai usage limits

No API exposes these two numbers; the only source is the page, and the only
authenticated browser is the real Brave profile on this machine (Chromium
refuses `--remote-debugging-port` on the default profile, and the session
cookie is device-bound, so a copied profile cannot log in). So: real
window, screenshot, local Tesseract OCR — no image ever reaches an LLM.

```powershell
& "$HOME\.claude\skills\check-claude-usage\check_usage.ps1"
```

It opens a new maximized Brave window on the usage page, resets zoom to
100% (Chromium persists zoom per origin), screenshots the 1920x1080 screen,
crops the settings pane (`485,140,1235,760`), upscales it 2x, OCRs it,
closes every tab with Ctrl+W (closing the last one exits cleanly; never
force-kill — an unclean exit puts a "Restore pages?" bubble over the
numbers on the next launch) and prints:

```
Current session: NN% used, resets in Xh Ym
Weekly limits: NN% used, resets <day> <time>
```

Report those two lines verbatim. Readings are cached for 15 minutes in
`state\last-check.json` — one account, four agents, so a fresh reading from
any of them is valid for all. About 15 seconds when not cached; don't call
it in a tight loop.

On error (`Write-Error` carrying the raw OCR text and the
`usage_*_crop.png` path) the page is a login page, a Cloudflare check, or
the layout moved. Say so and stop; never try to log in. For a layout
change, find the new crop rectangle from a fresh full screenshot and update
`$cropRect` in the script.

Facts the script depends on: the display is 1920x1080 at 150% scaling, so
`SetProcessDPIAware()` runs before `System.Windows.Forms` loads (otherwise
the capture is the top-left 1280x720); the 6-second render wait is a fixed
heuristic; Tesseract is at `C:\Program Files\Tesseract-OCR`, Brave under
`%LOCALAPPDATA%\BraveSoftware`.
