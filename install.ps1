#requires -Version 5.1
<#
.SYNOPSIS
    orkestra skill'ini ve kontrolcu alt ajanini Claude Code ve/veya Codex icin kurar.

.DESCRIPTION
    Kaynaklar script'in kendi konumuna gore bulunur ($PSScriptRoot/skills/orkestra,
    $PSScriptRoot/agents/kontrolcu.md). Windows PowerShell 5.1 ve PowerShell 7 ile
    calisir, dis modul gerektirmez.

.PARAMETER Scope
    Global (varsayilan) veya Project.

.PARAMETER Path
    Scope Project ise hedef proje klasoru (zorunlu).

.PARAMETER Target
    both (varsayilan), claude veya codex.

.PARAMETER Force
    Farkli bulunan hedefleri yedekleyip uzerine yazar.

.PARAMETER DryRun
    Hicbir dosya yazmadan yapilacaklari listeler.

.PARAMETER Uninstall
    Yalniz bizim kurdugumuz dosyalari kaldirir (frontmatter ile dogrulanir).

.PARAMETER HomeDir
    Ev dizini override (testler icin). Varsayilan: $HOME.
#>
[CmdletBinding()]
param(
    [ValidateSet('Global', 'Project')]
    [string]$Scope = 'Global',

    [string]$Path,

    [ValidateSet('both', 'claude', 'codex')]
    [string]$Target = 'both',

    [switch]$Force,
    [switch]$DryRun,
    [switch]$Uninstall,

    [string]$HomeDir
)

$ErrorActionPreference = 'Stop'

try {
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = $utf8
    [Console]::OutputEncoding = $utf8
} catch {
    # bazi host'larda konsol kodlamasi degistirilemez; sessizce devam et
}

