param(
    [ValidateSet('help', 'status', 'transports', 'host-status', 'host-frame', 'send-host-frame', 'watch-host', 'watch-send-host-frame', 'set-name', 'reset-bt', 'set-keyboard-filter', 'set-power-display', 'set-24g-multi-switch', 'raw65-set-name', 'raw65-send-hex', 'raw65-set-24g', 'raw65-set-switch-mask', 'raw65-data-select', 'raw65-data-write')]
    [string]$Command = 'status',

    [ValidateSet('auto', 'usb', '2.4g')]
    [string]$Transport = 'auto',

    [string]$Name,

    [string]$Value,

    [int]$PollMilliseconds = 1000,

    [int]$WatchSeconds = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (
    [Environment]::Is64BitProcess -and
    $Command -in @('raw65-set-name', 'raw65-send-hex', 'raw65-set-24g', 'raw65-set-switch-mask', 'raw65-data-select', 'raw65-data-write')
) {
    $wowPowerShell = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path $wowPowerShell) {
        $argList = @(
            '-ExecutionPolicy', 'Bypass',
            '-File', $MyInvocation.MyCommand.Path,
            '-Command', $Command,
            '-Transport', $Transport,
            '-PollMilliseconds', [string]$PollMilliseconds,
            '-WatchSeconds', [string]$WatchSeconds
        )

        if ($PSBoundParameters.ContainsKey('Name') -and $null -ne $Name) {
            $argList += @('-Name', $Name)
        }
        if ($PSBoundParameters.ContainsKey('Value')) {
            $argList += @('-Value', [string]$Value)
        }

        & $wowPowerShell @argList
        exit $LASTEXITCODE
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$backend = Join-Path $scriptDir 'probe_wireless_hid.ps1'
$rawHidDll = Join-Path $scriptDir 'USBHIDDevice.dll'

if (-not (Test-Path $backend)) {
    throw "Missing backend script: $backend"
}

if (-not (Test-Path $rawHidDll)) {
    throw "Missing raw HID library: $rawHidDll"
}

function Ensure-AudioInterop {
    if ('CodexAudio.AudioInterop' -as [type]) {
        return
    }

    Add-Type -Language CSharp @"
using System;
using System.Runtime.InteropServices;

namespace CodexAudio {
    public sealed class AudioState {
        public float VolumeScalar { get; set; }
        public int VolumePercent { get; set; }
        public bool IsMuted { get; set; }
    }

    public static class AudioInterop {
        public static AudioState GetDefaultRenderState() {
            IMMDeviceEnumerator enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
            IMMDevice device;
            Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(EDataFlow.eRender, ERole.eMultimedia, out device));

            Guid iid = typeof(IAudioEndpointVolume).GUID;
            object endpointObject;
            Marshal.ThrowExceptionForHR(device.Activate(ref iid, 23, IntPtr.Zero, out endpointObject));

            IAudioEndpointVolume endpoint = (IAudioEndpointVolume)endpointObject;
            float scalar;
            bool muted;
            Marshal.ThrowExceptionForHR(endpoint.GetMasterVolumeLevelScalar(out scalar));
            Marshal.ThrowExceptionForHR(endpoint.GetMute(out muted));

            return new AudioState {
                VolumeScalar = scalar,
                VolumePercent = (int)Math.Round(scalar * 100.0f),
                IsMuted = muted
            };
        }
    }

    enum EDataFlow {
        eRender,
        eCapture,
        eAll,
        EDataFlow_enum_count
    }

    enum ERole {
        eConsole,
        eMultimedia,
        eCommunications,
        ERole_enum_count
    }

    [ComImport]
    [Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    class MMDeviceEnumeratorComObject {
    }

    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        int EnumAudioEndpoints(EDataFlow dataFlow, int dwStateMask, out IntPtr ppDevices);
        int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice ppEndpoint);
        int GetDevice(string pwstrId, out IMMDevice ppDevice);
        int RegisterEndpointNotificationCallback(IntPtr pClient);
        int UnregisterEndpointNotificationCallback(IntPtr pClient);
    }

    [Guid("D666063F-1587-4E43-81F1-B948E807363F")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice {
        int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.Interface)] out object ppInterface);
        int OpenPropertyStore(int stgmAccess, out IntPtr ppProperties);
        int GetId([MarshalAs(UnmanagedType.LPWStr)] out string ppstrId);
        int GetState(out int pdwState);
    }

    [Guid("5CDF2C82-841E-4546-9722-0CF74078229A")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioEndpointVolume {
        int RegisterControlChangeNotify(IntPtr pNotify);
        int UnregisterControlChangeNotify(IntPtr pNotify);
        int GetChannelCount(out uint pnChannelCount);
        int SetMasterVolumeLevel(float fLevelDB, IntPtr pguidEventContext);
        int SetMasterVolumeLevelScalar(float fLevel, IntPtr pguidEventContext);
        int GetMasterVolumeLevel(out float pfLevelDB);
        int GetMasterVolumeLevelScalar(out float pfLevel);
        int SetChannelVolumeLevel(uint nChannel, float fLevelDB, IntPtr pguidEventContext);
        int SetChannelVolumeLevelScalar(uint nChannel, float fLevel, IntPtr pguidEventContext);
        int GetChannelVolumeLevel(uint nChannel, out float pfLevelDB);
        int GetChannelVolumeLevelScalar(uint nChannel, out float pfLevel);
        int SetMute([MarshalAs(UnmanagedType.Bool)] bool bMute, IntPtr pguidEventContext);
        int GetMute(out bool pbMute);
        int GetVolumeStepInfo(out uint pnStep, out uint pnStepCount);
        int VolumeStepUp(IntPtr pguidEventContext);
        int VolumeStepDown(IntPtr pguidEventContext);
        int QueryHardwareSupport(out uint pdwHardwareSupportMask);
        int GetVolumeRange(out float pflVolumeMindB, out float pflVolumeMaxdB, out float pflVolumeIncrementdB);
    }
"@
}

