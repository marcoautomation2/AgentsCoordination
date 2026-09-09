$ErrorActionPreference = 'Stop'

$root = 'C:\data\winCoordinator'
$logDir = Join-Path $root 'logs'
$diagFile = Join-Path $logDir 'diagnostic.log'
$stateFile = Join-Path $logDir 'watchdog-state.json'
$whitelistFile = Join-Path $root 'scripts\process-whitelist.txt'
$marcoLeftovers = 'C:\Users\sonta\Desktop\MarcoLeftovers'

New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$runStart = Get-Date
$logLines = New-Object System.Collections.Generic.List[string]
function Log($msg) { $logLines.Add("[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] $msg") }

function Remove-ItemSafe($path) {
  if ($path -like "$marcoLeftovers*") {
    Log "REFUSED to touch protected path: $path"
    return
  }
  Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
}

$state = if (Test-Path $stateFile) {
  Get-Content $stateFile -Raw | ConvertFrom-Json
} else {
  [pscustomobject]@{ lastEventCheckUtc = (Get-Date).ToUniversalTime().AddHours(-1).ToString('o') }
}

# --- 1. Whitelist + age enforcement: anything not whitelisted, alive > 1h, dies ---
try {
  $whitelist = Get-Content $whitelistFile |
    Where-Object { $_ -and $_.Trim() -and -not $_.Trim().StartsWith('#') } |
    ForEach-Object { $_.Trim().ToLowerInvariant() }
  $now = Get-Date
  $killedCount = 0
  Get-CimInstance Win32_Process | ForEach-Object {
    if ($_.ProcessId -le 4 -or -not $_.CreationDate) { return }
    $name = [IO.Path]::GetFileNameWithoutExtension($_.Name).ToLowerInvariant()
    if ($whitelist -contains $name) { return }
    $ageMin = ($now - $_.CreationDate).TotalMinutes
    if ($ageMin -lt 60) { return }
    try {
      Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop
      Log "killed non-whitelisted process: $($_.Name) (pid $($_.ProcessId), age $([math]::Round($ageMin))m, cmd: $($_.CommandLine))"
      $killedCount++
    } catch {
      Log "FAILED to kill $($_.Name) (pid $($_.ProcessId)): $($_.Exception.Message)"
    }
  }
  if ($killedCount -eq 0) { Log "process sweep: clean" }
} catch {
  Log "process sweep FAILED: $($_.Exception.Message)"
}

# --- 2. Stale git index.lock files ---
try {
  $lockCount = 0
  $gitRunning = [bool](Get-Process git -ErrorAction SilentlyContinue)
  Get-ChildItem 'C:\data' -Directory -Filter 'fearlessBranch*' -ErrorAction SilentlyContinue | ForEach-Object {
    Get-ChildItem $_.FullName -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      $lock = Join-Path $_.FullName '.git\index.lock'
      if (Test-Path $lock) {
        $ageMin = ((Get-Date) - (Get-Item $lock).LastWriteTime).TotalMinutes
        if ($ageMin -gt 15 -and -not $gitRunning) {
          Remove-ItemSafe $lock
          Log "removed stale git lock: $lock (age $([math]::Round($ageMin))m)"
          $lockCount++
        }
      }
    }
  }
  if ($lockCount -eq 0) { Log "git lock check: clean" }
} catch {
  Log "git lock check FAILED: $($_.Exception.Message)"
}

# --- 3. Autonomous stale-disk cleanup ---
# Every deletion below distinguishes "removed" from "still locked by a running
# process" (Test-Path after the attempt) and logs both -- silently swallowing
# a locked-file failure looks identical to "nothing to do" otherwise, and
# genuinely hides real state (e.g. an old self-update backup still pinned by
# a long-running session that hasn't restarted since).

