---
name: reboot-machine
description: Reboot this Windows machine safely — check that it will come back on its own with all four agents running, reboot, confirm the reboot is scheduled. Use when asked to reboot or restart, to apply an update that needs a restart, or to abort a scheduled reboot.
---

# Rebooting

Marco is not at the machine: if the relaunch chain is broken, a reboot
leaves no agent running and no way in. Check the chain, reboot, confirm.

## Pre-flight

```powershell
Get-ScheduledTask ClaudeAgentSupervisor,ClaudeCleanupWatchdog | Select TaskName,State,@{n='Run';e={$_.Principal.RunLevel}},@{n='Limit';e={$_.Settings.ExecutionTimeLimit}}
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' | Select AutoAdminLogon,DefaultUserName,AutoLogonCount
Get-BitLockerVolume C: | Select VolumeStatus,ProtectionStatus
Get-Command claude; Test-Path C:\data\startup\agent-supervisor.ps1
shutdown /a
```
Expected: both tasks Ready, RunLevel Highest, `ClaudeAgentSupervisor` with
`ExecutionTimeLimit PT0S`; `AutoAdminLogon=1`, `DefaultUserName=sonta`, no
`AutoLogonCount` (the password is an LSA secret set by
`C:\data\startup\Autologon64.exe`, not a `DefaultPassword` value — never
add one); BitLocker `ProtectionStatus Off`; `claude` on PATH; `shutdown /a`
exits 1116 when nothing is pending (0 means it cancelled a pending one).

## Reboot

Tell Marco first — the session dies with the machine. Then, as its own
PowerShell call (never chained: `$LASTEXITCODE` would report the other
command):
```powershell
shutdown /r /t 20 /c "Restart requested by Claude Code"
```
Confirm by issuing it again: exit 1190 ("a system shutdown has already
been scheduled") proves the first took. `shutdown` has no `/query`; passing
one prints the help text and exits 1. Abort with `shutdown /a`.

## Afterwards

All four agents come back within about a minute once the network is up
(`agent-supervisor.ps1` polls `https://api.anthropic.com/` every 5 s, then
launches all four, one detached `claude` process each — no restart if one
later crashes, it stays down until the next logon). None back: autologon
or the supervisor script/task itself. Some back: that agent's folder or
its `claude` launch specifically. Diagnosis needs physical access — say so
plainly.

Power: sleep/standby timeout is 0 on both AC and DC in all four power
schemes; the display may switch off after 5 minutes, which does not affect
screen capture.
