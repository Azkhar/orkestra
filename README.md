# orkestra

Alt ajanlarla çalışma protokolü. Ana oturum şeftir: işi böler, brif yazar, raporları okur,
karar verir. Okumayı, kurmayı, yazmayı ve ölçmeyi alt ajanlar yapar. Böylece ana oturumun
bağlamı temiz kalır, iş paralel ilerler ve yapılan her iş bağımsız bir gözden geçer.

Claude Code ve Codex için aynı skill.

## Ne kurar

| Dosya | Ne işe yarar |
|---|---|
| `skills/orkestra/SKILL.md` | Protokol: ne zaman dağıtılır, brif kalıbı, kontrolcü, model seçimi, ajan ölünce ne yapılır, kapanış |
| `agents/kontrolcu.md` | Claude Code alt ajanı: başka bir ajanın işini denetler, `REVIEW` JSON'uyla döner. Salt okunurluk talimatla sağlanır; Bash aracı olduğu için teknik olarak yazabilir. |

Nereye kurulur:

| | Claude Code | Codex |
|---|---|---|
| Global | `~/.claude/skills/orkestra/`, `~/.claude/agents/kontrolcu.md` | `~/.agents/skills/orkestra/` |
| Proje | `<proje>/.claude/skills/orkestra/`, `<proje>/.claude/agents/kontrolcu.md` | `<proje>/.agents/skills/orkestra/` |

`kontrolcu` yalnız Claude Code'a kurulur, Codex'te karşılığı yok. Codex yolları
[Codex skills belgesine](https://developers.openai.com/codex/skills) göre.

## Kurulum

```powershell
git clone https://github.com/Azkhar/orkestra.git
cd orkestra

# Windows, PowerShell 7
.\install.ps1                                  # global: Claude Code + Codex
.\install.ps1 -Scope Project -Path D:\proje    # yalnız bir projeye
.\install.ps1 -Target claude                   # yalnız Claude Code
.\install.ps1 -DryRun                          # ne yapacağını göster, yazma

# Windows PowerShell 5.1 (betik çalıştırma kapalıysa)
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

```bash
# macOS / Linux / Git Bash (bayraklar "--scope project" ya da "--scope=project" biçiminde)
./install.sh
./install.sh --scope project --path ~/proje
./install.sh --target codex
./install.sh --dry-run
```

- Hedefte farklı bir sürüm varsa betik üzerine yazmaz, uyarır.
- Güncellemek için `-Force` / `--force`: eski sürüm skills klasörünün bir üstüne
  `orkestra.bak-<zaman>` olarak taşınır (Claude ve Codex onu ayrı bir skill sanıp yüklemesin
  diye), sonra yenisi kurulur.
- Kaldırmak için `-Uninstall` / `--uninstall`: yalnız bu reponun kurduklarını siler
  (frontmatter adı `orkestra` / `kontrolcu` olanları).
- Çıkış kodları: `0` her şey tamam, `2` en az bir hedef farklı olduğu için atlandı, `1` hata.

Güncelleme: `git pull`, sonra kurulum komutunu `-Force` ile tekrar çalıştır.

Testler: `pwsh -File tests/test-install.ps1` ve `bash tests/test-install.sh`. İkisi de geçici
bir ev dizininde çalışır, gerçek `~/.claude` ve `~/.agents` klasörlerine dokunmaz.

## Kullanım

Skill kendiliğinden yüklenir: ajan alt ajan açmaya karar verdiğinde ya da sen şunlardan birini
söylediğinde.

```
Bu işi kendin okuma, orkestrayla yap: parçalara böl, alt ajanlara dağıt, sonunda kontrolcü baksın.
```

```
Şef ol. Şu üç klasördeki sayfaları incelet, her ajan yalnız kendi klasörüne baksın,
bana sadece bulgu, kanıt ve emin olmadıklarını getirsinler. Kod değiştirme, commit atma.
```

```
kontrolcu alt ajanıyla son değişikliği denetle.
```

İşin sonunda ajan başına model ve token tablosu gelir.

## Nereden geldi

Fikir Avenox'un "Bir kişi. Bir orkestra." anlatımından
([video](https://www.youtube.com/watch?v=MFqtKpzttGA),
[sunum](https://avenox.lol/orkestrasyon/)) geldi. Protokol ise bir gerçek koşuda sınandı:
4 alt ajan ve 1 kontrolcüyle bir hafıza sisteminin onarımı. O koşuda iki ajan öldü ve
kaldığı yerden diriltildi, bir ajan şefin brifindeki yanlış bir sayıyı düzeltti, kontrolcü üç
kuralda anlam kaymasını yakaladı, şef de kontrolcünün bir önerisini reddetti. Skill'deki
kuralların çoğu o gecenin dersi.

Başka orkestrasyon skill'leri de tarandı; çoğu elendi (sürekli çalışan ajan sürüleri, ek
platform ya da eklenti şartı, rol tiyatrosu). Kendi cümlemizle alınan birkaç fikir:
maliyet/süre söyleyip onay alma, "bulunamadı"yı da doğrulama ve dar düzeltme turları
([Koryakov/Skills](https://github.com/Koryakov/Skills)); başlamadan ölçülebilir kabul ölçütü
([swarm-orchestrator](https://github.com/moonrunnerkc/swarm-orchestrator)); birden fazla
oturuma yayılan işte diskte durum dosyası ([open-bridge](https://github.com/bks-lab/open-bridge)).
