/**
 * Mobil Dönüşüm Uygulaması - Simülasyon Testi
 * 
 * Bu script şunları sümile eder:
 * 1. .ncn Dosya İçeriği Ayrıştırma (Smart Parser)
 * 2. Affin Dönüşümü (En Küçük Kareler Yöntemi ile Parametre Hesabı)
 * 3. Dönüşüm Sonucu ve Hata (m0) Hesabı
 */

const fs = require('fs');
const path = require('path');

// --- 1. MATEMATİK KÜTÜPHANESİ (Mini-Lib) ---
class Matrix {
    constructor(rows, cols, data = []) {
        this.rows = rows;
        this.cols = cols;
        this.data = data.length ? data : Array(rows).fill(0).map(() => Array(cols).fill(0));
    }

    static fromList(list) {
        return new Matrix(list.length, list[0].length, list);
    }

    multiply(other) {
        if (this.cols !== other.rows) throw new Error("Boyut uyuşmazlığı");
        let result = new Matrix(this.rows, other.cols);
        for (let i = 0; i < this.rows; i++) {
            for (let j = 0; j < other.cols; j++) {
                let sum = 0;
                for (let k = 0; k < this.cols; k++) {
                    sum += this.data[i][k] * other.data[k][j];
                }
                result.data[i][j] = sum;
            }
        }
        return result;
    }

    transpose() {
        let result = new Matrix(this.cols, this.rows);
        for (let i = 0; i < this.rows; i++) {
            for (let j = 0; j < this.cols; j++) {
                result.data[j][i] = this.data[i][j];
            }
        }
        return result;
    }

    // Basit Gauss-Jordan Ters Alma (Sadece kare matrisler için)
    inverse() {
        if (this.rows !== this.cols) throw new Error("Kare matris değil");
        let n = this.rows;
        let A = JSON.parse(JSON.stringify(this.data)); // Kopya
        let I = []; // Birim matris

        for (let i = 0; i < n; i++) {
            I[i] = [];
            for (let j = 0; j < n; j++) I[i][j] = (i === j) ? 1 : 0;
        }

        for (let i = 0; i < n; i++) {
            let pivot = A[i][i];

            // Pivot 0 ise basit satır değişimi yap (Basit stabilite)
            if (Math.abs(pivot) < 1e-10) {
                for (let r = i + 1; r < n; r++) {
                    if (Math.abs(A[r][i]) > 1e-10) {
                        [A[i], A[r]] = [A[r], A[i]];
                        [I[i], I[r]] = [I[r], I[i]];
                        pivot = A[i][i];
                        break;
                    }
                }
            }

            for (let j = 0; j < n; j++) { A[i][j] /= pivot; I[i][j] /= pivot; }

            for (let k = 0; k < n; k++) {
                if (k !== i) {
                    let factor = A[k][i];
                    for (let j = 0; j < n; j++) {
                        A[k][j] -= factor * A[i][j];
                        I[k][j] -= factor * I[i][j];
                    }
                }
            }
        }
        return new Matrix(n, n, I);
    }
}

// --- 2. NCN PARSER MANTIĞI ---
function parseNcnLine(line) {
    // Örnek Satır: "P1 500100.00 4000100.00"
    let parts = line.trim().split(/\s+/);
    if (parts.length < 3) return null;

    let id = parts[0];
    let v1 = parseFloat(parts[1]);
    let v2 = parseFloat(parts[2]);

    if (isNaN(v1) || isNaN(v2)) return null;

    // SMART DETECT: Y (Sağa) ve X (Yukarı) tahmini
    // Türkiye'de Y ~ 500.000 (3-7 basamak), X ~ 4.000.000 (7 basamak)
    // Eğer v1 > v2 ise v1 muhtemelen X'tir.
    // Ancak UTM/ED50'de X (Kuzey) genelde Y (Sağa)'dan büyüktür (4milyon vs 500bin)

    let y, x;
    if (v1 > 3000000 && v2 < 1000000) {
        // v1 = X (Kuzey), v2 = Y (Sağa) -> Yer değiştir
        y = v2;
        x = v1;
    } else {
        // Standart: v1 = Y, v2 = X
        y = v1;
        x = v2;
    }
    return { id, y, x };
}

// --- 3. SENARYO ÇALIŞTIRMA ---
console.log("=== MOBİL DÖNÜŞÜM UYGULAMASI: SİMÜLASYON TESTİ (Affin Dönüşümü) ===\n");

// 1. Dosya Okuma Simülasyonu
const fakeFileContent = `
# Nokta No   Sağa(Y)        Yukarı(X)
P1           500100.00      4000100.00
P2           500200.00      4000200.00
P3           500150.00      4000300.00
P4           500300.00      4000150.00
`;

