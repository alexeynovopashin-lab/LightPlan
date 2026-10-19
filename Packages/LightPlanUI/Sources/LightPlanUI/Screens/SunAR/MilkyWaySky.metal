// Млечный Путь в AR: процедурная картина полосы (шаг 29.8в.14).
//
// Слово Алексея 18.10: «Б я за имитацию млечного пути» — рисуем сами, по формуле, снимок неба не берём.
// Положение расчётное: точка окна → луч в осях «восток, север, вверх» → галактические l, b тем же поворотом,
// что у `Sky.horizontal` и `MilkyWay.equatorial` (матрицы считает `MilkyWayLook` в ядре). Вид — имитация:
//
//   гладкая часть  — `MilkyWayLook.smooth`: гауссов профиль по b шириной `MilkyWay.halfWidth`, яркость к ядру,
//                    выпуклость ядра; эта формула меряется по кадру и обязана совпадать со Swift;
//   текстура       — облака звёзд (плавный шум на 3°) и зерно мелких звёзд (хэш по ячейке l, b — одни и те же
//                    звёзды в каждом кадре и на каждом телефоне, а не случайные);
//   пыль           — тёмные прожилки (Большой разлом, Лебедь–Орёл): шум, вытянутый вдоль полосы, сильнее при
//                    l от 300° до 60° через ноль.
//
// Цвет — тёплый у ядра, холодный по рукавам. Свет складывается с небом кадра (рисующий ставит `.plusLighter`).

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Раскладка чисел, которые передаёт `MilkyWaySkyShader`:
//  0…8   луч: строки «восток, север, вверх», столбцы — множители при x, y, 1;
//  9…17  оси галактики x, y, z в осях «восток, север, вверх»;
//  18,19 сдвиг холста в окне (копия под линзой рисует тот же кадр в маленьком холсте);
//  20    видимость 0…1;  21 части (1 гладкая, 2 текстура, 4 пыль);  22 непрозрачность при яркости 1;
//  23    фокус в точках (размер звезды — не меньше доли точки).

constant float PI_F = 3.14159265358979;

static uint mixHash(uint x) {
    x ^= x >> 16; x *= 0x7feb352dU;
    x ^= x >> 15; x *= 0x846ca68bU;
    x ^= x >> 16;
    return x;
}

// Хэш узла решётки 0…1. По долготе узел заворачивается на `period` — шов l = 0 / 360 не виден.
static float lattice(int i, int j, int period, uint seed) {
    int w = ((i % period) + period) % period;
    uint h = mixHash(uint(w) * 1597334677U ^ mixHash(uint(j + 100000) * 3812015801U + seed));
    return float(h) * (1.0 / 4294967295.0);
}

static float valueNoise(float2 p, int period, uint seed) {
    float2 c = floor(p);
    float2 f = p - c;
    float2 u = f * f * (3.0 - 2.0 * f);
    int i = int(c.x), j = int(c.y);
    float a = lattice(i, j, period, seed), b = lattice(i + 1, j, period, seed);
    float d = lattice(i, j + 1, period, seed), e = lattice(i + 1, j + 1, period, seed);
    return mix(mix(a, b, u.x), mix(d, e, u.x), u.y);
}

// Градиентный шум (Перлин) −1…1: у сеточного шума значений прожилки выходили прямоугольниками по осям l и b.
static float2 gradient(int i, int j, int period, uint seed) {
    float a = 6.2831853 * lattice(i, j, period, seed);
    return float2(cos(a), sin(a));
}

static float gradientNoise(float2 p, int period, uint seed) {
    float2 c = floor(p);
    float2 f = p - c;
    float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    int i = int(c.x), j = int(c.y);
    float a = dot(gradient(i, j, period, seed), f);
    float b = dot(gradient(i + 1, j, period, seed), f - float2(1, 0));
    float d = dot(gradient(i, j + 1, period, seed), f - float2(0, 1));
    float e = dot(gradient(i + 1, j + 1, period, seed), f - float2(1, 1));
    return 1.41 * mix(mix(a, b, u.x), mix(d, e, u.x), u.y);
}

// `octaves` октав; период по долготе удваивается вместе с частотой — шов l = 0 / 360 остаётся невидим.
static float fbm(float2 p, int period, uint seed, int octaves) {
    float sum = 0.0, amp = 0.5, norm = 0.0;
    for (int k = 0; k < octaves; k++) {
        sum += amp * gradientNoise(p, period, seed + uint(k) * 101U);
        norm += amp;
        p *= 2.0;
        period *= 2;
        amp *= 0.5;
    }
    return sum / norm;
}

// Угол от ядра по долготе, 0…180.
static float fromCore(float l) { return abs(fmod(l + 180.0, 360.0) - 180.0); }

// `MilkyWay.halfWidth` и `MilkyWayLook.smooth` — одна формула со Swift.
static float halfWidth(float l) {
    float k = cos(fromCore(l) * PI_F / 360.0);
    return 3.0 + 8.5 * k * k;
}

static float smoothPart(float l, float b) {
    float s = halfWidth(l) / sqrt(2.0 * log(2.0));
    float dl = fromCore(l);
    float band = (0.35 + 0.65 * cos(dl * PI_F / 360.0)) * exp(-b * b / (2.0 * s * s));
    float bulge = 0.75 * exp(-dl * dl / (2.0 * 49.0) - b * b / (2.0 * 25.0));
    return (band + bulge) / 1.75;
}