# 3a. Stale Claude build binaries: keep newest + any build a live process is executing.
try {
  $versionsDir = Join-Path $HOME '.local\share\claude\versions'
  if (Test-Path $versionsDir) {
    $builds = @(Get-ChildItem $versionsDir -File | Sort-Object LastWriteTime -Descending)
    if ($builds.Count -gt 1) {
      $inUse = @(Get-Process -ErrorAction SilentlyContinue |
                 ForEach-Object { try { $_.MainModule.FileName } catch {} } |
                 Where-Object { $_ -and $_.StartsWith($versionsDir, 'OrdinalIgnoreCase') } |
                 ForEach-Object { Split-Path $_ -Leaf })
      $freed = 0; $removed = 0; $locked = 0
      foreach ($b in $builds[1..($builds.Count - 1)]) {
        if ($inUse -contains $b.Name) { continue }
        $sz = $b.Length
        Remove-ItemSafe $b.FullName
        if (-not (Test-Path $b.FullName)) { $freed += $sz; $removed++ } else { $locked++ }
      }
      if ($removed -gt 0) { Log "pruned $removed stale Claude build(s) ($([math]::Round($freed/1MB,1)) MB)" }
      if ($locked -gt 0) { Log "$locked stale Claude build(s) still locked, will retry next hour" }
    }
  }
} catch {
  Log "Claude build prune FAILED: $($_.Exception.Message)"
}

# 3b. Spilled tool-result files older than 7 days.
try {
  $projectsDir = Join-Path $HOME '.claude\projects'
  if (Test-Path $projectsDir) {
    $cutoff = (Get-Date).AddDays(-7)
    $freed = 0; $removed = 0; $locked = 0
    Get-ChildItem $projectsDir -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object { $_.DirectoryName -like '*\tool-results' -and $_.LastWriteTime -lt $cutoff } |
      ForEach-Object {
        $sz = $_.Length
        Remove-ItemSafe $_.FullName
        if (-not (Test-Path $_.FullName)) { $freed += $sz; $removed++ } else { $locked++ }
      }
    Get-ChildItem $projectsDir -Recurse -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -eq 'tool-results' -and -not (Get-ChildItem $_.FullName -Force -ErrorAction SilentlyContinue) } |
      ForEach-Object { Remove-ItemSafe $_.FullName }
    if ($removed -gt 0) { Log "pruned $removed spilled tool-result file(s) ($([math]::Round($freed/1MB,1)) MB)" }
    if ($locked -gt 0) { Log "$locked spilled tool-result file(s) still locked, will retry next hour" }
  }
} catch {
  Log "tool-result prune FAILED: $($_.Exception.Message)"
}

# 3c. Generic stale-directory sweep: top-level items under a path whose newest
# content is >N days old get removed. A directory's age is its
# most-recently-touched file, so anything still active is never touched.
# Returns (freedBytes, removedCount, lockedCount).
function Clear-StaleTemp($tempPath, $ageDays) {
  $freed = 0; $removed = 0; $locked = 0
  if (-not (Test-Path $tempPath)) { return @($freed, $removed, $locked) }
  $cutoff = (Get-Date).AddDays(-$ageDays)
  foreach ($item in @(Get-ChildItem $tempPath -Force -ErrorAction SilentlyContinue)) {
    if ($item.PSIsContainer) {
      $files = @(Get-ChildItem $item.FullName -Recurse -File -Force -ErrorAction SilentlyContinue)
      $newest = if ($files.Count -gt 0) { ($files | Sort-Object LastWriteTime -Descending)[0].LastWriteTime } else { $item.LastWriteTime }
      $sz = ($files | Measure-Object Length -Sum).Sum
      if (-not $sz) { $sz = 0 }
    } else {
      $newest = $item.LastWriteTime
      $sz = $item.Length
    }
    if ($newest -lt $cutoff) {
      Remove-ItemSafe $item.FullName
      if (-not (Test-Path $item.FullName)) { $freed += $sz; $removed++ } else { $locked++ }
    }
  }
  return @($freed, $removed, $locked)
}
try {
  $r1 = Clear-StaleTemp $env:TEMP 7
  $r2 = Clear-StaleTemp 'C:\Windows\Temp' 7
  $totalFreed = $r1[0] + $r2[0]
  $totalRemoved = $r1[1] + $r2[1]
  $totalLocked = $r1[2] + $r2[2]
  if ($totalRemoved -gt 0) { Log "pruned $totalRemoved stale temp item(s) ($([math]::Round($totalFreed/1MB,1)) MB)" }
  if ($totalLocked -gt 0) { Log "$totalLocked stale temp item(s) still locked, will retry next hour" }
  if ($totalRemoved -eq 0 -and $totalLocked -eq 0) { Log "temp sweep: clean" }
} catch {
  Log "temp sweep FAILED: $($_.Exception.Message)"
}

# 3d. Recycle bin: unconditional empty (no age filtering -- reliable per-item
# deletion dates aren't available via PowerShell; contents are already
# user/system-deleted material, not primary storage).
try {
  Clear-RecycleBin -DriveLetter C -Force -ErrorAction SilentlyContinue
  Log "recycle bin emptied"
} catch {
  Log "recycle bin clear FAILED: $($_.Exception.Message)"
}

