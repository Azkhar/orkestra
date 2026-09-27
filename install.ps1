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

.PARAMETER Always
    Conductor modu: AGENTS.md / CLAUDE.md (ya da -Local ile CLAUDE.local.md) icine
    templates/conductor-block.md blogunu isler. Yalniz Scope Project ile kullanilir.

.PARAMETER Local
    Claude tarafinda blogu CLAUDE.md yerine CLAUDE.local.md'ye yazar; Codex tarafi atlanir.

.PARAMETER Profile
    lean, balanced veya generous. <HomeDir>/.orkestra/config.json dosyasini
    templates/profiles/<profile>.json ile kurar/gunceller.

.PARAMETER Purge
    Uninstall ile birlikte: .orkestra/config.json dosyasini da kaldirir (bos kalirsa klasoru de).

.PARAMETER BlockOnly
    Yalniz -Always ile birlikte, Scope Project: skill/agent dosyalarini projeye kopyalamadan
    yalniz conductor blogunu (ve verildiyse -Profile config'ini) isler.
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

    [string]$HomeDir,

    [switch]$Always,
    [switch]$Local,
    [string]$Profile,
    [switch]$Purge,
    [switch]$BlockOnly
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

if ($BlockOnly -and -not $Always) {
    Write-Error "-BlockOnly yalnizca -Always ile birlikte kullanilir"
    exit 1
}

if ($Purge -and -not $Uninstall) {
    Write-Error "-Purge yalnizca -Uninstall ile birlikte kullanilir"
    exit 1
}

if ($Always -and $Scope -ne 'Project') {
    Write-Error "Conductor modu (-Always) proje bazlidir: -Scope Project ve -Path kullanin"
    exit 1
}

$ProfileNormalized = $null
if (-not [string]::IsNullOrEmpty($Profile)) {
    $ProfileNormalized = $Profile.ToLowerInvariant()
    if ($ProfileNormalized -notin @('lean', 'balanced', 'generous')) {
        Write-Error "gecersiz -Profile: $Profile (lean, balanced veya generous olmali)"
        exit 1
    }
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
$srcConductorBlock = Join-Path $PSScriptRoot 'templates/conductor-block.md'
$srcProfilesDir = Join-Path $PSScriptRoot 'templates/profiles'

if (-not $BlockOnly) {
    if (-not (Test-Path -LiteralPath $srcSkillDir)) {
        Write-Error "Kaynak skill klasoru bulunamadi: $srcSkillDir"
        exit 1
    }
    if (-not (Test-Path -LiteralPath $srcAgentFile)) {
        Write-Error "Kaynak agent dosyasi bulunamadi: $srcAgentFile"
        exit 1
    }
}

if ($Always -and -not (Test-Path -LiteralPath $srcConductorBlock)) {
    Write-Error "Kaynak conductor blogu bulunamadi: $srcConductorBlock"
    exit 1
}
if (-not [string]::IsNullOrEmpty($ProfileNormalized) -and -not (Test-Path -LiteralPath (Join-Path $srcProfilesDir "$ProfileNormalized.json"))) {
    Write-Error "Kaynak profil dosyasi bulunamadi: $(Join-Path $srcProfilesDir "$ProfileNormalized.json")"
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

# ---- Conductor modu (-Always) ve profil (-Profile) icin yardimci fonksiyonlar ----

$script:BlockPattern = '<!--\s*orkestra:begin.*?-->[\s\S]*?<!--\s*orkestra:end\s*-->'

function Convert-ToLF {
    param([string]$Text)
    if ($null -eq $Text) { return $Text }
    return ($Text -replace "`r`n", "`n")
}

function Convert-FromLF {
    param([string]$Text, [bool]$UseCRLF)
    if (-not $UseCRLF) { return $Text }
    return ($Text -replace "`n", "`r`n")
}

function Read-TextFileRaw {
    # Dosyayi BOM/EOL bilgisini kaybetmeden okur. Icerik LF'e normalize edilerek doner.
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ Existed = $false; Content = ''; HadBOM = $false; IsCRLF = $false }
    }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hadBOM = $false
    $offset = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $hadBOM = $true
        $offset = 3
    }
    $text = [System.Text.Encoding]::UTF8.GetString($bytes, $offset, $bytes.Length - $offset)
    $isCRLF = $text -match "`r`n"
    return [pscustomobject]@{ Existed = $true; Content = (Convert-ToLF $text); HadBOM = $hadBOM; IsCRLF = $isCRLF }
}

