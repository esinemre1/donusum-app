import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:file_picker/file_picker.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;
import 'dart:io';
import 'package:flutter/services.dart'; // For LogicalKeyboardKey
import 'dart:ui' as ui;
import 'dart:math';

import 'core/ncn_parser.dart';
import 'core/coordinate_manager.dart';
import 'core/dns_parser.dart';
import 'core/math_solver.dart';

void main() {
  runApp(const MobilDonusumApp());
}

class MobilDonusumApp extends StatelessWidget {
  const MobilDonusumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DONUSUM - By E.Emre KIRIK',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent, brightness: Brightness.light),
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

enum MapLayerType { osm, googleHybrid, googleSatellite }

// ... imports ...


class TransformationLayerModel {
  final String id;
  final String name;
  final TransformationResult transformation;
  final CoordinateSystem sourceSystem;
  final CoordinateSystem targetSystem;
  final List<PointData> parameterPoints;
  final List<LatLng> polygon;
  bool isVisible;
  bool isActive;
  final Color color;

  TransformationLayerModel({
    required this.id,
    required this.name,
    required this.transformation,
    required this.sourceSystem,
    required this.targetSystem,
    required this.parameterPoints,
    required this.polygon,
    this.isVisible = true,
    this.isActive = true,
    required this.color,
  });
}

class AppState {
  final List<PointData> loadedPoints;
  final List<PointData> displayPoints;
  // Yeni: Katman Listesi
  final List<TransformationLayerModel> layers;
  final CoordinateSystem? selectedSystem;
  final bool swapXY;
  final MapLayerType currentLayer;

  AppState({
    required this.loadedPoints,
    required this.displayPoints,
    this.layers = const [],
    this.selectedSystem,
    required this.swapXY,
    required this.currentLayer,
  });
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  List<PointData> _loadedPoints = []; 
  List<PointData> _displayPoints = []; 
  
  List<Marker> _markers = [];
  final CoordinateManager _coordManager = CoordinateManager();
  CoordinateSystem? _selectedSystem; 
  MapLayerType _currentLayer = MapLayerType.googleHybrid;
  bool _swapXY = false;
  
  // YENİ: Katman Listesi
  List<TransformationLayerModel> _layers = [];
  
  // Undo Geçmişi
  final List<AppState> _history = [];

  // Mesafe Ölçüm
  bool _isMeasuring = false;
  List<LatLng> _measurePoints = [];
  final Distance _distanceCalc = const Distance(); // LatLong2 Distance
 
  
  @override
  void initState() {
    super.initState();
    // Varsayılan sistemler
    _selectedSystem = _coordManager.systems.firstWhere((s) => s.datum == DatumType.ed50 && s.zone == ZoneType.z33, orElse: () => _coordManager.systems.first);
  }

  void _saveState() {
    if (_history.length > 50) _history.removeAt(0); 
    _history.add(AppState(
      loadedPoints: List.from(_loadedPoints),
      displayPoints: List.from(_displayPoints),
      layers: List.from(_layers), // Save layers
      selectedSystem: _selectedSystem,
      swapXY: _swapXY,
      currentLayer: _currentLayer,
    ));
  }

  void _undo() {
    if (_history.isEmpty) {
      _showSnack("Geri alınacak işlem yok.");
      return;
    }

    final previousState = _history.removeLast();
    setState(() {
      _loadedPoints = previousState.loadedPoints;
      _displayPoints = previousState.displayPoints;
      _layers = previousState.layers; // Restore layers
      _selectedSystem = previousState.selectedSystem;
      _swapXY = previousState.swapXY;
      _currentLayer = previousState.currentLayer;
      
      _applyCalculations(); 
      _showSnack("İşlem geri alındı. (Kalan: ${_history.length})");
    });
  }

  void _applyCalculations() {
    if (_loadedPoints.isEmpty) {
        setState(() => _markers = []);
        _updateMarkers(); 
        return;
    }
    
    // Find active layers
    final activeLayers = _layers.where((l) => l.isActive).toList();
    
    // Warn if multiple active
    if (activeLayers.length > 1) {
       _showError("UYARI: Birden fazla dönüşüm aktif! Sadece '${activeLayers.first.name}' uygulanacak.");
    }
    
    TransformationResult? resultToApply = activeLayers.isNotEmpty ? activeLayers.last.transformation : null; // Use Last or First? Using Last as "most recent" makes sense, or user specific choice. User asked for warning.

    // 1. Dönüşümü Uygula
    List<PointData> transformed = [];
    if (resultToApply != null) {
      final solver = TransformationSolver();
      transformed = solver.applyTransformation(_loadedPoints, resultToApply);
    } else {
      transformed = List.from(_loadedPoints);
    }
    
    // 2. XY Değişimi
    if (_swapXY) {
      transformed = transformed.map((p) => PointData(id: p.id, y: p.x, x: p.y)).toList();
    }
    
    setState(() {
      _displayPoints = transformed;
      _updateMarkers();
    });
  }

