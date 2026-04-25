param(
    [ValidateSet('help', 'scan', 'set-now', 'watch', 'send-lock-now', 'watch-lock')]
    [string]$Command = 'scan',

    [string]$DevicePath,

    [int]$TimeoutMilliseconds = 1200,

    [int]$PollMilliseconds = 3000,

    [int]$WatchSeconds = 0,

    [int]$LockSymbolMilliseconds = 90,

    [int]$LockRepeatCount = 1,

    [int]$LockInterFrameMilliseconds = 250
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ViaVendorId = '5965'
$ViaProductId = '0179'

$ViaCommandIdGetProtocolVersion = 0x01
$ViaCommandIdCustomSetValue     = 0x07
$ViaCustomChannelId             = 0x00
$LocalClockDatetimeValueId      = 0x11
$ViaProtocolVersion             = 0x000C
$LockSyncPreamble               = @(0, 1, 2, 3)

Add-Type -AssemblyName System.Windows.Forms

if (-not ('MasterTimeSync.NativeHid' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace MasterTimeSync {
    public static class NativeHid {
        public const uint DIGCF_PRESENT = 0x00000002;
        public const uint DIGCF_DEVICEINTERFACE = 0x00000010;

        public const uint GENERIC_READ = 0x80000000;
        public const uint GENERIC_WRITE = 0x40000000;
        public const uint FILE_SHARE_READ = 0x00000001;
        public const uint FILE_SHARE_WRITE = 0x00000002;
        public const uint OPEN_EXISTING = 3;
        public const uint FILE_FLAG_OVERLAPPED = 0x40000000;

        [StructLayout(LayoutKind.Sequential)]
        public struct SP_DEVICE_INTERFACE_DATA {
            public int cbSize;
            public Guid InterfaceClassGuid;
            public int Flags;
            public IntPtr Reserved;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct HIDP_CAPS {
            public short Usage;
            public short UsagePage;
            public short InputReportByteLength;
            public short OutputReportByteLength;
            public short FeatureReportByteLength;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)]
            public short[] Reserved;
            public short NumberLinkCollectionNodes;
            public short NumberInputButtonCaps;
            public short NumberInputValueCaps;
            public short NumberInputDataIndices;
            public short NumberOutputButtonCaps;
            public short NumberOutputValueCaps;
            public short NumberOutputDataIndices;
            public short NumberFeatureButtonCaps;
            public short NumberFeatureValueCaps;
            public short NumberFeatureDataIndices;
        }

        [DllImport("hid.dll")]
        public static extern void HidD_GetHidGuid(out Guid HidGuid);

        [DllImport("setupapi.dll", SetLastError = true)]
        public static extern IntPtr SetupDiGetClassDevs(
            ref Guid ClassGuid,
            IntPtr Enumerator,
            IntPtr hwndParent,
            uint Flags
        );

        [DllImport("setupapi.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetupDiEnumDeviceInterfaces(
            IntPtr DeviceInfoSet,
            IntPtr DeviceInfoData,
            ref Guid InterfaceClassGuid,
            uint MemberIndex,
            ref SP_DEVICE_INTERFACE_DATA DeviceInterfaceData
        );

        [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Auto)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetupDiGetDeviceInterfaceDetail(
            IntPtr DeviceInfoSet,
            ref SP_DEVICE_INTERFACE_DATA DeviceInterfaceData,
            IntPtr DeviceInterfaceDetailData,
            uint DeviceInterfaceDetailDataSize,
            out uint RequiredSize,
            IntPtr DeviceInfoData
        );

        [DllImport("setupapi.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetupDiDestroyDeviceInfoList(IntPtr DeviceInfoSet);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern SafeFileHandle CreateFile(
            string lpFileName,
            uint dwDesiredAccess,
            uint dwShareMode,
            IntPtr lpSecurityAttributes,
            uint dwCreationDisposition,
            uint dwFlagsAndAttributes,
            IntPtr hTemplateFile
        );

        [DllImport("hid.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool HidD_GetPreparsedData(
            IntPtr HidDeviceObject,
            out IntPtr PreparsedData
        );

        [DllImport("hid.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool HidD_FreePreparsedData(IntPtr PreparsedData);

        [DllImport("hid.dll", SetLastError = true)]
        public static extern int HidP_GetCaps(
            IntPtr PreparsedData,
            out HIDP_CAPS Capabilities
        );
    }
}
"@
}

if (-not ('MasterTimeSync.NativeKeys' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace MasterTimeSync {
    public static class NativeKeys {
        public const int KEYEVENTF_KEYUP = 0x0002;

        [DllImport("user32.dll")]
        public static extern short GetKeyState(int nVirtKey);

        [DllImport("user32.dll")]
        public static extern void keybd_event(byte bVk, byte bScan, int dwFlags, int dwExtraInfo);
    }
}
"@
}

function Format-ByteArray {
    param(
        [byte[]]$Bytes
    )

    if (-not $Bytes) {
        return ''
    }

    return (($Bytes | ForEach-Object { '{0:X2}' -f $_ }) -join ' ')
}

function Get-LockState {
    return [pscustomobject]@{
        NumLock    = [System.Windows.Forms.Control]::IsKeyLocked([System.Windows.Forms.Keys]::NumLock)
        CapsLock   = [System.Windows.Forms.Control]::IsKeyLocked([System.Windows.Forms.Keys]::CapsLock)
        ScrollLock = [System.Windows.Forms.Control]::IsKeyLocked([System.Windows.Forms.Keys]::Scroll)
    }
}

function Invoke-LockKeyToggle {
    param(
        [Parameter(Mandatory = $true)]
        [byte]$VirtualKey
    )

    [MasterTimeSync.NativeKeys]::keybd_event($VirtualKey, 0x45, 0, 0)
    Start-Sleep -Milliseconds 15
    [MasterTimeSync.NativeKeys]::keybd_event($VirtualKey, 0x45, [MasterTimeSync.NativeKeys]::KEYEVENTF_KEYUP, 0)
    Start-Sleep -Milliseconds 20
}

function Set-LockKeyState {
    param(
        [Parameter(Mandatory = $true)]
        [byte]$VirtualKey,

        [Parameter(Mandatory = $true)]
        [bool]$DesiredState
    )

    $currentState = (([MasterTimeSync.NativeKeys]::GetKeyState($VirtualKey) -band 0x0001) -ne 0)
    if ($currentState -ne $DesiredState) {
        Invoke-LockKeyToggle -VirtualKey $VirtualKey
    }
}

function Set-LockStates {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$NumLock,

        [Parameter(Mandatory = $true)]
        [bool]$CapsLock,

        [Parameter(Mandatory = $true)]
        [bool]$ScrollLock
    )

    Set-LockKeyState -VirtualKey 0x90 -DesiredState $NumLock
    Set-LockKeyState -VirtualKey 0x14 -DesiredState $CapsLock
    Set-LockKeyState -VirtualKey 0x91 -DesiredState $ScrollLock
}

function Get-LockSyncPayload {
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$DateTime
    )

    $yearOffset = $DateTime.Year - 2000
    if ($yearOffset -lt 0 -or $yearOffset -gt 63) {
        throw "Year out of range for lock sync payload: $($DateTime.Year)"
    }

    [uint32]$payload = 0
    $payload = $payload -bor ([uint32]$yearOffset -shl 26)
    $payload = $payload -bor ([uint32]$DateTime.Month -shl 22)
    $payload = $payload -bor ([uint32]$DateTime.Day -shl 17)
    $payload = $payload -bor ([uint32]$DateTime.Hour -shl 12)
    $payload = $payload -bor ([uint32]$DateTime.Minute -shl 6)
    $payload = $payload -bor [uint32]$DateTime.Second
    return $payload
}

function Get-LockSyncSymbols {
    param(
        [Parameter(Mandatory = $true)]
        [uint32]$Payload
    )

    $symbols = [System.Collections.Generic.List[int]]::new()
    foreach ($symbol in $LockSyncPreamble) {
        $symbols.Add($symbol)
    }

    for ($shift = 30; $shift -ge 0; $shift -= 2) {
        $symbols.Add([int](($Payload -shr $shift) -band 0x03))
    }

    return @($symbols)
}

function Send-LockClockNow {
    param(
        [Parameter(Mandatory = $true)]
        [int]$SymbolMs,

        [Parameter(Mandatory = $true)]
        [int]$RepeatCount,

        [Parameter(Mandatory = $true)]
        [int]$InterFrameMs
    )

    $now = Get-Date
    $original = Get-LockState
    $payload = Get-LockSyncPayload -DateTime $now
    $symbols = @(Get-LockSyncSymbols -Payload $payload)
    $scrollState = $original.ScrollLock

    try {
        for ($repeat = 0; $repeat -lt $RepeatCount; $repeat++) {
            foreach ($symbol in $symbols) {
                $numLock = (($symbol -band 0x01) -ne 0)
                $capsLock = (($symbol -band 0x02) -ne 0)
                $scrollState = -not $scrollState

                Set-LockStates -NumLock $numLock -CapsLock $capsLock -ScrollLock $scrollState
                Start-Sleep -Milliseconds $SymbolMs
            }

            if ($repeat -lt ($RepeatCount - 1)) {
                Start-Sleep -Milliseconds $InterFrameMs
            }
        }
    }
    finally {
        Set-LockStates -NumLock $original.NumLock -CapsLock $original.CapsLock -ScrollLock $original.ScrollLock
    }

    return [pscustomobject]@{
        SyncedAt              = $now.ToString('yyyy-MM-dd HH:mm:ss')
        PayloadHex            = ('0x{0:X8}' -f $payload)
        SymbolCount           = $symbols.Count
        RepeatCount           = $RepeatCount
        SymbolMilliseconds    = $SymbolMs
        InterFrameMilliseconds = $InterFrameMs
    }
}

function Get-HidDevicePaths {
    param(
        [string]$VendorId,
        [string]$ProductId
    )

    $guid = [guid]::Empty
    [MasterTimeSync.NativeHid]::HidD_GetHidGuid([ref]$guid)

    $deviceInfoSet = [MasterTimeSync.NativeHid]::SetupDiGetClassDevs(
        [ref]$guid,
        [IntPtr]::Zero,
        [IntPtr]::Zero,
        [MasterTimeSync.NativeHid]::DIGCF_PRESENT -bor [MasterTimeSync.NativeHid]::DIGCF_DEVICEINTERFACE
    )

    if ($deviceInfoSet -eq [IntPtr]::Zero -or $deviceInfoSet.ToInt64() -eq -1) {
        throw 'SetupDiGetClassDevs failed for HID enumeration.'
    }

    $results = @()
    $index = 0

    try {
        while ($true) {
            $interfaceData = New-Object MasterTimeSync.NativeHid+SP_DEVICE_INTERFACE_DATA
            $interfaceData.cbSize = [Runtime.InteropServices.Marshal]::SizeOf([type]'MasterTimeSync.NativeHid+SP_DEVICE_INTERFACE_DATA')

            $enumOk = [MasterTimeSync.NativeHid]::SetupDiEnumDeviceInterfaces(
                $deviceInfoSet,
                [IntPtr]::Zero,
                [ref]$guid,
                [uint32]$index,
                [ref]$interfaceData
            )

            if (-not $enumOk) {
                break
            }

            [uint32]$requiredSize = 0
            [void][MasterTimeSync.NativeHid]::SetupDiGetDeviceInterfaceDetail(
                $deviceInfoSet,
                [ref]$interfaceData,
                [IntPtr]::Zero,
                0,
                [ref]$requiredSize,
                [IntPtr]::Zero
            )

            if ($requiredSize -gt 0) {
                $detailBuffer = [Runtime.InteropServices.Marshal]::AllocHGlobal([int]$requiredSize)
                try {
                    $cbSize = if ([IntPtr]::Size -eq 8) { 8 } else { 6 }
                    [Runtime.InteropServices.Marshal]::WriteInt32($detailBuffer, $cbSize)

                    $detailOk = [MasterTimeSync.NativeHid]::SetupDiGetDeviceInterfaceDetail(
                        $deviceInfoSet,
                        [ref]$interfaceData,
                        $detailBuffer,
                        $requiredSize,
                        [ref]$requiredSize,
                        [IntPtr]::Zero
                    )

                    if ($detailOk) {
                        # The API expects cbSize=8 on x64, but the DevicePath string still
                        # starts immediately after the DWORD cbSize field in the returned buffer.
                        # Reading from offset 8 drops the leading "\\", which produces an invalid
                        # path like "?\hid..." and causes Win32=123 when opening the HID device.
                        $pathOffset = 4
                        $path = [Runtime.InteropServices.Marshal]::PtrToStringAuto([IntPtr]($detailBuffer.ToInt64() + $pathOffset))
                        if ($path) {
                            $vidPidMatch = ('VID_{0}&PID_{1}' -f $VendorId.ToUpperInvariant(), $ProductId.ToUpperInvariant())
                            if ($path.ToUpperInvariant().Contains($vidPidMatch)) {
                                $results += $path
                            }
                        }
                    }
                }
                finally {
                    [Runtime.InteropServices.Marshal]::FreeHGlobal($detailBuffer)
                }
            }

            $index++
        }
    }
    finally {
        [void][MasterTimeSync.NativeHid]::SetupDiDestroyDeviceInfoList($deviceInfoSet)
    }

    return @($results | Select-Object -Unique)
}

function Open-HidDevice {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $handle = [MasterTimeSync.NativeHid]::CreateFile(
        $Path,
        [MasterTimeSync.NativeHid]::GENERIC_READ -bor [MasterTimeSync.NativeHid]::GENERIC_WRITE,
        [MasterTimeSync.NativeHid]::FILE_SHARE_READ -bor [MasterTimeSync.NativeHid]::FILE_SHARE_WRITE,
        [IntPtr]::Zero,
        [MasterTimeSync.NativeHid]::OPEN_EXISTING,
        [MasterTimeSync.NativeHid]::FILE_FLAG_OVERLAPPED,
        [IntPtr]::Zero
    )

    if (-not $handle -or $handle.IsInvalid) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "Failed to open HID device: $Path (Win32=$code)"
    }

    try {
        [IntPtr]$preparsed = [IntPtr]::Zero
        if (-not [MasterTimeSync.NativeHid]::HidD_GetPreparsedData($handle.DangerousGetHandle(), [ref]$preparsed)) {
            $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "HidD_GetPreparsedData failed for $Path (Win32=$code)"
        }

        try {
            $caps = New-Object MasterTimeSync.NativeHid+HIDP_CAPS
            $ntStatus = [MasterTimeSync.NativeHid]::HidP_GetCaps($preparsed, [ref]$caps)
            if ($ntStatus -ne 0x00110000) {
                throw ('HidP_GetCaps failed for {0} (NTSTATUS=0x{1:X8})' -f $Path, $ntStatus)
            }
        }
        finally {
            [void][MasterTimeSync.NativeHid]::HidD_FreePreparsedData($preparsed)
        }

        $stream = New-Object System.IO.FileStream($handle, [System.IO.FileAccess]::ReadWrite, [Math]::Max([int]$caps.InputReportByteLength, 64), $true)
        return [pscustomobject]@{
            DevicePath         = $Path
            Handle             = $handle
            Stream             = $stream
            InputReportLength  = [int]$caps.InputReportByteLength
            OutputReportLength = [int]$caps.OutputReportByteLength
            FeatureReportLength = [int]$caps.FeatureReportByteLength
        }
    }
    catch {
        try { $handle.Dispose() } catch {}
        throw
    }
}

function Close-HidDevice {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Device
    )

    try {
        if ($Device.Stream) {
            $Device.Stream.Dispose()
        }
    }
    catch {
    }

    try {
        if ($Device.Handle) {
            $Device.Handle.Dispose()
        }
    }
    catch {
    }
}

function Read-HidReport {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Device,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutMs
    )

    $buffer = New-Object byte[] $Device.InputReportLength
    $asyncResult = $Device.Stream.BeginRead($buffer, 0, $buffer.Length, $null, $null)

    try {
        if (-not $asyncResult.AsyncWaitHandle.WaitOne($TimeoutMs)) {
            return $null
        }

        $bytesRead = $Device.Stream.EndRead($asyncResult)
        if ($bytesRead -le 0) {
            return $null
        }

        if ($bytesRead -lt $buffer.Length) {
            $trimmed = New-Object byte[] $bytesRead
            [Array]::Copy($buffer, 0, $trimmed, 0, $bytesRead)
            return $trimmed
        }

        return $buffer
    }
    finally {
        try { $asyncResult.AsyncWaitHandle.Close() } catch {}
    }
}

function Send-HidReport {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Device,

        [Parameter(Mandatory = $true)]
        [byte[]]$Report
    )

    if ($Report.Length -gt $Device.OutputReportLength) {
        throw "Report too long for device. Report=$($Report.Length), OutputReportLength=$($Device.OutputReportLength)"
    }

    if ($Report.Length -lt $Device.OutputReportLength) {
        $padded = New-Object byte[] $Device.OutputReportLength
        [Array]::Copy($Report, 0, $padded, 0, $Report.Length)
        $Report = $padded
    }

    $Device.Stream.Write($Report, 0, $Report.Length)
    $Device.Stream.Flush()
    return $Report
}

function Get-MasterCandidatePaths {
    if ($DevicePath) {
        return @($DevicePath)
    }

    return @(Get-HidDevicePaths -VendorId $ViaVendorId -ProductId $ViaProductId)
}

function New-ViaProtocolVersionRequest {
    param(
        [Parameter(Mandatory = $true)]
        [int]$OutputReportLength
    )

    $packet = New-Object byte[] $OutputReportLength
    $packet[0] = 0x00
    $packet[1] = [byte]$ViaCommandIdGetProtocolVersion
    return $packet
}

function New-ViaDatetimeSetPacket {
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$DateTime,

        [Parameter(Mandatory = $true)]
        [int]$OutputReportLength
    )

    $yearOffset = $DateTime.Year - 2000
    if ($yearOffset -lt 0 -or $yearOffset -gt 255) {
        throw "Year out of range for VIA datetime packet: $($DateTime.Year)"
    }

    $packet = New-Object byte[] $OutputReportLength
    $packet[0] = 0x00
    $packet[1] = [byte]$ViaCommandIdCustomSetValue
    $packet[2] = [byte]$ViaCustomChannelId
    $packet[3] = [byte]$LocalClockDatetimeValueId
    $packet[4] = [byte]$yearOffset
    $packet[5] = [byte]$DateTime.Month
    $packet[6] = [byte]$DateTime.Day
    $packet[7] = [byte]$DateTime.Hour
    $packet[8] = [byte]$DateTime.Minute
    $packet[9] = [byte]$DateTime.Second

    return $packet
}