if (-not $PSScriptRoot) {
    $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

if ([string]::IsNullOrEmpty($HomeDir)) {
    $HomeDir = $HOME
}

if ($Scope -eq 'Global' -and -not [string]::IsNullOrEmpty($Path)) {
    Write-Warning "Global scope'ta -Path yok sayiliyor"
}

if ($Scope -eq 'Project') {
    if ([string]::IsNullOrEmpty($Path)) {
        Write-Error "Project scope icin -Path zorunlu"
        exit 1
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Error "Proje yolu bulunamadi veya bir klasor degil: $Path"
        exit 1
    }
    $base = (Resolve-Path -LiteralPath $Path).Path
} else {
    $base = $HomeDir
}

if ([string]::IsNullOrWhiteSpace($base)) {
    Write-Error "Gecerli bir taban dizin yok (HOME bos ve -HomeDir verilmedi); -HomeDir ile belirtin"
    exit 1
}

$srcSkillDir = Join-Path $PSScriptRoot 'skills/orkestra'
$srcAgentFile = Join-Path $PSScriptRoot 'agents/kontrolcu.md'

if (-not (Test-Path -LiteralPath $srcSkillDir)) {
    Write-Error "Kaynak skill klasoru bulunamadi: $srcSkillDir"
    exit 1
}
if (-not (Test-Path -LiteralPath $srcAgentFile)) {
    Write-Error "Kaynak agent dosyasi bulunamadi: $srcAgentFile"
    exit 1
}

function Write-ResultLine {
    param([string]$Action, [string]$TargetPath)
    Write-Output ("{0}  {1}" -f $Action, $TargetPath)
}

function Test-DirIdentical {
    param([string]$SrcDir, [string]$DstDir)
    if (-not (Test-Path -LiteralPath $DstDir)) { return $false }
    $srcFull = (Resolve-Path -LiteralPath $SrcDir).Path.TrimEnd('\', '/')
    $dstFull = (Resolve-Path -LiteralPath $DstDir).Path.TrimEnd('\', '/')
    $srcFiles = Get-ChildItem -LiteralPath $srcFull -Recurse -File -Force |
        ForEach-Object { $_.FullName.Substring($srcFull.Length).TrimStart('\', '/') } | Sort-Object
    $dstFiles = Get-ChildItem -LiteralPath $dstFull -Recurse -File -Force |
        ForEach-Object { $_.FullName.Substring($dstFull.Length).TrimStart('\', '/') } | Sort-Object
    $diff = Compare-Object -ReferenceObject @($srcFiles) -DifferenceObject @($dstFiles)
    if ($diff) { return $false }
    foreach ($rel in $srcFiles) {
        $sHash = (Get-FileHash -LiteralPath (Join-Path $srcFull $rel) -Algorithm SHA256).Hash
        $dHash = (Get-FileHash -LiteralPath (Join-Path $dstFull $rel) -Algorithm SHA256).Hash
        if ($sHash -ne $dHash) { return $false }
    }
    return $true
}

function Test-FileIdentical {
    param([string]$SrcFile, [string]$DstFile)
    if (-not (Test-Path -LiteralPath $DstFile)) { return $false }
    $sHash = (Get-FileHash -LiteralPath $SrcFile -Algorithm SHA256).Hash
    $dHash = (Get-FileHash -LiteralPath $DstFile -Algorithm SHA256).Hash
    return ($sHash -eq $dHash)
}

function Test-IsOrkestraSkillDir {
    param([string]$Dir)
    $skillFile = Join-Path $Dir 'SKILL.md'
    if (-not (Test-Path -LiteralPath $skillFile)) { return $false }
    $head = Get-Content -LiteralPath $skillFile -TotalCount 10 -ErrorAction SilentlyContinue
    foreach ($line in $head) {
        if ($line -match '^name:\s*orkestra\s*$') { return $true }
    }
    return $false
}

function Test-IsKontrolcuAgent {
    param([string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath)) { return $false }
    $head = Get-Content -LiteralPath $FilePath -TotalCount 10 -ErrorAction SilentlyContinue
    foreach ($line in $head) {
        if ($line -match '^name:\s*kontrolcu\s*$') { return $true }
    }
    return $false
}

function Get-BackupPath {
    # Klasor hedeflerinde yedek, skills/ klasorunun disina (bir ust seviyeye)
    # tasinir: <...>/.claude/orkestra.bak-<ts> veya <...>/.agents/orkestra.bak-<ts>.
    # Boylece Claude/Codex onu ayri bir skill olarak taramaz. Dosya hedeflerinde
    # (kontrolcu.md) yedek oldugu yerde, dosyanin yaninda kalir.
    param([string]$DstPath, [string]$Kind, [string]$Timestamp)
    if ($Kind -eq 'dir') {
        $skillsParent = Split-Path -Parent $DstPath
        $containerBase = Split-Path -Parent $skillsParent
        $leaf = Split-Path -Leaf $DstPath
        return Join-Path $containerBase "$leaf.bak-$Timestamp"
    } else {
        return "$DstPath.bak-$Timestamp"
    }
}

function Copy-Target {
    param([string]$SrcPath, [string]$DstPath, [string]$Kind)
    $parent = Split-Path -Parent $DstPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    if ($Kind -eq 'dir') {
        Copy-Item -LiteralPath $SrcPath -Destination $DstPath -Recurse -Force
    } else {
        Copy-Item -LiteralPath $SrcPath -Destination $DstPath -Force
    }
}

# Hedef listesi
$targets = @()
$claudeBase = Join-Path $base '.claude'
$codexSkillDst = Join-Path $base '.agents/skills/orkestra'

if ($Target -eq 'both' -or $Target -eq 'claude') {
    $targets += [pscustomobject]@{
        Name = 'claude-skill'; Src = $srcSkillDir
        Dst  = Join-Path $claudeBase 'skills/orkestra'; Kind = 'dir'
    }
    $targets += [pscustomobject]@{
        Name = 'claude-agent'; Src = $srcAgentFile
        Dst  = Join-Path $claudeBase 'agents/kontrolcu.md'; Kind = 'file'
    }
}
if ($Target -eq 'both' -or $Target -eq 'codex') {
    $targets += [pscustomobject]@{
        Name = 'codex-skill'; Src = $srcSkillDir
        Dst  = $codexSkillDst; Kind = 'dir'
    }
}

$hadSkip = $false
$hadError = $false

foreach ($t in $targets) {
    try {
        if ($Uninstall) {
            $exists = Test-Path -LiteralPath $t.Dst
            if (-not $exists) {
                Write-ResultLine 'yok' $t.Dst
                continue
            }
            $isOurs = if ($t.Kind -eq 'dir') { Test-IsOrkestraSkillDir $t.Dst } else { Test-IsKontrolcuAgent $t.Dst }
            if (-not $isOurs) {
                Write-ResultLine 'atlandi: bizim degil' $t.Dst
                continue
            }
            if ($DryRun) {
                Write-ResultLine 'kaldirilacak' $t.Dst
                continue
            }
            if ($t.Kind -eq 'dir') {
                Remove-Item -LiteralPath $t.Dst -Recurse -Force
            } else {
                Remove-Item -LiteralPath $t.Dst -Force
            }
            Write-ResultLine 'kaldirildi' $t.Dst
            continue
        }

        # kurulum modu
        $exists = Test-Path -LiteralPath $t.Dst
        if (-not $exists) {
            if ($DryRun) {
                Write-ResultLine 'kurulacak' $t.Dst
                continue
            }
            Copy-Target -SrcPath $t.Src -DstPath $t.Dst -Kind $t.Kind
            Write-ResultLine 'kuruldu' $t.Dst
            continue
        }

        $identical = if ($t.Kind -eq 'dir') { Test-DirIdentical $t.Src $t.Dst } else { Test-FileIdentical $t.Src $t.Dst }
        if ($identical) {
            Write-ResultLine 'guncel' $t.Dst
            continue
        }

        if (-not $Force) {
            Write-ResultLine 'atlandi: farkli, -Force ile uzerine yaz' $t.Dst
            $hadSkip = $true
            continue
        }

        if ($DryRun) {
            Write-ResultLine 'yedeklenecek-ve-kurulacak' $t.Dst
            continue
        }

        $ts = Get-Date -Format 'yyyyMMddHHmmss'
        $bak = Get-BackupPath -DstPath $t.Dst -Kind $t.Kind -Timestamp $ts
        Move-Item -LiteralPath $t.Dst -Destination $bak -Force
        Copy-Target -SrcPath $t.Src -DstPath $t.Dst -Kind $t.Kind
        Write-ResultLine 'yedeklendi ve kuruldu' $t.Dst
    } catch {
        Write-ResultLine "hata: $($_.Exception.Message)" $t.Dst
        $hadError = $true
    }
}

if ($hadError) {
    exit 1
} elseif ($hadSkip) {
    exit 2
} else {
    exit 0
}