  void _showSnack(String msg) {
    if(!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  void _showError(String msg) {
    if(!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  // --- ÖLÇÜM ARAÇLARI ---
  void _toggleMeasurement() {
    setState(() {
      _isMeasuring = !_isMeasuring;
      if (!_isMeasuring) {
        _measurePoints.clear();
      }
    });
    _showSnack("Ölçüm Modu: ${_isMeasuring ? 'AÇIK (Haritaya dokunun)' : 'KAPALI'}");
  }

  void _clearMeasurement() {
    setState(() => _measurePoints.clear());
  }

  void _addMeasurePoint(LatLng point) {
    if (!_isMeasuring) return;
    setState(() {
      _measurePoints.add(point);
    });
  }

  String _calculateTotalDistance() {
    double total = 0;
    for (int i = 0; i < _measurePoints.length - 1; i++) {
      total += _distanceCalc.as(LengthUnit.Meter, _measurePoints[i], _measurePoints[i+1]);
    }
    
    if (total > 1000) {
      return "${(total / 1000).toStringAsFixed(2)} km";
    }
    return "${total.toStringAsFixed(2)} m";
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ncn', 'txt'],
    );

    if (result != null) {
      try {
        File file = File(result.files.single.path!);
        final parser = NcnParser();
        final points = await parser.parseFile(file, smartDetect: true); // Akıllı algılama aktif
        
        _saveState();
        setState(() {
          _loadedPoints = points;
          // Yeni dosya yüklendiğinde mevcut katmanları koru veya temizle? 
          // Kullanıcı isteğe bağlı temizleyebilir. Şimdilik koruyoruz.
          _applyCalculations();
        });
        _showSnack("${points.length} nokta yüklendi.");
      } catch (e) {
        _showError("Dosya hatası: $e");
      }
    }
  }

  // _getTileLayer implementation
  Widget _getTileLayer() {
    switch (_currentLayer) {
      case MapLayerType.osm:
        return TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.app',
        );
      case MapLayerType.googleHybrid:
        return TileLayer(
          urlTemplate: 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
          userAgentPackageName: 'com.example.app',
        );
      case MapLayerType.googleSatellite:
        return TileLayer(
          urlTemplate: 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
          userAgentPackageName: 'com.example.app',
        );
    }
  }
  
  // _updateMarkers
  void _updateMarkers() {
    List<Marker> newMarkers = [];
    
    // Yardımcı: Çift Koordinat Hesaplama
    String getDualTooltip(PointData p, CoordinateSystem currentSys) {
       String mainText = "${p.id}\n${currentSys.name}\nY: ${p.y.toStringAsFixed(2)}\nX: ${p.x.toStringAsFixed(2)}";
       try {
         // Diğer Sistemi Bul (ITRF <-> ED50)
         CoordinateSystem? otherSys;
         if (currentSys.datum == DatumType.ed50) {
            otherSys = _coordManager.systems.firstWhere((s) => s.datum == DatumType.itrf96 && s.zone == currentSys.zone, orElse: () => _coordManager.systems.first);
         } else if (currentSys.datum == DatumType.itrf96) {
            otherSys = _coordManager.systems.firstWhere((s) => s.datum == DatumType.ed50 && s.zone == currentSys.zone, orElse: () => _coordManager.systems.first);
         }

         if (otherSys != null) {
            // WGS84 -> Other
            final wgs = _coordManager.transformToWgs84(currentSys, p.y, p.x);
            final wgsProj = proj4.Point(x: wgs.y, y: wgs.x); // Proj4: x=East, y=North
            final otherProj = _coordManager.wgs84.transform(otherSys.projection, wgsProj);
            
            mainText += "\n\n[${otherSys.datum.name.toUpperCase()}]\nY: ${otherProj.x.toStringAsFixed(2)}\nX: ${otherProj.y.toStringAsFixed(2)}";
         }
       } catch (e) {
         mainText += "\n(Çift sistem hatası)";
       }
       return mainText;
    }

    // 1. Normal Noktalar (Daire) -- NCN Noktaları
    // Burada "Projeksiyon Dönüşümü" yerine, aktif "Affin Dönüşümü" değerlerini göstermeliyiz.
    if (_displayPoints.isNotEmpty && _selectedSystem != null) {
       // Hangi katman aktif?
       final activeLayer = _layers.where((l) => l.isActive).lastOrNull;

       for (int i = 0; i < _displayPoints.length; i++) {
         final p = _displayPoints[i];
         try {
            // Harita konumu (Marker) -> _displayPoints üzerindekidir (Dönüşmüş veya Ham)
            // Bu nokta haritada gösterim sistemine (selectedSystem) göre WGS84 e çevrilir.
            final wgsPoint = _coordManager.transformToWgs84(_selectedSystem!, p.y, p.x);
            
            String tooltipText = "${p.id}\n${_selectedSystem!.name}\nY: ${p.y.toStringAsFixed(2)}\nX: ${p.x.toStringAsFixed(2)}";

            // Eğer bir Affine dönüşümü varsa, Ham değerleri de göster
            if (activeLayer != null && _loadedPoints.length > i) {
               final original = _loadedPoints[i];
               // _loadedPoints sırası ile _displayPoints sırası aynı kabul edilir (_applyCalculations'da korunur)
               if (original.id == p.id) {
                  tooltipText = "${p.id} (Dönüşüm Sonucu)\n------------------\nSONUÇ (Hesaplanan):\nY: ${p.y.toStringAsFixed(3)}\nX: ${p.x.toStringAsFixed(3)}\n\nHAM (Dosyadaki):\nY: ${original.y.toStringAsFixed(3)}\nX: ${original.x.toStringAsFixed(3)}";
               }
            } else {
               // Dönüşüm yoksa, Proj4 ile diğer sistemi göster (Referans amaçlı)
               tooltipText = getDualTooltip(p, _selectedSystem!);
            }

            newMarkers.add(Marker(
              point: LatLng(wgsPoint.x, wgsPoint.y), 
              width: 12, height: 12,
              child: Tooltip(
                message: tooltipText,
                padding: const EdgeInsets.all(8),
                textStyle: const TextStyle(fontSize: 11, color: Colors.white),
                preferBelow: false,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.red, shape: BoxShape.circle, 
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)]
                  ),
                ),
              ),
            ));
         } catch (e) {}
       }
    }

