<#
.SYNOPSIS
    Deploys clean MerchantMaster runtime files to a local WoW Forever AddOns folder.
.DESCRIPTION
    Copies only allowlisted runtime addon files (respecting .pkgmeta exclusions)
    from this repository into the target MerchantMaster AddOns directory.
    Use -Clean to wipe the target directory before copying (or combine with
    -SkipCopy to wipe an old pre-modular folder cleanly before WowUp install).
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$TargetDir = "",
    [switch]$Clean,
    [switch]$SkipCopy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-DefaultTargetDir {
    if ($env:MERCHANTMASTER_ADDONS_DIR) {
        return (Join-Path $env:MERCHANTMASTER_ADDONS_DIR "MerchantMaster")
    }
    foreach ($drive in @("C", "D", "E", "F", "G")) {
        $addonsRoot = Join-Path ($drive + ":") "Games"
        $addonsRoot = Join-Path $addonsRoot "Blizzard"
        $addonsRoot = Join-Path $addonsRoot "World of Warcraft"
        $addonsRoot = Join-Path $addonsRoot "_forever_"
        $addonsRoot = Join-Path $addonsRoot "Interface"
        $addonsRoot = Join-Path $addonsRoot "AddOns"
        if (Test-Path -LiteralPath $addonsRoot) {
            return (Join-Path $addonsRoot "MerchantMaster")
        }
    }
    $pf86 = ${env:ProgramFiles(x86)}
    if ($pf86) {
        $pfAddOns = Join-Path $pf86 "World of Warcraft"
        $pfAddOns = Join-Path $pfAddOns "_forever_"
        $pfAddOns = Join-Path $pfAddOns "Interface"
        $pfAddOns = Join-Path $pfAddOns "AddOns"
        if (Test-Path -LiteralPath $pfAddOns) {
            return (Join-Path $pfAddOns "MerchantMaster")
        }
    }
    return ""
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path

if ([string]::IsNullOrWhiteSpace($TargetDir)) {
    $TargetDir = Resolve-DefaultTargetDir
    if ([string]::IsNullOrWhiteSpace($TargetDir)) {
        throw "Could not auto-detect WoW Forever Interface\AddOns\MerchantMaster. Pass -TargetDir explicitly or set MERCHANTMASTER_ADDONS_DIR."
    }
}

$fullTarget = [System.IO.Path]::GetFullPath($TargetDir)
if ($fullTarget.TrimEnd('\', '/') -eq $repoRoot.TrimEnd('\', '/')) {
    throw "TargetDir cannot be the repository root itself ($repoRoot)."
}
if ((Split-Path -Leaf $fullTarget) -ne "MerchantMaster") {
    throw "Safety check failed: TargetDir leaf folder must be 'MerchantMaster' (got '$fullTarget')."
}

if ($Clean -and (Test-Path -LiteralPath $fullTarget)) {
    if ($PSCmdlet.ShouldProcess($fullTarget, "Clean existing MerchantMaster target directory")) {
        Remove-Item -LiteralPath $fullTarget -Recurse -Force
    }
}

if ($SkipCopy) {
    Write-Output "DEPLOY_CLEAN_ONLY target=$fullTarget"
    exit 0
}

$runtimeItems = New-Object System.Collections.Generic.List[string]

$rootAllow = @("MerchantMaster.toc", "LICENSE", "THIRD_PARTY_LICENSES.md")
foreach ($name in $rootAllow) {
    $src = Join-Path $repoRoot $name
    if (-not (Test-Path -LiteralPath $src)) {
        throw "Missing required runtime file: $src"
    }
    $runtimeItems.Add($name)
}

foreach ($luaFile in (Get-ChildItem -LiteralPath $repoRoot -Filter "*.lua" -File | Sort-Object Name)) {
    $runtimeItems.Add($luaFile.Name)
}

foreach ($sub in @("Analytics", "Libs")) {
    $subPath = Join-Path $repoRoot $sub
    if (Test-Path -LiteralPath $subPath) {
        foreach ($f in (Get-ChildItem -LiteralPath $subPath -Filter "*.lua" -File | Sort-Object Name)) {
            $runtimeItems.Add((Join-Path $sub $f.Name))
        }
    }
}

$allowedAssetExts = @(".blp", ".tga", ".ttf", ".txt")
foreach ($dirName in @("Assets", "Textures")) {
    $dirPath = Join-Path $repoRoot $dirName
    if (Test-Path -LiteralPath $dirPath) {
        foreach ($f in (Get-ChildItem -LiteralPath $dirPath -Recurse -File | Sort-Object FullName)) {
            if ($allowedAssetExts -contains $f.Extension.ToLowerInvariant()) {
                $rel = $f.FullName.Substring($repoRoot.Length).TrimStart('\', '/')
                $runtimeItems.Add($rel)
            }
        }
    }
}

if ($PSCmdlet.ShouldProcess($fullTarget, "Copy $($runtimeItems.Count) runtime files")) {
    New-Item -ItemType Directory -Path $fullTarget -Force | Out-Null
    foreach ($rel in $runtimeItems) {
        $src = Join-Path $repoRoot $rel
        $dst = Join-Path $fullTarget $rel
        $dstDir = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $dstDir)) {
            New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }
    Write-Output "DEPLOY_LOCAL_OK target=$fullTarget files=$($runtimeItems.Count) clean=$($Clean.IsPresent)"
}
