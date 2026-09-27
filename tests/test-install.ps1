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
    # PS 5.1'de $ErrorActionPreference='Stop' iken 2>&1 ile yakalanan native stderr
    # satirlari terminating hataya donusuyor; bu fonksiyon icinde yerel olarak
    # 'Continue' yapiyoruz (dis kapsami etkilemez).
    $ErrorActionPreference = 'Continue'
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

function New-TestProjectDir {
    param([string]$Suffix)
    # Bosluk + Turkce karakterli proje klasoru; her senaryo icin izole.
    $p = Join-Path $TestRoot ("proje ğüş " + $Suffix)
    New-Item -ItemType Directory -Force -Path $p | Out-Null
    return $p
}

function Get-MarkerCount {
    param([string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath)) { return 0 }
    $content = Get-Content -LiteralPath $FilePath -Raw
    return ([regex]::Matches($content, 'orkestra:begin')).Count
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

    # ============================================================
    # Conductor modu (-Always) ve limit profili (-Profile) testleri
    # ============================================================

    # ---- Senaryo 11 (a): -Always -Target both, bos proje ----
    $Proj11 = New-TestProjectDir '11'
    $Home11 = Join-Path $TestRoot 'home11'
    $r11 = Invoke-Install @('-Scope', 'Project', '-Path', $Proj11, '-Always', '-Target', 'both', '-HomeDir', $Home11)
    Test-Assert ($r11.ExitCode -eq 0) "Senaryo11: exit kodu 0"
    $agents11 = Join-Path $Proj11 'AGENTS.md'
    $claude11 = Join-Path $Proj11 'CLAUDE.md'
    Test-Assert (Test-Path -LiteralPath $agents11) "Senaryo11: AGENTS.md olustu"
    Test-Assert ((Get-Content -LiteralPath $agents11 -Raw) -match 'orkestra:begin') "Senaryo11: AGENTS.md blogu iceriyor"
    Test-Assert ((Get-Content -LiteralPath $claude11 -Raw).Trim() -eq '@AGENTS.md') "Senaryo11: CLAUDE.md tam olarak @AGENTS.md"

    # ---- Senaryo 12 (b): CLAUDE.md zaten @AGENTS.md iceriyor -> degismez ----
    $Proj12 = New-TestProjectDir '12'
    $Home12 = Join-Path $TestRoot 'home12'
    New-Item -ItemType Directory -Force -Path $Proj12 | Out-Null
    Set-Content -LiteralPath (Join-Path $Proj12 'CLAUDE.md') -Value '@AGENTS.md' -Encoding UTF8 -NoNewline
    $r12 = Invoke-Install @('-Scope', 'Project', '-Path', $Proj12, '-Always', '-Target', 'both', '-HomeDir', $Home12)
    Test-Assert ($r12.ExitCode -eq 0) "Senaryo12: exit kodu 0"
    Test-Assert ($r12.Text -match 'AGENTS.md uzerinden') "Senaryo12: 'AGENTS.md uzerinden' raporlandi"
    Test-Assert ((Get-Content -LiteralPath (Join-Path $Proj12 'CLAUDE.md') -Raw).Trim() -eq '@AGENTS.md') "Senaryo12: CLAUDE.md hala yalniz @AGENTS.md"

    # ---- Senaryo 13 (c): kullanici metni olan AGENTS.md + import'suz CLAUDE.md -> ikisine de eklenir, metin korunur ----
    $Proj13 = New-TestProjectDir '13'
    $Home13 = Join-Path $TestRoot 'home13'
    New-Item -ItemType Directory -Force -Path $Proj13 | Out-Null
    Set-Content -LiteralPath (Join-Path $Proj13 'AGENTS.md') -Value 'Kullanici notu satiri.' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $Proj13 'CLAUDE.md') -Value 'CLAUDE ozel not.' -Encoding UTF8
    $r13 = Invoke-Install @('-Scope', 'Project', '-Path', $Proj13, '-Always', '-Target', 'both', '-HomeDir', $Home13)
    Test-Assert ($r13.ExitCode -eq 0) "Senaryo13: exit kodu 0"
    $agents13Text = Get-Content -LiteralPath (Join-Path $Proj13 'AGENTS.md') -Raw
    $claude13Text = Get-Content -LiteralPath (Join-Path $Proj13 'CLAUDE.md') -Raw
    Test-Assert ($agents13Text -match 'Kullanici notu satiri\.') "Senaryo13: AGENTS.md kullanici metni korundu"
    Test-Assert ($agents13Text -match 'orkestra:begin') "Senaryo13: AGENTS.md bloğu aldi"
    Test-Assert ($claude13Text -match 'CLAUDE ozel not\.') "Senaryo13: CLAUDE.md kullanici metni korundu"
    Test-Assert ($claude13Text -match 'orkestra:begin') "Senaryo13: CLAUDE.md bloğu aldi"
    Test-Assert ((Get-MarkerCount (Join-Path $Proj13 'AGENTS.md')) -eq 1) "Senaryo13: AGENTS.md'de tek blok"
    Test-Assert ((Get-MarkerCount (Join-Path $Proj13 'CLAUDE.md')) -eq 1) "Senaryo13: CLAUDE.md'de tek blok"

    # ---- Senaryo 14 (d): tekrar kosu -> guncel, marker sayisi hala 1 ----
    $r14 = Invoke-Install @('-Scope', 'Project', '-Path', $Proj13, '-Always', '-Target', 'both', '-HomeDir', $Home13)
    Test-Assert ($r14.ExitCode -eq 0) "Senaryo14: exit kodu 0"
    Test-Assert ($r14.Text -match 'guncel') "Senaryo14: 'guncel' raporlandi"
    Test-Assert ((Get-MarkerCount (Join-Path $Proj13 'AGENTS.md')) -eq 1) "Senaryo14: AGENTS.md'de hala tek blok"
    Test-Assert ((Get-MarkerCount (Join-Path $Proj13 'CLAUDE.md')) -eq 1) "Senaryo14: CLAUDE.md'de hala tek blok (import satiriyla)"

    # ---- Senaryo 15 (e): sablon degisti (gecici repo kopyasinda) -> blok degisir, cogalmaz ----
    $TmpRepo15 = Join-Path $TestRoot 'repo-copy-15'
    New-Item -ItemType Directory -Force -Path $TmpRepo15 | Out-Null
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'install.ps1') -Destination (Join-Path $TmpRepo15 'install.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'skills') -Destination (Join-Path $TmpRepo15 'skills') -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'agents') -Destination (Join-Path $TmpRepo15 'agents') -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'templates') -Destination (Join-Path $TmpRepo15 'templates') -Recurse -Force
    $InstallScript15 = Join-Path $TmpRepo15 'install.ps1'
    $Proj15 = New-TestProjectDir '15'
    $Home15 = Join-Path $TestRoot 'home15'
    $argList15a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $InstallScript15, '-Scope', 'Project', '-Path', $Proj15, '-Always', '-BlockOnly', '-Target', 'codex', '-HomeDir', $Home15)
    & $CurrentExe @argList15a | Out-Null
    Set-Content -LiteralPath (Join-Path $TmpRepo15 'templates/conductor-block.md') -Value "<!-- orkestra:begin (managed by the orkestra installer; edit via /orkestra settings or reinstall) -->`nNEW BLOCK CONTENT CHANGED`n<!-- orkestra:end -->" -Encoding UTF8 -NoNewline
    $argList15b = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $InstallScript15, '-Scope', 'Project', '-Path', $Proj15, '-Always', '-BlockOnly', '-Target', 'codex', '-HomeDir', $Home15)
    $out15b = & $CurrentExe @argList15b 2>&1 | ForEach-Object { $_.ToString() }
    $agents15Text = Get-Content -LiteralPath (Join-Path $Proj15 'AGENTS.md') -Raw
    Test-Assert ($agents15Text -match 'NEW BLOCK CONTENT CHANGED') "Senaryo15: yeni blok icerigi yazildi"
    Test-Assert ((Get-MarkerCount (Join-Path $Proj15 'AGENTS.md')) -eq 1) "Senaryo15: blok cogalmadi (tek marker)"

    # ---- Senaryo 16 (f): -Local -> yalniz CLAUDE.local.md, AGENTS.md dokunulmaz ----
    $Proj16 = New-TestProjectDir '16'
    $Home16 = Join-Path $TestRoot 'home16'
    $r16 = Invoke-Install @('-Scope', 'Project', '-Path', $Proj16, '-Always', '-Local', '-Target', 'both', '-HomeDir', $Home16)
    Test-Assert ($r16.ExitCode -eq 0) "Senaryo16: exit kodu 0"
    Test-Assert (-not (Test-Path -LiteralPath (Join-Path $Proj16 'AGENTS.md'))) "Senaryo16: AGENTS.md olusturulmadi"
    Test-Assert (-not (Test-Path -LiteralPath (Join-Path $Proj16 'CLAUDE.md'))) "Senaryo16: CLAUDE.md olusturulmadi"
    Test-Assert (Test-Path -LiteralPath (Join-Path $Proj16 'CLAUDE.local.md')) "Senaryo16: CLAUDE.local.md olustu"
    Test-Assert ((Get-Content -LiteralPath (Join-Path $Proj16 'CLAUDE.local.md') -Raw) -match 'orkestra:begin') "Senaryo16: CLAUDE.local.md blogu iceriyor"

    # ---- Senaryo 17 (g): CRLF dosya CRLF kaliyor ----
    $Proj17 = New-TestProjectDir '17'
    $Home17 = Join-Path $TestRoot 'home17'
    New-Item -ItemType Directory -Force -Path $Proj17 | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $Proj17 'AGENTS.md'), "CRLF user line`r`n", [System.Text.UTF8Encoding]::new($false))
    $r17 = Invoke-Install @('-Scope', 'Project', '-Path', $Proj17, '-Always', '-BlockOnly', '-Target', 'codex', '-HomeDir', $Home17)
    Test-Assert ($r17.ExitCode -eq 0) "Senaryo17: exit kodu 0"
    $bytes17 = [System.IO.File]::ReadAllBytes((Join-Path $Proj17 'AGENTS.md'))
    $text17 = [System.Text.Encoding]::UTF8.GetString($bytes17)
    $lfOnly17 = [regex]::Matches($text17, "(?<!`r)`n").Count
    Test-Assert ($text17 -match "`r`n") "Senaryo17: dosyada CRLF var"
    Test-Assert ($lfOnly17 -eq 0) "Senaryo17: tek basina LF yok, hepsi CRLF"

    # ---- Senaryo 18 (h): uninstall bloklari kaldirir, kullanici metnini korur, sadece blok iceren dosyalari siler ----
    $r18 = Invoke-Install @('-Scope', 'Project', '-Path', $Proj13, '-Always', '-Target', 'both', '-HomeDir', $Home13, '-Uninstall')
    Test-Assert ($r18.ExitCode -eq 0) "Senaryo18: exit kodu 0"
    $agents18Text = Get-Content -LiteralPath (Join-Path $Proj13 'AGENTS.md') -Raw
    $claude18Text = Get-Content -LiteralPath (Join-Path $Proj13 'CLAUDE.md') -Raw
    Test-Assert ($agents18Text.Trim() -eq 'Kullanici notu satiri.') "Senaryo18: AGENTS.md yalniz kullanici metnini icersin"
    Test-Assert ($claude18Text.Trim() -eq 'CLAUDE ozel not.') "Senaryo18: CLAUDE.md yalniz kullanici metnini icersin"

    $Proj18b = New-TestProjectDir '18b'
    $Home18b = Join-Path $TestRoot 'home18b'
    Invoke-Install @('-Scope', 'Project', '-Path', $Proj18b, '-Always', '-BlockOnly', '-Target', 'both', '-HomeDir', $Home18b) | Out-Null
    $r18b = Invoke-Install @('-Scope', 'Project', '-Path', $Proj18b, '-Always', '-BlockOnly', '-Target', 'both', '-HomeDir', $Home18b, '-Uninstall')
    Test-Assert ($r18b.ExitCode -eq 0) "Senaryo18b: exit kodu 0"
    Test-Assert (-not (Test-Path -LiteralPath (Join-Path $Proj18b 'AGENTS.md'))) "Senaryo18b: sadece blok iceren AGENTS.md silindi"
    Test-Assert (-not (Test-Path -LiteralPath (Join-Path $Proj18b 'CLAUDE.md'))) "Senaryo18b: sadece @AGENTS.md iceren CLAUDE.md silindi"

    # ---- Senaryo 19 (i): profil kurulum / guncel / farkli-atlandi(exit2) / Force yedek / gecersiz isim(exit1) ----
    $Home19 = Join-Path $TestRoot 'home19'
    $r19a = Invoke-Install @('-Scope', 'Global', '-HomeDir', $Home19, '-Profile', 'balanced')
    Test-Assert ($r19a.ExitCode -eq 0) "Senaryo19a: exit kodu 0"
    $configPath19 = Join-Path $Home19 '.orkestra/config.json'
    Test-Assert (Test-Path -LiteralPath $configPath19) "Senaryo19a: config.json olustu"
    $origBalanced = Get-Content -LiteralPath (Join-Path $RepoRoot 'templates/profiles/balanced.json') -Raw
    $installedBalanced = Get-Content -LiteralPath $configPath19 -Raw
    Test-Assert ($origBalanced -eq $installedBalanced) "Senaryo19a: config icerigi kaynakla birebir ayni"

    $r19b = Invoke-Install @('-Scope', 'Global', '-HomeDir', $Home19, '-Profile', 'balanced')
    Test-Assert ($r19b.ExitCode -eq 0) "Senaryo19b: exit kodu 0"
    Test-Assert ($r19b.Text -match 'guncel') "Senaryo19b: 'guncel' raporlandi"

    $r19c = Invoke-Install @('-Scope', 'Global', '-HomeDir', $Home19, '-Profile', 'lean')
    Test-Assert ($r19c.ExitCode -eq 2) "Senaryo19c: farkli profil -Force olmadan exit kodu 2"
    Test-Assert ($r19c.Text -match 'atlandi') "Senaryo19c: 'atlandi' mesaji var"
    Test-Assert ((Get-Content -LiteralPath $configPath19 -Raw) -match '"balanced"') "Senaryo19c: config hala eskisi (balanced)"

    $r19d = Invoke-Install @('-Scope', 'Global', '-HomeDir', $Home19, '-Profile', 'lean', '-Force')
    Test-Assert ($r19d.ExitCode -eq 0) "Senaryo19d: -Force ile exit kodu 0"
    Test-Assert ((Get-Content -LiteralPath $configPath19 -Raw) -match '"lean"') "Senaryo19d: config artik lean"
    $bakFiles19 = @(Get-ChildItem -LiteralPath (Join-Path $Home19 '.orkestra') -Filter 'config.json.bak-*')
    Test-Assert ($bakFiles19.Count -ge 1) "Senaryo19d: eski config yedeklendi"

    $r19e = Invoke-Install @('-Scope', 'Global', '-HomeDir', (Join-Path $TestRoot 'home19e'), '-Profile', 'bogus-profile')
    Test-Assert ($r19e.ExitCode -eq 1) "Senaryo19e: gecersiz profil adi exit kodu 1"

    # ---- Senaryo 20 (j): uninstall config'i korur, -Purge kaldirir ----
    $r20a = Invoke-Install @('-Scope', 'Global', '-HomeDir', $Home19, '-Uninstall')
    Test-Assert ($r20a.ExitCode -eq 0) "Senaryo20a: exit kodu 0"
    Test-Assert (Test-Path -LiteralPath $configPath19) "Senaryo20a: -Purge olmadan config hala duruyor"

    $r20b = Invoke-Install @('-Scope', 'Global', '-HomeDir', $Home19, '-Uninstall', '-Purge')
    Test-Assert ($r20b.ExitCode -eq 0) "Senaryo20b: exit kodu 0"
    Test-Assert (-not (Test-Path -LiteralPath $configPath19)) "Senaryo20b: -Purge ile config kaldirildi"

    # ---- Senaryo 21 (k): DryRun ile -Always + -Profile hicbir sey yazmaz ----
    $Proj21 = New-TestProjectDir '21'
    $Home21 = Join-Path $TestRoot 'home21'
    $r21 = Invoke-Install @('-Scope', 'Project', '-Path', $Proj21, '-Always', '-BlockOnly', '-Profile', 'generous', '-HomeDir', $Home21, '-DryRun')
    Test-Assert ($r21.ExitCode -eq 0) "Senaryo21: exit kodu 0"
    Test-Assert (@(Get-ChildItem -LiteralPath $Proj21 -Force -ErrorAction SilentlyContinue).Count -eq 0) "Senaryo21: proje klasorune hicbir sey yazilmadi"
    Test-Assert (-not (Test-Path -LiteralPath $Home21)) "Senaryo21: home dizini hic olusmadi"

    # ---- Senaryo 22 (l): -Always ile -Scope Global -> exit 1 ----
    $r22 = Invoke-Install @('-Scope', 'Global', '-Always', '-HomeDir', (Join-Path $TestRoot 'home22'))
    Test-Assert ($r22.ExitCode -eq 1) "Senaryo22: -Always + Global exit kodu 1"

    # ---- Senaryo 23 (m): -Always -BlockOnly bos projede -> skill dosyalari kopyalanmaz ----
    $Proj23 = New-TestProjectDir '23'
    $Home23 = Join-Path $TestRoot 'home23'
    $r23 = Invoke-Install @('-Scope', 'Project', '-Path', $Proj23, '-Always', '-BlockOnly', '-Target', 'both', '-HomeDir', $Home23)
    Test-Assert ($r23.ExitCode -eq 0) "Senaryo23: exit kodu 0"
    Test-Assert (Test-Path -LiteralPath (Join-Path $Proj23 'AGENTS.md')) "Senaryo23: AGENTS.md olustu"
    Test-Assert ((Get-Content -LiteralPath (Join-Path $Proj23 'CLAUDE.md') -Raw).Trim() -eq '@AGENTS.md') "Senaryo23: CLAUDE.md @AGENTS.md"
    Test-Assert (-not (Test-Path -LiteralPath (Join-Path $Proj23 '.claude/skills/orkestra'))) "Senaryo23: claude skill kopyalanmadi"
    Test-Assert (-not (Test-Path -LiteralPath (Join-Path $Proj23 '.agents/skills/orkestra'))) "Senaryo23: codex skill kopyalanmadi"
    Test-Assert (-not (Test-Path -LiteralPath (Join-Path $Proj23 '.claude/agents/kontrolcu.md'))) "Senaryo23: kontrolcu.md kopyalanmadi"

    # ---- Senaryo 24 (n): -BlockOnly, -Always olmadan -> exit 1 ----
    $Proj24 = New-TestProjectDir '24'
    $r24 = Invoke-Install @('-Scope', 'Project', '-Path', $Proj24, '-BlockOnly', '-HomeDir', (Join-Path $TestRoot 'home24'))
    Test-Assert ($r24.ExitCode -eq 1) "Senaryo24: -BlockOnly + -Always yok -> exit kodu 1"

    # ---- Senaryo 25 (o): both kurulum sonrasi -Target claude tekrar kosu -> CLAUDE.md hala @AGENTS.md, blok cogalmadi (B1) ----
    $Proj25 = New-TestProjectDir '25'
    $Home25 = Join-Path $TestRoot 'home25'
    Invoke-Install @('-Scope', 'Project', '-Path', $Proj25, '-Always', '-BlockOnly', '-Target', 'both', '-HomeDir', $Home25) | Out-Null
    $r25 = Invoke-Install @('-Scope', 'Project', '-Path', $Proj25, '-Always', '-BlockOnly', '-Target', 'claude', '-HomeDir', $Home25)
    Test-Assert ($r25.ExitCode -eq 0) "Senaryo25: exit kodu 0"
    $claude25 = Join-Path $Proj25 'CLAUDE.md'
    $agents25 = Join-Path $Proj25 'AGENTS.md'
    Test-Assert ((Get-Content -LiteralPath $claude25 -Raw).Trim() -eq '@AGENTS.md') "Senaryo25: CLAUDE.md hala tam olarak @AGENTS.md"
    Test-Assert ((Get-MarkerCount $claude25) -eq 0) "Senaryo25: CLAUDE.md'de marker yok"
    Test-Assert ((Get-MarkerCount $agents25) -eq 1) "Senaryo25: AGENTS.md'de tek marker"

    # ---- Senaryo 26 (p): -Target claude, AGENTS.md'de blok zaten var, CLAUDE.md yok -> CLAUDE.md olusturulur (B1) ----
    $Proj26 = New-TestProjectDir '26'
    $Home26 = Join-Path $TestRoot 'home26'
    Invoke-Install @('-Scope', 'Project', '-Path', $Proj26, '-Always', '-BlockOnly', '-Target', 'codex', '-HomeDir', $Home26) | Out-Null
    $agents26 = Join-Path $Proj26 'AGENTS.md'
    $claude26 = Join-Path $Proj26 'CLAUDE.md'
    Test-Assert (Test-Path -LiteralPath $agents26) "Senaryo26: on-kosul: AGENTS.md olustu"
    Test-Assert (-not (Test-Path -LiteralPath $claude26)) "Senaryo26: on-kosul: CLAUDE.md henuz yok"
    $r26 = Invoke-Install @('-Scope', 'Project', '-Path', $Proj26, '-Always', '-BlockOnly', '-Target', 'claude', '-HomeDir', $Home26)
    Test-Assert ($r26.ExitCode -eq 0) "Senaryo26: exit kodu 0"
    Test-Assert (Test-Path -LiteralPath $claude26) "Senaryo26: CLAUDE.md olusturuldu"
    Test-Assert ((Get-Content -LiteralPath $claude26 -Raw).Trim() -eq '@AGENTS.md') "Senaryo26: CLAUDE.md tam olarak @AGENTS.md"
    Test-Assert ((Get-MarkerCount $claude26) -eq 0) "Senaryo26: CLAUDE.md'de marker yok"

    # ---- Senaryo 27 (q): -Purge, -Uninstall olmadan -> exit 1, hicbir sey yazilmaz (B2) ----
    $Home27 = Join-Path $TestRoot 'home27'
    $r27 = Invoke-Install @('-Scope', 'Global', '-HomeDir', $Home27, '-Purge')
    Test-Assert ($r27.ExitCode -eq 1) "Senaryo27: -Purge olmadan -Uninstall -> exit kodu 1"
    Test-Assert (-not (Test-Path -LiteralPath $Home27)) "Senaryo27: home dizini hic olusmadi"

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