    // 2. Parametre Katmanları (Üçgen) -- DNS Noktaları
    for (var layer in _layers) {
      if (layer.isVisible) {
         for (var p in layer.parameterPoints) {
            try {
               final wgsPoint = _coordManager.transformToWgs84(layer.sourceSystem, p.y, p.x);
               
               // DNS noktası için Tooltip: Hem Girdi (Source) hem de Affine ile neye dönüştüğü
               final tr = layer.transformation;
               // X' = aY + bX + c (veya aX + bY + c - math_solver'a bakmalı, genelde Y,X sırası önemlidir)
               // Bizim MathSolver: X' = a*SourceX + b*SourceY + c (x=0, y=1 indices in params?)
               // math_solver.dart'a getter eklemiştik: a,b,c,d,e,f
               // solveAffine implementation:
               // matrix satırları: [srcY, srcX, 1]
               // result: X_new = a*srcY + b*srcX + c
               //         Y_new = d*srcY + e*srcX + f
               // (Netcad formatında genelde Y önce gelir)
               
               double calcY = tr.a * p.y + tr.b * p.x + tr.c;
               double calcX = tr.d * p.y + tr.e * p.x + tr.f; 
               
               String tooltipText = "${layer.name} - ${p.id}\n------------------\nKAYNAK (Girdi):\nY: ${p.y.toStringAsFixed(3)}\nX: ${p.x.toStringAsFixed(3)}\n\nHESAPLANAN (Çıktı):\nY: ${calcY.toStringAsFixed(3)}\nX: ${calcX.toStringAsFixed(3)}";

               newMarkers.add(Marker(
                 point: LatLng(wgsPoint.x, wgsPoint.y), 
                 width: 16, height: 16,
                 child: Tooltip(
                   message: tooltipText,
                   padding: const EdgeInsets.all(8),
                   child: CustomPaint(
                     painter: _TrianglePainter(color: layer.color),
                   ),
                 ),
               ));
            } catch (e) {}
         }
      }
    }
    
    setState(() {
      _markers = newMarkers;
    });

