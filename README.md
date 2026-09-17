# Controller Starter

Xbox kontrolcünü açtığında **Steam otomatik açılır**, kontrolcüyü kapattığında **açık olan oyun ve Steam otomatik kapanır.**

Konsol gibi bir deneyim: kontrolcüyü aç, oyna, kapat. Klavye ve fareye dokunmana gerek yok.

![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078D6)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)
![License](https://img.shields.io/badge/license-MIT-green)

---

## İçindekiler

- [Ne yapıyor?](#ne-yapıyor)
- [Nasıl çalışıyor?](#nasıl-çalışıyor)
- [Gereksinimler](#gereksinimler)
- [Kurulum](#kurulum)
- [Test etme](#test-etme)
- [Ayarlar](#ayarlar)
- [Sık karşılaşılan durumlar](#sık-karşılaşılan-durumlar)
- [Güvenlik notu](#güvenlik-notu)
- [Kaldırma](#kaldırma)
- [Lisans](#lisans)

---

## Ne yapıyor?

| Olay | Sonuç |
|---|---|
| Kontrolcü bağlandı (Bluetooth, USB veya Xbox Wireless Adapter) | Steam açılır — varsayılan olarak **Big Picture** modunda |
| Kontrolcü kapandı / bağlantısı koptu | Önce açık Steam oyunu nazikçe kapatılır, sonra Steam kapatılır |
| Kontrolcü kısa süreliğine koptu (sinyal dalgalanması) | Hiçbir şey olmaz — geri gelirse oyun kapanmaz |
| Steam'i kendin kapattın, kontrolcü hâlâ açık | Steam tekrar açılmaz; kontrolcüyü kapatıp açman beklenir |

Windows başlangıcında sessizce çalışır, arka planda pencere göstermez.

## Nasıl çalışıyor?

Kontrolcü algılama **XInput** üzerinden yapılır (`XInputGetState`). Cihaz listesi taramak yerine Windows'a doğrudan "şu anda bağlı bir gamepad var mı?" diye sorar — kontrolcü uykuya geçtiğinde veya pili bittiğinde de bunu anında görür.

Betik küçük bir durum makinesi ile çalışır:

```
Waiting   ── kontrolcü 2 sn boyunca bağlı ─────────►  Steam açılır  ──►  Active
Active    ── kontrolcü 20 sn boyunca yok ──────────►  oyun + Steam kapanır  ──►  Waiting
Active    ── Steam'i kullanıcı kapattı ────────────►  Suspended
Suspended ── kontrolcü kapalı ─────────────────────►  Waiting  (tekrar hazır)
```

`Suspended` durumu şunun için var: Steam'den kendi isteğinle çıktığında, kontrolcü hâlâ açık olduğu için Steam'in anında yeniden açılmasını engeller.

**Oyun tespiti:** Kapatılacak oyunlar, çalışan işlemler arasından yolu bir Steam kütüphanesinin `steamapps\common\` klasörünün altında olanlardan seçilir. Kütüphane yolları `libraryfolders.vdf` dosyasından okunur, yani ikinci/üçüncü diskteki oyunlar da bulunur. Bu klasörlerin dışındaki hiçbir işleme dokunulmaz.

**Kapatma sırası:** Önce `CloseMainWindow()` ile pencere kapatma isteği gönderilir (oyun kaydını yapabilsin diye), 15 saniye beklenir, hâlâ açıksa zorla sonlandırılır. Steam için `steam.exe -shutdown` kullanılır — bu Steam'in kendi temiz kapanma yoludur.

## Gereksinimler

- Windows 10 veya 11
- Windows PowerShell 5.1 (Windows ile birlikte gelir, ayrıca kurulum gerekmez)
- Steam
- XInput uyumlu bir kontrolcü (Xbox One, Xbox Series, Xbox 360 ve XInput taklidi yapan çoğu üçüncü parti kontrolcü)

> **Not:** DualShock / DualSense gibi kontrolcüler XInput ile görünmez. DS4Windows ya da Steam Input gibi bir katman kullanıyorsan çalışır.

## Kurulum

```bash
git clone https://github.com/KULLANICI_ADIN/controller-starter.git
```

> `KULLANICI_ADIN` yerine kendi GitHub kullanıcı adını yaz.

Klasörü istediğin yere koy, sonra PowerShell'de o klasörün içinde:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1
```

Kurulum betiği şunları yapar:

1. Oturum açıldığında çalışan bir **Zamanlanmış Görev** (`ControllerStarter`) oluşturur.
2. Görev oluşturulamazsa otomatik olarak **Başlangıç klasörüne** bir kısayol koyar.
3. Watcher'ı hemen başlatır.

Yönetici hakkı gerekmez. Zorla bir yöntem seçmek istersen:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -Method Startup
```

## Test etme

Her şeyin doğru algılandığını tek komutla görebilirsin:

```powershell
powershell -ExecutionPolicy Bypass -File .\ControllerStarter.ps1 -Once
```

Örnek çıktı:

```
Controller Starter - status
---------------------------
Controller connected : True
Pads detected        : 1
XInput backend       : xinput1_4.dll
Steam executable     : C:\Program Files (x86)\Steam\steam.exe
Steam running        : False
Game folders         : c:\program files (x86)\steam\steamapps\common\
Detected games       : (none)
```

Pencereyi görerek canlı izlemek için:

```powershell
powershell -ExecutionPolicy Bypass -File .\ControllerStarter.ps1 -NoHide
```

Arka planda çalışırken olan biten `logs\controller-starter.log` dosyasına yazılır.

## Ayarlar

Tüm ayarlar `config.json` içinde. Değiştirdikten sonra watcher'ı yeniden başlat (`Uninstall.ps1` sonra `Install.ps1`, ya da bilgisayarı yeniden başlat).

| Anahtar | Varsayılan | Açıklama |
|---|---|---|
| `steamExePath` | `""` | Boşsa Steam kayıt defterinden bulunur. Gerekirse tam yol yaz. |
| `steamLaunchArgs` | `["-bigpicture"]` | Steam'e verilecek parametreler. Normal pencerede açılsın istersen `[]` yap. |
| `pollIntervalSeconds` | `2` | Kontrolcü durumunun kaç saniyede bir kontrol edileceği. |
| `connectDebounceSeconds` | `2` | Steam açılmadan önce kontrolcünün kaç saniye bağlı kalması gerektiği. |
| `disconnectGraceSeconds` | `20` | **Önemli.** Bağlantı koptuktan sonra kapatmadan önce beklenecek süre. |
| `launchIfControllerAlreadyConnectedAtStartup` | `false` | Windows açılırken kontrolcü zaten bağlıysa Steam açılsın mı? |
| `closeGamesOnDisconnect` | `true` | Bağlantı kesilince oyun kapatılsın mı? |
| `closeSteamOnDisconnect` | `true` | Bağlantı kesilince Steam kapatılsın mı? |
| `closeSteamOnlyIfLaunchedByThisTool` | `false` | `true` ise, Steam'i sen açtıysan ona dokunulmaz. |
| `gracefulCloseTimeoutSeconds` | `15` | Oyun kendi kapanmazsa zorla kapatılmadan önce beklenecek süre. |
| `steamShutdownTimeoutSeconds` | `30` | Steam temiz kapanmazsa zorla kapatılmadan önce beklenecek süre. |
| `extraGameProcessNames` | `[]` | Steam kütüphanesi dışındaki oyunlar için exe adları, ör. `["RiotClientServices.exe"]`. |
| `ignoreProcessNames` | Steam yardımcıları | Asla kapatılmayacak işlem adları. |
| `logEnabled` | `true` | Dosyaya log yazılsın mı? |
| `logMaxSizeKB` | `1024` | Log dosyası bu boyutu aşınca döndürülür. |

### Önerdiğim ayarlamalar

**Xbox kontrolcüsü 15 dakika hareketsiz kalınca kendini kapatır.** Uzun ara verdiğinde oyunun kapanmasını istemiyorsan `disconnectGraceSeconds` değerini yükselt:

```json
"disconnectGraceSeconds": 90
```

Sadece Steam kapansın, oyun açık kalsın istersen:

```json
"closeGamesOnDisconnect": false
```

Big Picture yerine normal Steam penceresi istersen:

```json
"steamLaunchArgs": []
```

## Sık karşılaşılan durumlar

**Kontrolcüyü şarj etmek için USB'ye taktığımda Steam açılıyor.**
Kabloyla bağlı kontrolcü XInput'ta "bağlı" görünür, ayırt etmenin bir yolu yok. `launchIfControllerAlreadyConnectedAtStartup` zaten `false` olduğu için Windows açılışında sorun olmaz; çalışırken takarsan `connectDebounceSeconds` değerini yükseltmek kısa denemeleri filtreler.

**Oyun ortasında kontrolcü uyudu ve oyun kapandı.**
`disconnectGraceSeconds` değerini yükselt (yukarıdaki öneriye bak).

**Steam açılmıyor.**
`-Once` ile çalıştırıp `Steam executable` satırına bak. `NOT FOUND` yazıyorsa `config.json` içinde `steamExePath` alanına tam yolu yaz.

**Kontrolcü algılanmıyor.**
`-Once` çıktısında `Pads detected: 0` görüyorsan kontrolcü XInput'a ulaşmıyor demektir. Windows'un "Oyun kumandalarını kur" ekranında (`joy.cpl`) görünüyor mu kontrol et.

**Steam kapanırken "Steam is shutting down" takılı kalıyor.**
Normal; `steamShutdownTimeoutSeconds` (varsayılan 30 sn) dolunca zorla kapatılır. İndirme sürüyorsa bu süreyi uzatmak isteyebilirsin.

**Betik çalışıyor mu nasıl anlarım?**

```powershell
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*ControllerStarter*' }
```

## Güvenlik notu

Bu araç işlem kapatıyor, dolayısıyla neye dokunduğu net olsun:

- Yalnızca yolu bir Steam kütüphanesinin `steamapps\common\` klasörü altında olan işlemler kapatılır.
- Bunun tek istisnası, `config.json` içine **senin** eklediğin `extraGameProcessNames` listesidir.
- Kapatma her zaman önce nazik yoldan denenir; zorla sonlandırma yalnızca zaman aşımından sonra devreye girer.
- Yönetici hakkı istenmez, sistem ayarı değiştirilmez, ağ bağlantısı kurulmaz.

Kaydedilmemiş oyun ilerlemesi kaybolabilir — özellikle otomatik kayıt yapmayan oyunlarda. Bunu göz önünde bulundurarak `disconnectGraceSeconds` süresini kendine göre ayarla.

## Kaldırma

```powershell
powershell -ExecutionPolicy Bypass -File .\Uninstall.ps1
```

Zamanlanmış görevi, başlangıç kısayolunu ve çalışan örneği kaldırır. Proje klasörüne dokunmaz.

## Lisans

[MIT](LICENSE) — Samet Ege
