#requires -Version 5.1
<#
    install.ps1 icin test paketi. Gecici bir HOME ve gecici bir proje klasoru
    (bosluk + Turkce karakterli) kullanir, gercek ~/.claude, ~/.codex, ~/.agents
    klasorlerine dokunmaz.
#>

$ErrorActionPreference = 'Stop'

try {
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = $utf8
    [Console]::OutputEncoding = $utf8
} catch {}

if (-not $PSScriptRoot) {
    $PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
$InstallScript = Join-Path $RepoRoot 'install.ps1'

if (-not (Test-Path -LiteralPath $InstallScript)) {
    Write-Output "FAIL: install.ps1 bulunamadi: $InstallScript"
    exit 1
}

try {
    $CurrentExe = (Get-Process -Id $PID).Path
} catch {
    $CurrentExe = 'powershell.exe'
}

$TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("orkestra-test-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null

$script:PassCount = 0
$script:FailCount = 0

function Test-Assert {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        $script:PassCount++
        Write-Output "PASS: $Message"
    } else {
        $script:FailCount++
        Write-Output "FAIL: $Message"
    }
}

function Invoke-Install {
    param([string[]]$InstallArgs)
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $InstallScript) + $InstallArgs
    $outLines = & $CurrentExe @argList 2>&1 | ForEach-Object { $_.ToString() }
    $code = $LASTEXITCODE
    [pscustomobject]@{ Output = @($outLines); ExitCode = $code; Text = ($outLines -join "`n") }
}

function New-FakeFrontmatterFile {
    param([string]$FilePath, [string]$Name)
    $parent = Split-Path -Parent $FilePath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $content = "---`nname: $Name`ndescription: baskasinin dosyasi`n---`n# Baska"
    Set-Content -LiteralPath $FilePath -Value $content -Encoding UTF8
}