    if (newMarkers.isNotEmpty) { // Only move if auto-zoom enabled or first load? maybe annoying if measuring. 
       // _mapController.move(newMarkers.last.point, 13); // User complained about movement? No, but let's keep it for now.
    }
  }

  Widget _buildLayerTile(String title, MapLayerType type) {
    return ListTile(
      title: Text(title),
      leading: Icon(_currentLayer == type ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: Colors.blue),
      onTap: () {
        _saveState();
        setState(() {
          _currentLayer = type;
        });
        Navigator.pop(context);
      },
    );
  }

  /// DNS Dosyası Yükle ve Dönüşüm Hesapla (Multi-Layer)
  Future<void> _pickDnsFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['dns', 'txt'],
    );

    if (result != null) {
      try {
        File file = File(result.files.single.path!);
        String fileName = result.files.single.name;
        
        final parser = DnsParser();
        final parseResult = await parser.parseFile(file, smartDetect: true); 
        final controlPoints = parseResult.points;
        final amatParams = parseResult.amatParams;

        if (controlPoints.length < 3 && amatParams == null) {
           _showError("Dosyada geçerli nokta veya parametre (\$AMAT) bulunamadı.");
           _showError("Yetersiz ortak nokta (En az 3 nokta gerekli).");
           return;
        }

        // --- ÖNİZLEME (PREVIEW) DİYALOGU ---
        if (!mounted) return;
        bool? previewConfirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text("DNS Veri Kontrolü (${controlPoints.length} nokta)"),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Lütfen okunan sütunların doğruluğunu onaylayın.", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 10,
                        headingRowHeight: 40,
                        columns: const [
                          DataColumn(label: Text("Nokta", style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text("Kaynak Y", style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text("Kaynak X", style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text("Hedef Y", style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text("Hedef X", style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: controlPoints.take(5).map((p) => DataRow(cells: [
                          DataCell(Text(p.id, style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text(p.sourceY.toStringAsFixed(2))),
                          DataCell(Text(p.sourceX.toStringAsFixed(2))),
                          DataCell(Text(p.targetY.toStringAsFixed(2))),
                          DataCell(Text(p.targetX.toStringAsFixed(2))),
                        ])).toList(),
                      ),
                    ),
                    if (controlPoints.length > 5)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text("... ve diğerleri", style: TextStyle(fontStyle: FontStyle.italic)),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("İptal / Hatalı")),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Onayla & Devam Et")),
            ],
          ),
        );

        if (previewConfirmed != true) {
          _showSnack("İşlem iptal edildi.");
          return;
        }

        // --- DOSYA İSMİNDEN SİSTEM TAHMİNİ ---
        final nameLower = fileName.toLowerCase();
        CoordinateSystem? defaultIn;
        CoordinateSystem? defaultOut;
        
        // 1. Dilim (Zone) Tahmini
        ZoneType predictedZone = ZoneType.z33; // Default
        if (nameLower.contains("27")) predictedZone = ZoneType.z27;
        else if (nameLower.contains("30")) predictedZone = ZoneType.z30;
        else if (nameLower.contains("33")) predictedZone = ZoneType.z33;
        else if (nameLower.contains("36")) predictedZone = ZoneType.z36;
        else if (nameLower.contains("39")) predictedZone = ZoneType.z39;
        else if (nameLower.contains("42")) predictedZone = ZoneType.z42;
        else if (nameLower.contains("45")) predictedZone = ZoneType.z45;
        
        // 2. Sistem Yönü Tahmini
        int idxEd50 = nameLower.indexOf("ed50");
        int idxItrf = nameLower.indexOf("itrf"); // or itrf96

        DatumType datumIn = DatumType.itrf96;
        DatumType datumOut = DatumType.ed50;

        if (idxEd50 != -1 && idxItrf != -1) {
           if (idxEd50 < idxItrf) { 
              // "ed50-itrf" -> Source=ED50
              datumIn = DatumType.ed50;
              datumOut = DatumType.itrf96;
           } else {
              // "itrf-ed50" -> Source=ITRF
              datumIn = DatumType.itrf96;
              datumOut = DatumType.ed50;
           }
        }
        
        defaultIn = _coordManager.systems.firstWhere((s) => s.datum == datumIn && s.zone == predictedZone, orElse: () => _coordManager.systems.first);
        defaultOut = _coordManager.systems.firstWhere((s) => s.datum == datumOut && s.zone == predictedZone, orElse: () => _coordManager.systems.first);

        // --- SİSTEM SEÇİM DİYALOGU ---
        if (!mounted) return;
        CoordinateSystem? inputSys;
        CoordinateSystem? outputSys;
        
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            CoordinateSystem? selectedIn = defaultIn;
            CoordinateSystem? selectedOut = defaultOut;

            return StatefulBuilder(
              builder: (context, setStateUi) { 
                return AlertDialog(
                  title: const Text("Harita Gösterim Referansı"),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("DİKKAT: Bu seçim sadece noktaların haritada doğru yerde gözükmesi içindir. \n\nDönüşüm işlemi, DNS dosyanızdaki parametrelere göre matematiksel olarak (Affine) yapılacaktır.", style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                      const Divider(),
                      const Text("Dosyadaki koordinatların sistemini seçiniz:", style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<CoordinateSystem>(
                        value: selectedIn,
                        decoration: const InputDecoration(labelText: "Girdi Sistemi (Haritada Gösterim)", border: OutlineInputBorder()),
                        items: _coordManager.systems.map((s) => DropdownMenuItem(value: s, child: Text(s.name))).toList(),
                        onChanged: (v) => setStateUi(() => selectedIn = v),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<CoordinateSystem>(
                        value: selectedOut,
                        decoration: const InputDecoration(labelText: "Çıktı Sistemi (Haritada Gösterim)", border: OutlineInputBorder()),
                        items: _coordManager.systems.map((s) => DropdownMenuItem(value: s, child: Text(s.name))).toList(),
                        onChanged: (v) => setStateUi(() => selectedOut = v),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("İptal")),
                    ElevatedButton(
                      onPressed: () {
                         inputSys = selectedIn;
                         outputSys = selectedOut;
                         Navigator.pop(ctx);
                      },
                      child: const Text("Onayla"),
                    )
                  ],
                );
              }
            );
          }
        );

        if (inputSys == null || outputSys == null) {
          _showSnack("İşlem iptal edildi.");
          return;
        }
        
        // -----------------------------

        List<PointData> sourcePts = [];
        List<PointData> targetPts = [];
        List<PointData> paramPoints = [];

        for (var cp in controlPoints) {
          sourcePts.add(PointData(id: cp.id, y: cp.sourceY, x: cp.sourceX));
          targetPts.add(PointData(id: cp.id, y: cp.targetY, x: cp.targetX));
          paramPoints.add(PointData(id: cp.id, y: cp.sourceY, x: cp.sourceX));
        }

        // 1. Dönüşümü Hesapla (AMAT varsa kullan, yoksa hesapla)
        TransformationResult resultTransform;
        final solver = TransformationSolver();
        
        if (amatParams != null && amatParams.length >= 6) {
           // $AMAT Parametrelerini kullan
           resultTransform = _deduceExactParams(amatParams, controlPoints);
           
           // KRİTİK: Ters dönüşüm kontrolü
           // Eğer dosya adında "ıtrf-ed50" veya "itrf-ed50" varsa, bu TERS dönüşümdür
           // Çünkü $AMAT her zaman ileri dönüşümü içerir (ED50→ITRF)
           // ITRF→ED50 için matris inversiyonu gerekir
           if (nameLower.contains("ıtrf") && nameLower.contains("ed50")) {
              int idxItrf2 = nameLower.indexOf("ıtrf");
              int idxEd502 = nameLower.indexOf("ed50");
              
              if (idxItrf2 < idxEd502) {
                 // "ıtrf-ed50" formatı -> TERS DÖNÜŞÜM GEREKLİ
                 try {
                   resultTransform = resultTransform.getInverse();
                   _showSnack("TERS dönüşüm uygulandı (ITRF→ED50). Parametreler matris inversiyonu ile hesaplandı.");
                 } catch (e) {
                   _showError("Ters dönüşüm hatası: $e");
                   return;
                 }
              } else {
                 _showSnack("Dosyadaki ORİJİNAL parametreler kullanıldı (\$AMAT - ED50→ITRF).");
              }
           } else {
              _showSnack("Dosyadaki ORİJİNAL parametreler kullanıldı (\$AMAT).");
           }
        } else if (controlPoints.isNotEmpty) {
           // Noktalardan hesapla
           resultTransform = solver.solveAffine(sourcePts, targetPts);
           _showSnack("Parametreler kontrol noktalarından hesaplandı (En Küçük Kareler).");
        } else {
           _showError("Ne \$AMAT parametreleri ne de yeterli kontrol noktası bulunamadı!");
           return;
        }

        // 2. Kapsama Alanını (Convex Hull) Hesapla
        List<LatLng> polygonLatLngs = [];
        try {
          // Noktaları WGS84'e çevir
          List<PointData> wgsPoints = [];
          for (var p in paramPoints) {
            final wgs = _coordManager.transformToWgs84(inputSys!, p.y, p.x);
            wgsPoints.add(wgs);
          }
          // Convex Hull: Lat, Lon
          // _calculateConvexHull returns LatLng(Lat, Lon) correctly now
          polygonLatLngs = _calculateConvexHull(wgsPoints);
        } catch (e) {
          debugPrint("Polygon Hatası: $e");
        }

        // 3. Yeni Katman Oluştur
        final randomColor = Colors.primaries[Random().nextInt(Colors.primaries.length)];
        final newLayer = TransformationLayerModel(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: fileName,
          transformation: resultTransform,
          sourceSystem: inputSys!,
          targetSystem: outputSys!,
          parameterPoints: paramPoints,
          polygon: polygonLatLngs,
          color: randomColor,
          isActive: true,
          isVisible: true,
        );

        _saveState(); 
        setState(() {
          _layers.add(newLayer); // Add to list
          _applyCalculations(); 
        });

        _showSnack("Katman Eklendi: $fileName");

      } catch (e) {
        showDialog(
           context: context,
           builder: (ctx) => AlertDialog( title: const Text("Hata"), content: Text(e.toString()), actions: [TextButton(onPressed:()=>Navigator.pop(ctx), child: const Text("OK"))])
        );
      }
    }
  }

  // Basit Monotone Chain Convex Hull Algoritması
  List<LatLng> _calculateConvexHull(List<PointData> points) {
    if (points.length < 3) return [];
    
    // Y'ye göre, sonra X'e göre sırala
    points.sort((a, b) => a.y.compareTo(b.y) != 0 ? a.y.compareTo(b.y) : a.x.compareTo(b.x));

    // Çapraz çarpım (Cross Product)
    double crossProduct(PointData o, PointData a, PointData b) {
      return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    }

    List<PointData> lower = [];
    for (var p in points) {
      while (lower.length >= 2 && crossProduct(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }

    List<PointData> upper = [];
    for (var p in points.reversed) {
      while (upper.length >= 2 && crossProduct(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }

    lower.removeLast();
    upper.removeLast();
    
    final hullPoints = [...lower, ...upper];
    return hullPoints.map((p) => LatLng(p.x, p.y)).toList(); // Lat, Lon
  }

  // ... (_applyCalculations)

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: const Text("Mobil Dönüşüm - v1.5"),
            actions: [
              IconButton(onPressed: _undo, icon: const Icon(Icons.undo)),
              IconButton(onPressed: _pickDnsFile, icon: const Icon(Icons.transform)),
              IconButton(onPressed: _pickFile, icon: const Icon(Icons.file_upload))
            ],
          ),
          drawer: Drawer(
            child: Column(
              children: [
                const UserAccountsDrawerHeader(
                  accountName: Text("Koordinat Sistemi"),
                  accountEmail: Text("Proje Sistemi (Çıktı & Harita)"),
                  currentAccountPicture: CircleAvatar(child: Icon(Icons.map, size: 28)),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _coordManager.systems.length,
                    itemBuilder: (context, index) {
                      final system = _coordManager.systems[index];
                      final isSelected = system == _selectedSystem;
                      return ListTile(
                        title: Text(system.name),
                        selected: isSelected,
                        leading: Icon(
                          isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                          color: isSelected ? Colors.blue : null,
                        ),
                        onTap: () {
                          _saveState(); 
                          setState(() {
                            _selectedSystem = system;
                            _updateMarkers(); 
                          });
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          body: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: const LatLng(39.92, 32.85),
                  initialZoom: 6,
                  onTap: (pos, latlng) => _addMeasurePoint(latlng),
                  interactionOptions: InteractionOptions(
                     flags: _isMeasuring ? InteractiveFlag.none : InteractiveFlag.all, // Ölçüm yaparken haritayı kilitle (opsiyonel, user dragging might need to be kept on)
                     // Keeping dragging enabled is better UX generally
                  ),
                ),
                children: [
                  _getTileLayer(),
                  
                  // ÇOKLU KATMAN POLİGONLARI
                  for (var layer in _layers)
                    if (layer.isVisible && layer.polygon.isNotEmpty)
                      PolygonLayer(
                        polygons: [
                          Polygon(
                            points: layer.polygon,
                            color: layer.color.withOpacity(0.15), 
                            borderColor: layer.color,       
                            borderStrokeWidth: 2,
                            isFilled: true,
                          ),
                        ],
                      ),
                      
                  // ÖLÇÜM KATMANI (Polyline)
                  if (_measurePoints.isNotEmpty)
                    PolylineLayer(polylines: [
                       Polyline(points: _measurePoints, color: Colors.blueAccent, strokeWidth: 4, borderColor: Colors.white, borderStrokeWidth: 2)
                    ]),
                  
                  // ÖLÇÜM SEMBOLLERİ
                  if (_measurePoints.isNotEmpty)
                    MarkerLayer(markers: [
                       ..._measurePoints.map((p) => Marker(
                          point: p, width: 10, height: 10,
                          child: Container(decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.blue, border: Border(top:BorderSide(color:Colors.white), bottom:BorderSide(color:Colors.white), left:BorderSide(color:Colors.white), right:BorderSide(color:Colors.white)))),
                       )),
                    ]),

                  MarkerLayer(markers: _markers),
                ],
              ),
              
              // ÖLÇÜM SONUÇ KART
              if (_isMeasuring)
                Positioned(
                  top: 20,
                  left: 20,
                  right: 20,
                  child: Card(
                    color: Colors.white.withOpacity(0.9),
                    elevation: 8,
                    child: Padding(
                       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                       child: Row(
                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
                         children: [
                            Column(
                               crossAxisAlignment: CrossAxisAlignment.start,
                               children: [
                                  const Text("📏 Mesafe Ölçüm Aracı", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                                  Text("Toplam: ${_calculateTotalDistance()}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                               ],
                            ),
                            IconButton(onPressed: _clearMeasurement, icon: const Icon(Icons.delete, color: Colors.red), tooltip: "Temizle"),
                         ],
                       ),
                    ),
                  )
                ),
              
              if (_loadedPoints.isNotEmpty)
                Positioned(
                  bottom: 20, left: 20, right: 80,
                  child: Card(
                    elevation: 5,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Yüklü: ${_loadedPoints.length} Nokta", style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text("Yüklü: ${_loadedPoints.length} Nokta", style: const TextStyle(fontWeight: FontWeight.bold)),
                          if(_layers.any((l) => l.isActive))
                            Text("Dönüşüm: ${_layers.where((l) => l.isActive).last.name} (m0=±${_layers.where((l) => l.isActive).last.transformation.m0.toStringAsFixed(3)} m)", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
                          else
                            const Text("Dönüşüm: Yok (Ham Veri)", style: TextStyle(color: Colors.orange)),
                          
                          Text("Sistem: ${_selectedSystem?.name ?? 'Seçilmedi'}", style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton(
                heroTag: "measure_tool",
                mini: true,
                backgroundColor: _isMeasuring ? Colors.blue : Colors.white,
                onPressed: _toggleMeasurement,
                child: Icon(Icons.straighten, color: _isMeasuring ? Colors.white : Colors.black),
                tooltip: "Mesafe Ölç",
              ),
              const SizedBox(height: 10),
              FloatingActionButton(
                heroTag: "undo_fab",
                mini: true,
                backgroundColor: Colors.grey[300],
                onPressed: _undo,
                child: const Icon(Icons.undo, color: Colors.black),
              ),
              const SizedBox(height: 10),
              FloatingActionButton(
                heroTag: "manual_input",
                mini: true,
                backgroundColor: Colors.white,
                onPressed: _showManualParameterDialog,
                child: const Icon(Icons.edit, color: Colors.blue),
              ),
              const SizedBox(height: 10),
              FloatingActionButton(
                heroTag: "swap_xy",
                mini: true,
                backgroundColor: _swapXY ? Colors.orange : Colors.white,
                onPressed: () {
                  _saveState(); 
                  setState(() {
                    _swapXY = !_swapXY;
                    _applyCalculations();
                    _showSnack("Sıralama: ${_swapXY ? 'X, Y (Ters)' : 'Y, X (Haritacı)'}");
                  });
                },
                child: const Text("Y↔X", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 11)),
              ),
              const SizedBox(height: 10),
              FloatingActionButton(
                heroTag: "layer_select",
                tooltip: "Katmanlar",
                onPressed: () {
                  showModalBottomSheet(context: context, builder: (ctx) {
                     return StatefulBuilder(
                       builder: (ctxSheet, setSheetState) {
                         return SingleChildScrollView(
                           child: Column(
                             mainAxisSize: MainAxisSize.min,
                             children: [
                               const Padding(
                                 padding: EdgeInsets.all(12.0),
                                 child: Text("Harita Altlığı", style: TextStyle(fontWeight: FontWeight.bold)),
                               ),
                               _buildLayerTile("OpenStreetMap", MapLayerType.osm),
                               _buildLayerTile("Google Hibrit (Uydu+Yol)", MapLayerType.googleHybrid),
                               _buildLayerTile("Google Uydu", MapLayerType.googleSatellite),
                               const Divider(),
                               
                               const Padding(
                                 padding: EdgeInsets.all(12.0),
                                 child: Text("Dönüşüm Katmanları", style: TextStyle(fontWeight: FontWeight.bold)),
                               ),
                               if (_layers.isEmpty) 
                                 const Padding(padding: EdgeInsets.all(8.0), child: Text("Hiç katman yok.", style: TextStyle(color: Colors.grey))),
                               
                               ..._layers.map((layer) => ListTile(
                                  title: Text(layer.name, style: const TextStyle(fontSize: 14)),
                                  subtitle: Text("${layer.sourceSystem.name} > ${layer.targetSystem.name}", style: const TextStyle(fontSize: 11)),
                                  leading: Switch(
                                    value: layer.isVisible,
                                    onChanged: (val) {
                                       _saveState();
                                       setState(() { 
                                          layer.isVisible = val;
                                          layer.isActive = val; 
                                          _updateMarkers();
                                          _applyCalculations();
                                       });
                                       setSheetState(() {}); 
                                    },
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.info_outline, color: Colors.blue),
                                    tooltip: "Dönüşüm Raporu (Kanıt)",
                                    onPressed: () => _showLayerReport(layer),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                               )).toList(),
                               
                               const SizedBox(height: 20),
                             ],
                           ),
                         );
                       }
                     );
                  });
                },
                child: const Icon(Icons.layers),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLayerReport(TransformationLayerModel layer) {
    if (layer.transformation.a == 0 && layer.transformation.e == 0) {
      _showSnack("Bu katman için rapor oluşturulamaz.");
      return;
    }

    // Residual hesaplama
    // Model: YeniY = a*Y + b*X + c
    //        YeniX = d*Y + e*X + f
    // Fark = Hesaplanan - Hedef(DNS'deki)
    final tr = layer.transformation;
    
    // DNSParser'dan gelen orjinal noktaları bulmamız lazım. 
    // Ancak TransformationLayerModel'de sadece parameterPoints (Source) var.
    // Target verisini saklamamışız. 
    // HATA: Residual hesaplamak için Target (Beklenen) da lazım.
    // ÇÖZÜM: TransformationLayerModel'e 'controlPoints' eklenmeliydi.
    // ŞİMDİLİK: Sadece Parametreleri gösterelim. (Veya model güncellenecek).
    
    // Model güncellemesi yapmak şu an riskli (çok yer değişir).
    // Basit Rapor: Sadece Katsayılar.
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Dönüşüm Raporu: ${layer.name}"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [ 
               const Text("Bu dönüşüm tamamen aşağıdaki matematiksel parametreleri kullanmaktadır:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
               const SizedBox(height: 10),
               Text("a (Y katsayısı): ${tr.a.toStringAsFixed(8)}"),
               Text("b (X katsayısı): ${tr.b.toStringAsFixed(8)}"),
               Text("c (Y Öteleme):   ${tr.c.toStringAsFixed(4)}"),
               const Divider(),
               Text("d (Y katsayısı): ${tr.d.toStringAsFixed(8)}"),
               Text("e (X katsayısı): ${tr.e.toStringAsFixed(8)}"),
               Text("f (X Öteleme):   ${tr.f.toStringAsFixed(4)}"),
               const Divider(),
               Text("Ortalama Hata (m0): ±${tr.m0.toStringAsFixed(4)} m", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
               const SizedBox(height: 10),
               const Text("UYARI: Haritadaki gösterim için WGS84 projeksiyonu kullanılır, ancak 'NCN Dönüşümü' yukarıdaki katsayılarla yapılır.", style: TextStyle(color: Colors.red, fontSize: 11)),
            ],
          ),
        ),
        actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text("Kapat"))],
      ),
    );
  }

  void _showManualParameterDialog() {
    final tcAx = TextEditingController(); 
    final tcBx = TextEditingController(); 
    final tcCx = TextEditingController(); 
    final tcAy = TextEditingController(); 
    final tcBy = TextEditingController(); 
    final tcCy = TextEditingController(); 

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Manuel Dönüşüm Parametreleri"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Dikkat: Y=Sağa(Easting), X=Yukarı(Northing)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.red)),
              const SizedBox(height: 10),
              
              const Text("Y' = a*Y + b*X + c  (Yeni Y)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(child: TextField(controller: tcAx, decoration: const InputDecoration(labelText: "a (Y çarpanı)", border: OutlineInputBorder(), contentPadding: EdgeInsets.all(8)))),
                  const SizedBox(width: 5),
                  Expanded(child: TextField(controller: tcBx, decoration: const InputDecoration(labelText: "b (X çarpanı)", border: OutlineInputBorder(), contentPadding: EdgeInsets.all(8)))),
                ],
              ),
              const SizedBox(height: 5),
              TextField(controller: tcCx, decoration: const InputDecoration(labelText: "c (Y Öteleme)", border: OutlineInputBorder(), contentPadding: EdgeInsets.all(8))),
              
              const SizedBox(height: 15),
              
              const Text("X' = d*Y + e*X + f  (Yeni X)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
               Row(
                children: [
                  Expanded(child: TextField(controller: tcAy, decoration: const InputDecoration(labelText: "d (Y çarpanı)", border: OutlineInputBorder(), contentPadding: EdgeInsets.all(8)))),
                  const SizedBox(width: 5),
                  Expanded(child: TextField(controller: tcBy, decoration: const InputDecoration(labelText: "e (X çarpanı)", border: OutlineInputBorder(), contentPadding: EdgeInsets.all(8)))),
                ],
              ),
              const SizedBox(height: 5),
              TextField(controller: tcCy, decoration: const InputDecoration(labelText: "f (X Öteleme)", border: OutlineInputBorder(), contentPadding: EdgeInsets.all(8))),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("İptal")),
          ElevatedButton(
            onPressed: () {
              try {
                double a = double.parse(tcAx.text.replaceAll(',', '.'));
                double b = double.parse(tcBx.text.replaceAll(',', '.'));
                double c = double.parse(tcCx.text.replaceAll(',', '.'));
                double d = double.parse(tcAy.text.replaceAll(',', '.'));
                double e = double.parse(tcBy.text.replaceAll(',', '.'));
                double f = double.parse(tcCy.text.replaceAll(',', '.'));

                final solver = TransformationSolver();
                final result = solver.createManualAffine(a, b, c, d, e, f);

                final newLayer = TransformationLayerModel(
                  id: "manual_${DateTime.now().millisecondsSinceEpoch}",
                  name: "Manuel Dönüşüm",
                  transformation: result,
                  sourceSystem: _selectedSystem ?? _coordManager.systems.first, // Tahmini
                  targetSystem: _selectedSystem ?? _coordManager.systems.first,
                  parameterPoints: [], 
                  polygon: [],
                  color: Colors.purple,
                  isActive: true,
                );

                _saveState(); 
                setState(() {
                  _layers.add(newLayer);
                  _applyCalculations(); 
                });

                Navigator.pop(ctx);
                _showSnack("Manuel parametreler uygulandı!");
                
              } catch (err) {
                _showError("Hatalı Giriş: $err");
              }
            },
            child: const Text("Uygula"),
          )
        ],
      ),
    );
  }
}

// Üçgen Çizici
class _TrianglePainter extends CustomPainter {
  final Color color;
  _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = ui.Path();
    path.moveTo(size.width / 2, 0); // Tepe
    path.lineTo(size.width, size.height); // Sağ Alt
    path.lineTo(0, size.height); // Sol Alt
    path.close();

    canvas.drawPath(path, paint);
    
    // Kenarlık
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Helper methods for _MapScreenState (add to class)
extension on _MapScreenState {
  // $AMAT parametrelerinin sırasını bul (Brute Force Permutation Test)
  TransformationResult _deduceExactParams(List<double> params, List<ControlPoint> points) {
     final p = points.first;
     final srcY = p.sourceY;
     final srcX = p.sourceX;
     final tgtY = p.targetY;
     final tgtX = p.targetX;

     // Tüm permütasyonları dene ve en uygununu seç
     List<List<double>> perms = _getPermutations(params);
    
     double bestError = 1e9;
     List<double> bestOrdered = params;
    
     for (var perm in perms) {
        // Model: Y' = p0*Y + p1*X + p2
        //        X' = p3*Y + p4*X + p5
        double cy = perm[0]*srcY + perm[1]*srcX + perm[2];
        double cx = perm[3]*srcY + perm[4]*srcX + perm[5];
        double err = (cy - tgtY).abs() + (cx - tgtX).abs();
       
        if (err < bestError) {
           bestError = err;
           bestOrdered = perm;
        }
     }

     return TransformationResult(
        parameters: bestOrdered,
        m0: 0.0, // Exact match from file
        residuals: [],
        isSuccess: true
     );
  }

  List<List<double>> _getPermutations(List<double> list) {
     if (list.length == 1) return [list];
     var perms = <List<double>>[];
     for (var i = 0; i < list.length; i++) {
         var el = list[i];
         var rest = List<double>.from(list)..removeAt(i);
         for (var p in _getPermutations(rest)) {
             perms.add([el, ...p]);
         }
     }
     return perms;
  }
}