function Test-ViaInterface {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutMs
    )

    $device = Open-HidDevice -Path $Path
    try {
        $request = New-ViaProtocolVersionRequest -OutputReportLength $device.OutputReportLength
        [void](Send-HidReport -Device $device -Report $request)
        $reply = Read-HidReport -Device $device -TimeoutMs $TimeoutMs

        $protocolVersion = $null
        $isVia = $false

        if ($reply -and $reply.Length -ge 4 -and $reply[1] -eq $ViaCommandIdGetProtocolVersion) {
            $protocolVersion = ([int]$reply[2] -shl 8) -bor [int]$reply[3]
            $isVia = $protocolVersion -eq $ViaProtocolVersion
        }

        return [pscustomobject]@{
            DevicePath          = $Path
            InputReportLength   = $device.InputReportLength
            OutputReportLength  = $device.OutputReportLength
            FeatureReportLength = $device.FeatureReportLength
            IsVia               = [bool]$isVia
            ProtocolVersion     = $protocolVersion
            ReplyPreview        = if ($reply) { Format-ByteArray -Bytes $reply } else { '' }
        }
    }
    finally {
        Close-HidDevice -Device $device
    }
}

function Get-ViaCandidates {
    param(
        [int]$TimeoutMs = 1200
    )

    $paths = @(Get-MasterCandidatePaths)
    $results = @()

    foreach ($path in $paths) {
        try {
            $results += Test-ViaInterface -Path $path -TimeoutMs $TimeoutMs
        }
        catch {
            $results += [pscustomobject]@{
                DevicePath          = $path
                InputReportLength   = $null
                OutputReportLength  = $null
                FeatureReportLength = $null
                IsVia               = $false
                ProtocolVersion     = $null
                ReplyPreview        = ''
                Error               = $_.Exception.Message
            }
        }
    }

    return @($results)
}