function Ensure-RawHidInterop {
    if ('USBHIDDevice.UsbHidDevice' -as [type]) {
        return
    }

    [void][Reflection.Assembly]::LoadFile($rawHidDll)
}

function Invoke-BackendCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [string]$Target,

        [string]$ExtraValue,

        [int]$TimeoutSeconds = 3
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

    return @(& powershell.exe @argList 2>&1)
}

function Get-TransportAvailability {
    $paths = Invoke-BackendCapture -Action 'list' -Target 'all'

    $result = [ordered]@{
        UsbPath      = $null
        ReceiverPath = $null
    }

    foreach ($line in $paths) {
        $text = [string]$line
        if ($text -match 'VID_213F' -and $text -match 'PID_1108' -and -not $result.UsbPath) {
            $result.UsbPath = $text
        }
        if ($text -match 'VID_213F' -and $text -match 'PID_1109' -and -not $result.ReceiverPath) {
            $result.ReceiverPath = $text
        }
    }

    return [pscustomobject]$result
}

function Get-HostState {
    Ensure-AudioInterop

    $now = Get-Date
    $audio = [CodexAudio.AudioInterop]::GetDefaultRenderState()

    return [pscustomobject]@{
        TimestampIso    = $now.ToString('yyyy-MM-ddTHH:mm:ssK')
        TimeDisplay     = $now.ToString('HH:mm')
        DateDisplay     = $now.ToString('yyyy-MM-dd')
        VolumePercent   = $audio.VolumePercent
        IsMuted         = [bool]$audio.IsMuted
        VolumeScalar    = [math]::Round([double]$audio.VolumeScalar, 4)
    }
}

function Resolve-Target {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestedTransport,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Availability
    )

    switch ($RequestedTransport) {
        'usb' {
            if (-not $Availability.UsbPath) {
                throw 'USB transport not detected.'
            }
            return 'module'
        }
        '2.4g' {
            if (-not $Availability.ReceiverPath) {
                throw '2.4G receiver transport not detected.'
            }
            return 'receiver'
        }
        'auto' {
            if ($Availability.UsbPath) {
                return 'module'
            }
            if ($Availability.ReceiverPath) {
                return 'receiver'
            }
            throw 'No supported transport detected.'
        }
        default {
            throw "Unsupported transport: $RequestedTransport"
        }
    }
}