function Write-TextFileRaw {
    param([string]$Path, [string]$LFContent, [bool]$HadBOM, [bool]$UseCRLF)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $final = Convert-FromLF $LFContent $UseCRLF
    $enc = [System.Text.UTF8Encoding]::new($HadBOM)
    [System.IO.File]::WriteAllText($Path, $final, $enc)
}

function Get-ConductorBlockTemplate {
    param([string]$SrcPath)
    $raw = [System.IO.File]::ReadAllText($SrcPath, [System.Text.Encoding]::UTF8)
    $lf = Convert-ToLF $raw
    return $lf.TrimEnd("`n")
}

function Set-ConductorBlock {
    # Dosyada blogu kurar/gunceller/ekler. BlockTemplateLF sondaki newline olmadan verilir.
    param([string]$Path, [string]$BlockTemplateLF, [bool]$DryRun)
    $info = Read-TextFileRaw -Path $Path
    if (-not $info.Existed) {
        if ($DryRun) { return [pscustomobject]@{ Action = 'kurulacak'; Wrote = $false } }
        Write-TextFileRaw -Path $Path -LFContent ($BlockTemplateLF + "`n") -HadBOM $false -UseCRLF $false
        return [pscustomobject]@{ Action = 'kuruldu'; Wrote = $true }
    }
    $content = $info.Content
    $m = [regex]::Match($content, $script:BlockPattern)
    if ($m.Success) {
        if ($m.Value -eq $BlockTemplateLF) {
            return [pscustomobject]@{ Action = 'guncel'; Wrote = $false }
        }
        if ($DryRun) { return [pscustomobject]@{ Action = 'guncellenecek'; Wrote = $false } }
        $newContent = $content.Substring(0, $m.Index) + $BlockTemplateLF + $content.Substring($m.Index + $m.Length)
        Write-TextFileRaw -Path $Path -LFContent $newContent -HadBOM $info.HadBOM -UseCRLF $info.IsCRLF
        return [pscustomobject]@{ Action = 'guncellendi'; Wrote = $true }
    } else {
        if ($DryRun) { return [pscustomobject]@{ Action = 'eklenecek'; Wrote = $false } }
        $trimmed = $content -replace '[\r\n]+$', ''
        if ($trimmed -eq '') {
            $newContent = $BlockTemplateLF + "`n"
        } else {
            $newContent = $trimmed + "`n`n" + $BlockTemplateLF + "`n"
        }
        Write-TextFileRaw -Path $Path -LFContent $newContent -HadBOM $info.HadBOM -UseCRLF $info.IsCRLF
        return [pscustomobject]@{ Action = 'eklendi'; Wrote = $true }
    }
}

function Remove-ConductorBlock {
    # Blogu (ondeki bos satiriyla) dosyadan kaldirir. Icerik bos/whitespace kalirsa dosyayi siler.
    param([string]$Path, [bool]$DryRun)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ Action = 'yok'; Deleted = $false; NoBlockContent = $null }
    }
    $info = Read-TextFileRaw -Path $Path
    $content = $info.Content
    $removePattern = '(\n\n)?' + $script:BlockPattern
    $m = [regex]::Match($content, $removePattern)
    if (-not $m.Success) {
        return [pscustomobject]@{ Action = 'atlandi: blok yok'; Deleted = $false; NoBlockContent = $content }
    }
    $newContent = $content.Substring(0, $m.Index) + $content.Substring($m.Index + $m.Length)
    $isEmpty = ($newContent.Trim() -eq '')
    if ($DryRun) {
        if ($isEmpty) { return [pscustomobject]@{ Action = 'silinecek'; Deleted = $false; NoBlockContent = $null } }
        return [pscustomobject]@{ Action = 'kaldirilacak'; Deleted = $false; NoBlockContent = $null }
    }
    if ($isEmpty) {
        Remove-Item -LiteralPath $Path -Force
        return [pscustomobject]@{ Action = 'silindi'; Deleted = $true; NoBlockContent = $null }
    }
    Write-TextFileRaw -Path $Path -LFContent $newContent -HadBOM $info.HadBOM -UseCRLF $info.IsCRLF
    return [pscustomobject]@{ Action = 'kaldirildi'; Deleted = $false; NoBlockContent = $null }
}

