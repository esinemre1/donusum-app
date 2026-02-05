# 🌍 DONUSUM - Mobil Koordinat Dönüşüm Uygulaması

![Platform](https://img.shields.io/badge/Platform-Android-green?style=flat-square)
![Build Status](https://img.shields.io/github/actions/workflow/status/esinemre1/donusum-app/android-build.yml?style=flat-square&label=Build)
![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)

**DONUSUM**, Harita Mühendisleri ve CBS uzmanları için geliştirilmiş, profesyonel bir mobil koordinat dönüşüm ve görüntüleme aracıdır. **ED50** ve **ITRF96** datumları arasında, Türkiye'nin kullandığı **3 derecelik (TM)** dilim sistemine tam uyumlu dönüşümler yapar.

---

## 🚀 Özellikler

### 📍 Gelişmiş Koordinat Dönüşümü
- **Otomatik Algılama:** Yüklenen `.dns` dosyasının adından dönüşüm yönünü (ED50→ITRF veya ITRF→ED50) akıllıca tespit eder.
- **Hassas Projeksiyon:** Türkiye için özel parametreler (Zone 27-45) ve **towgs84** datum dönüşüm parametreleri ile cm mertebesinde hassasiyet (kontrol noktalarına bağlı olarak).
- **Affine Dönüşümü:** Kontrol noktaları üzerinden Affine dönüşümü uygulayarak yerel uyuşmazlıkları giderir.

### 🗺️ Harita Entegrasyonu
- **Google Maps & OSM:** Altlık olarak Google Hibrit, Uydu veya OpenStreetMap kullanma imkanı.
- **Dinamik Katmanlar:** Birden fazla DNS dosyasını aynı anda yükleyip, katman katman yönetebilirsiniz.
- **Görselleştirme:** Noktalar harita üzerinde ID ve koordinat bilgileriyle görüntülenir.

### 📱 Kullanıcı Dostu Arayüz
- **Kolay Dosya Yükleme:** Tek tıkla cihazınızdan `.dns` veya `.txt` dosyalarını yükleyin.
- **Çevrimdışı Çalışma:** Temel matematiksel hesaplamalar cihaz üzerinde yapılır.
- **Modern UI:** Flutter ile geliştirilmiş akıcı ve modern arayüz.

---

## 📥 Kurulum (APK İndirme)

Uygulamanın en son sürümünü GitHub üzerinden otomatik olarak indirebilirsiniz:

1. Bu sayfanın yukarısındaki **"Actions"** sekmesine tıklayın.
2. Listelenen en son (en üstteki) **"Android Release Build"** işlemine tıklayın.
3. Sayfanın altındaki **Artifacts** bölümünden **`donusum-app-release`** dosyasına tıklayarak indirin.
4. İndirilen ZIP dosyasını açın ve `app-release.apk` dosyasını Android cihazınıza yükleyin.

*(Not: Dışarıdan yükleme olduğu için telefonunuz güvenlik uyarısı verebilir, "Yine de yükle" seçeneği ile devam edebilirsiniz.)*

---

## 🛠️ Teknik Altyapı

Bu proje **Flutter** kullanılarak geliştirilmiştir.

- **Dil:** Dart 3.x
- **Framework:** Flutter 3.x
- **Harita:** `flutter_map`, `latlong2`
- **Projeksiyon:** `proj4dart` (Özel tanımlı projeksiyonlar)
- **Matematik:** `ml_linalg` (Affine hesaplamaları için)

---

## 👤 Geliştirici

**E. Emre KIRIK**

---

<p align="center">
  <i>Bu proje E. Emre KIRIK tarafından geliştirilmiştir. Tüm hakları saklıdır.</i>
</p>
