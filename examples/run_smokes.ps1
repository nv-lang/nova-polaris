# SPDX-License-Identifier: MIT OR Apache-2.0
# Polaris examples — build every example --strict-effects, then for each one
# that runs a server: start it, hit it with 1-2 curl requests, stop it.
# Plan 230 Ф.1 gate.
#
# Env overrides (all optional):
#   NOVA_BIN              - path to the nova CLI binary (default: `nova`,
#                            resolved via PATH)
#   NOVA_GC_LIB_DIR / NOVA_GC_INCLUDE_DIR / NOVA_RT_DIR / NOVA_CG_INCLUDE
#                         - Boehm GC + nova_rt + codegen-include paths
#   NOVA_STD_PATH         - stdlib source root (needed when building outside
#                            the nova repo itself)

$ErrorActionPreference = 'Continue'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$NovaBin = if ($env:NOVA_BIN) { $env:NOVA_BIN } else { 'nova' }

$Pass = 0
$Fail = 0
$FailedNames = @()

# example dir -> @{ port = N; checks = @(@{path=...; expect=...}, ...) }
$SmokePlan = @{
  '01-hello'          = @{ port = 18082; checks = @(@{ path = '/hello/nova'; expect = 'hello, nova' }, @{ path = '/'; expect = 'hello, world' }) }
  '02-routing'        = @{ port = 18083; checks = @(@{ path = '/users/42'; expect = 'user 42' }, @{ path = '/api/widgets/9'; expect = 'widget 9' }) }
  '03-json-api'       = @{ port = 18084; checks = @(@{ path = '/todos'; expect = '[]' }) }
  '04-middleware'     = @{ port = 18085; checks = @(@{ path = '/x'; expect = 'base' }) }
  '05-auth'           = @{ port = 18086; checks = @(@{ path = '/public'; expect = 'public' }) }
  '06-static-site'    = @{ port = 18087; checks = @(@{ path = '/assets/style.css'; expect = 'font-family' }, @{ path = '/'; expect = 'h1' }) }
  '07-sse-stream'     = @{ port = 18088; checks = @(@{ path = '/events'; expect = 'event:' }) }
  '08-websocket-echo' = @{ port = 18089; checks = @(@{ path = '/health'; expect = 'ok' }) }
  '09-graceful'       = @{ port = 18090; checks = @(@{ path = '/health'; expect = 'ok' }, @{ path = '/policy'; expect = 'max_inflight' }) }
  '10-mini-service'   = @{ port = 18091; checks = @(@{ path = '/health'; expect = 'ok' }, @{ path = '/articles'; expect = '[]' }) }
}

function Check-One {
  param([string]$Dir)
  $Name = Split-Path -Leaf $Dir
  Write-Host "=== $Name ==="

  Push-Location $Dir
  & $NovaBin build --strict-effects src/main.nv
  $buildExit = $LASTEXITCODE
  Pop-Location

  if ($buildExit -ne 0) {
    Write-Host "BUILD-FAIL $Name"
    $script:Fail++
    $script:FailedNames += "$Name (build)"
    return
  }
  Write-Host "BUILD-OK   $Name"

  if (-not $SmokePlan.ContainsKey($Name)) {
    Write-Host "SMOKE-SKIP $Name (no smoke plan yet)"
    $script:Pass++
    return
  }

  $plan = $SmokePlan[$Name]
  $exePath = Join-Path $Dir 'main.exe'
  $proc = Start-Process -FilePath $exePath -WorkingDirectory $Dir -PassThru -WindowStyle Hidden
  Start-Sleep -Seconds 1

  $ok = $true
  foreach ($chk in $plan.checks) {
    $url = "http://127.0.0.1:$($plan.port)$($chk.path)"
    try {
      $resp = Invoke-WebRequest -Uri $url -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
      $body = $resp.Content
    } catch {
      if ($_.Exception.Response) {
        $stream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $body = $reader.ReadToEnd()
      } else {
        $body = ''
      }
    }
    if ($body -like "*$($chk.expect)*") {
      Write-Host "  OK   GET $($chk.path) -> contains `"$($chk.expect)`""
    } else {
      Write-Host "  FAIL GET $($chk.path) -> expected `"$($chk.expect)`", got: $body"
      $ok = $false
    }
  }

  if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }

  if ($ok) {
    Write-Host "SMOKE-OK   $Name"
    $script:Pass++
  } else {
    Write-Host "SMOKE-FAIL $Name"
    $script:Fail++
    $script:FailedNames += "$Name (smoke)"
  }
}

Get-ChildItem -Path $ScriptDir -Directory | Where-Object { $_.Name -match '^\d\d-' } | Sort-Object Name | ForEach-Object {
  Check-One -Dir $_.FullName
}

Write-Host ""
Write-Host "===== SUMMARY ====="
Write-Host "PASS: $Pass  FAIL: $Fail"
if ($Fail -gt 0) {
  Write-Host "Failed: $($FailedNames -join ', ')"
  exit 1
}
exit 0
