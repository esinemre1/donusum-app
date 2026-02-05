import 'dart:io';

/// Dönüşüm için kontrol noktası (Kaynak -> Hedef)
class ControlPoint {
  final String id;
  final double sourceY;
  final double sourceX;
  final double targetY;
  final double targetX;

  ControlPoint({
    required this.id,
    required this.sourceY,
    required this.sourceX,
    required this.targetY,
    required this.targetX,
  });
}

class DnsParseResult {
  final List<ControlPoint> points;
  final List<double>? amatParams; // a,b,c,d,e,f found in $AMAT
  DnsParseResult(this.points, this.amatParams);
}

class DnsParser {
  /// .dns dosyasını parse eder
  /// Beklenen format: 
  /// $NOK
  /// NoktaAdi, Y, X, Y, X,
  Future<DnsParseResult> parseFile(File file, {bool smartDetect = false}) async {
    final content = await file.readAsString();
    List<ControlPoint> points = [];
    List<double> amatValues = [];
    
    final lines = content.split('\n');
    int parsedCount = 0;
    List<String> failedLines = [];
    bool parsingPoints = false;
    bool parsingAmat = false;

    // Eğer dosyada $NOK etiketi varsa, ondan sonrasını okumaya başla.
    // Yoksa baştan başla (eski format desteği)
    if (content.contains(r'$NOK')) {
      parsingPoints = false; 
    } else {
      parsingPoints = true; // Eski formatta header yok
    }

    for (var line in lines) {
      String originalLine = line;
      line = line.trim();
      
      if (line.isEmpty) continue;
      
      // Bölüm Kontrolü
      if (line.startsWith(r'$NOK')) {
        parsingPoints = true;
        parsingAmat = false;
        continue;
      }
      if (line.startsWith(r'$AMAT')) {
         parsingAmat = true;
         parsingPoints = false;
         continue;
      }

      if (line.startsWith(r'$') && line != r'$NOK') {
        // $SON veya diğerleri
        if (line.startsWith(r'$SON')) break;
        parsingPoints = false; 
        parsingAmat = false;
        continue;
      }

      // $AMAT Okuma
      if (parsingAmat) {
         try {
            // Boşluk veya virgül ile ayrılmış sayıları al
            final parts = line.split(RegExp(r'[,\s]+')).where((s) => s.isNotEmpty);
            for (var p in parts) {
               // Virgülleri noktaya çevir (TR support)
               p = p.replaceAll(',', '.');
               amatValues.add(double.parse(p));
            }
         } catch(e) {}
         continue; 
      }

      if (!parsingPoints) continue;

      // Yorum satırları
      if (line.startsWith('#') || line.startsWith('//') || line.startsWith('!')) continue;

      // Ayrıştırma Mantığı
      List<String> parts;

      // Netcad DNS genelde virgül ayracılıdır: "P1, 500.00, 600.00, ..."
      if (line.contains(',')) {
         parts = line.split(',');
      } else {
         // Boşluk ayracılı olabilir
         parts = line.split(RegExp(r'\s+'));
      }

      // Parça temizliği
      parts = parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
      
      // En az 5 kolon bekliyoruz: ID, SY, SX, TY, TX
      // 7 kolon varsa (ID, SY, SX, SZ, TY, TX, TZ) Z'leri atlayacağız.
      if (parts.length < 5) {
        // Eğer satırda veri varsa ama kolon eksikse hata logla
        // Ama sadece "0.000" gibi boş satırlarsa atla
        if (originalLine.contains("0.000") && parts.length < 5) continue;
        
        if (parts.isNotEmpty) failedLines.add("Eksik Kolon (${parts.length}/5): $originalLine");
        continue;
      }
      
      // Helper defined inside loop previously but now extracting for scope if needed or keep inside
      // Keep inside for now.
      double parseVal(String val) {
           if (val.contains('.') && val.contains(',')) {
              val = val.replaceAll(',', ''); 
           } else if (val.contains(',')) {
              val = val.replaceAll(',', '.');
           }
           return double.parse(val);
      }

      try {
        String id = parts[0];
        
        // Sayı formatı kontrolü: Eğer sayılar virgüllü ise (500,12) noktaya çevir
        // Ama önce nokta var mı diye bak, varsa elleme.
        double parseVal(String val) {
           if (val.contains('.') && val.contains(',')) {
              // 1.234,56 gibi karmaşık format? Netcad genelde bunu yapmaz.
              // Ya 1234.56 ya da 1234,56 verir.
              // Eğer hem nokta hem virgül varsa ve virgül sondaysa (parse hatası olmasın)
              val = val.replaceAll(',', ''); // Belki binlik ayracıdır?
           } else if (val.contains(',')) {
              val = val.replaceAll(',', '.');
           }
           return double.parse(val);
        }


        // HEURISTIC KOLON SEÇİMİ (Z-Koordinatları ve Hatalı Kolonları Atlamak İçin)
        // Strateji: Satırdaki tüm sayısal değerleri çıkar.
        // Koordinat büyüklüğünde olanları (> 20,000) Ayır (Y, X adayları).
        // Küçük olanları (< 10,000) Z varsay ve atla.

        List<double> validCoords = [];
        // ID (index 0) haricindeki tüm kolonlara bak
        for (int i = 1; i < parts.length; i++) {
           try {
             double val = parseVal(parts[i]);
             // Türkiye'de Y ve X değerleri genelde 200,000 metreden büyüktür (UTM, ED50, ITRF).
             // Z değerleri ise genelde 5000 metreden küçüktür.
             if (val > 20000) { 
               validCoords.add(val);
             }
           } catch (e) {
             // Sayı değilse (açıklama vs) atla
           }
        }

        double sy, sx, ty, tx;
        
        if (validCoords.length >= 4) {
           // En az 4 tane "Büyük Koordinat" bulduk. Sırasıyla alıyoruz.
           // Genelde sıra: SrcY, SrcX, TgtY, TgtX
           sy = validCoords[0];
           sx = validCoords[1];
           ty = validCoords[2];
           tx = validCoords[3];
        } else {
           // Yeterli büyük sayı yoksa, klasik yönteme geri dön (Belki yerel koordinattır, 1000, 2000 gibi)
           // Ama en az 5 parça olduğunu zaten kontrol etmiştik.
           sy = parseVal(parts[1]);
           sx = parseVal(parts[2]);
           // 7 kolon varsa Z atla, yoksa 3,4 al
           if (parts.length >= 7) {
             ty = parseVal(parts[4]);
             tx = parseVal(parts[5]);
           } else {
             ty = parseVal(parts[3]);
             tx = parseVal(parts[4]);
           }
        }

        // Smart Detect Logic for Source (Input)
        if (smartDetect) {
           if (sy > sx && sy > 3000000 && sx < 1000000) {
              double temp = sy; sy = sx; sx = temp;
           }
           // Smart Detect Logic for Target (Output)
           if (ty > tx && ty > 3000000 && tx < 1000000) {
              double temp = ty; ty = tx; tx = temp;
           }
        }

        // Sıfır satırlarını (Placeholder) atla
        if (sy == 0 && sx == 0 && ty == 0 && tx == 0) continue;

        points.add(ControlPoint(
          id: id,
          sourceY: sy,
          sourceX: sx,
          targetY: ty,
          targetX: tx,
        ));
        parsedCount++;
      } catch (e) {
        failedLines.add("Parse Hatası ($e): $originalLine");
        continue;
      }
    }
    
    // Hata Ayıklama Raporu
    if (points.length < 3 && amatValues.isEmpty) {
      String report = "Okunan Satır: ${lines.length}, Parse Edilen: $parsedCount\n";
      if (failedLines.isNotEmpty) {
         report += "Hatalı Satırlar (İlk 5):\n" + failedLines.take(5).join("\n");
      }
      print("DNS Parse Uyarısı: Yetersiz nokta. \n$report");
    }

    return DnsParseResult(points, amatValues.isNotEmpty && amatValues.length >= 6 ? amatValues : null);
  }
}
