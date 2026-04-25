param(
    [ValidateSet('list', 'methods', 'probe', 'watch', 'raw', 'set-blname', 'reset-bt', 'set-wifikg', 'set-stdlxs', 'set-gbkey10', 'set-wf24', 'ws', 'stqkbl', 'qcdmtdys', 'bldown')]
    [string]$Action = 'probe',

    [ValidateSet('module', 'receiver', 'all')]
    [string]$Target = 'module',

    [string]$DevicePath,

    [string]$Value,

    [int]$TimeoutSeconds = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([Environment]::Is64BitProcess) {
    $wowPowerShell = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path $wowPowerShell) {
        $argList = @(
            '-ExecutionPolicy', 'Bypass',
            '-File', $MyInvocation.MyCommand.Path
        )

        if ($PSBoundParameters.ContainsKey('Action')) {
            $argList += @('-Action', $Action)
        }
        if ($PSBoundParameters.ContainsKey('Target')) {
            $argList += @('-Target', $Target)
        }
        if ($PSBoundParameters.ContainsKey('DevicePath') -and $DevicePath) {
            $argList += @('-DevicePath', $DevicePath)
        }
        if ($PSBoundParameters.ContainsKey('Value') -and $Value) {
            $argList += @('-Value', $Value)
        }
        if ($PSBoundParameters.ContainsKey('TimeoutSeconds')) {
            $argList += @('-TimeoutSeconds', [string]$TimeoutSeconds)
        }

        & $wowPowerShell @argList
        exit $LASTEXITCODE
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolPath = Join-Path $scriptDir 'USBHIDControl.exe'

if (-not (Test-Path $toolPath)) {
    throw "Missing tool: $toolPath"
}

[void][Reflection.Assembly]::LoadFile($toolPath)

function Get-UsbHidFieldValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$UsbHid,

        [Parameter(Mandatory = $true)]
        [string]$FieldName
    )

    $field = $UsbHid.GetType().GetField(
        $FieldName,
        [System.Reflection.BindingFlags]'Instance,NonPublic,Public'
    )

    if (-not $field) {
        throw "Missing USBHID field: $FieldName"
    }

    return $field.GetValue($UsbHid)
}

function Format-ByteArray {
    param(
        [byte[]]$Bytes
    )

    if (-not $Bytes) {
        return ''
    }

    return (($Bytes | ForEach-Object { '0x{0:X2}' -f $_ }) -join ' ')
}

function Get-TargetPatterns {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode
    )

    switch ($Mode) {
        'module'   { return @('VID_213F', 'PID_1108', 'MI_03') }
        'receiver' { return @('VID_213F', 'PID_1109', 'MI_03') }
        'all'      { return @('VID_213F', 'MI_03') }
        default    { throw "Unknown target mode: $Mode" }
    }
}

function Test-DevicePathMatch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        if ($Path -notmatch [Regex]::Escape($pattern)) {
            return $false
        }
    }

    return $true
}

function Get-MatchingDevicePaths {
    param(
        [Parameter(Mandatory = $true)]
        [object]$UsbHid,

        [Parameter(Mandatory = $true)]
        [string]$Mode,

        [string]$ExplicitPath
    )

    if ($ExplicitPath) {
        return @($ExplicitPath)
    }

    $patterns = Get-TargetPatterns -Mode $Mode
    $allPaths = @($UsbHid.GetDeviceList())

    return @(
        $allPaths | Where-Object {
            Test-DevicePathMatch -Path $_ -Patterns $patterns
        }
    )
}

function Open-UsbHidDevice {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $usbHid = New-Object USBHIDControl.USBHID
    $opened = $usbHid.OpenUSBHid($Path)

    if (-not $opened) {
        throw "Failed to open HID device: $Path"
    }

    return $usbHid
}