# 3e. Stale Claude CLI self-updater backups: each update renames the previous
# claude.exe to claude.exe.old.<timestamp> before writing the new one, and
# never cleans it up. Usually still locked until every long-running session
# that was alive during the swap restarts and releases the old file -- that's
# expected, not an error, so it's logged distinctly and just retried hourly.
try {
  $binDir = Join-Path $HOME '.local\bin'
  $cutoff = (Get-Date).AddMinutes(-30)
  $freed = 0; $removed = 0; $locked = 0
  Get-ChildItem $binDir -Filter 'claude.exe.old.*' -File -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.LastWriteTime -lt $cutoff) {
      $sz = $_.Length
      Remove-ItemSafe $_.FullName
      if (-not (Test-Path $_.FullName)) { $freed += $sz; $removed++ } else { $locked++ }
    }
  }
  if ($removed -gt 0) { Log "pruned $removed stale claude.exe.old backup(s) ($([math]::Round($freed/1MB,1)) MB)" }
  if ($locked -gt 0) { Log "$locked stale claude.exe.old backup(s) still locked (likely a session that hasn't restarted since that update), will retry next hour" }
} catch {
  Log "claude updater-backup prune FAILED: $($_.Exception.Message)"
}

# 3f. Fearless build/generated output: explicitly gitignored per-repo (see
# each repo's .gitignore), so regenerable by design. Deliberately excludes
# externalJars (a dependency cache -- old there means stable, not stale).
try {
  $genPaths = @(
    'out', 'Commons\.out', 'Coordinator\.out', 'StandardLibrary\.out',
    'StandardLibrary\gen_java_base', 'StandardLibrary\dbgOut',
    'StandardLibrary\fearlessArtefact', 'StandardLibrary\fearlessManagedArtefact'
  )
  $freed = 0; $removed = 0; $locked = 0
  Get-ChildItem 'C:\data' -Directory -Filter 'fearlessBranch*' -ErrorAction SilentlyContinue | ForEach-Object {
    $branchDir = $_.FullName
    foreach ($p in $genPaths) {
      $r = Clear-StaleTemp (Join-Path $branchDir $p) 7
      $freed += $r[0]; $removed += $r[1]; $locked += $r[2]
    }
    # .fearless_out is per-integration-test-project, not a single fixed path.
    $integrationTestsDir = Join-Path $branchDir 'StandardLibrary\integrationTests'
    Get-ChildItem $integrationTestsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      $r = Clear-StaleTemp (Join-Path $_.FullName '.fearless_out') 7
      $freed += $r[0]; $removed += $r[1]; $locked += $r[2]
    }
  }
  if ($removed -gt 0) { Log "pruned $removed stale Fearless build-output item(s) ($([math]::Round($freed/1MB,1)) MB)" }
  if ($locked -gt 0) { Log "$locked stale Fearless build-output item(s) still locked, will retry next hour" }
} catch {
  Log "Fearless build-output prune FAILED: $($_.Exception.Message)"
}

# 3g. Downloads: personal content, so moved (never deleted) into
# MarcoLeftovers once stale.
function Move-StaleToLeftovers($srcPath, $ageDays) {
  $count = 0
  if (-not (Test-Path $srcPath)) { return $count }
  $cutoff = (Get-Date).AddDays(-$ageDays)
  foreach ($item in @(Get-ChildItem $srcPath -Force -ErrorAction SilentlyContinue)) {
    if ($item.Name -eq 'desktop.ini') { continue }
    if ($item.PSIsContainer) {
      $files = @(Get-ChildItem $item.FullName -Recurse -File -Force -ErrorAction SilentlyContinue)
      $newest = if ($files.Count -gt 0) { ($files | Sort-Object LastWriteTime -Descending)[0].LastWriteTime } else { $item.LastWriteTime }
    } else {
      $newest = $item.LastWriteTime
    }
    if ($newest -ge $cutoff) { continue }
    $destPath = Join-Path $marcoLeftovers $item.Name
    if (Test-Path $destPath) {
      $stamp = Get-Date -Format 'yyyyMMddHHmmss'
      $destPath = Join-Path $marcoLeftovers "$([IO.Path]::GetFileNameWithoutExtension($item.Name))_$stamp$([IO.Path]::GetExtension($item.Name))"
    }
    try {
      Move-Item -LiteralPath $item.FullName -Destination $destPath -ErrorAction Stop
      $count++
    } catch {
      Log "FAILED to move $($item.FullName) to MarcoLeftovers: $($_.Exception.Message)"
    }
  }
  return $count
}
try {
  $moved = Move-StaleToLeftovers (Join-Path $HOME 'Downloads') 7
  if ($moved -gt 0) { Log "moved $moved stale Downloads item(s) into MarcoLeftovers" }
  else { Log "Downloads sweep: clean" }
} catch {
  Log "Downloads sweep FAILED: $($_.Exception.Message)"
}

