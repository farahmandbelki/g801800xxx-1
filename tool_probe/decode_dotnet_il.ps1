param(
    [Parameter(Mandatory = $true)]
    [string]$AssemblyPath,

    [Parameter(Mandatory = $true)]
    [string]$TypeName,

    [Parameter(Mandatory = $true)]
    [string[]]$MethodNames
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $AssemblyPath)) {
    throw "Assembly not found: $AssemblyPath"
}

$assemblyDirectory = Split-Path -Parent $AssemblyPath
if (-not ('CodexDecode.AssemblyResolveRegistered' -as [type])) {
    Add-Type -TypeDefinition @"
namespace CodexDecode {
    public static class AssemblyResolveRegistered {
    }
}
"@ | Out-Null

    [AppDomain]::CurrentDomain.add_AssemblyResolve({
        param($sender, $eventArgs)

        $simpleName = ($eventArgs.Name.Split(',')[0] + '.dll')
        $candidate = Join-Path $assemblyDirectory $simpleName
        if (Test-Path $candidate) {
            try {
                return [Reflection.Assembly]::LoadFile($candidate)
            }
            catch {
            }
        }

        return $null
    })
}

Get-ChildItem -Path $assemblyDirectory -Filter '*.dll' -File | ForEach-Object {
    try {
        [void][Reflection.Assembly]::LoadFile($_.FullName)
    }
    catch {
    }
}

$assembly = [Reflection.Assembly]::LoadFile($AssemblyPath)
$type = $assembly.GetType($TypeName)
if (-not $type) {
    throw "Type not found: $TypeName"
}

$bindingFlags = [System.Reflection.BindingFlags]'Instance,Static,Public,NonPublic,DeclaredOnly'

$singleByteOpCodes = @{}
$doubleByteOpCodes = @{}
foreach ($field in [System.Reflection.Emit.OpCodes].GetFields([System.Reflection.BindingFlags]'Public,Static')) {
    $opCode = [System.Reflection.Emit.OpCode]$field.GetValue($null)
    $value = ([int]$opCode.Value) -band 0xFFFF
    if ($value -le 0xFF) {
        $singleByteOpCodes[[byte]$value] = $opCode
    }
    else {
        $doubleByteOpCodes[[byte]($value -band 0xFF)] = $opCode
    }
}

function Read-Int32LE {
    param(
        [byte[]]$Bytes,
        [int]$Offset
    )

    return [BitConverter]::ToInt32($Bytes, $Offset)
}

function Read-UInt32LE {
    param(
        [byte[]]$Bytes,
        [int]$Offset
    )

    return [BitConverter]::ToUInt32($Bytes, $Offset)
}

function Read-Int16LE {
    param(
        [byte[]]$Bytes,
        [int]$Offset
    )

    return [BitConverter]::ToInt16($Bytes, $Offset)
}

function Resolve-Token {
    param(
        [Reflection.Module]$Module,
        [int]$Token,
        [Type[]]$GenericTypeArguments,
        [Type[]]$GenericMethodArguments
    )

    try {
        return $Module.ResolveMember($Token, $GenericTypeArguments, $GenericMethodArguments)
    }
    catch {
        try {
            return $Module.ResolveString($Token)
        }
        catch {
            return ('token:0x{0:X8}' -f $Token)
        }
    }
}

function Format-ResolvedMember {
    param(
        [object]$Resolved
    )

    if ($Resolved -is [string]) {
        return '"' + $Resolved + '"'
    }

    if ($Resolved -is [Reflection.MethodBase]) {
        $declaring = if ($Resolved.DeclaringType) { $Resolved.DeclaringType.FullName } else { '<global>' }
        $parameters = ($Resolved.GetParameters() | ForEach-Object { $_.ParameterType.Name }) -join ', '
        return "$declaring::$($Resolved.Name)($parameters)"
    }

    if ($Resolved -is [Reflection.FieldInfo]) {
        $declaring = if ($Resolved.DeclaringType) { $Resolved.DeclaringType.FullName } else { '<global>' }
        return "$declaring::$($Resolved.Name)"
    }

    if ($Resolved -is [Type]) {
        return $Resolved.FullName
    }

    if ($null -eq $Resolved) {
        return '<null>'
    }

    return $Resolved.ToString()
}