function Get-UsbHidMethods {
    param(
        [Parameter(Mandatory = $true)]
        [object]$UsbHid
    )

    return @(
        $UsbHid.GetType().GetMethods(
            [System.Reflection.BindingFlags]'Instance,Public,NonPublic,DeclaredOnly'
        ) | Sort-Object Name
    )
}

function Get-UsbHidSummary {
    param(
        [Parameter(Mandatory = $true)]
        [object]$UsbHid,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    [pscustomobject]@{
        DevicePath         = $Path
        InputReportLength  = Get-UsbHidFieldValue -UsbHid $UsbHid -FieldName 'inputReportLength'
        OutputReportLength = Get-UsbHidFieldValue -UsbHid $UsbHid -FieldName 'outputReportLength'
    }
}

function Invoke-UsbHidMethod {
    param(
        [Parameter(Mandatory = $true)]
        [object]$UsbHid,

        [Parameter(Mandatory = $true)]
        [string]$MethodName,

        [object[]]$Arguments = @()
    )

    $methods = @(
        $UsbHid.GetType().GetMethods(
            [System.Reflection.BindingFlags]'Instance,Public,NonPublic,DeclaredOnly'
        ) | Where-Object {
            $_.Name -eq $MethodName -and $_.GetParameters().Count -eq $Arguments.Count
        }
    )

    if (-not $methods.Count) {
        $available = @(
            Get-UsbHidMethods -UsbHid $UsbHid | Select-Object -ExpandProperty Name -Unique
        ) -join ', '
        throw "Method not found: $MethodName/$($Arguments.Count). Available methods: $available"
    }

    return $methods[0].Invoke($UsbHid, $Arguments)
}

function Watch-UsbHidReplies {
    param(
        [Parameter(Mandatory = $true)]
        [object]$UsbHid,

        [Parameter(Mandatory = $true)]
        [int]$Seconds
    )

    $sourceId = 'wireless-hid-watch-' + [Guid]::NewGuid().ToString('N')
    Register-ObjectEvent -InputObject $UsbHid -EventName DataReceived -SourceIdentifier $sourceId | Out-Null

    try {
        $deadline = (Get-Date).AddSeconds($Seconds)

        while ((Get-Date) -lt $deadline) {
            $eventItem = Wait-Event -SourceIdentifier $sourceId -Timeout 1
            if (-not $eventItem) {
                continue
            }

            $report = $eventItem.SourceEventArgs
            $reportId = if ($report.reportID -ne $null) { '0x{0:X2}' -f $report.reportID } else { '?' }
            Write-Output ('[RX] reportId={0} payload={1}' -f $reportId, (Format-ByteArray -Bytes $report.reportBuff))
            Remove-Event -EventIdentifier $eventItem.EventIdentifier
        }
    }
    finally {
        Unregister-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue
    }
}

function Invoke-UsbHidAction {
    param(
        [Parameter(Mandatory = $true)]
        [object]$UsbHid,

        [Parameter(Mandatory = $true)]
        [string]$Cmd,

        [string]$Arg
    )

    switch ($Cmd) {
        'raw' {
            if (-not $Arg) { throw 'raw requires -Value as a string payload' }
            return Invoke-UsbHidMethod -UsbHid $UsbHid -MethodName 'WriteUSBHID' -Arguments @($Arg)
        }
        'set-blname' {
            if (-not $Arg) { throw 'set-blname requires -Value as the Bluetooth name' }
            return Invoke-UsbHidMethod -UsbHid $UsbHid -MethodName 'WriteBLNAME' -Arguments @($Arg)
        }
        'reset-bt' {
            return Invoke-UsbHidMethod -UsbHid $UsbHid -MethodName 'WriteBLREST' -Arguments @()
        }
        'set-wifikg' {
            if (-not $Arg) { throw 'set-wifikg requires -Value, usually 0 or 1' }
            return Invoke-UsbHidMethod -UsbHid $UsbHid -MethodName 'WriteWIFIKG' -Arguments @([byte][int]$Arg)
        }
        'set-stdlxs' {
            if (-not $Arg) { throw 'set-stdlxs requires -Value, usually 0 or 1' }
            return Invoke-UsbHidMethod -UsbHid $UsbHid -MethodName 'WriteSTDLXS' -Arguments @([byte][int]$Arg)
        }
        'set-gbkey10' {
            if (-not $Arg) { throw 'set-gbkey10 requires -Value, usually 0 or 1' }
            return Invoke-UsbHidMethod -UsbHid $UsbHid -MethodName 'WriteGBKEY10' -Arguments @([byte][int]$Arg)
        }
        'set-wf24' {
            if (-not $Arg) { throw 'set-wf24 requires -Value in the form address,band,receiverId' }
            $parts = @($Arg -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
            if ($parts.Count -ne 3) {
                throw 'set-wf24 requires exactly 3 values: address,band,receiverId'
            }

            $address = [byte][int]$parts[0]
            $band = [byte][int]$parts[1]
            $receiverId = [byte][int]$parts[2]

            return Invoke-UsbHidMethod -UsbHid $UsbHid -MethodName 'WriteWF24' -Arguments @(
                [byte[]]@($address),
                [byte[]]@($band),
                [byte[]]@($receiverId)
            )
        }
        'ws' {
            return Invoke-UsbHidMethod -UsbHid $UsbHid -MethodName 'WriteWS' -Arguments @()
        }
        'stqkbl' {
            return Invoke-UsbHidMethod -UsbHid $UsbHid -MethodName 'WriteSTQKBL' -Arguments @()
        }
        'qcdmtdys' {
            return Invoke-UsbHidMethod -UsbHid $UsbHid -MethodName 'WriteQCDMTDYS' -Arguments @()
        }
        'bldown' {
            return Invoke-UsbHidMethod -UsbHid $UsbHid -MethodName 'WriteBLDOWN' -Arguments @()
        }
        default {
            throw "Unsupported write action: $Cmd"
        }
    }
}

$enumerator = New-Object USBHIDControl.USBHID
$matchedPaths = @(Get-MatchingDevicePaths -UsbHid $enumerator -Mode $Target -ExplicitPath $DevicePath)

if ($Action -eq 'list') {
    if (-not $matchedPaths.Count) {
        Write-Output 'No matching HID devices found.'
        return
    }

    $matchedPaths | ForEach-Object { Write-Output $_ }
    return
}

if (-not $matchedPaths.Count) {
    throw "No matching HID devices found for Target=$Target"
}

$path = $matchedPaths[0]
$usbHid = Open-UsbHidDevice -Path $path

try {
    $summary = Get-UsbHidSummary -UsbHid $usbHid -Path $path
    Write-Output ('DevicePath         : {0}' -f $summary.DevicePath)
    Write-Output ('InputReportLength  : {0}' -f $summary.InputReportLength)
    Write-Output ('OutputReportLength : {0}' -f $summary.OutputReportLength)

    switch ($Action) {
        'methods' {
            Get-UsbHidMethods -UsbHid $usbHid | ForEach-Object {
                $params = @($_.GetParameters() | ForEach-Object { $_.ParameterType.Name })
                Write-Output ($_.Name + '(' + [string]::Join(',', $params) + ')')
            }
        }
        'probe' {
            Watch-UsbHidReplies -UsbHid $usbHid -Seconds $TimeoutSeconds
        }
        'watch' {
            Watch-UsbHidReplies -UsbHid $usbHid -Seconds $TimeoutSeconds
        }
        default {
            $result = Invoke-UsbHidAction -UsbHid $usbHid -Cmd $Action -Arg $Value
            Write-Output ('Result             : {0}' -f $result)
            Watch-UsbHidReplies -UsbHid $usbHid -Seconds $TimeoutSeconds
        }
    }
}
finally {
    if ($usbHid) {
        $usbHid.CloseDevice()
    }
}
