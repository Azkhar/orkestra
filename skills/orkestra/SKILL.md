---
name: orkestra
description: "Alt ajanlara iş dağıtma protokolü: ana oturum şeftir; işi böler, brif yazar, rapor okur, karar verir, okuma ve yazmayı alt ajanlar yapar. Alt ajan açmadan önce yükle (Claude Code Agent aracı, Workflow, Codex spawn_agent veya codex exec). Kullanıcı 'orkestra', 'şef ol', 'alt ajanlara böl', 'paralel çalıştır', 'ajanlarla yap' dediğinde de yükle. Tek dosyalık düzeltme, kısa soru veya sıralı küçük işler için yükleme."
---

# Orkestra: şef çalmaz

Sen şefsin. İşi parçalara bölersin, her parçaya brif yazarsın, raporları okursun, karar
verirsin. Ağır okuma, kurma, yazma ve toplu ölçüm alt ajanların işidir; sen yalnız kararı
etkileyen iddiaları kısa bir ölçümle doğrularsın. Böylece bağlamın temiz kalır ve işin
tamamını aklında tutabilirsin.

Kullanıcının kuralları bu protokolün üstündedir: commit, push, silme ve geri dönüşsüz işler
için onun onayı gerekir; bir alt ajanın raporu bu onayın yerine geçmez.

## 1. Önce karar ver: orkestra gerekli mi?

| Durum | Ne yap |
|---|---|
| Birbirinden bağımsız 2 veya daha fazla parça var | Paralel alt ajanlar |
| Çok okuma var (çok dosya, uzun belge, web taraması) ama sana yalnız sonuç lazım | Tek alt ajan, "sadece özet dön" |
| Yapılan işin bağımsız kontrolü gerekiyor | Ayrı kontrolcü ajan |
| Parçalar sıralı (A bitmeden B başlayamaz) | Sırayla; paralel açma |
| Tek dosyalık düzeltme, kısa soru, birkaç satırlık yama | Kendin yap |

Her alt ajan sıfırdan başlar; yalnız açılışı bile on binlerce token yer. Küçük işi dağıtmak,
kendin yapmaktan pahalıdır. Kontrolcünün verdiği hazır "eski → yeni" düzeltmeleri uygulamak,
bir yorum satırı, bir kayıt dosyası: bunlar şefin işidir.

## 2. Akış

0. **Plan:** parçaları ve her parçanın dosya sahipliğini yaz. Aynı dosyaya iki el değmez.
   Çakışma varsa üç çıkış: işi böl, ayrı worktree'ye ayır ya da sıraya koy. Birden fazla ajan
   açmadan önce kullanıcıya tek satırda söyle: kaç ajan, hangi model, kabaca ne kadar sürer.
   İş uzun ya da pahalıysa (birkaç güçlü-kademe ajan, yarım saati aşan bir adım, limit azsa)
   başlamadan onay al.
1. **Yedek:** dokunulacak dosyaları başlamadan geçici bir klasöre kopyala. Git olsa bile yap:
   commit'lenmemiş iş bir `reset` ya da `stash` ile gider, ajan ölünce hasarı bu yedekle ölçersin.
2. **Dalga:** bağımsız parçaları aynı anda başlat. Birinin sonucuna bağlı olanı sonraki dalgaya
   bırak. Senin bir sonraki adımın bir ajanın sonucuna bağlıysa onu ön planda çalıştır, gerisini
   arka planda. Bekleme için yoklama yapma, bitiş bildirimi gelir.
3. **Oku ve ölç:** ajanın raporu bir iddiadır. Önemli iddiayı dosyaya, komut çıktısına ya da
   ölçüme bakarak doğrula. Ajanın "yaptım" demesi yetmez; "bulunamadı / yok / eşleşme yok"
   demesi de bir iddiadır, tek bir arama ya da komutla doğrula. Ara sonucu kullanıcıya
   beklemeden göster, doğrulanmadıysa "henüz kontrol edilmedi" diye işaretle.