function Resolve-ViaDevice {
    param(
        [int]$TimeoutMs = 1200
    )

    $candidates = @(Get-ViaCandidates -TimeoutMs $TimeoutMs)
    $match = $candidates | Where-Object { $_.IsVia } | Select-Object -First 1

    if (-not $match) {
        throw 'No VIA-compatible master interface found. Please connect the master directly by USB and run the scan command first.'
    }

    return $match
}

function Set-MasterClockNow {
    param(
        [int]$TimeoutMs = 1200
    )

    $viaDevice = Resolve-ViaDevice -TimeoutMs $TimeoutMs
    $device = Open-HidDevice -Path $viaDevice.DevicePath

    try {
        $now = Get-Date
        $packet = New-ViaDatetimeSetPacket -DateTime $now -OutputReportLength $device.OutputReportLength
        [void](Send-HidReport -Device $device -Report $packet)
        $reply = Read-HidReport -Device $device -TimeoutMs $TimeoutMs

        return [pscustomobject]@{
            DevicePath          = $viaDevice.DevicePath
            InputReportLength   = $device.InputReportLength
            OutputReportLength  = $device.OutputReportLength
            FeatureReportLength = $device.FeatureReportLength
            SyncedAt            = $now.ToString('yyyy-MM-dd HH:mm:ss')
            PacketPreview       = Format-ByteArray -Bytes $packet
            ReplyPreview        = if ($reply) { Format-ByteArray -Bytes $reply } else { '' }
        }
    }
    finally {
        Close-HidDevice -Device $device
    }
}

