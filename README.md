# DONUSUM Mobil Uygulama

**By E.Emre KIRIK**

Bu proje, ED50 ve ITRF koordinat sistemleri arasında dönüşüm yapan ve DNS dosyalarını harita üzerinde görüntüleyen bir mobil uygulamadır.

## Özellikler
- **DNS Dosyası Desteği**: `.dns` dosyalarını okur ve haritaya işler.
- **Otomatik Algılama**: Dosya adından dönüşüm yönünü (ED50-ITRF veya ITRF-ED50) otomatik algılar.
- **Doğru Projeksiyon**: Türkiye için özel 3 derecelik Transverse Mercator projeksiyonları (ED50 & ITRF96 Zone 36).
- **Offline Çalışma**: Temel hesaplamalar cihazda yapılır (Harita için internet gerekir).

## Android Kurulumu (APK)

### GitHub Actions ile İndirme
Yazılım her güncellemede otomatik olarak GitHub üzerinde derlenir:
1. GitHub repo'suna gidin.
2. **Actions** sekmesine tıklayın.
3. Son başarılı build'i seçin (yeşil tikli).
4. **Artifacts** bölümünden `donusum-app-release.zip` dosyasını indirin.
5. ZIP'i açın ve `app-release.apk` dosyasını telefonunuza yükleyin.

### Local Build
```bash
flutter pub get
flutter build apk --release
```
Oluşan dosya: `build/app/outputs/flutter-apk/app-release.apk`

---
Copyright © 2026 E.Emre KIRIK