function Get-TransportLabel {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    switch ($Target) {
        'module'   { return 'USB (PID 1108)' }
        'receiver' { return '2.4G receiver (PID 1109)' }
        default    { return $Target }
    }
}

function Show-Help {
    Write-Output 'Wireless companion prototype'
    Write-Output ''
    Write-Output 'Commands:'
    Write-Output '  status               Show detected transports and current preferred route'
    Write-Output '  transports           Show raw device paths for USB and 2.4G'
    Write-Output '  host-status          Show current host time, volume and mute state'
    Write-Output '  host-frame           Build the current sync frame without sending it'
    Write-Output '  send-host-frame      Build and send the current sync frame over the selected route'
    Write-Output '  watch-host           Poll host time, volume and mute and print changes'
    Write-Output '  watch-send-host-frame Poll host state and send a frame whenever it changes'
    Write-Output '  set-name             Change Bluetooth name through USB transport'
    Write-Output '  reset-bt             Reset Bluetooth pairing through USB transport'
    Write-Output '  set-keyboard-filter  Send GBKEY10 flag through selected transport'
    Write-Output '  set-power-display    Toggle the module battery display feature'
    Write-Output '  set-24g-multi-switch Toggle the 2.4G multi-device switch feature'
    Write-Output '  raw65-set-name       Send a raw 65-byte Bluetooth-name packet directly through USBHIDDevice'
    Write-Output '  raw65-send-hex       Send a raw 65-byte packet from hex bytes through USBHIDDevice'
    Write-Output '  raw65-set-24g        Send a raw 65-byte 2.4G config packet (address,band,receiverId)'
    Write-Output '  raw65-set-switch-mask Send a raw 65-byte switch-mask packet (single byte mask)'
    Write-Output '  raw65-data-select    Send the observed 0xBE data-select packet (mode,slot)'
    Write-Output '  raw65-data-write     Send the observed 0xBA data-write packet (6 payload bytes)'
    Write-Output ''
    Write-Output 'Transport options:'
    Write-Output '  auto   Prefer USB, fall back to 2.4G receiver'
    Write-Output '  usb    Force PID 1108'
    Write-Output '  2.4g   Force PID 1109'
    Write-Output ''
    Write-Output 'Examples:'
    Write-Output '  .\wireless_companion.ps1 -Command status'
    Write-Output '  .\wireless_companion.ps1 -Command transports'
    Write-Output '  .\wireless_companion.ps1 -Command host-status'
    Write-Output '  .\wireless_companion.ps1 -Command host-frame'
    Write-Output '  .\wireless_companion.ps1 -Command send-host-frame -Transport usb'
    Write-Output '  .\wireless_companion.ps1 -Command watch-host -PollMilliseconds 1000'
    Write-Output '  .\wireless_companion.ps1 -Command watch-send-host-frame -Transport 2.4g -PollMilliseconds 1000'
    Write-Output '  .\wireless_companion.ps1 -Command set-name -Name TESTKB'
    Write-Output '  .\wireless_companion.ps1 -Command set-keyboard-filter -Transport 2.4g -Value 0'
    Write-Output '  .\wireless_companion.ps1 -Command set-power-display -Value 1'
    Write-Output '  .\wireless_companion.ps1 -Command set-24g-multi-switch -Transport usb -Value 1'
    Write-Output '  .\wireless_companion.ps1 -Command raw65-set-name -Name TESTKB_1'
    Write-Output '  .\wireless_companion.ps1 -Command raw65-send-hex -Transport usb -Value "00 AA 05 54 45 53 54 31"'
    Write-Output '  .\wireless_companion.ps1 -Command raw65-set-24g -Value "10,0,1"'
    Write-Output '  .\wireless_companion.ps1 -Command raw65-set-switch-mask -Value 0x13'
    Write-Output '  .\wireless_companion.ps1 -Command raw65-data-select -Value "2,3"'
    Write-Output '  .\wireless_companion.ps1 -Command raw65-data-write -Value "00 12 34 05 E9 00"'
}