function Watch-AndSyncMasterClock {
    param(
        [Parameter(Mandatory = $true)]
        [int]$IntervalMs,

        [Parameter(Mandatory = $true)]
        [int]$DurationSeconds,

        [int]$TimeoutMs = 1200
    )

    $deadline = if ($DurationSeconds -gt 0) { (Get-Date).AddSeconds($DurationSeconds) } else { $null }
    $lastSyncedPath = $null

    while (-not $deadline -or (Get-Date) -lt $deadline) {
        try {
            $viaDevice = Resolve-ViaDevice -TimeoutMs $TimeoutMs
            if ($viaDevice.DevicePath -ne $lastSyncedPath) {
                $result = Set-MasterClockNow -TimeoutMs $TimeoutMs
                Write-Output ('[SYNC] {0} -> {1}' -f $result.SyncedAt, $result.DevicePath)
                $lastSyncedPath = $viaDevice.DevicePath
            }
        }
        catch {
            $lastSyncedPath = $null
        }

        Start-Sleep -Milliseconds $IntervalMs
    }
}

function Watch-AndSendLockClock {
    param(
        [Parameter(Mandatory = $true)]
        [int]$IntervalMs,

        [Parameter(Mandatory = $true)]
        [int]$DurationSeconds,

        [Parameter(Mandatory = $true)]
        [int]$SymbolMs,

        [Parameter(Mandatory = $true)]
        [int]$RepeatCount,

        [Parameter(Mandatory = $true)]
        [int]$InterFrameMs
    )

    $deadline = if ($DurationSeconds -gt 0) { (Get-Date).AddSeconds($DurationSeconds) } else { $null }

    do {
        $result = Send-LockClockNow -SymbolMs $SymbolMs -RepeatCount $RepeatCount -InterFrameMs $InterFrameMs
        Write-Output ('[LOCK-SYNC] {0} payload={1}' -f $result.SyncedAt, $result.PayloadHex)

        if ($deadline -and (Get-Date) -ge $deadline) {
            break
        }

        Start-Sleep -Milliseconds $IntervalMs
    } while (-not $deadline -or (Get-Date) -lt $deadline)
}

