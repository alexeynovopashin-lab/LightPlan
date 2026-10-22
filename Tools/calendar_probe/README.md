# Что календарь iOS разрешает под «только запись» и под полным доступом (шаг 30.1, замер 22.10.2026)

`probe.swift` — приложение на 100 строк без проекта: собирается `swiftc` под симулятор, ставится вручную,
пишет `Documents/probe.txt`. Нужен был один вопрос: можно ли построить зеркало `docs/14` на «только записи»?

```
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
mkdir Probe.app && cp Info.plist Probe.app/      # Info.plist: bundle probe.ek + обе строки NSCalendars…UsageDescription
xcrun swiftc -sdk $SDK -target arm64-apple-ios17.0-simulator -parse-as-library -o Probe.app/probe probe.swift
codesign -s - --force Probe.app
xcrun simctl install <udid> Probe.app && xcrun simctl launch <udid> probe.ek write     # или `full`
```

Системное окно нажимается рукой (симулятор, `control tap`): `simctl privacy grant calendar` даёт только полный доступ.

## Итог (iOS 26.5, симулятор)

| | `requestWriteOnlyAccessToEvents` (статус 4) | `requestFullAccessToEvents` (статус 3) |
|---|---|---|
| `store.sources` | один виртуальный «Account» (`VIRTUAL_APP_SOURCE_UUID`) | настоящие: «Default» (iCloud/локальный), «Other» |
| `calendars(for: .event)` | один виртуальный «Calendar» | все |
| `saveCalendar` (свой календарь «Light Plan») | **ошибка 17: «That account does not allow calendars to be added or removed»** | да |
| `removeCalendar` | ошибка 16 | да |
| `save(event)` | да — в календарь по умолчанию телефона | да |
| `event(withIdentifier:)` после сохранения | **`nil`** | событие |
| `events(matching:)` | **пусто** | события |
| обновить / удалить событие по сохранённому идентификатору | **нельзя** (объект не находится; работает только пока держишь сам `EKEvent` в памяти того же процесса) | да |

Вывод: под «только записью» нет ни своего календаря, ни выбора учётной записи, ни обновления и удаления события.
Зеркало «создать, сдвинуть, убрать» держится только на полном доступе (`NSCalendarsFullAccessUsageDescription`).
Диалог полного доступа тяжелее: он показывает человеку превью его собственных событий.
