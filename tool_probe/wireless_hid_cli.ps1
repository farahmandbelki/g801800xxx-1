param(
    [ValidateSet('help', 'list', 'status', 'module-info', 'receiver-info', 'module-methods', 'receiver-methods', 'module-watch', 'receiver-watch', 'set-name', 'reset-bt', 'raw', 'set-keyboard-filter', 'set-24g')]
    [string]$Command = 'help',

    [string]$Name,

    [string]$Value,

    [int]$Address = 10,

    [int]$Band = 1,

    [int]$ReceiverId = 10,

    [int]$TimeoutSeconds = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$backend = Join-Path $scriptDir 'probe_wireless_hid.ps1'

if (-not (Test-Path $backend)) {
    throw "Missing backend script: $backend"
}

function Invoke-Backend {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [string]$Target,

        [string]$ExtraValue
    )

    $argList = @(
        '-ExecutionPolicy', 'Bypass',
        '-File', $backend,
        '-Action', $Action,
        '-Target', $Target,
        '-TimeoutSeconds', [string]$TimeoutSeconds
    )

    if ($ExtraValue) {
        $argList += @('-Value', $ExtraValue)
    }

    & powershell.exe @argList
}

function Show-Help {
    Write-Output 'Wireless HID helper'
    Write-Output ''
    Write-Output 'Commands:'
    Write-Output '  list                List module and receiver HID config interfaces'
    Write-Output '  status              Show module and receiver interface summary'
    Write-Output '  module-info         Show module HID interface info'
    Write-Output '  receiver-info       Show receiver HID interface info'
    Write-Output '  module-methods      List callable methods on module HID object'
    Write-Output '  receiver-methods    List callable methods on receiver HID object'
    Write-Output '  module-watch        Watch module HID replies'
    Write-Output '  receiver-watch      Watch receiver HID replies'
    Write-Output '  set-name            Change module Bluetooth name'
    Write-Output '  reset-bt            Reset module Bluetooth pairing info'
    Write-Output '  raw                 Send a raw string payload to the module'
    Write-Output '  set-keyboard-filter Set GBKEY10 flag on module or receiver'
    Write-Output '  set-24g             Set 2.4G address, band and receiver id on both sides'
    Write-Output ''
    Write-Output 'Examples:'
    Write-Output '  .\wireless_hid_cli.ps1 -Command list'
    Write-Output '  .\wireless_hid_cli.ps1 -Command status'
    Write-Output '  .\wireless_hid_cli.ps1 -Command module-info'
    Write-Output '  .\wireless_hid_cli.ps1 -Command set-name -Name TESTKB'
    Write-Output '  .\wireless_hid_cli.ps1 -Command reset-bt'
    Write-Output '  .\wireless_hid_cli.ps1 -Command raw -Value TEST'
    Write-Output '  .\wireless_hid_cli.ps1 -Command set-keyboard-filter -Value 0'
    Write-Output '  .\wireless_hid_cli.ps1 -Command set-24g -Address 10 -Band 1 -ReceiverId 10'
}

function Show-Status {
    Write-Output '=== Module ==='
    Invoke-Backend -Action 'probe' -Target 'module'
    Write-Output ''
    Write-Output '=== Receiver ==='
    Invoke-Backend -Action 'probe' -Target 'receiver'
}

switch ($Command) {
    'help' {
        Show-Help
    }
    'list' {
        Invoke-Backend -Action 'list' -Target 'all'
    }
    'status' {
        Show-Status
    }
    'module-info' {
        Invoke-Backend -Action 'probe' -Target 'module'
    }
    'receiver-info' {
        Invoke-Backend -Action 'probe' -Target 'receiver'
    }
    'module-methods' {
        Invoke-Backend -Action 'methods' -Target 'module'
    }
    'receiver-methods' {
        Invoke-Backend -Action 'methods' -Target 'receiver'
    }
    'module-watch' {
        Invoke-Backend -Action 'watch' -Target 'module'
    }
    'receiver-watch' {
        Invoke-Backend -Action 'watch' -Target 'receiver'
    }
    'set-name' {
        if (-not $Name) {
            throw 'set-name requires -Name'
        }
        Invoke-Backend -Action 'set-blname' -Target 'module' -ExtraValue $Name
    }
    'reset-bt' {
        Invoke-Backend -Action 'reset-bt' -Target 'module'
    }
    'raw' {
        if (-not $Value) {
            throw 'raw requires -Value'
        }
        Invoke-Backend -Action 'raw' -Target 'module' -ExtraValue $Value
    }
    'set-keyboard-filter' {
        if (-not $Value) {
            throw 'set-keyboard-filter requires -Value'
        }
        Write-Output '=== Module ==='
        Invoke-Backend -Action 'set-gbkey10' -Target 'module' -ExtraValue $Value
        Write-Output ''
        Write-Output '=== Receiver ==='
        Invoke-Backend -Action 'set-gbkey10' -Target 'receiver' -ExtraValue $Value
    }
    'set-24g' {
        $packed = '{0},{1},{2}' -f $Address, $Band, $ReceiverId
        Write-Output '=== Module ==='
        Invoke-Backend -Action 'set-wf24' -Target 'module' -ExtraValue $packed
        Write-Output ''
        Write-Output '=== Receiver ==='
        Invoke-Backend -Action 'set-wf24' -Target 'receiver' -ExtraValue $packed
    }
    default {
        throw "Unsupported command: $Command"
    }
}
