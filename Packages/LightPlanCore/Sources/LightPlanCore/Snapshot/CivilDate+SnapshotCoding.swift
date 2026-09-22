import Foundation

/// Строка дня в снимке: `saveAll` пишет «ГГГГ-ММ-ДД» (веб `dayText`), но
/// `dayOf` веба и сегодня терпит прежний момент ISO — читаем оба
/// (`docs/17` § 6, «день записи там бывает и строкой, и прежним моментом»).
///
/// Прежний момент читается днём **машины, на которой открыли файл** — тем же
/// приёмом, что и `dayOf` (`new Date(v).getFullYear()` в часах браузера):
/// это осознанно унаследованная особенность старого формата, не общее
/// правило натива («показываем настенное время места» здесь не при чём —
/// момент без места, зона берётся откуда есть, у машины).
extension CivilDate {
    private static let plain = try! NSRegularExpression(pattern: "^(\\d{4})-(\\d{2})-(\\d{2})$")

    /// `nil` — ни «ГГГГ-ММ-ДД», ни ISO-момент не разобрались.
    public init?(snapshotString s: String) {
        let range = NSRange(s.startIndex..., in: s)
        if let m = CivilDate.plain.firstMatch(in: s, range: range), m.numberOfRanges == 4,
           let yr = Range(m.range(at: 1), in: s), let mr = Range(m.range(at: 2), in: s),
           let dr = Range(m.range(at: 3), in: s),
           let y = Int(s[yr]), let mo = Int(s[mr]), let d = Int(s[dr]) {
            self.init(year: y, month: mo, day: d)
            return
        }
        guard let date = SnapshotDate.parse(s) else { return nil }
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let mo = c.month, let d = c.day else { return nil }
        self.init(year: y, month: mo, day: d)
    }

    /// «ГГГГ-ММ-ДД», как пишет веб.
    public var snapshotString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}
