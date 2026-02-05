import 'package:proj4dart/proj4dart.dart';
import 'ncn_parser.dart';

/// Desteklenen Koordinat Sistemleri Türleri
enum DatumType { ed50, itrf96, wgs84 }

/// Dilimler (Zones) - 3 Derecelik
enum ZoneType { z27, z30, z33, z36, z39, z42, z45 }

/// Koordinat Sistemi Tanımı
class CoordinateSystem {
  final String name;
  final DatumType datum;
  final ZoneType? zone;
  final Projection projection;

  CoordinateSystem({
    required this.name,
    required this.datum,
    required this.projection,
    this.zone,
  });

  @override
  String toString() => name;
}

class CoordinateManager {
  // Singleton
  static final CoordinateManager _instance = CoordinateManager._internal();
  factory CoordinateManager() => _instance;
  CoordinateManager._internal() {
    _initProjections();
  }

  late final Projection wgs84;
  
  // Sistem Listeleri
  final List<CoordinateSystem> systems = [];

  void _initProjections() {
    // 1. WGS84 (Coğrafi)
    wgs84 = Projection.parse('+proj=longlat +datum=WGS84 +no_defs');
    
    // 2. ED50 Tanımları (Türkiye için 3 derecelik)
    // Parametreler genelde: +proj=tmerc +lat_0=0 +k=1 +x_0=500000 +y_0=0 +ellps=intl +units=m +no_defs
    // Central Meridian (lon_0) dilime göre değişir.
    _addSystem(DatumType.ed50, ZoneType.z27, 27);
    _addSystem(DatumType.ed50, ZoneType.z30, 30);
    _addSystem(DatumType.ed50, ZoneType.z33, 33);
    _addSystem(DatumType.ed50, ZoneType.z36, 36);
    _addSystem(DatumType.ed50, ZoneType.z39, 39);
    _addSystem(DatumType.ed50, ZoneType.z42, 42);
    _addSystem(DatumType.ed50, ZoneType.z45, 45);

    // 3. ITRF96 (GRS80 elipsoidi kullanır, WGS84 ile çok yakındır)
    // +proj=tmerc +lat_0=0 +k=1 +x_0=500000 +y_0=0 +ellps=GRS80 +units=m +no_defs
    _addSystem(DatumType.itrf96, ZoneType.z27, 27);
    _addSystem(DatumType.itrf96, ZoneType.z30, 30);
    _addSystem(DatumType.itrf96, ZoneType.z33, 33);
    _addSystem(DatumType.itrf96, ZoneType.z36, 36);
    _addSystem(DatumType.itrf96, ZoneType.z39, 39);
    _addSystem(DatumType.itrf96, ZoneType.z42, 42);
    _addSystem(DatumType.itrf96, ZoneType.z45, 45);
  }

  void _addSystem(DatumType type, ZoneType zone, int centralMeridian) {
    String name = "${type.name.toUpperCase()} Loop ${zone.name.substring(1)} (${centralMeridian}°)";
    String projStr = "";

    if (type == DatumType.ed50) {
      projStr = '+proj=tmerc +lat_0=0 +lon_0=$centralMeridian +k=1 +x_0=500000 +y_0=0 +ellps=intl +towgs84=-87,-98,-121,0,0,0,0 +units=m +no_defs';
    } else if (type == DatumType.itrf96) {
      // ITRF96 / GRS80
      projStr = '+proj=tmerc +lat_0=0 +lon_0=$centralMeridian +k=1 +x_0=500000 +y_0=0 +ellps=GRS80 +units=m +no_defs';
    }

    if (projStr.isNotEmpty) {
      try {
        final proj = Projection.parse(projStr);
        systems.add(CoordinateSystem(
          name: name,
          datum: type,
          zone: zone,
          projection: proj,
        ));
      } catch (e) {
        print("Projeksiyon hatası ($name): $e");
      }
    }
  }

  /// Verilen kaynak sistemden WGS84'e dönüşüm yapar
  /// [y] = Easting (Sağa), [x] = Northing (Yukarı)
  PointData transformToWgs84(CoordinateSystem sourceSystem, double y, double x) {
    // Proj4 Dart: Point(x: ..., y: ...) -> X=Easting, Y=Northing
    // Ancak kütüphanenin versiyonuna ve tanımına göre x/y sırası karışabilir.
    // Standart: x=Long/East, y=Lat/North
    final pSrc = Point(x: y, y: x);
    final pRes = sourceSystem.projection.transform(wgs84, pSrc);
    
    // PointData: y=Easting, x=Northing
    // Proj4 Point: x=Easting, y=Northing
    return PointData(id: "WGS", y: pRes.x, x: pRes.y);
  }
}