function Show-Help {
    Write-Output 'Master clock sync helper'
    Write-Output ''
    Write-Output 'Commands:'
    Write-Output '  scan      List direct USB master HID interfaces and probe for VIA protocol'
    Write-Output '  set-now   Set the master local clock to the current PC datetime once'
    Write-Output '  watch     Keep polling and sync once whenever the direct USB master appears'
    Write-Output '  send-lock-now  Encode the current PC datetime over Num/Caps/Scroll lock LEDs once'
    Write-Output '  watch-lock     Re-broadcast the current PC datetime over lock LEDs on an interval'
    Write-Output ''
    Write-Output 'Examples:'
    Write-Output '  .\master_time_sync.ps1 -Command scan'
    Write-Output '  .\master_time_sync.ps1 -Command set-now'
    Write-Output '  .\master_time_sync.ps1 -Command watch -PollMilliseconds 3000'
    Write-Output '  .\master_time_sync.ps1 -Command send-lock-now -LockSymbolMilliseconds 90'
}

switch ($Command) {
    'help' {
        Show-Help
    }
    'scan' {
        $results = @(Get-ViaCandidates -TimeoutMs $TimeoutMilliseconds)
        if ($results.Count -eq 0) {
            Write-Output ('No HID interfaces found for VID_{0} / PID_{1}.' -f $ViaVendorId, $ViaProductId)
            return
        }

        foreach ($result in $results) {
            $result | Format-List
            Write-Output ''
        }
    }
    'set-now' {
        Set-MasterClockNow -TimeoutMs $TimeoutMilliseconds | Format-List
    }
    'watch' {
        Watch-AndSyncMasterClock -IntervalMs $PollMilliseconds -DurationSeconds $WatchSeconds -TimeoutMs $TimeoutMilliseconds
    }
    'send-lock-now' {
        Send-LockClockNow -SymbolMs $LockSymbolMilliseconds -RepeatCount $LockRepeatCount -InterFrameMs $LockInterFrameMilliseconds | Format-List
    }
    'watch-lock' {
        Watch-AndSendLockClock -IntervalMs $PollMilliseconds -DurationSeconds $WatchSeconds -SymbolMs $LockSymbolMilliseconds -RepeatCount $LockRepeatCount -InterFrameMs $LockInterFrameMilliseconds
    }
    default {
        throw "Unsupported command: $Command"
    }
}