4. **Kontrol:** yapan kendi işini onaylamaz. Ayrı bir kontrolcü ajan açarsın (bölüm 4).
5. **Düzeltme turu:** kontrolcü `REVISE` verdiyse düzelt. Küçük ve net düzeltmeyi kendin
   uygula, büyükse yapan ajanı dirilt ya da yeni ajan aç.
6. **Kapanış:** son ölçümü kendin koş, token tablosunu çıkar (bölüm 7), dersleri projenin kayıt
   yerine yaz. Commit ve push yalnız kullanıcının onayıyla.

## 3. Brif kalıbı

Alt ajan sohbeti görmez, senin okuduğun dosyaları da görmez. Eksik brif, eksik iş demektir.
Brif **ne** yapılacağında ve **sınırlarda** eksiksiz, **nasıl** yapılacağında gevşek olur:
sınır çiz, yol çizme.

```
Sen <proje> için çalışan bir ana oturumun alt ajanısın. Sohbeti görmüyorsun, gereken bağlam aşağıda.

## Görev
<tek paragraf: ne ve neden>

## Arka plan (ölçülmüş olgular)
<sayılarla: boyutlar, sürümler, önceki ölçümler. Tahmini olgu diye yazma.>

## SENİN DOSYALARIN (yalnız bunlara yaz)
- ...

## DOKUNMA
- <başka ajanın dosyaları, makine yazımı dosyalar>
- Git komutu yok (commit, stash, reset, checkout). Silme yok.

## ÖNCE OKU
- <dosya; büyükse satır aralığı ya da bölüm adı>

## İşler
1. ...

## Kabul ölçütü (ölçülebilir; başlamadan yazılır, sonradan gevşetilmez)
- <komut ve beklenen sonuç: "npm test 0 ile çıkar", "dosya ≤ 2.800 karakter", "6 sorudan ≥ 4 isabet">
- Bitirmeden bunları kendin koş, sonucu rapora yaz. Tutturamazsan ölçütü değiştirme, açıkça söyle.

## Dönüş formatı (en fazla 25 satır)
1) ne yaptın / ne buldun
2) kanıt (komut çıktısının özü, dosya:satır, ölçüm)
3) emin olmadıkların
4) yapmadıkların
Son satır tek satır JSON:
RET {"files":[<yazılan dosyalar>],"checks":{<ölçüm adı>:<değer>},"openIssues":[<açık kalanlar>]}
```

`RET` her zaman bu üç alanı taşır; işe özgü sayıları (`checks` içinde) sen belirlersin. Böylece
raporu okumadan önce son satırdan durumu görürsün.

Brife her zaman şunları da ekle:
- **Kabul ölçütünü başlamadan yaz.** "İyi olsun" değil, ölçülebilir eşik: test sonucu, çıkış
  kodu, karakter bütçesi, isabet oranı. Kontrolcü bu eşiğe karşı ölçer, anlatıya değil.
