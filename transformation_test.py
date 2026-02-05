import math
import sys

# --- 1. MATEMATİK KÜTÜPHANESİ (Vanilla Python) ---
class Matrix:
    def __init__(self, rows, cols, data=None):
        self.rows = rows
        self.cols = cols
        if data:
            self.data = data
        else:
            self.data = [[0.0] * cols for _ in range(rows)]

    def transpose(self):
        new_data = [[self.data[r][c] for r in range(self.rows)] for c in range(self.cols)]
        return Matrix(self.cols, self.rows, new_data)

    def multiply(self, other):
        if self.cols != other.rows:
            raise ValueError("Matris boyutları çarpım için uygun değil")
        
        result = Matrix(self.rows, other.cols)
        for i in range(self.rows):
            for j in range(other.cols):
                acc = 0.0
                for k in range(self.cols):
                    acc += self.data[i][k] * other.data[k][j]
                result.data[i][j] = acc
        return result

    def inverse(self):
        # Gauss-Jordan Eliminasyonu
        n = self.rows
        if n != self.cols:
            raise ValueError("Kare matris değil")
        
        # A matrisini kopyala
        A = [row[:] for row in self.data]
        # Birim matris oluştur
        I = [[1.0 if i == j else 0.0 for j in range(n)] for i in range(n)]

        for i in range(n):
            # Pivot seçimi
            pivot = A[i][i]
            if abs(pivot) < 1e-10:
                # Basit pivot değişimi (sonraki satırlara bak)
                for k in range(i+1, n):
                    if abs(A[k][i]) > 1e-10:
                        A[i], A[k] = A[k], A[i]
                        I[i], I[k] = I[k], I[i]
                        pivot = A[i][i]
                        break
            
            if abs(pivot) < 1e-10:
                raise ValueError("Matris Tekil (Singular), tersi alınamaz")

            # Pivot satırını normalize et
            for j in range(n):
                A[i][j] /= pivot
                I[i][j] /= pivot

            # Diğer satırları sıfırla
            for k in range(n):
                if k != i:
                    factor = A[k][i]
                    for j in range(n):
                        A[k][j] -= factor * A[i][j]
                        I[k][j] -= factor * I[i][j]
        
        return Matrix(n, n, I)

    def __str__(self):
        return '\n'.join(['\t'.join([f"{x:.4f}" for x in row]) for row in self.data])

# --- 2. NCN PARSER MANTIĞI ---
def parse_ncn_line(line):
    parts = line.strip().split()
    if len(parts) < 3:
        return None
    
    id = parts[0]
    try:
        v1 = float(parts[1])
        v2 = float(parts[2])
    except ValueError:
        return None

    # SMART DETECT: Y ve X tahmini
    # Türkiye'de Y ~ 500.000, X ~ 4.000.000. X genelde daha büyük
    if v1 > 3000000 and v2 < 1000000:
        y, x = v2, v1
    else:
        y, x = v1, v2
    
    return {'id': id, 'y': y, 'x': x}

# --- 3. SENARYO ÇALIŞTIRMA ---
def main():
    print("=== MOBİL DÖNÜŞÜM UYGULAMASI: PYTHON SİMÜLASYONU (Affin) ===\n")
    
    fake_file_content = """
# Nokta No   Sağa(Y)        Yukarı(X)
P1           500100.00      4000100.00
P2           500200.00      4000200.00
P3           500150.00      4000300.00
P4           500300.00      4000150.00
"""
    print("1. NCN Dosyası Okunuyor...")
    print(fake_file_content.strip())
    print("\n-> Ayrıştırılan Koordinatlar (Smart Detect):")

    source_points = []
    for line in fake_file_content.strip().split('\n'):
        if line.startswith("#"): continue
        p = parse_ncn_line(line)
        if p:
            source_points.append(p)
            print(f"   ID: {p['id']}, Y: {p['y']:.2f}, X: {p['x']:.2f}")

    if len(source_points) < 3:
        print("Hata: Yetersiz nokta sayısı")
        return

    # 2. Hedef Noktalar (Simüle)
    # Affin Dönüşümü: X' = aX + bY + c 
    # Parametreler: ölçek=1.00005, öteleme=(100, 50)
    target_points = []
    print("\n2. Hedef Sistem (ITRF96 - Simüle) Noktaları:")
    for p in source_points:
        scale = 1.00005
        ty = p['y'] * scale + 100.00
        tx = p['x'] * scale + 50.00
        target_points.append({'id': p['id'], 'y': ty, 'x': tx})
        print(f"   ID: {p['id']}, Y: {ty:.3f}, X: {tx:.3f}")

    # 3. Hesaplama (Least Squares)
    print("\n3. Dönüşüm Parametreleri Hesaplanıyor (Least Squares - Affine)...")
    
    A_data = []
    L_data = []

    for s, t in zip(source_points, target_points):
        # Denklem 1: a*Y + b*X + c = Y' -> matris sırası: Y, X, 1, 0, 0, 0
        A_data.append([s['y'], s['x'], 1.0, 0.0, 0.0, 0.0])
        L_data.append([t['y']]) # Y'
        
        # Denklem 2: d*Y + e*X + f = X' -> matris sırası: 0, 0, 0, Y, X, 1
        A_data.append([0.0, 0.0, 0.0, s['y'], s['x'], 1.0])
        L_data.append([t['x']]) # X'

    A = Matrix(len(A_data), 6, A_data)
    L = Matrix(len(L_data), 1, L_data)

    # x = (A^T * A)^-1 * A^T * L
    AT = A.transpose()
    ATA = AT.multiply(A)
    
    try:
        INV_ATA = ATA.inverse()
        X_mat = INV_ATA.multiply(AT).multiply(L)
        params = [row[0] for row in X_mat.data]
        # params: [a, b, c, d, e, f]
        
        print(f"\n   >>> HESAPLANAN DÖNÜŞÜM PARAMETRELERİ <<<")
        print(f"   a (Y Ölçek/Rot): {params[0]:.6f}")
        print(f"   b (X Rotasyon) : {params[1]:.6f}")
        print(f"   c (Y Öteleme)  : {params[2]:.3f}")
        print(f"   d (Y Rotasyon) : {params[3]:.6f}")
        print(f"   e (X Ölçek/Rot): {params[4]:.6f}")
        print(f"   f (X Öteleme)  : {params[5]:.3f}")

        # m0 Hesabı
        print("\n4. Sonuç ve m0 Hata Analizi:")
        vv_sum = 0.0
        for s, t in zip(source_points, target_points):
            calc_y = params[0]*s['y'] + params[1]*s['x'] + params[2]
            calc_x = params[3]*s['y'] + params[4]*s['x'] + params[5]
            
            vy = calc_y - t['y']
            vx = calc_x - t['x']
            
            vv_sum += (vy**2 + vx**2)
            print(f"   {s['id']} -> Kalıntı (vy, vx): {vy:.5f}, {vx:.5f}")

        u = 6
        n_eq = len(source_points) * 2
        m0 = math.sqrt(vv_sum / (n_eq - u))

        print(f"\n   >>> m0 (Karesel Ortalama Hata): ±{m0:.6f} m <<<")
        
        if m0 < 0.1:
            print("   SONUÇ: Dönüşüm BAŞARILI (Hassasiyet yüksek)")
        else:
            print("   SONUÇ: Dönüşüm HATALI (Hata sınırı aşıldı)")

    except ValueError as e:
        print(f"Matris hatası: {e}")

if __name__ == "__main__":
    main()
