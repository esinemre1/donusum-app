import 'dart:io';

/// Nokta verilerini tutan basit model sınıfı
class PointData {
  final String id;
  final double y; // Sağa değer (Easting)
  final double x; // Yukarı değer (Northing)
  final double? z; // Kot (Elevation), opsiyonel

  PointData({required this.id, required this.y, required this.x, this.z});

  @override
  String toString() => 'PointData(id: $id, y: $y, x: $x, z: $z)';
}

/// NCN (Netcad) ve benzeri nokta dosyalarını okuyan sınıf
class NcnParser {
  /// Dosya içeriğini parse eder
  /// [smartDetect] false: Netcad standartına (Y, X) sadık kalır.
  Future<List<PointData>> parseFile(File file, {bool smartDetect = false}) async {
    final content = await file.readAsString();
    return parseString(content, smartDetect: smartDetect);
  }

  /// String içeriği parse eder
  /// Netcad standart: NoktaAdi Y(Sağa/East) X(Yukarı/North) Z(Kot)
  List<PointData> parseString(String content, {bool smartDetect = false}) {
    List<PointData> points = [];
    final lines = content.split('\n');

    for (var line in lines) {
      line = line.trim();
      // Yorum satırları ve boş satırları geç
      if (line.isEmpty || line.startsWith('#') || line.startsWith('/')) continue;

      // Genellikle boşluk veya tab ile ayrılır
      final parts = line.split(RegExp(r'\s+'));

      // En az 3 eleman olmalı: Ad, Y, X (veya Ad, X, Y)
      if (parts.length < 3) continue;

      String id = parts[0];
      // Sayısal değerleri deniyoruz
      double? v1 = double.tryParse(parts[1]);
      double? v2 = double.tryParse(parts[2]);
      double? v3 = (parts.length > 3) ? double.tryParse(parts[3]) : null;

      if (v1 == null || v2 == null) {
        // Belki header satırıdır, atla
        continue;
      }

      double finalY = v1;
      double finalX = v2;

      // Türkiye özelinde Akıllı Tespit (Smart Detect)
      // ITRF veya ED50 3 derecelik dilimlerde Y değeri genellikle 500.000 civarında (datumuna göre değişir)
      // X değeri ise 4.000.000 üzerindedir.
      if (smartDetect) {
        if (v1 > v2) {
          // Eğer 1. değer 2. değerden çok büyükse, muhtemelen 1. değer X (kuzey), 2. değer Y (sağa) dır.
          // Netcad standartı Y, X, Z şeklindedir ama bazı cihazlar X, Y basabilir.
          // Basit heuristic: X (4milyon) > Y (500bin)
          // NOT: Bu sadece Türkiye için ve UTM projeksiyonu için geçerli bir varsayımdır.
          if (v1 > 3000000 && v2 < 1000000) {
             finalY = v2; 
             finalX = v1;
          }
        }
      }

      points.add(PointData(id: id, y: finalY, x: finalX, z: v3));
    }

    return points;
  }
}