try {
    # ---- Kurulum: gecici klasorler ----
    $FakeHome = Join-Path $TestRoot 'home'
    $FakeProject = Join-Path $TestRoot 'proje ğüş'
    New-Item -ItemType Directory -Force -Path $FakeHome | Out-Null
    New-Item -ItemType Directory -Force -Path $FakeProject | Out-Null

    $claudeSkillFile = Join-Path $FakeHome '.claude/skills/orkestra/SKILL.md'
    $origSkillFile = Join-Path $RepoRoot 'skills/orkestra/SKILL.md'

    # ---- Senaryo 1: global both temiz kurulum ----
    $r1 = Invoke-Install @('-Scope', 'Global', '-Target', 'both', '-HomeDir', $FakeHome)
    Test-Assert ($r1.ExitCode -eq 0) "Senaryo1: exit kodu 0"
    Test-Assert (Test-Path -LiteralPath $claudeSkillFile) "Senaryo1: claude skill kuruldu"
    Test-Assert (Test-Path -LiteralPath (Join-Path $FakeHome '.claude/agents/kontrolcu.md')) "Senaryo1: claude agent kuruldu"
    Test-Assert (Test-Path -LiteralPath (Join-Path $FakeHome '.agents/skills/orkestra/SKILL.md')) "Senaryo1: codex skill kuruldu"
    Test-Assert ($r1.Text -match 'kuruldu') "Senaryo1: cikti 'kuruldu' iceriyor"
    $codexKontrolcuHits = @(Get-ChildItem -LiteralPath (Join-Path $FakeHome '.agents') -Recurse -Filter 'kontrolcu.md' -ErrorAction SilentlyContinue)
    Test-Assert ($codexKontrolcuHits.Count -eq 0) "Senaryo1: kontrolcu.md codex hedefine gitmedi"

    # ---- Senaryo 2: tekrar kosu -> guncel ----
    $r2 = Invoke-Install @('-Scope', 'Global', '-Target', 'both', '-HomeDir', $FakeHome)
    Test-Assert ($r2.ExitCode -eq 0) "Senaryo2: exit kodu 0"
    $guncelCount = @($r2.Output | Where-Object { $_ -match '^guncel\s' }).Count
    Test-Assert ($guncelCount -eq 3) "Senaryo2: uc hedef de guncel raporlandi (bulunan: $guncelCount)"

    # ---- Senaryo 3: kurulu SKILL.md'yi degistir -> tekrar kosu atlar, exit 2 ----
    Add-Content -LiteralPath $claudeSkillFile -Value "`nEXTRA LINE" -Encoding UTF8
    $r3 = Invoke-Install @('-Scope', 'Global', '-Target', 'both', '-HomeDir', $FakeHome)
    Test-Assert ($r3.ExitCode -eq 2) "Senaryo3: exit kodu 2"
    Test-Assert ($r3.Text -match 'atlandi') "Senaryo3: 'atlandi' mesaji var"
    Test-Assert ((Get-Content -LiteralPath $claudeSkillFile -Raw) -match 'EXTRA LINE') "Senaryo3: dosyaya dokunulmadi"

    # ---- Senaryo 4: Force -> yedek skills/ disina (bir ust seviyeye) tasinir, kaynakla ayni olur ----
    $r4 = Invoke-Install @('-Scope', 'Global', '-Target', 'both', '-HomeDir', $FakeHome, '-Force')
    Test-Assert ($r4.ExitCode -eq 0) "Senaryo4: exit kodu 0"
    Test-Assert ($r4.Text -match 'yedeklendi ve kuruldu') "Senaryo4: 'yedeklendi ve kuruldu' mesaji var"
    $bakDirs = @(Get-ChildItem -LiteralPath (Join-Path $FakeHome '.claude') -Filter 'orkestra.bak-*' -Directory -ErrorAction SilentlyContinue)
    Test-Assert ($bakDirs.Count -ge 1) "Senaryo4: yedek klasoru .claude altinda (skills disinda) olustu"
    $skillsBak = @(Get-ChildItem -LiteralPath (Join-Path $FakeHome '.claude/skills') -Filter '*.bak-*' -ErrorAction SilentlyContinue)
    Test-Assert ($skillsBak.Count -eq 0) "Senaryo4: skills/ altinda hicbir .bak-* yok"
    $freshSkill = Get-Content -LiteralPath $claudeSkillFile -Raw
    $origSkill = Get-Content -LiteralPath $origSkillFile -Raw
    Test-Assert ($freshSkill -eq $origSkill) "Senaryo4: kurulan dosya kaynakla birebir ayni"

    # ---- Senaryo 5: Project modu ----
    $r5 = Invoke-Install @('-Scope', 'Project', '-Path', $FakeProject, '-Target', 'both')
    Test-Assert ($r5.ExitCode -eq 0) "Senaryo5: exit kodu 0"
    Test-Assert (Test-Path -LiteralPath (Join-Path $FakeProject '.claude/skills/orkestra/SKILL.md')) "Senaryo5: proje claude skill kuruldu"
    Test-Assert (Test-Path -LiteralPath (Join-Path $FakeProject '.claude/agents/kontrolcu.md')) "Senaryo5: proje claude agent kuruldu"
    Test-Assert (Test-Path -LiteralPath (Join-Path $FakeProject '.agents/skills/orkestra/SKILL.md')) "Senaryo5: proje codex skill kuruldu"

    # ---- Senaryo 6: Target claude yalniz Claude'a kurar ----
    $FakeHome2 = Join-Path $TestRoot 'home2'
    New-Item -ItemType Directory -Force -Path $FakeHome2 | Out-Null
    $r6 = Invoke-Install @('-Scope', 'Global', '-Target', 'claude', '-HomeDir', $FakeHome2)
    Test-Assert ($r6.ExitCode -eq 0) "Senaryo6: exit kodu 0"
    Test-Assert (Test-Path -LiteralPath (Join-Path $FakeHome2 '.claude/skills/orkestra/SKILL.md')) "Senaryo6: claude skill kuruldu"
    Test-Assert (-not (Test-Path -LiteralPath (Join-Path $FakeHome2 '.agents/skills/orkestra'))) "Senaryo6: codex hedefine dokunulmadi"

    # ---- Senaryo 7: DryRun hicbir sey yazmaz ----
    $FakeHome3 = Join-Path $TestRoot 'home3'
    New-Item -ItemType Directory -Force -Path $FakeHome3 | Out-Null
    $r7 = Invoke-Install @('-Scope', 'Global', '-Target', 'both', '-HomeDir', $FakeHome3, '-DryRun')
    Test-Assert ($r7.ExitCode -eq 0) "Senaryo7: exit kodu 0"
    Test-Assert (-not (Test-Path -LiteralPath (Join-Path $FakeHome3 '.claude'))) "Senaryo7: .claude yazilmadi"
    Test-Assert (-not (Test-Path -LiteralPath (Join-Path $FakeHome3 '.agents'))) "Senaryo7: .agents yazilmadi"
    Test-Assert ($r7.Text -match 'kurulacak') "Senaryo7: 'kurulacak' mesaji var"

    # ---- Senaryo 8: Uninstall yalniz bizimkini kaldirir (yol farkli, ilgisiz skill) ----
    $FakeHome4 = Join-Path $TestRoot 'home4'
    New-Item -ItemType Directory -Force -Path $FakeHome4 | Out-Null
    $unrelatedSkillDir = Join-Path $FakeHome4 '.claude/skills/baska-skill'
    New-Item -ItemType Directory -Force -Path $unrelatedSkillDir | Out-Null
    Set-Content -LiteralPath (Join-Path $unrelatedSkillDir 'SKILL.md') -Value "---`nname: baska-skill`ndescription: test`n---`n# Baska" -Encoding UTF8

    Invoke-Install @('-Scope', 'Global', '-Target', 'both', '-HomeDir', $FakeHome4) | Out-Null

    $r8 = Invoke-Install @('-Scope', 'Global', '-Target', 'both', '-HomeDir', $FakeHome4, '-Uninstall')
    Test-Assert ($r8.ExitCode -eq 0) "Senaryo8: exit kodu 0"
    Test-Assert (-not (Test-Path -LiteralPath (Join-Path $FakeHome4 '.claude/skills/orkestra'))) "Senaryo8: orkestra skill kaldirildi"
    Test-Assert (-not (Test-Path -LiteralPath (Join-Path $FakeHome4 '.claude/agents/kontrolcu.md'))) "Senaryo8: kontrolcu.md kaldirildi"
    Test-Assert (-not (Test-Path -LiteralPath (Join-Path $FakeHome4 '.agents/skills/orkestra'))) "Senaryo8: codex skill kaldirildi"
    Test-Assert (Test-Path -LiteralPath $unrelatedSkillDir) "Senaryo8: ilgisiz skill klasorune dokunulmadi"
    Test-Assert (Test-Path -LiteralPath (Join-Path $unrelatedSkillDir 'SKILL.md')) "Senaryo8: ilgisiz skill dosyasi hala var"

    # ---- Senaryo 9: Uninstall frontmatter korumasi -- ayni YOLDA yabanci icerik ----
    $FakeHome5 = Join-Path $TestRoot 'home5'
    New-Item -ItemType Directory -Force -Path $FakeHome5 | Out-Null
    $claudeSkillDir5 = Join-Path $FakeHome5 '.claude/skills/orkestra'
    $claudeAgentFile5 = Join-Path $FakeHome5 '.claude/agents/kontrolcu.md'
    $codexSkillDir5 = Join-Path $FakeHome5 '.agents/skills/orkestra'

    New-FakeFrontmatterFile -FilePath (Join-Path $claudeSkillDir5 'SKILL.md') -Name 'baska'
    New-FakeFrontmatterFile -FilePath $claudeAgentFile5 -Name 'baska'
    New-FakeFrontmatterFile -FilePath (Join-Path $codexSkillDir5 'SKILL.md') -Name 'baska'

    $r9 = Invoke-Install @('-Scope', 'Global', '-Target', 'both', '-HomeDir', $FakeHome5, '-Uninstall')
    Test-Assert ($r9.ExitCode -eq 0) "Senaryo9: exit kodu 0"
    $skipLines9 = @($r9.Output | Where-Object { $_ -match 'bizim degil' }).Count
    Test-Assert ($skipLines9 -eq 3) "Senaryo9: uc hedef de 'bizim degil' ile atlandi (bulunan: $skipLines9)"
    Test-Assert (Test-Path -LiteralPath (Join-Path $claudeSkillDir5 'SKILL.md')) "Senaryo9: yabanci claude skill dosyasi silinmedi"
    Test-Assert (Test-Path -LiteralPath $claudeAgentFile5) "Senaryo9: yabanci kontrolcu.md silinmedi"
    Test-Assert (Test-Path -LiteralPath (Join-Path $codexSkillDir5 'SKILL.md')) "Senaryo9: yabanci codex skill dosyasi silinmedi"

    # ---- Senaryo 10: DryRun + Force ve DryRun + Uninstall gercekten hicbir sey yapmaz ----
    $FakeHome6 = Join-Path $TestRoot 'home6'
    New-Item -ItemType Directory -Force -Path $FakeHome6 | Out-Null
    $claudeSkillFile6 = Join-Path $FakeHome6 '.claude/skills/orkestra/SKILL.md'
    $claudeAgentFile6 = Join-Path $FakeHome6 '.claude/agents/kontrolcu.md'
    $codexSkillFile6 = Join-Path $FakeHome6 '.agents/skills/orkestra/SKILL.md'

    Invoke-Install @('-Scope', 'Global', '-Target', 'both', '-HomeDir', $FakeHome6) | Out-Null
    Add-Content -LiteralPath $claudeSkillFile6 -Value "`nEXTRA LINE 6" -Encoding UTF8

    $r10a = Invoke-Install @('-Scope', 'Global', '-Target', 'both', '-HomeDir', $FakeHome6, '-Force', '-DryRun')
    Test-Assert ($r10a.ExitCode -eq 0) "Senaryo10a: Force+DryRun exit kodu 0"
    $bak10 = @(Get-ChildItem -LiteralPath (Join-Path $FakeHome6 '.claude') -Recurse -Filter '*.bak-*' -ErrorAction SilentlyContinue)
    Test-Assert ($bak10.Count -eq 0) "Senaryo10a: Force+DryRun sonrasi hicbir .bak-* yok"
    Test-Assert ((Get-Content -LiteralPath $claudeSkillFile6 -Raw) -match 'EXTRA LINE 6') "Senaryo10a: degisiklik hala duruyor"

    $r10b = Invoke-Install @('-Scope', 'Global', '-Target', 'both', '-HomeDir', $FakeHome6, '-Uninstall', '-DryRun')
    Test-Assert ($r10b.ExitCode -eq 0) "Senaryo10b: Uninstall+DryRun exit kodu 0"
    Test-Assert (Test-Path -LiteralPath $claudeSkillFile6) "Senaryo10b: claude skill hala duruyor"
    Test-Assert (Test-Path -LiteralPath $claudeAgentFile6) "Senaryo10b: claude agent hala duruyor"
    Test-Assert (Test-Path -LiteralPath $codexSkillFile6) "Senaryo10b: codex skill hala duruyor"

} finally {
    try { Remove-Item -LiteralPath $TestRoot -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

Write-Output ""
Write-Output ("Ozet: {0} PASS, {1} FAIL" -f $script:PassCount, $script:FailCount)

if ($script:FailCount -gt 0) {
    exit 1
} else {
    exit 0
}