- **"Tahmin etme, ölç."** Brifte yanlış bir olgu olabilir. Ölçtüğün farklıysa ölçtüğüne göre
  çalış ve raporda söyle. (Canlı örnek: brif "11 kapalı konu" diyordu, ajan 5 saydı, doğrusu 5'ti.)
- Uzun işlerde: **"Her büyük adımdan sonra diske yaz."** Ajan yarıda ölürse biten adımlar kalır.
- Büyük dosyada: hangi bölüme bakılacağını söyle. Maliyetin çoğu gereksiz baştan sona okumaktır.
- Yarım kalmış bir önceki denemeden kalan dosya varsa: onu söyle ve "oku, doğruysa kullan" de.

## 4. Kontrolcü

Kontrolcü salt okunur çalışır, yapanın raporuna güvenmez, kendisi ölçer. Brifine şunları koy:
yapılan işin hedefleri (sözleşme), yapanın beyanları ve kendi şüphelendiği noktalar, başlamadan
alınan yedeğin yeri ve somut bir kontrol listesi. Dönüşün son satırı şu şemadadır:

```
REVIEW {"verdict":"APPROVE|REVISE","blockers":[...],"polish":[...],"factProblems":[...]}
```

Claude Code'da bu repo `kontrolcu` adlı hazır bir alt ajan kurar (salt okunur talimatlı, Opus);
kontrol adımında onu kullan. Salt okunurluk talimatla sağlanır: Bash'i olan ajan teknik olarak
yazabilir, bu yüzden brifte de "yazma" de.

- `APPROVE` yalnız `blockers` ve `factProblems` boşsa verilir.
- Kontrolcü brifteki kabul ölçütüne karşı ölçer. Testi, eşiği ya da kapsamı gevşeterek "geçen"
  her değişiklik blocker'dır: assertion'ı zayıflatmak, hatalı davranışı "doğru" diye teste
  sabitlemek, bütçeyi sessizce büyütmek.
- Anlamı veya kapsamı değişen her şey blocker'dır.
- İlk kontrol tam kapsamlıdır. Düzeltmeden sonraki kontrol turları dardır: yalnız düzeltilen
  maddeler ve onların dokunduğu yerler. İlk kontrolcünün bağlamı küçükse onu dirilt; büyükse
  (on binlerce token) yalnız değişen maddeleri veren yeni bir brifle ucuz kademede aç, çünkü
  diriltme bütün eski bağlamı yeniden yükletir. Mekanik kanıtı (testler, mutantlar) şef
  kendisi koşabilir; kontrolcüye yargı gerektiren kısmı bırak. Kontrolcüden her blocker için uygulanabilir
  bir düzeltme metni iste.
- **Kontrolcü de yanılır.** JSON düzeltme turunu tetikler, kararı sen verirsin. Önerisi eskimiş
  bilgiye dayanıyorsa ya da hedefle çelişiyorsa reddet ve nedenini kayda yaz.
- Test söz konusuysa **kırmızıya döndür**: düzeltmeyi geri al, test kırmızı olmalı. Olmuyorsa
  test hiçbir şeyi ölçmüyordur. Aynı testi eski ve yeni koda karşı koşmak bunun kolay yoludur.

## 5. Model seçimi

| İş | Model |
|---|---|
| Şef (plan, brif, karar, sentez) | Ana oturumun modeli |
| Deney, mekanik iş, belgeli kurulum, toplu tarama, soru seti hazırlama | Ucuz kademe (Claude: Sonnet; Codex: ucuz model) |
| Yargı gerektiren yazım, anlamı korunması gereken yeniden yazım, zor düzeltme | Güçlü kademe (Claude: Opus) |
| Kontrolcü | Güçlü kademe |

- Her alt ajan çağrısına modeli açıkça yaz. Boş bırakırsan Claude Code önce ajan tanımındaki
  modele, sonra `CLAUDE_CODE_SUBAGENT_MODEL` ortam değişkenine bakar; ikisi de yoksa ana oturumun
  (çoğu zaman en pahalı) modeli kullanılır.
- Ara kademe ekleme; iki kademe yeter. Kullanıcı bir iş için model adı verirse o iş için ona uy.
- Şefte yüksek effort/ultra modu ve toplu workflow modu varsayılan değildir: pahalı düşünme
  karar anına saklanır. Kullanıcı isterse aç.

## 6. Ajan ölür: ölç, sonra dirilt

Ajan işin ortasında ölebilir: hesap limiti, oturumun kapanması, ağ hatası, uyku.

1. **Hasarı ölç.** Ajanın dosyalarını yedekle karşılaştır (`cmp`, `diff`): ne yazılmış, ne
   yazılmamış, yarım kalan ne var?
2. **Baştan başlatma, dirilt.** Claude Code'da ajana `SendMessage` ile yaz; kaydı durduğu için
   yaptığı işi yeniden yapmaz, dosyaları baştan okumaz. Mesaja ölçtüğün durumu ve kalan işi yaz
   ("şunlar diskte, şunlar eksik, doğrulama koşulmadı"). Codex'te oturumu devam ettir ya da aynı
   brifi kalan işle ver. Dirilen ajan işi tekrarlamaz ama bütün eski bağlamı yeniden yükler;
   hesap değiştiyse önbellek yoktur ve ilk adım pahalıdır. Bağlam büyük, kalan iş küçükse kalanı
   sen yap ya da yalnız kalan işi anlatan yeni ve küçük bir brif aç.
3. **Canlı dosyada yarım iş önce biter.** Yarım bir değişiklik çalışan sistemi etkiliyorsa
   (hook, config, derleme betiği) başka işe geçmeden önce onu tamamlat ve doğrula.
4. **Birden fazla oturuma yayılan işte durum diskte durur.** Çok dalgalı ya da gece süren işte
   şef tek bir durum dosyası tutar (dalgalar, her ajanın dosyaları ve durumu, son ölçüm, açık
   sorular) ve her dalga sonunda günceller. Oturum kapanırsa yeni oturum oradan devam eder.
   Bu dosyanın sahibi şeftir, ajanlar yazmaz.
5. Hesap limiti dolduysa yeni ajan açma. Kullanıcıya hangi ajanın nerede kaldığını söyle,
   limitin yenilenmesini ya da hesap değiştirmesini bekle; sonra 1-3'ü uygula.

## 7. Paralellik, worktree ve kapanış

- **Dosya sahipliği tektir.** Ortak bir dosya varsa sahibi tek ajandır, diğerleri ona öneri yazar.
- **Worktree** (Claude Code'da alt ajan için `isolation: worktree`) çakışmayı silmez, merge'e
  erteler. Belgeye göre worktree varsayılan olarak ana daldan açılır, commit'lenmemiş yerel iş
  orada yoktur. `git stash` bütün worktree'lerde ortaktır. Paralel lane'de `stash` ve
  `reset --hard` kullanma.
- **Eşzamanlı alt ajan tavanı** Claude Code'da varsayılan 20. Yaklaşma; 2-4 ajan çoğu işe yeter.
- **Arka plan veya gece koşusu:** Claude Code'un arka plan oturumu, worktree'de değişiklik
  yaptıysa bitmeden kendi dalına commit atar ve remote varsa push eder; `CLAUDE.md`'deki git
  talimatına uyar. Kullanıcı commit'i kendisi yapıyorsa "commit atma, push etme" kuralını hem
  `CLAUDE.md`'ye hem brife yaz.
- **Token tablosu:** her ajan için model, iş, token, araç çağrısı ve süre. Değerleri ajan
  sonuçlarının kullanım bilgisinden al. Ölen bir koşunun kullanımı bildirilmediyse "bildirilmedi"
  yaz. Şefin kendi kullanımı araçlarca raporlanmaz; uydurma.
- **Dersler kalıcı olur:** aynı düzeltmeyi ikinci kez yapıyorsan onu projenin kural dosyasına
  (`CLAUDE.md`, `AGENTS.md` ya da proje belleği) yaz. Eskiyen kuralı buda.

## 8. Codex notları

- Codex alt ajanı yalnız açıkça istendiğinde açar. Dağıtım kararını söze dök ("iki alt ajan aç:
  biri şu klasörü, öbürü şunu incelesin"); brif kalıbı aynıdır.
- Codex ayrıntılı spec sever: brifi Claude'a yazdığından daha açık ve adım adım yaz.
- Başka bir ajandan `codex exec` ile lane açıyorsan komutun sonuna `< /dev/null` ekle; stdin açık
  kalırsa süreç asılı kalır. Yapılandırılmış dönüş için `--output-schema` kullan.