function New-HostFrame {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$State
    )

    $dateCompact = (Get-Date $State.TimestampIso).ToString('yyyyMMdd')
    $timeCompact = $State.TimeDisplay.Replace(':', '')
    $muteFlag = if ($State.IsMuted) { '1' } else { '0' }

    $frame = 'SYNC|T={0}|D={1}|V={2:000}|M={3}' -f $timeCompact, $dateCompact, [int]$State.VolumePercent, $muteFlag
    return $frame
}

function Show-HostFrame {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Frame,

        [AllowNull()]
        [string]$RouteLabel
    )

    if ($RouteLabel) {
        Write-Output ('Route           : {0}' -f $RouteLabel)
    }
    Write-Output ('Frame           : {0}' -f $Frame)
    Write-Output ('FrameLength     : {0}' -f $Frame.Length)
}

function Send-HostFrame {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Frame,

        [Parameter(Mandatory = $true)]
        [string]$Target,

        [Parameter(Mandatory = $true)]
        [string]$RouteLabel
    )

    Write-Output ('Using route     : {0}' -f $RouteLabel)
    Write-Output ('Sending frame   : {0}' -f $Frame)
    Invoke-BackendCapture -Action 'raw' -Target $Target -ExtraValue $Frame -TimeoutSeconds 3 | Write-Output
}

function Show-HostState {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$State,

        [AllowNull()]
        [string]$RouteLabel
    )

    if ($RouteLabel) {
        Write-Output ('Route           : {0}' -f $RouteLabel)
    }
    Write-Output ('Timestamp       : {0}' -f $State.TimestampIso)
    Write-Output ('Time            : {0}' -f $State.TimeDisplay)
    Write-Output ('Date            : {0}' -f $State.DateDisplay)
    Write-Output ('VolumePercent   : {0}' -f $State.VolumePercent)
    Write-Output ('Muted           : {0}' -f $State.IsMuted)
    Write-Output ('VolumeScalar    : {0}' -f $State.VolumeScalar)
}

function Watch-HostState {
    param(
        [Parameter(Mandatory = $true)]
        [int]$IntervalMs,

        [Parameter(Mandatory = $true)]
        [int]$DurationSeconds,

        [AllowNull()]
        [string]$RouteLabel
    )

    if ($IntervalMs -lt 100) {
        throw 'PollMilliseconds must be at least 100.'
    }

    $deadline = if ($DurationSeconds -gt 0) { (Get-Date).AddSeconds($DurationSeconds) } else { $null }
    $previousSignature = $null

    while ($true) {
        if ($deadline -and (Get-Date) -ge $deadline) {
            break
        }

        $state = Get-HostState
        $signature = '{0}|{1}|{2}|{3}' -f $state.TimeDisplay, $state.DateDisplay, $state.VolumePercent, $state.IsMuted

        if ($signature -ne $previousSignature) {
            Write-Output '---'
            Show-HostState -State $state -RouteLabel $RouteLabel
            $previousSignature = $signature
        }

        Start-Sleep -Milliseconds $IntervalMs
    }
}

function Watch-AndSendHostFrames {
    param(
        [Parameter(Mandatory = $true)]
        [int]$IntervalMs,

        [Parameter(Mandatory = $true)]
        [int]$DurationSeconds,

        [Parameter(Mandatory = $true)]
        [string]$Target,

        [Parameter(Mandatory = $true)]
        [string]$RouteLabel
    )

    if ($IntervalMs -lt 100) {
        throw 'PollMilliseconds must be at least 100.'
    }

    $deadline = if ($DurationSeconds -gt 0) { (Get-Date).AddSeconds($DurationSeconds) } else { $null }
    $previousFrame = $null

    while ($true) {
        if ($deadline -and (Get-Date) -ge $deadline) {
            break
        }

        $state = Get-HostState
        $frame = New-HostFrame -State $state

        if ($frame -ne $previousFrame) {
            Write-Output '---'
            Show-HostState -State $state -RouteLabel $RouteLabel
            Show-HostFrame -Frame $frame
            Invoke-BackendCapture -Action 'raw' -Target $Target -ExtraValue $frame -TimeoutSeconds 3 | Write-Output
            $previousFrame = $frame
        }

        Start-Sleep -Milliseconds $IntervalMs
    }
}