# --- 4. Disk space (informational) ---
try {
  $freeGB = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
  Log "disk free: ${freeGB}GB on C:"
  if ($freeGB -lt 10) { Log "ATTENTION: critically low disk space (${freeGB}GB free)" }
  elseif ($freeGB -lt 20) { Log "ATTENTION: disk space getting low (${freeGB}GB free)" }
} catch {
  Log "disk check FAILED: $($_.Exception.Message)"
}

# --- 5. Core agent fleet health (informational) ---
try {
  foreach ($t in 'ClaudeWin1Agent','ClaudeWin2Agent','ClaudeWin3Agent','ClaudeWinCoordinatorAgent') {
    $task = Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue
    if (-not $task) { Log "ATTENTION: scheduled task '$t' is missing" }
    elseif ($task.State -eq 'Disabled') { Log "ATTENTION: scheduled task '$t' is disabled" }
  }
  $claudeCount = (Get-Process claude -ErrorAction SilentlyContinue | Measure-Object).Count
  Log "claude.exe processes running: $claudeCount"
  if ($claudeCount -lt 4) { Log "ATTENTION: only $claudeCount claude.exe process(es) running, expected at least 4" }
} catch {
  Log "fleet health check FAILED: $($_.Exception.Message)"
}

# --- 6. Pending reboot (informational) ---
try {
  $pending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
             (Test-Path 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Auto Update\RebootRequired')
  if ($pending) { Log "INFO: Windows has a pending-reboot flag set" }
} catch {
  Log "reboot-flag check FAILED: $($_.Exception.Message)"
}

# --- 7. Recent Critical/Error events (informational) ---
try {
  $since = [datetime]$state.lastEventCheckUtc
  $nowUtc = (Get-Date).ToUniversalTime()
  $errCount = 0
  try {
    $events = Get-WinEvent -FilterHashtable @{ LogName = 'System','Application'; Level = 1,2; StartTime = $since } -ErrorAction Stop
    $errCount = @($events).Count
  } catch {
    if ($_.Exception.Message -notmatch 'No events were found') { throw }
  }
  if ($errCount -gt 0) { Log "Critical/Error events since last check: $errCount" }
  $state.lastEventCheckUtc = $nowUtc.ToString('o')
} catch {
  Log "event log check FAILED: $($_.Exception.Message)"
}

# --- 8. Daily 5:45am review freshness (informational safety net) ---
try {
  $existingForCheck = @(Get-Content $diagFile -ErrorAction SilentlyContinue)
  $lastReviewLine = $existingForCheck | Where-Object { $_ -match '\[DAILY REVIEW\]' } | Select-Object -Last 1
  if ($lastReviewLine -and $lastReviewLine -match '^\[(?<ts>[\d-]+ [\d:]+)\]') {
    $hoursSince = ((Get-Date) - [datetime]$matches['ts']).TotalHours
    if ($hoursSince -gt 30) { Log "ATTENTION: daily winCoordinator review hasn't run in $([math]::Round($hoursSince,1))h (expected ~24h)" }
  }
} catch {
  Log "daily-review freshness check FAILED: $($_.Exception.Message)"
}

# --- persist state, write + rotate diagnostic file ---
$state | ConvertTo-Json -Depth 5 | Set-Content -Path $stateFile -Encoding utf8
Add-Content -Path $diagFile -Value $logLines -Encoding utf8

$existing = @(Get-Content $diagFile -ErrorAction SilentlyContinue)
if ($existing.Count -gt 8000) {
  $existing | Select-Object -Last 4000 | Set-Content -Path $diagFile -Encoding utf8
}

$elapsed = ((Get-Date) - $runStart).TotalSeconds
Add-Content -Path $diagFile -Value "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] run complete ($([math]::Round($elapsed,1))s)" -Encoding utf8
