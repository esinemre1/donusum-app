import 'dart:math';
import 'package:ml_linalg/linalg.dart';
import 'ncn_parser.dart';

/// Dönüşüm Sonuç Modeli
class TransformationResult {
  final List<double> parameters; // Hesaplanan parametreler [a,b,c,d,e,f]
  final double m0; // Karesel Ortalama Hata (RMSE)
  final List<PointData> residuals; // Nokta bazlı uyuşumsuzluklar (vx, vy)
  final bool isSuccess;

  TransformationResult({
    required this.parameters,
    required this.m0,
    required this.residuals,
    this.isSuccess = true,
  });

  // Getterlar (Affine için 6 parametre varsayımı)
  // X' = ax + by + c
  // Y' = dx + ey + f
  // Parametre listesi sırası: a, b, c, d, e, f
  double get a => parameters.length > 0 ? parameters[0] : 0;
  double get b => parameters.length > 1 ? parameters[1] : 0;
  double get c => parameters.length > 2 ? parameters[2] : 0;
  double get d => parameters.length > 3 ? parameters[3] : 0;
  double get e => parameters.length > 4 ? parameters[4] : 0;
  double get f => parameters.length > 5 ? parameters[5] : 0;

  /// Ters dönüşüm parametrelerini hesaplar (Inverse Affine Transformation)
  /// Eğer A*x + b = y ise, ters dönüşüm: x = A^-1 * (y - b)
  TransformationResult getInverse() {
    // Affine matris:
    // | a  b  c |
    // | d  e  f |
    // | 0  0  1 |
    
    // Rotasyon/Ölçek kısmının determinantı
    double det = a * e - b * d;
    
    if (det.abs() < 1e-10) {
      throw Exception("Dönüşüm matrisi tekil (singular), ters alınamıyor!");
    }

    // Ters matris hesaplama (2x2 kısmı)
    double invA = e / det;
    double invB = -b / det;
    double invD = -d / det;
    double invE = a / det;
    
    // Translasyon kısmının tersi: -A^-1 * b
    double invC = -(invA * c + invB * f);
    double invF = -(invD * c + invE * f);

    return TransformationResult(
      parameters: [invA, invB, invC, invD, invE, invF],
      m0: m0, // Hata aynı kalır
      residuals: residuals,
      isSuccess: isSuccess,
    );
  }
}

class TransformationSolver {
  
  /// Affin Dönüşümü (6 Parametre) Çözücü
  /// X' = aX + bY + c
  /// Y' = dX + eY + f
  /// En Küçük Kareler (Least Squares) yöntemi kullanır.
  TransformationResult solveAffine(List<PointData> source, List<PointData> target) {
    if (source.length != target.length || source.length < 3) {
      throw Exception("Affin dönüşümü için en az 3 ortak nokta gereklidir.");
    }

    int n = source.length;
    
    // A Matrisi (Katsayılar) ve L Vektörü (Bilinenler/Target) oluşturuluyor
    // Bilinmeyenler vektörü x: [a, b, c, d, e, f]^T
    List<List<double>> aData = [];
    List<double> lData = [];

    for (int i = 0; i < n; i++) {
       // X denklemi: a*Sx + b*Sy + c*1 + d*0 + e*0 + f*0 = Tx
       aData.add([source[i].y, source[i].x, 1.0, 0.0, 0.0, 0.0]);
       lData.add(target[i].y);
       
       // Y denklemi: a*0 + b*0 + c*0 + d*Sx + e*Sy + f*1 = Ty
       aData.add([0.0, 0.0, 0.0, source[i].y, source[i].x, 1.0]);
       lData.add(target[i].x);
    }

    final Matrix A = Matrix.fromList(aData);
    // L'yi Matrix (sütun vektör) olarak tanımlıyoruz
    final Matrix L = Matrix.fromColumns([Vector.fromList(lData)]);

    // Denklem: A * x = L  =>  x = (A^T * A)^-1 * A^T * L
    final AT = A.transpose();
    final ATA = AT * A;
    
    Matrix inverseATA;
    try {
      inverseATA = ATA.inverse();
    } catch (e) {
       throw Exception("Matris tekil (singular), çözüm yapılamıyor. Noktalar doğrusal olabilir.");
    }

    // x bir Matrix (6x1) olacak
    final Matrix x = inverseATA * (AT * L);
    
    // --- m0 HESAPLAMA ---
    // v = A*x - L  (Düzeltmeler)
    final Matrix AX = A * x;
    final Matrix V = AX - L; // Residual matrix (nx1)
    
    double vvSum = 0;
    List<PointData> residualPoints = [];
    
    // Vektörden vx, vy değerlerini çekip listeye atalım
    for (int i = 0; i < n; i++) {
      // V[row][col], burada col=0
      double vx = V[2 * i][0];
      double vy = V[2 * i + 1][0];
      vvSum += (vx * vx) + (vy * vy);
      
      residualPoints.add(PointData(
        id: source[i].id, 
        y: vx, 
        x: vy
      ));
    }
    
    // Bilinmeyen sayısı u = 6
    int u = 6;
    double m0 = 0.0;
    if (2 * n > u) {
       m0 = sqrt(vvSum / (2 * n - u));
    }

    // x matrisinin ilk sütununu listeye çeviriyoruz
    List<double> paramsList = x.map((row) => row.first).toList();

    return TransformationResult(
      parameters: paramsList,
      m0: m0,
      residuals: residualPoints
    );
  }

  /// Verilen parametrelerle tek bir noktayı dönüştürür
  PointData applyAffine(PointData p, List<double> params) {
    // params: [a, b, c, d, e, f]
    // Dikkat: solveAffine metodunda;
    // 1. Denklem (Y): a*y + b*x + c = NewY
    // 2. Denklem (X): d*y + e*x + f = NewX
    double a = params[0];
    double b = params[1];
    double c = params[2];
    double d = params[3];
    double e = params[4];
    double f = params[5];

    double newY = a * p.y + b * p.x + c;
    double newX = d * p.y + e * p.x + f;

    return PointData(id: p.id, y: newY, x: newX, z: p.z);
  }

  /// Manuel Katsayı Girişi için Sonuç Üretir
  TransformationResult createManualAffine(double a, double b, double c, double d, double e, double f) {
     return TransformationResult(
       parameters: [a, b, c, d, e, f],
       m0: 0.0, // Manuel girişte hata sıfır varsayılır
       residuals: [],
       isSuccess: true
     );
  }

  /// Toplu Dönüşüm Uygula
  List<PointData> applyTransformation(List<PointData> points, TransformationResult result) {
    return points.map((p) => applyAffine(p, result.parameters)).toList();
  }

  /// $AMAT parametrelerinden TransformationResult oluştur
  /// $AMAT formatı: a b c d e f (6 parametre)
  TransformationResult createFromAMAT(List<double> amatParams) {
    if (amatParams.length < 6) {
      throw Exception("\$AMAT için 6 parametre gereklidir, ${amatParams.length} bulundu.");
    }
    
    return TransformationResult(
      parameters: amatParams.sublist(0, 6),
      m0: 0.0,
      residuals: [],
      isSuccess: true,
    );
  }
}