function Convert-HexStringToByteArray {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HexString
    )

    $tokens = @(
        $HexString -split '[,\s]+' |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne '' }
    )

    if (-not $tokens.Count) {
        throw 'Hex payload is empty.'
    }

    $bytes = New-Object byte[] $tokens.Count
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $token = $tokens[$i]
        if ($token.StartsWith('0x', [System.StringComparison]::OrdinalIgnoreCase)) {
            $token = $token.Substring(2)
        }
        if ($token.Length -gt 2) {
            throw "Invalid hex token: $($tokens[$i])"
        }
        $bytes[$i] = [Convert]::ToByte($token, 16)
    }

    return $bytes
}

function New-Raw65BluetoothNamePacket {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BluetoothName
    )

    $nameBytes = [System.Text.Encoding]::Default.GetBytes($BluetoothName)
    if ($nameBytes.Length -gt 62) {
        throw 'Bluetooth name is too long for the raw 65-byte packet.'
    }

    $payload = New-Object byte[] 65
    $payload[0] = 0
    $payload[1] = 0xAA
    $payload[2] = [byte]$nameBytes.Length
    [Array]::Copy($nameBytes, 0, $payload, 3, $nameBytes.Length)
    return $payload
}

function Convert-ValueStringToByteList {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputValue
    )

    $tokens = @(
        $InputValue -split '[,\s]+' |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne '' }
    )

    if (-not $tokens.Count) {
        throw 'Value list is empty.'
    }

    $values = New-Object 'System.Collections.Generic.List[byte]'
    foreach ($token in $tokens) {
        $normalized = $token
        $base = 10
        if ($normalized.StartsWith('0x', [System.StringComparison]::OrdinalIgnoreCase)) {
            $normalized = $normalized.Substring(2)
            $base = 16
        }
        elseif ($normalized -match '[A-Fa-f]') {
            $base = 16
        }

        $values.Add([byte]([Convert]::ToInt32($normalized, $base)))
    }

    return [byte[]]$values.ToArray()
}

function New-Raw65Packet {
    param(
        [Parameter(Mandatory = $true)]
        [byte]$Opcode,

        [byte[]]$PayloadBytes = @()
    )

    if ($PayloadBytes.Length -gt 63) {
        throw 'Payload cannot exceed 63 bytes for the raw 65-byte packet.'
    }

    $payload = New-Object byte[] 65
    $payload[0] = 0
    $payload[1] = $Opcode
    if ($PayloadBytes.Length -gt 0) {
        [Array]::Copy($PayloadBytes, 0, $payload, 2, $PayloadBytes.Length)
    }
    return $payload
}

function Send-Raw65Packet {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Payload,

        [Parameter(Mandatory = $true)]
        [string]$DevicePath
    )

    Ensure-RawHidInterop

    if ($Payload.Length -gt 65) {
        throw 'Raw payload cannot exceed 65 bytes.'
    }

    if ($Payload.Length -lt 65) {
        $padded = New-Object byte[] 65
        [Array]::Copy($Payload, 0, $padded, 0, $Payload.Length)
        $Payload = $padded
    }

    $device = New-Object USBHIDDevice.UsbHidDevice
    $openMethod = [USBHIDDevice.UsbHidDevice].GetMethod('OpenDevice', [System.Reflection.BindingFlags]'Instance,NonPublic,Public,DeclaredOnly')
    $sendMethod = [USBHIDDevice.UsbHidDevice].GetMethod('SendMessage', [System.Reflection.BindingFlags]'Instance,NonPublic,Public,DeclaredOnly')

    $opened = $false
    for ($attempt = 0; $attempt -lt 5; $attempt++) {
        $opened = [bool]$openMethod.Invoke($device, @($DevicePath))
        if ($opened) {
            break
        }
        Start-Sleep -Milliseconds 300
    }

    $message = New-Object USBHIDDevice.CommandMessage(0, $Payload)
    $sendArgs = New-Object object[] 1
    $sendArgs[0] = [USBHIDDevice.IMesage]$message
    $sent = if ($opened) { [bool]$sendMethod.Invoke($device, $sendArgs) } else { $false }

    return [pscustomobject]@{
        DevicePath     = $DevicePath
        Opened         = [bool]$opened
        Sent           = [bool]$sent
        PayloadLength  = $Payload.Length
        PayloadPreview = (($Payload[0..([Math]::Min(15, $Payload.Length - 1))] | ForEach-Object { '{0:X2}' -f $_ }) -join ' ')
    }
}

