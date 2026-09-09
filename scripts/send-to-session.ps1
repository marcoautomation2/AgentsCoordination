[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Name,
  [Parameter(Mandatory=$true)][string]$Message,
  [int]$TimeoutMs = 5000
)
$ErrorActionPreference = 'Stop'

$sessDir = Join-Path $env:USERPROFILE '.claude\sessions'
$live = Get-ChildItem -LiteralPath $sessDir -Filter '*.json' | ForEach-Object {
  $info = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
  if (-not $info.messagingSocketPath) { return }
  if (-not (Get-Process -Id $info.pid -ErrorAction SilentlyContinue)) { return }
  $info
}

$match = @($live | Where-Object { $_.name -eq $Name })
if ($match.Count -eq 0) {
  $match = @($live | Where-Object { (Split-Path $_.cwd -Leaf) -eq $Name -or $_.name -like "$Name-*" })
}
if ($match.Count -ne 1) {
  throw "expected exactly one live session for '$Name', found $($match.Count) (live: $(($live | ForEach-Object { $_.name }) -join ', '))"
}
$target = $match[0]

$keyFile = Get-ChildItem -LiteralPath $sessDir -Filter "$($target.pid).*.key" | Select-Object -First 1
$token = (Get-Content -LiteralPath $keyFile.FullName -Raw | ConvertFrom-Json).peerToken

$auth = @{ type = 'auth'; token = $token } | ConvertTo-Json -Compress
$user = @{ type = 'user'; message = @{ role = 'user'; content = $Message } } | ConvertTo-Json -Compress

$pipe = New-Object System.IO.Pipes.NamedPipeClientStream '.', ($target.messagingSocketPath -replace '^\\\\\.\\pipe\\', ''), ([System.IO.Pipes.PipeDirection]::InOut)
try {
  try { $pipe.Connect($TimeoutMs) } catch {
    if ($_.Exception.InnerException -is [UnauthorizedAccessException]) {
      throw "'$Name' (pid $($target.pid)) runs at a higher integrity level than this process: register the caller's scheduled task with -RunLevel Highest."
    }
    throw
  }
  $writer = New-Object System.IO.StreamWriter $pipe
  $writer.NewLine = "`n"
  $writer.WriteLine($auth)
  $writer.WriteLine($user)
  $writer.Flush()
} finally {
  $pipe.Dispose()
}
$target
