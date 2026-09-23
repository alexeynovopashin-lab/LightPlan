// Прозрачное стекло: окно барабана и кольцо ручки ползунка (DECISIONS
// «Прозрачное стекло: окно барабана и кольцо ручки», 23 сентября 2026).
//
// Алексей: «окошко барабана стеклянное, края должны искажать числа которые
// заезжают под край окошка. это по сути кусок стекла, который лежит над
// шкалой с датами». Веб так не умеет — у него статичные блики.
//
// Стекло не размывает: в середине картинка один к одному, дата чёткая. У
// кромки берётся картинка дальше от центра — толстая кромка сжимает в себя
// то, что лежит за ней, и число, заезжающее под край, гнётся. Сила сдвига
// растёт к кромке квадратом: у настоящей скруглённой кромки наклон
// поверхности круче всего у самого края.
//
// Оптика стекла та же, что у веба (`--glass-optic`): насыщенность и яркость
// того, что под стеклом.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Насыщенность и яркость — `saturate()` и `brightness()` CSS, матрица из
// Filter Effects. Цвет слоя умножен на альфу; обе операции линейны по
// цвету и альфу не трогают, поэтому делить на неё не нужно.
static half4 optic(half4 c, float saturation, float brightness) {
    float s = saturation;
    float3x3 m = float3x3(
        float3(0.213 + 0.787 * s, 0.213 - 0.213 * s, 0.213 - 0.213 * s),
        float3(0.715 - 0.715 * s, 0.715 + 0.285 * s, 0.715 - 0.715 * s),
        float3(0.072 - 0.072 * s, 0.072 - 0.072 * s, 0.072 + 0.928 * s));
    float3 rgb = (m * float3(c.rgb)) * brightness;
    return half4(half3(clamp(rgb, 0.0, float(c.a))), c.a);
}

// Окно барабана: прямоугольник со скруглением `radius`, центр `center`,
// половины сторон `halfSize`. Боковые кромки (`sideBand` шириной, сдвиг до
// `sideShift`) — там заезжают числа; верх и низ (`capBand`, `capShift`)
// тоньше и слабее, чтобы дата и знак под окном не гнулись.
[[ stitchable ]] half4 glassSlab(float2 p, SwiftUI::Layer layer,
                                 float2 center, float2 halfSize, float radius,
                                 float sideBand, float sideShift, float capBand, float capShift,
                                 float saturation, float brightness) {
    float2 d = p - center;
    float2 q = abs(d) - (halfSize - radius);
    float inside = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    if (inside >= 0.0) return layer.sample(p);
    float2 s = float2(0.0);
    float ex = halfSize.x - abs(d.x);
    float ey = halfSize.y - abs(d.y);
    if (ex < sideBand) { float t = 1.0 - ex / sideBand; s.x = sign(d.x) * sideShift * t * t; }
    if (ey < capBand) { float t = 1.0 - ey / capBand; s.y = sign(d.y) * capShift * t * t; }
    return optic(layer.sample(p + s), saturation, brightness);
}

// Кольцо ручки: эллипс с полуосями `radii` (ручка сплющивается под
// нажимом), прозрачное кольцо шириной `ring` у края, сдвиг до `shift`.
// Середина — матовое системное стекло, её здесь не трогаем.
[[ stitchable ]] half4 glassRing(float2 p, SwiftUI::Layer layer,
                                 float2 center, float2 radii, float ring, float shift,
                                 float saturation, float brightness) {
    float2 d = p - center;
    float r = length(d / radii);
    float rin = 1.0 - ring / min(radii.x, radii.y);
    if (r >= 1.0 || r <= rin) return layer.sample(p);
    float t = (r - rin) / (1.0 - rin);
    return optic(layer.sample(p + normalize(d) * shift * t * t), saturation, brightness);
}