function Get-Operand {
    param(
        [System.Reflection.Emit.OpCode]$OpCode,
        [byte[]]$Bytes,
        [int]$Offset,
        [Reflection.Module]$Module,
        [Type[]]$GenericTypeArguments,
        [Type[]]$GenericMethodArguments
    )

    $size = 0
    $display = ''

    switch ($OpCode.OperandType) {
        'InlineNone' {
            $size = 0
            $display = ''
        }
        'ShortInlineI' {
            $size = 1
            $display = [sbyte]$Bytes[$Offset]
        }
        'ShortInlineVar' {
            $size = 1
            $display = 'V_' + $Bytes[$Offset]
        }
        'InlineVar' {
            $size = 2
            $display = 'V_' + (Read-Int16LE -Bytes $Bytes -Offset $Offset)
        }
        'InlineI' {
            $size = 4
            $display = Read-Int32LE -Bytes $Bytes -Offset $Offset
        }
        'InlineI8' {
            $size = 8
            $display = [BitConverter]::ToInt64($Bytes, $Offset)
        }
        'ShortInlineR' {
            $size = 4
            $display = [BitConverter]::ToSingle($Bytes, $Offset)
        }
        'InlineR' {
            $size = 8
            $display = [BitConverter]::ToDouble($Bytes, $Offset)
        }
        'ShortInlineBrTarget' {
            $size = 1
            $delta = if ($Bytes[$Offset] -ge 128) { $Bytes[$Offset] - 256 } else { $Bytes[$Offset] }
            $display = ('IL_{0:X4}' -f ($Offset + 1 + $delta))
        }
        'InlineBrTarget' {
            $size = 4
            $delta = Read-Int32LE -Bytes $Bytes -Offset $Offset
            $display = ('IL_{0:X4}' -f ($Offset + 4 + $delta))
        }
        'InlineString' {
            $size = 4
            $token = Read-Int32LE -Bytes $Bytes -Offset $Offset
            $display = Format-ResolvedMember -Resolved (Resolve-Token -Module $Module -Token $token -GenericTypeArguments $GenericTypeArguments -GenericMethodArguments $GenericMethodArguments)
        }
        'InlineMethod' {
            $size = 4
            $token = Read-Int32LE -Bytes $Bytes -Offset $Offset
            $display = Format-ResolvedMember -Resolved (Resolve-Token -Module $Module -Token $token -GenericTypeArguments $GenericTypeArguments -GenericMethodArguments $GenericMethodArguments)
        }
        'InlineField' {
            $size = 4
            $token = Read-Int32LE -Bytes $Bytes -Offset $Offset
            $display = Format-ResolvedMember -Resolved (Resolve-Token -Module $Module -Token $token -GenericTypeArguments $GenericTypeArguments -GenericMethodArguments $GenericMethodArguments)
        }
        'InlineType' {
            $size = 4
            $token = Read-Int32LE -Bytes $Bytes -Offset $Offset
            $display = Format-ResolvedMember -Resolved (Resolve-Token -Module $Module -Token $token -GenericTypeArguments $GenericTypeArguments -GenericMethodArguments $GenericMethodArguments)
        }
        'InlineTok' {
            $size = 4
            $token = Read-Int32LE -Bytes $Bytes -Offset $Offset
            $display = Format-ResolvedMember -Resolved (Resolve-Token -Module $Module -Token $token -GenericTypeArguments $GenericTypeArguments -GenericMethodArguments $GenericMethodArguments)
        }
        'InlineSig' {
            $size = 4
            $token = Read-Int32LE -Bytes $Bytes -Offset $Offset
            $display = ('sig:0x{0:X8}' -f $token)
        }
        'InlineSwitch' {
            $count = Read-Int32LE -Bytes $Bytes -Offset $Offset
            $size = 4 + (4 * $count)
            $targets = @()
            $base = $Offset + $size
            for ($i = 0; $i -lt $count; $i++) {
                $delta = Read-Int32LE -Bytes $Bytes -Offset ($Offset + 4 + ($i * 4))
                $targets += ('IL_{0:X4}' -f ($base + $delta))
            }
            $display = $targets -join ', '
        }
        default {
            $display = "<unsupported:$($OpCode.OperandType)>"
        }
    }

    return [pscustomobject]@{
        Size    = $size
        Display = [string]$display
    }
}

foreach ($methodName in $MethodNames) {
    $methods = @($type.GetMethods($bindingFlags) | Where-Object { $_.Name -eq $methodName })
    if (-not $methods.Count) {
        Write-Output "=== $methodName (not found) ==="
        continue
    }

    foreach ($method in $methods) {
        $body = $method.GetMethodBody()
        if (-not $body) {
            Write-Output "=== $($method) (no body) ==="
            continue
        }

        $bytes = $body.GetILAsByteArray()
        $genericTypeArgs = if ($method.DeclaringType) { $method.DeclaringType.GetGenericArguments() } else { @() }
        $genericMethodArgs = $method.GetGenericArguments()

        Write-Output "=== $($method) ==="
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $instructionOffset = $offset
            $first = $bytes[$offset]
            $offset++

            if ($first -eq 0xFE) {
                $second = $bytes[$offset]
                $offset++
                $opCode = $doubleByteOpCodes[$second]
            }
            else {
                $opCode = $singleByteOpCodes[$first]
            }

            if ($null -eq $opCode) {
                Write-Output ('IL_{0:X4}: <unknown opcode>' -f $instructionOffset)
                break
            }

            $operand = Get-Operand -OpCode $opCode -Bytes $bytes -Offset $offset -Module $method.Module -GenericTypeArguments $genericTypeArgs -GenericMethodArguments $genericMethodArgs
            $offset += $operand.Size

            if ([string]::IsNullOrWhiteSpace($operand.Display)) {
                Write-Output ('IL_{0:X4}: {1}' -f $instructionOffset, $opCode.Name)
            }
            else {
                Write-Output ('IL_{0:X4}: {1} {2}' -f $instructionOffset, $opCode.Name, $operand.Display)
            }
        }

        Write-Output ''
    }
}
