// Подставные настенные часы для тестов (аудит часов, 24.10.2026). Загружается в процесс тестов через
// DYLD_INSERT_LIBRARIES: LPFAKE_NOW=<unix-секунды> — «сейчас» в момент загрузки, дальше часы идут как идут.
// Подменяются только настенные часы (CLOCK_REALTIME, gettimeofday, time) — Date(), Date.now, CFAbsoluteTimeGetCurrent и
// триггеры уведомлений видят сдвиг; монотонные часы (тайм-ауты, анимации) не трогаются. Без LPFAKE_NOW ничего не меняет.
#include <stdint.h>
#include <stdlib.h>
#include <sys/time.h>
#include <time.h>

static double shift = 0; // секунды, прибавляемые к настоящим часам

static int lp_gettimeofday(struct timeval *tv, void *tz) {
    int r = gettimeofday(tv, tz);
    if (r == 0 && tv && shift != 0) {
        double t = tv->tv_sec + tv->tv_usec / 1e6 + shift;
        tv->tv_sec = (time_t)t;
        tv->tv_usec = (suseconds_t)((t - (double)tv->tv_sec) * 1e6);
    }
    return r;
}

static int lp_clock_gettime(clockid_t id, struct timespec *ts) {
    int r = clock_gettime(id, ts);
    if (r == 0 && ts && shift != 0 && id == CLOCK_REALTIME) {
        int64_t ns = (int64_t)ts->tv_sec * 1000000000LL + ts->tv_nsec + (int64_t)(shift * 1e9);
        ts->tv_sec = ns / 1000000000LL;
        ts->tv_nsec = ns % 1000000000LL;
    }
    return r;
}

static uint64_t lp_clock_gettime_nsec_np(clockid_t id) {
    uint64_t v = clock_gettime_nsec_np(id);
    if (shift != 0 && id == CLOCK_REALTIME) v += (int64_t)(shift * 1e9);
    return v;
}

static time_t lp_time(time_t *out) {
    time_t t = time(NULL) + (time_t)shift;
    if (out) *out = t;
    return t;
}

// CFAbsoluteTimeGetCurrent сам зовёт эти функции — его подменять не нужно (подмена дала бы двойной сдвиг, замер 24.10).
__attribute__((used)) static struct { const void *rep; const void *orig; } interposers[]
    __attribute__((section("__DATA,__interpose"))) = {
    { (const void *)lp_gettimeofday, (const void *)gettimeofday },
    { (const void *)lp_clock_gettime, (const void *)clock_gettime },
    { (const void *)lp_clock_gettime_nsec_np, (const void *)clock_gettime_nsec_np },
    { (const void *)lp_time, (const void *)time },
};

__attribute__((constructor)) static void lp_fake_init(void) {
    const char *s = getenv("LPFAKE_NOW");
    if (!s) return;
    struct timeval tv;
    gettimeofday(&tv, NULL);
    shift = atof(s) - (tv.tv_sec + tv.tv_usec / 1e6);
}
