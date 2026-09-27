<div align="center">

# 🎼 orkestra

**Şef çalmaz.**

**Claude Code** ve **Codex** için alt ajan orkestrasyon skill'i. Ana oturum şef olur: işi
böler, sıkı brifler yazar, kısa raporları okur ve karar verir. Okumayı, yazmayı ve ölçmeyi
alt ajanlar yapar; her sonucu bağımsız bir kontrolcü denetler.

[English](README.md) · [Tek cümleyle kurulum](#-tek-cümleyle-kurulum) · [Ayarlar](#%EF%B8%8F-ayarlar)

</div>

---

## Neden

Her şeyi tek başına okuyan ajan kendi bağlamını doldurur, unutmaya başlar ve limitini daha
ucuz bir modelin yapabileceği işe harcar. Yirmi ajan açmak da çözüm değil: çoğu iş buna
ihtiyaç duymaz ve her alt ajan sıfırdan başlar. orkestra, gerçek koşulardan damıtılmış orta
yol:

- **Varsayılan: kendin yap.** Yalnız bağımsız parçalar, ağır okuma ya da bağımsız kontrol
  gerektiğinde dağıt.
- **Sınırı çizilmiş brifler.** Her ajanın kendi dosyaları, dokunma listesi, ölçülebilir kabul
  ölçütü ve tek satırlık JSON'la biten sabit dönüş formatı var.
- **Kimse kendi işini onaylamaz.** Salt okunur kontrolcü `APPROVE` ya da `REVISE` döner;
  kararı yine şef verir.
- **Ajan ölür, iş ölmez.** Önce yedek, sonra hasar ölçümü, baştan başlatmak yerine diriltme.
- **Modelleri limitlerin belirler.** Profil (`lean`, `balanced`, `generous`) her iş türünü hızlı
  ya da güçlü kademeye bağlar. Claude model takma adları yeni sürümleri kendiliğinden izler.

## 🚀 Tek cümleyle kurulum

Projende Claude Code ya da Codex'i aç ve şunu yaz:

```
https://github.com/Azkhar/orkestra reposunu bu projeye kur.
```

Ajan [INSTALL.md](INSTALL.md)'yi okur, sana üç soru sorar (global mi proje mi, şef modu,
limitin ne kadar rahat), önce deneme koşusunu gösterir, sonra kurar.

**Şef modu** açıksa o projedeki her Claude Code ve Codex oturumu şef olarak başlar ve işi alt
ajanlara bölüp bölmeyeceğine kendisi karar verir. Varsayılan yine "kendin yap"tır; küçük işler
için ajan açılmaz.

Elle kurulum, bayraklar ve dosyaların nereye gittiği için [İngilizce README](README.md#-install-with-one-prompt).

## ⚙️ Ayarlar

Claude Code'da **`/orkestra settings`** (Codex'te **`$orkestra settings`**) yaz; birkaç seçmeli
soru gelir ve ayar dosyası senin yerine yazılır.

| Profil | Kimin için | Mekanik / yargı / kontrol | Paralel | Ajan açmadan önce sor |
|---|---|---|---|---|
| `lean` | limiti dar, küçük paket | hızlı / hızlı / hızlı | 2 | her zaman |
| `balanced` | normal kullanım | hızlı / güçlü / güçlü | 3 | pahalıysa |
| `generous` | büyük paket | güçlü / güçlü / güçlü | 5 | sorma (yine de planı söyler) |

Claude Code'da hızlı = `sonnet`, güçlü = `opus`. Bunlar sağlayıcının önerdiği sürümü izleyen
takma adlar; yeni model çıkınca bir şey değiştirmen gerekmez.

## 🔬 Gerçek bir koşudan doğdu

orkestra, bir hafıza sisteminin dört alt ajan ve bir kontrolcüyle onarıldığı bir gecenin
ardından yazıldı. O gece iki ajan işin ortasında öldü ve iş kaybı olmadan diriltildi, bir ajan
şefin brifindeki yanlış bir sayıyı düzeltti, kontrolcü anlamı sessizce kaymış üç kuralı
yakaladı, şef de kontrolcünün bir önerisini reddetti. Skill'deki kuralların çoğu o gecenin
dersi.

## 🙏 Teşekkür

Fikir Avenox'un "Bir kişi. Bir orkestra." anlatımından geldi
([video](https://www.youtube.com/watch?v=MFqtKpzttGA), [sunum](https://avenox.lol/orkestrasyon/)).
Diğer kaynaklar için [İngilizce README](README.md#-credits).

## Geliştirenler

- Hakan Temur ([@Azkhar](https://github.com/Azkhar))
- Emir OĞUZ ([@Ranork](https://github.com/Ranork))

Katkı kuralları: [CONTRIBUTING.md](CONTRIBUTING.md).

## Lisans

[MIT](LICENSE)