$availability = Get-TransportAvailability

$resolvedRouteLabel = $null
if ($availability.UsbPath -or $availability.ReceiverPath) {
    try {
        $resolvedRouteLabel = Get-TransportLabel -Target (Resolve-Target -RequestedTransport $Transport -Availability $availability)
    }
    catch {
        $resolvedRouteLabel = $null
    }
}

switch ($Command) {
    'help' {
        Show-Help
        return
    }
    'transports' {
        Write-Output ('USB path      : {0}' -f ($(if ($availability.UsbPath) { $availability.UsbPath } else { 'not detected' })))
        Write-Output ('2.4G path     : {0}' -f ($(if ($availability.ReceiverPath) { $availability.ReceiverPath } else { 'not detected' })))
        return
    }
    'status' {
        Write-Output ('USB available : {0}' -f [bool]$availability.UsbPath)
        Write-Output ('2.4G available: {0}' -f [bool]$availability.ReceiverPath)
        if ($availability.UsbPath -or $availability.ReceiverPath) {
            $target = Resolve-Target -RequestedTransport $Transport -Availability $availability
            Write-Output ('Active route  : {0}' -f (Get-TransportLabel -Target $target))
        } else {
            Write-Output 'Active route  : none'
        }
        return
    }
    'host-status' {
        Show-HostState -State (Get-HostState) -RouteLabel $resolvedRouteLabel
        return
    }
    'host-frame' {
        Show-HostFrame -Frame (New-HostFrame -State (Get-HostState)) -RouteLabel $resolvedRouteLabel
        return
    }
    'watch-host' {
        Watch-HostState -IntervalMs $PollMilliseconds -DurationSeconds $WatchSeconds -RouteLabel $resolvedRouteLabel
        return
    }
}

$target = Resolve-Target -RequestedTransport $Transport -Availability $availability