// Звёзды одной сетки: в ячейке не больше одной звезды, место и яркость — из хэша ячейки.
static float grain(float l, float b, float cell, float density, float radius, uint seed) {
    int period = int(round(360.0 / cell));
    float2 g = float2(l / cell, (b + 90.0) / cell);
    float2 c = floor(g);
    int i = int(c.x), j = int(c.y);
    if (lattice(i, j, period, seed) > density) return 0.0;
    // Звезда во внутренней половине ячейки: радиус не больше четверти ячейки, соседей смотреть не нужно.
    float2 at = float2(0.25 + 0.5 * lattice(i, j, period, seed + 11U), 0.25 + 0.5 * lattice(i, j, period, seed + 23U));
    float2 d = (g - c - at) * cell;
    d.x *= cos(b * PI_F / 180.0);
    float bright = lattice(i, j, period, seed + 37U);
    bright = bright * bright * bright;
    return (0.25 + 0.75 * bright) * exp(-dot(d, d) / (2.0 * radius * radius));
}

[[ stitchable ]] half4 milkyWaySky(float2 position, device const float *m, int count) {
    if (count < 24) return half4(0);
    float2 p = position + float2(m[18], m[19]);
    float3 e = float3(m[0] * p.x + m[1] * p.y + m[2],
                      m[3] * p.x + m[4] * p.y + m[5],
                      m[6] * p.x + m[7] * p.y + m[8]);
    e = normalize(e);
    // Под горизонтом полосы нет; в дымке до 8° (`MilkyWayDust.haze`) она тает.
    float alt = asin(clamp(e.z, -1.0, 1.0)) * 180.0 / PI_F;
    float ft = clamp(alt / 8.0, 0.0, 1.0);
    float fade = ft * ft * (3.0 - 2.0 * ft);
    if (fade <= 0.0) return half4(0);

    float gx = dot(e, float3(m[9], m[10], m[11]));
    float gy = dot(e, float3(m[12], m[13], m[14]));
    float gz = dot(e, float3(m[15], m[16], m[17]));
    float l = atan2(gy, gx) * 180.0 / PI_F;
    if (l < 0.0) l += 360.0;
    float b = atan2(gz, sqrt(gx * gx + gy * gy)) * 180.0 / PI_F;
    if (abs(b) > 40.0) return half4(0);

    int parts = int(m[21]);
    float s = smoothPart(l, b);
    // Вне полосы света меньше 1/255 при любой видимости: зерно и пыль от неё же — считать нечего.
    if (s < 0.003) return half4(0);
    float intensity = (parts & 1) ? s : 0.0;

    if (parts & 2) {
        // Облака звёзд: яркость полосы гуляет на ±30 % пятнами в несколько градусов.
        float cloud = 0.65 * valueNoise(float2(l / 3.0, (b + 90.0) / 3.0), 120, 7U)
                    + 0.35 * valueNoise(float2(l / 1.5, (b + 90.0) / 1.5), 240, 13U);
        intensity *= 0.7 + 0.6 * cloud;
        // Зерно: две сетки — мелкая частая и редкая крупная. Размер звезды не меньше 0,6 точки экрана.
        float pt = 180.0 / (PI_F * max(m[23], 1.0));
        float fine = grain(l, b, 0.15, 0.25 + 0.5 * s, max(0.03, 0.6 * pt), 101U);
        float coarse = grain(l, b, 0.5, 0.18, max(0.05, 0.9 * pt), 211U);
        intensity += (0.45 * fine + 0.8 * coarse) * s;
    }

    // Пыль — только там, где ей есть что гасить (у середины полосы и ближе к ядру): шум дорогой.
    float dlDust = fromCore(l);
    float sdDust = 0.6 * halfWidth(l) / sqrt(2.0 * log(2.0));
    float laneDust = (1.0 - 0.7 * smoothstep(60.0, 90.0, dlDust)) * exp(-b * b / (2.0 * sdDust * sdDust));
    if ((parts & 4) && laneDust > 0.01) {
        // Пыль: шум, вытянутый вдоль полосы вчетверо (10° по долготе на 2,5° по широте), с изгибом — прожилки
        // гнутся, а не идут по линейке. Два вида: несколько длинных прожилок (гребни шума) и тёмные облака.
        float2 q = float2(l / 10.0, (b + 90.0) / 2.5);
        float2 warp = float2(fbm(q * 0.5 + float2(3.1, 0.0), 18, 401U, 3), fbm(q * 0.5 + float2(0.0, 7.7), 18, 409U, 3));
        float2 w = q + 0.7 * warp;
        float ridge = 1.0 - abs(fbm(w, 36, 301U, 3));
        // Прожилки не везде: низкочастотная маска оставляет их кусками, иначе нити сплетаются в сетку.
        // Масштаб по долготе — с целым периодом на 360° (q.x пробегает 36): иначе на l = 0, ровно на ядре, шов.
        float where = smoothstep(0.0, 0.4, fbm(q / 3.0 + float2(5.3, 1.9), 12, 601U, 2));
        float cloud = fbm(w * (2.0 / 3.0) + float2(11.0, 0.0), 24, 503U, 4);
        float dark = 0.6 * smoothstep(0.74, 0.97, ridge) * where + 0.45 * smoothstep(0.18, 0.6, cloud);
        // Сильнее всего у ядра и по Лебедю–Орлу (|Δl| ≤ 60°), к 90° — до трети; поперёк — у середины полосы.
        intensity *= 1.0 - clamp(laneDust * dark, 0.0, 0.75);
    }

    float a = clamp(intensity * m[22] * m[20] * fade, 0.0, 1.0);
    float warm = exp(-fromCore(l) * fromCore(l) / (2.0 * 35.0 * 35.0));
    float3 color = mix(float3(0.72, 0.80, 1.0), float3(1.0, 0.84, 0.64), warm);
    return half4(half3(color * a), half(a));
}
