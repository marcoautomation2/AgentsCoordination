$ErrorActionPreference = 'Stop'
$sender = 'C:\data\winCoordinator\scripts\send-to-session.ps1'
$scheduleFile = 'C:\data\winCoordinator\config\scheduledTasks.txt'

function send($agentName, $msg) {
  & $sender -Name $agentName -Message $msg
}

function start_agent($agentName, $workDir) {
  Start-Process -FilePath 'claude' -ArgumentList "--remote-control $agentName -n $agentName" -WorkingDirectory $workDir -WindowStyle Maximized
}

function check_action() {
  if (-not (Test-Path -LiteralPath $scheduleFile)) {
    send 'winCoordinator' 'scheduler_failed'
    return -1
  }
  $now = Get-Date
  foreach ($line in Get-Content -LiteralPath $scheduleFile) {
    if (-not $line.Trim()) { continue }
    $parts = $line -split ',' | ForEach-Object { $_.Trim() }
    $time = [datetime]::ParseExact($parts[0], 'HH:mm', $null)
    $scheduled = Get-Date -Hour $time.Hour -Minute $time.Minute -Second 0
    if ([math]::Abs(($now - $scheduled).TotalMinutes) -lt 1) {
      send $parts[1] $parts[2]
      return 10
    }
  }
  return 1
}

while ($true) {
  try {
    Invoke-WebRequest -Uri 'https://api.anthropic.com/' -TimeoutSec 10 -UseBasicParsing | Out-Null
    break
  } catch {
    Start-Sleep -Seconds 5
  }
}

start_agent 'win1' 'C:\data\fearlessBranch1'
start_agent 'win2' 'C:\data\fearlessBranch2'
start_agent 'win3' 'C:\data\fearlessBranch3'
start_agent 'winCoordinator' 'C:\data\winCoordinator'

Start-Sleep -Seconds 60

try {
  while ($true) {
    $res = check_action
    if ($res -eq -1) { break }
    Start-Sleep -Seconds ($res * 60)
  }
} catch {
  send 'winCoordinator' 'scheduler_failed'
}