# Hedef listesi
$targets = @()
$claudeBase = Join-Path $base '.claude'
$codexSkillDst = Join-Path $base '.agents/skills/orkestra'

if (-not $BlockOnly) {
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

# ---- Conductor modu (-Always): AGENTS.md / CLAUDE.md / CLAUDE.local.md ----
if ($Always) {
    $agentsPath = Join-Path $base 'AGENTS.md'
    $claudeMdPath = Join-Path $base 'CLAUDE.md'
    $claudeLocalPath = Join-Path $base 'CLAUDE.local.md'

    if ($Uninstall) {
        $agentsDeleted = $false
        if ($Target -eq 'both' -or $Target -eq 'codex') {
            try {
                $r = Remove-ConductorBlock -Path $agentsPath -DryRun:$DryRun
                Write-ResultLine $r.Action $agentsPath
                if ($r.Deleted) { $agentsDeleted = $true }
            } catch {
                Write-ResultLine "hata: $($_.Exception.Message)" $agentsPath
                $hadError = $true
            }
        }
        if ($Target -eq 'both' -or $Target -eq 'claude') {
            try {
                $rc = Remove-ConductorBlock -Path $claudeMdPath -DryRun:$DryRun
                if ($rc.Action -eq 'atlandi: blok yok' -and $agentsDeleted -and $null -ne $rc.NoBlockContent -and $rc.NoBlockContent.Trim() -eq '@AGENTS.md') {
                    if ($DryRun) {
                        $rc = [pscustomobject]@{ Action = 'silinecek' }
                    } else {
                        Remove-Item -LiteralPath $claudeMdPath -Force
                        $rc = [pscustomobject]@{ Action = 'silindi' }
                    }
                }
                Write-ResultLine $rc.Action $claudeMdPath
            } catch {
                Write-ResultLine "hata: $($_.Exception.Message)" $claudeMdPath
                $hadError = $true
            }

            try {
                $rl = Remove-ConductorBlock -Path $claudeLocalPath -DryRun:$DryRun
                Write-ResultLine $rl.Action $claudeLocalPath
            } catch {
                Write-ResultLine "hata: $($_.Exception.Message)" $claudeLocalPath
                $hadError = $true
            }
        }
    } else {
        $blockTemplateLF = Get-ConductorBlockTemplate -SrcPath $srcConductorBlock
        $agentsHasBlock = $false

        if (-not $Local -and (Test-Path -LiteralPath $agentsPath -PathType Leaf)) {
            $existingAgents = Read-TextFileRaw -Path $agentsPath
            if ([regex]::IsMatch($existingAgents.Content, $script:BlockPattern)) {
                $agentsHasBlock = $true
            }
        }

        if (-not $Local -and ($Target -eq 'both' -or $Target -eq 'codex')) {
            try {
                $r = Set-ConductorBlock -Path $agentsPath -BlockTemplateLF $blockTemplateLF -DryRun:$DryRun
                Write-ResultLine $r.Action $agentsPath
                $agentsHasBlock = $true
            } catch {
                Write-ResultLine "hata: $($_.Exception.Message)" $agentsPath
                $hadError = $true
            }
        }
        if ($Local -and ($Target -eq 'both' -or $Target -eq 'codex')) {
            Write-ResultLine 'atlandi: Codex icin yerel talimat dosyasi yok' $agentsPath
        }

        if ($Target -eq 'both' -or $Target -eq 'claude') {
            if ($Local) {
                try {
                    $r = Set-ConductorBlock -Path $claudeLocalPath -BlockTemplateLF $blockTemplateLF -DryRun:$DryRun
                    Write-ResultLine $r.Action $claudeLocalPath
                    if ($r.Wrote) {
                        Write-Output "not: CLAUDE.local.md dosyasini .gitignore'a ekleyin (gizli tutulmasi onerilir)"
                    }
                } catch {
                    Write-ResultLine "hata: $($_.Exception.Message)" $claudeLocalPath
                    $hadError = $true
                }
            } else {
                try {
                    $claudeExists = Test-Path -LiteralPath $claudeMdPath -PathType Leaf
                    $hasImportLine = $false
                    if ($claudeExists) {
                        $existingClaude = Read-TextFileRaw -Path $claudeMdPath
                        foreach ($line in ($existingClaude.Content -split "`n")) {
                            if ($line.TrimEnd() -eq '@AGENTS.md') { $hasImportLine = $true; break }
                        }
                    }
                    if ($agentsHasBlock -and $claudeExists -and $hasImportLine) {
                        Write-ResultLine 'AGENTS.md uzerinden' $claudeMdPath
                    } elseif ($agentsHasBlock -and -not $claudeExists) {
                        if ($DryRun) {
                            Write-ResultLine 'kurulacak' $claudeMdPath
                        } else {
                            Write-TextFileRaw -Path $claudeMdPath -LFContent "@AGENTS.md`n" -HadBOM $false -UseCRLF $false
                            Write-ResultLine 'kuruldu' $claudeMdPath
                        }
                    } else {
                        $r = Set-ConductorBlock -Path $claudeMdPath -BlockTemplateLF $blockTemplateLF -DryRun:$DryRun
                        Write-ResultLine $r.Action $claudeMdPath
                    }
                } catch {
                    Write-ResultLine "hata: $($_.Exception.Message)" $claudeMdPath
                    $hadError = $true
                }
            }
        }
    }
}

# ---- Limit profili (-Profile) ----
if (-not [string]::IsNullOrEmpty($ProfileNormalized)) {
    $orkestraDir = Join-Path $HomeDir '.orkestra'
    $configPath = Join-Path $orkestraDir 'config.json'
    $srcProfileFile = Join-Path $srcProfilesDir "$ProfileNormalized.json"

    if (-not $Uninstall) {
        try {
            $exists = Test-Path -LiteralPath $configPath -PathType Leaf
            if (-not $exists) {
                if ($DryRun) {
                    Write-ResultLine 'kurulacak' $configPath
                } else {
                    New-Item -ItemType Directory -Force -Path $orkestraDir | Out-Null
                    Copy-Item -LiteralPath $srcProfileFile -Destination $configPath -Force
                    Write-ResultLine 'kuruldu' $configPath
                }
            } elseif (Test-FileIdentical $srcProfileFile $configPath) {
                Write-ResultLine 'guncel' $configPath
            } elseif (-not $Force) {
                Write-ResultLine "atlandi: mevcut config farkli, /orkestra settings ile degistirin veya -Force kullanin" $configPath
                $hadSkip = $true
            } else {
                if ($DryRun) {
                    Write-ResultLine 'yedeklenecek-ve-kurulacak' $configPath
                } else {
                    $ts = Get-Date -Format 'yyyyMMddHHmmss'
                    $bak = "$configPath.bak-$ts"
                    Move-Item -LiteralPath $configPath -Destination $bak -Force
                    Copy-Item -LiteralPath $srcProfileFile -Destination $configPath -Force
                    Write-ResultLine 'yedeklendi ve kuruldu' $configPath
                }
            }
        } catch {
            Write-ResultLine "hata: $($_.Exception.Message)" $configPath
            $hadError = $true
        }
    }
}

# ---- Uninstall + -Purge: config.json'u da kaldir ----
if ($Uninstall -and $Purge) {
    $orkestraDir = Join-Path $HomeDir '.orkestra'
    $configPath = Join-Path $orkestraDir 'config.json'
    try {
        if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
            Write-ResultLine 'yok' $configPath
        } elseif ($DryRun) {
            Write-ResultLine 'kaldirilacak' $configPath
        } else {
            Remove-Item -LiteralPath $configPath -Force
            Write-ResultLine 'kaldirildi' $configPath
            if (Test-Path -LiteralPath $orkestraDir) {
                $remaining = @(Get-ChildItem -LiteralPath $orkestraDir -Force -ErrorAction SilentlyContinue)
                if ($remaining.Count -eq 0) {
                    Remove-Item -LiteralPath $orkestraDir -Force
                }
            }
        }
    } catch {
        Write-ResultLine "hata: $($_.Exception.Message)" $configPath
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