switch ($Command) {
    'send-host-frame' {
        $frame = New-HostFrame -State (Get-HostState)
        Send-HostFrame -Frame $frame -Target $target -RouteLabel (Get-TransportLabel -Target $target)
    }
    'watch-send-host-frame' {
        Watch-AndSendHostFrames -IntervalMs $PollMilliseconds -DurationSeconds $WatchSeconds -Target $target -RouteLabel (Get-TransportLabel -Target $target)
    }
    'set-name' {
        if (-not $Name) {
            throw 'set-name requires -Name'
        }
        if ($target -ne 'module') {
            throw 'set-name currently requires USB transport because Bluetooth name belongs to the module.'
        }
        Invoke-BackendCapture -Action 'set-blname' -Target 'module' -ExtraValue $Name -TimeoutSeconds 3 | Write-Output
    }
    'reset-bt' {
        if ($target -ne 'module') {
            throw 'reset-bt currently requires USB transport because pairing reset belongs to the module.'
        }
        Invoke-BackendCapture -Action 'reset-bt' -Target 'module' -TimeoutSeconds 3 | Write-Output
    }
    'set-keyboard-filter' {
        if ($PSBoundParameters.ContainsKey('Value') -eq $false) {
            throw 'set-keyboard-filter requires -Value'
        }
        Invoke-BackendCapture -Action 'set-gbkey10' -Target $target -ExtraValue ([string]$Value) -TimeoutSeconds 3 | Write-Output
    }
    'set-power-display' {
        if ($PSBoundParameters.ContainsKey('Value') -eq $false) {
            throw 'set-power-display requires -Value'
        }
        if ($target -ne 'module') {
            throw 'set-power-display currently requires USB transport because this setting belongs to the module.'
        }
        Invoke-BackendCapture -Action 'set-stdlxs' -Target 'module' -ExtraValue ([string]$Value) -TimeoutSeconds 3 | Write-Output
    }
    'set-24g-multi-switch' {
        if ($PSBoundParameters.ContainsKey('Value') -eq $false) {
            throw 'set-24g-multi-switch requires -Value'
        }
        Invoke-BackendCapture -Action 'set-wifikg' -Target $target -ExtraValue ([string]$Value) -TimeoutSeconds 3 | Write-Output
    }
    'raw65-set-name' {
        if (-not $Name) {
            throw 'raw65-set-name requires -Name'
        }
        if ($target -ne 'module') {
            throw 'raw65-set-name currently requires USB transport because the Bluetooth name belongs to the module.'
        }

        $result = Send-Raw65Packet -Payload (New-Raw65BluetoothNamePacket -BluetoothName $Name) -DevicePath $availability.UsbPath
        $result
    }
    'raw65-send-hex' {
        if (-not $PSBoundParameters.ContainsKey('Value')) {
            throw 'raw65-send-hex requires -Value with hex bytes'
        }

        $devicePath = if ($target -eq 'module') { $availability.UsbPath } else { $availability.ReceiverPath }
        $result = Send-Raw65Packet -Payload (Convert-HexStringToByteArray -HexString ([string]$Value)) -DevicePath $devicePath
        $result
    }
    'raw65-set-24g' {
        if (-not $PSBoundParameters.ContainsKey('Value')) {
            throw 'raw65-set-24g requires -Value in the form address,band,receiverId'
        }

        $bytes = Convert-ValueStringToByteList -InputValue ([string]$Value)
        if ($bytes.Length -ne 3) {
            throw 'raw65-set-24g requires exactly 3 bytes: address,band,receiverId'
        }

        $devicePath = if ($target -eq 'module') { $availability.UsbPath } else { $availability.ReceiverPath }
        $result = Send-Raw65Packet -Payload (New-Raw65Packet -Opcode 0xEE -PayloadBytes $bytes) -DevicePath $devicePath
        $result
    }
    'raw65-set-switch-mask' {
        if (-not $PSBoundParameters.ContainsKey('Value')) {
            throw 'raw65-set-switch-mask requires -Value with a single byte mask'
        }

        $bytes = Convert-ValueStringToByteList -InputValue ([string]$Value)
        if ($bytes.Length -ne 1) {
            throw 'raw65-set-switch-mask requires exactly 1 byte'
        }

        $devicePath = if ($target -eq 'module') { $availability.UsbPath } else { $availability.ReceiverPath }
        $result = Send-Raw65Packet -Payload (New-Raw65Packet -Opcode 0xE4 -PayloadBytes $bytes) -DevicePath $devicePath
        $result
    }
    'raw65-data-select' {
        if (-not $PSBoundParameters.ContainsKey('Value')) {
            throw 'raw65-data-select requires -Value in the form mode,slot'
        }

        $bytes = Convert-ValueStringToByteList -InputValue ([string]$Value)
        if ($bytes.Length -ne 2) {
            throw 'raw65-data-select requires exactly 2 bytes: mode,slot'
        }

        $devicePath = if ($target -eq 'module') { $availability.UsbPath } else { $availability.ReceiverPath }
        $result = Send-Raw65Packet -Payload (New-Raw65Packet -Opcode 0xBE -PayloadBytes $bytes) -DevicePath $devicePath
        $result
    }
    'raw65-data-write' {
        if (-not $PSBoundParameters.ContainsKey('Value')) {
            throw 'raw65-data-write requires -Value with 6 payload bytes'
        }

        $bytes = Convert-ValueStringToByteList -InputValue ([string]$Value)
        if ($bytes.Length -ne 6) {
            throw 'raw65-data-write requires exactly 6 bytes'
        }

        $devicePath = if ($target -eq 'module') { $availability.UsbPath } else { $availability.ReceiverPath }
        $result = Send-Raw65Packet -Payload (New-Raw65Packet -Opcode 0xBA -PayloadBytes $bytes) -DevicePath $devicePath
        $result
    }
    default {
        throw "Unsupported command: $Command"
    }
}