console.log("1. NCN Dosyası Okunuyor...");
console.log(fakeFileContent.trim());
console.log("\n-> Ayrıştırılan Koordinatlar (Smart Detect):");

let sourcePoints = [];
fakeFileContent.split('\n').forEach(line => {
    let p = parseNcnLine(line);
    // Yorum satırlarını ve hatalıları atla
    if (p && !p.id.startsWith('#')) {
        sourcePoints.push(p);
        console.log(`   ID: ${p.id}, Y: ${p.y.toFixed(2)}, X: ${p.x.toFixed(2)}`);
    }
});

if (sourcePoints.length < 3) {
    console.error("Yetersiz nokta sayısı!");
    process.exit(1);
}

// 2. Hedef Koordinatlar (Simüle edilmiş ITRF96)
// Affin dönüşümü için: X' = aX + bY + c 
// Basit bir ötelenmiş sistem hayal edelim (+100m, +50m) ve çok az ölçek farkı
// Y' = 1.00005 * Y + 100.00
// X' = 1.00005 * X + 50.00
let targetPoints = sourcePoints.map(p => ({
    id: p.id,
    y: p.y * 1.00005 + 100.00,
    x: p.x * 1.00005 + 50.00
}));

console.log("\n2. Hedef Sistem (ITRF96 - Simüle) Noktaları:");
targetPoints.forEach(p => console.log(`   ID: ${p.id}, Y: ${p.y.toFixed(3)}, X: ${p.x.toFixed(3)}`));

// 3. Affin Dönüşüm Hesabı (Least Squares)
console.log("\n3. Dönüşüm Parametreleri Hesaplanıyor (Least Squares - Affine)...");

// Matrisleri Hazırla
let A_data = [];
let L_data = [];

for (let i = 0; i < sourcePoints.length; i++) {
    let s = sourcePoints[i];
    let t = targetPoints[i];

    // Denklem 1: a*Y + b*X + c = Y'
    A_data.push([s.y, s.x, 1, 0, 0, 0]);
    L_data.push([t.y]);

    // Denklem 2: d*Y + e*X + f = X'
    A_data.push([0, 0, 0, s.y, s.x, 1]);
    L_data.push([t.x]);
}

let A = Matrix.fromList(A_data);
let L = Matrix.fromList(L_data);

// Çözüm: X = (A^T * A)^-1 * A^T * L
let AT = A.transpose();
let ATA = AT.multiply(A);
let INV_ATA = ATA.inverse();
let X_params = INV_ATA.multiply(AT).multiply(L);

let params = X_params.data.map(row => row[0]);
// [a, b, c, d, e, f]
console.log(`\n   >>> HESAPLANAN DÖNÜŞÜM PARAMETRELERİ <<<`);
console.log(`   a (Y Ölçek/Rot): ${params[0].toFixed(6)}`);
console.log(`   b (X Rotasyon) : ${params[1].toFixed(6)}`);
console.log(`   c (Y Öteleme)  : ${params[2].toFixed(3)}`);
console.log(`   d (Y Rotasyon) : ${params[3].toFixed(6)}`);
console.log(`   e (X Ölçek/Rot): ${params[4].toFixed(6)}`);
console.log(`   f (X Öteleme)  : ${params[5].toFixed(3)}`);

console.log("\n4. Sonuç ve m0 Hata Analizi:");
// m0 Hesabı
let vvSum = 0;
for (let i = 0; i < sourcePoints.length; i++) {
    let s = sourcePoints[i];
    let t = targetPoints[i];

    // Hesaplanan
    let calcY = params[0] * s.y + params[1] * s.x + params[2];
    let calcX = params[3] * s.y + params[4] * s.x + params[5];

    let vy = calcY - t.y;
    let vx = calcX - t.x;

    vvSum += (vy * vy + vx * vx);
    console.log(`   ${s.id} -> Kalıntı Hata (vy, vx): ${vy.toFixed(5)}, ${vx.toFixed(5)}`);
}

let u = 6; // parametre sayısı
let n_eq = sourcePoints.length * 2; // denklem sayısı
let m0 = Math.sqrt(vvSum / (n_eq - u));

console.log(`\n   >>> m0 (Karesel Ortalama Hata): ±${m0.toFixed(6)} m <<<`);

if (m0 < 0.1) {
    console.log("   SONUÇ: Dönüşüm BAŞARILI (Hassasiyet yüksek)");
} else {
    console.log("   SONUÇ: Dönüşüm HATALI (Hata sınırı aşıldı)");
}
