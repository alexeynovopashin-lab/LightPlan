# 34.0 — бумаги к выпуску в TestFlight

Справка к итерации 34 (подпись, App Store Connect, TestFlight). Код не менялся: всё ниже — замер по `main`
на коммите `ad4f4b0` (30.10.2026) и предложения. Ссылки `файл:строка` — от корня репозитория `LightPlan`;
`Packages/` в путях опущен там, где путь начинается с имени пакета. Где из кода ответа нет — так и написано:
«из кода не ясно». Всё, что про правила Apple и условия сервисов, — по моим знаниям, а не по коду; такие места
помечены «(правила, не код)». Юридически ничего не проверялось.

Коротко:

- **Системных вопросов о доступе — 5** (геопозиция, камера, календарь, контакты, уведомления). Для четырёх нужна
  строка-объяснение в `Info.plist` — **все четыре есть**, на пяти языках. Отсутствующих ключей, из-за которых
  приложение упадёт, нет.
- **Две строки говорят неправду** и до выпуска их надо поправить: объяснение доступа к Календарю (не упоминает
  «чужие календари») и строка «На наш сервер не уходит ничего — его нет» в «О приложении».
- **Нет файла `PrivacyInfo.xcprivacy`** (манифест конфиденциальности). Это не системный вопрос, но без него
  App Store Connect сборку не примет (правила, не код).
- **Сеть: 10 адресов**, куда приложение ходит само, плюс службы Apple и адреса картинок, которые вставит человек.
  Наружу уходят координаты мест и — по нажатию «Связать с бронью» — номера телефонов участников съёмки.
  Съёмки, клиенты, заметки, документы, фото мудборда, календарь и контакты из телефона не уходят.
- **Маршруты по дорогам на карте OpenStreetMap идут через бесплатные демо-серверы**, чьи условия не допускают
  приложение в магазине. Это главный правовой вопрос выпуска (§ 7, вопрос 1).

---

## 1. Разрешения

### 1.1 Что спрашивает система (окно «Разрешить…»)

| # | Доступ | Ключ `Info.plist` | Где спрашивается (словами приложения) | Строка сейчас |
|---|---|---|---|---|
| 1 | Геопозиция, «при использовании» | `NSLocationWhenInUseUsageDescription` | Шапка «Места» → «Найти меня» (первый запрос точки), слежение за своим местом | **есть**, 5 языков; `Config/iOS.xcconfig:23`, переводы `App-iOS/InfoPlist.xcstrings` |
| 2 | Камера | `NSCameraUsageDescription` | Первый вход в слой AR («где будет солнце» поверх кадра) | **есть**, 5 языков; `Config/iOS.xcconfig:26` |
| 3 | Календарь, полный доступ | `NSCalendarsFullAccessUsageDescription` | Включение «Съёмки в Календаре» и включение чужих календарей «призраками» | **есть**, 5 языков; `Config/iOS.xcconfig:30` — **текст неточен**, см. ниже |
| 4 | Контакты | `NSContactsUsageDescription` | Первое открытие «Клиентов» (если тумблер «Сохранять клиентов в Контакты iPhone» включён) и сам тумблер | **есть**, 5 языков; `Config/iOS.xcconfig:34` |
| 5 | Уведомления | ключа нет и не нужно — текст окна системный | «Напоминать о съёмке», «Прогноз переменился», «Поздравлять», студийный час — при первом включении любого из них | — |

Откуда это видно в коде:

- Геопозиция: `requestWhenInUseAuthorization` — `LightPlanData/Sources/LightPlanData/Location/DeviceLocation.swift:118`;
  «всегда» (`requestAlways…`) приложение не просит нигде (grep — ноль). Слежение — служба значимых смещений
  (`startMonitoringSignificantLocationChanges`, там же :90, :139), точность сотни метров (:71). Компас
  (`startUpdatingHeading`, `Location/Heading.swift:39`, `Motion/DeviceAttitude.swift:105`) отдельного вопроса не
  задаёт.
- Камера: `AVCaptureDevice.requestAccess(for: .video)` — `LightPlanUI/Sources/LightPlanUI/Screens/SunAR/SunARCamera.swift:80`;
  спрашивается, только если задняя камера есть (:77).
- Календарь: `requestFullAccessToEvents` — `LightPlanData/Sources/LightPlanData/Calendar/EventKitCalendarStore.swift:40`;
  вызывается из зеркала съёмок (`Calendar/CalendarMirror.swift:95`) **и** из «призраков» — чужих календарей
  (`LightPlanUI/Sources/LightPlanUI/App/AppModel+Ghosts.swift:149`, шаг 30.5).
- Контакты: `CNContactStore.requestAccess` — `LightPlanData/Sources/LightPlanData/Contacts/CNContactsStore.swift:39`;
  вызовы — `LightPlanUI/Sources/LightPlanUI/App/AppModel+ClientContacts.swift:165` (открыли «Клиенты») и :188 (тумблер).
- Уведомления: `requestAuthorization(options: [.alert, .sound])` —
  `LightPlanData/Sources/LightPlanData/Notify/SystemNotificationCenter.swift:68`; вызовы —
  `AppModel+ShootReminder.swift:38`, `AppModel+WeatherWatch.swift:261`, `AppModel+Greetings.swift:97`,
  `AppModel+StudioAlerts.swift:96` (все в `LightPlanUI/Sources/LightPlanUI/App/`). Уведомления только местные:
  push-сервера нет.

### 1.2 Что не задаёт вопроса, но записано в `Info.plist` (для проверки Apple)

| Что | Ключ | Где | Зачем |
|---|---|---|---|
| Фоновое обновление | `UIBackgroundModes = fetch`, `BGTaskSchedulerPermittedIdentifiers = Novopashin.LightPlan.wx` | `Config/Info-iOS.plist` | «Прогноз переменился» при закрытом приложении (`LightPlanData/.../Notify/WeatherRefreshTask.swift`). Проверяющий Apple может спросить, зачем фон, — ответ: сверка прогноза к ближайшей съёмке, не чаще раза в час. |
| Плашка на экране блокировки | `NSSupportsLiveActivities = YES` | `Config/Info-iOS.plist` | Экран активности, пока идёт съёмка (`LightPlanUI/.../Activity/ActivityHost.swift:52`). Человек может выключить в настройках iPhone; вопроса нет. |
| Своя ссылка `lightplan://` | `CFBundleURLTypes` | `Config/Info-iOS.plist` | Ответ клиента из опросника возвращается в приложение. |
| Общая папка с виджетом | `com.apple.security.application-groups` | `Config/LightPlan-iOS.entitlements`, `Config/LightPlanWidget.entitlements` | Виджет читает то, что сам не посчитает. |

### 1.3 Проверено и не нужно

| API | Почему ключ не нужен | Где |
|---|---|---|
| Фото: `PhotosPicker` (референсы в мудборд) | Системный выбор фото работает вне приложения, доступа к медиатеке не просит. Сохранения в «Фото» в коде нет (`PHPhotoLibrary`, `UIImageWriteToSavedPhotosAlbum` — ноль), а «Поделиться» отдаёт только ссылку и текст (`CardQuest.swift:191`, `SettingsPieces.swift:90`) — поэтому и `NSPhotoLibraryAddUsageDescription` не нужен. Появится «сохранить картинку» — ключ станет обязательным. | `LightPlanUI/.../Screens/Moodboard/MoodboardFolder.swift:24` |
| Выбор человека из Контактов (`CNContactPickerViewController`) | Системный лист, доступа не требует. | `LightPlanUI/.../Screens/Org/ContactPicker.swift:30` |
| Датчики движения (`CMMotionManager`, положение телефона в AR) | Вопрос (`NSMotionUsageDescription`) нужен только для шагомера, высотомера и «активности»; их нет. | `LightPlanData/.../Motion/DeviceAttitude.swift:136` |
| Звук (`AVAudioEngine`, щелчок, затвор, корзина) | Только воспроизведение в режиме `ambient`; микрофон не открывается. | `LightPlanUI/.../App/SoundCenter.swift:126` |
| Слежение за сетью (`NWPathMonitor`) | Не трогает локальную сеть; Bonjour и поиска устройств в коде нет. | `LightPlanData/.../Weather/NetworkReachability.swift` |
| Рекламный идентификатор, ATT | `ATTrackingManager`, `advertisingIdentifier`, `identifierForVendor` — ноль; `NSUserTrackingUsageDescription` не нужен. | grep по `Packages`, `App-iOS`, `LightPlanWidget` |
| Карты Apple, маршрут Apple, поиск адреса (`MapKit`, `MKDirections`, `CLGeocoder`) | Своих вопросов нет; поиск места по геопозиции идёт под тем же разрешением геопозиции. | `LightPlanUI/Sources/LightPlanMapCanvas/RoadRouter.swift:75`, `LightPlanData/.../Location/ReverseGeocoding.swift:49` |

### 1.4 Чего не хватает

1. **Ключей-объяснений — ничего.** Каждому вызову из § 1.1 соответствует ключ в `Config/iOS.xcconfig`, и для
   каждого есть ru, en, es, ja, zh-Hans в `App-iOS/InfoPlist.xcstrings`.
2. **`PrivacyInfo.xcprivacy` нет** (grep по всему репозиторию — ноль файлов). Приложение пользуется «API с
   обязательной причиной» (правила, не код: такие API надо объяснить в манифесте, иначе App Store Connect
   отвергает загрузку с письмом ITMS-91053; распространяется ли это на сборки только для TestFlight — проверить
   первой загрузкой):
   - `UserDefaults` — 56 файлов (например `LightPlanUI/Sources/LightPlanMapCanvas/MapLibreCanvas.swift:123`) →
     категория `NSPrivacyAccessedAPICategoryUserDefaults`, причина `CA92.1` (данные только самого приложения);
   - `ProcessInfo.systemUptime` — 24 места (например `LightPlanUI/.../Timebar/TimebarState.swift:248`) →
     `NSPrivacyAccessedAPICategorySystemBootTime`, причина `35F9.1` (замер промежутков времени внутри приложения);
   - время правки файла — `LightPlanData/.../Store/RefImageStore.swift:32` (свои картинки) и
     `LightPlanUI/.../Screens/Settings/SettingsChapterView.swift:487` (штамп сборки) →
     `NSPrivacyAccessedAPICategoryFileTimestamp`, причина `C617.1` (файлы внутри своего контейнера).
   В тот же файл — `NSPrivacyTracking = false`, `NSPrivacyCollectedDataTypes` по § 2.3. Есть ли манифест внутри
   MapLibre 6.31.0 — из кода не ясно (пакет приходит бинарником).
3. **`ITSAppUsesNonExemptEncryption` не задан** (grep — ноль). Не падение, но без него App Store Connect при каждой
   загрузке спрашивает про шифрование. Приложение шифрует только через HTTPS системы → предлагается
   `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` в `Config/iOS.xcconfig` (правила, не код).

### 1.5 Две строки, которые надо поправить

- **Календарь.** Сейчас: «приложение читает и меняет только свой календарь, чужие события не трогает». С шага 30.5
  приложение по желанию человека **читает события чужих календарей** и показывает их «призраками»
  (`AppModel+Ghosts.swift:1-6`, `:149`). Не меняет — это правда; «читает только свой» — уже нет. Apple отклоняет
  приложения, чьё объяснение не совпадает с тем, что делает код (правила, не код).
- **Геопозиция.** Сейчас: «Точные координаты больше никуда не отправляются» (кроме Open-Meteo, Yandex Cloud, Apple).
  По коду координаты места ещё уходят серверам маршрутов (`RoadServers.swift:57,63,68`) и, крупным квадратом
  5°×5°, атласу засветки (`GlowAtlas.swift:19`). Точка маршрута — не обязательно ваша геопозиция, но строка
  должна быть верна и в худшем случае.

### 1.6 Предлагаемые строки (5 языков)

Камеру и Контакты можно оставить как есть — нынешние тексты верны; ниже они даны в предлагаемой редакции для
единообразия. Календарь и геопозицию — заменить.

**1. Геопозиция — `NSLocationWhenInUseUsageDescription`** (заменить)

- ru: Light Plan берёт вашу геопозицию, чтобы посчитать свет, солнце и погоду там, где вы стоите. Координаты получают только службы погоды (Open-Meteo или наш сервер погоды в Yandex Cloud), засветки неба и маршрутов; название места определяет Apple. Ваши съёмки и клиенты остаются на iPhone.
- en: Light Plan uses your location to work out light, sun and weather where you are. Coordinates go only to the services that compute weather (Open-Meteo or our weather server in Yandex Cloud), sky glow and road routes; Apple looks up the place name. Your shoots and clients stay on your iPhone.
- es: Light Plan usa tu ubicación para calcular la luz, el sol y el tiempo donde estás. Las coordenadas solo llegan a los servicios que calculan el tiempo (Open-Meteo o nuestro servidor meteorológico en Yandex Cloud), la contaminación lumínica y las rutas; Apple busca el nombre del lugar. Tus sesiones y clientes se quedan en tu iPhone.
- ja: Light Plan は、今いる場所の光・太陽・天気を計算するために位置情報を使います。座標は天気（Open-Meteo または Yandex Cloud 上の当アプリの天気サーバー）、光害、ルートを計算するサービスにだけ送られ、地名は Apple が調べます。撮影予定とクライアントの情報は iPhone に残ります。
- zh: Light Plan 使用你的位置来计算你所在之处的光线、太阳和天气。坐标只会发送给计算天气（Open-Meteo 或我们在 Yandex Cloud 上的天气服务器）、光污染和路线的服务；地名由 Apple 查询。你的拍摄安排和客户信息留在 iPhone 上。

**2. Камера — `NSCameraUsageDescription`** (можно оставить нынешнюю)

- ru: Камера нужна для слоя AR: Light Plan рисует путь солнца и Млечный Путь поверх живого кадра. Кадры не сохраняются и никуда не отправляются.
- en: The camera is used for the AR view: Light Plan draws the sun’s path and the Milky Way over the live picture. Frames are not saved and are not sent anywhere.
- es: La cámara se usa para la vista AR: Light Plan dibuja la trayectoria del sol y la Vía Láctea sobre la imagen en vivo. Los fotogramas no se guardan ni se envían a ningún sitio.
- ja: カメラは AR 表示に使います。Light Plan はライブ映像の上に太陽の軌道と天の川を描きます。映像は保存されず、どこにも送信されません。
- zh: 相机用于 AR 视图：Light Plan 在实时画面上绘制太阳轨迹和银河。画面不会被保存，也不会发送到任何地方。

**3. Календарь — `NSCalendarsFullAccessUsageDescription`** (заменить)

- ru: Light Plan ведёт ваши съёмки в отдельном календаре «Light Plan» и обновляет его, когда вы что-то меняете. Если вы включите чужие календари, их события появятся бледными подсказками — только для чтения, приложение их не меняет. Ничего из Календаря никуда не отправляется.
- en: Light Plan keeps your shoots in its own “Light Plan” calendar and updates it when you change something. If you turn on other calendars, their events appear as faint hints — read only, never changed. Nothing from Calendar is sent anywhere.
- es: Light Plan guarda tus sesiones en su propio calendario «Light Plan» y lo actualiza cuando cambias algo. Si activas otros calendarios, sus eventos aparecen como avisos tenues: solo lectura, nunca se modifican. Nada del Calendario se envía a ningún sitio.
- ja: Light Plan は撮影予定を専用の「Light Plan」カレンダーに記録し、変更があると更新します。ほかのカレンダーをオンにすると、その予定は薄い表示で示されます（読み取りのみで、変更はしません）。カレンダーの内容はどこにも送信されません。
- zh: Light Plan 把你的拍摄安排记在专用的“Light Plan”日历中，并在你修改时更新。若你开启其他日历，其中的事件会以浅色提示显示——只读，不会被更改。日历中的任何内容都不会发送到任何地方。

**4. Контакты — `NSContactsUsageDescription`** (можно оставить нынешнюю)

- ru: Light Plan сохраняет ваших клиентов в Контакты, чтобы iPhone показывал, кто звонит. Контакты, которые вы завели сами, приложение не меняет (лишь подсматривает день рождения или мессенджер, если их нет у клиента) и ничего никуда не отправляет.
- en: Light Plan saves your clients to Contacts so your iPhone shows who is calling. It never changes contacts you created yourself (it only reads a birthday or messenger a client is missing) and sends nothing anywhere.
- es: Light Plan guarda a tus clientes en Contactos para que el iPhone muestre quién llama. Nunca modifica los contactos que creaste tú (solo lee un cumpleaños o un mensajero que le falte al cliente) y no envía nada a ningún sitio.
- ja: Light Plan はクライアントを連絡先に保存し、着信時に iPhone が相手を表示できるようにします。ご自身で作成した連絡先は変更しません（クライアントに足りない誕生日やメッセンジャーを読み取るだけです）。何も外部に送信しません。
- zh: Light Plan 会把你的客户保存到通讯录，让 iPhone 显示来电者。它不会更改你自己创建的联系人（只读取客户缺少的生日或通讯账号），也不会向任何地方发送内容。

**5. Уведомления** — ключа нет; системное окно Apple пишет само. Своё пояснение до вопроса уже есть в каждом
месте включения (из кода: вопрос задаётся только после тумблера).

---

## 2. Сеть и данные

### 2.1 Куда приложение ходит само

Метод: grep `https://` по `*.swift`, `*.json`, `*.xcstrings` (без тестов), затем каждый `URLSession`,
`CLGeocoder`, `MKDirections`; сверено со справкой веба `light_plan:Light_Plan/docs/network_reference.md` § 2.
Виджет в сеть не ходит (в `LightPlanWidget/` нет ни одного `URLSession`). Календарь и Контакты в сеть не ходят
(в `Calendar/` и `Contacts/` нет сетевых вызовов).

| # | Адрес | Что делает | Что уносит | Через Yandex Cloud? | Код |
|---|---|---|---|---|---|
| 1 | `api.open-meteo.com` | прогноз по часам на 16 дней | **точные** широта и долгота места (все знаки) | нет — это прямой путь | `LightPlanData/Sources/LightPlanData/Weather/WeatherSource.swift:144-152` |
| 1а | `api.open-meteo.com` (HEAD) | проверка «открывается ли зарубежное» | ничего, кроме самого запроса | нет | `LightPlanData/.../Network/ForeignReachDetector.swift:38,58` |
| 2 | `air-quality-api.open-meteo.com` | дымка и пыль на 5 дней | точные широта и долгота | нет | `WeatherSource.swift:161-167` |
| 3 | `functions.yandexcloud.net/d4ed8…` (наш сервер погоды) | то же, что № 1 и № 2, когда Open-Meteo не открывается или так выбрано в «Сеть» | широта и долгота **с двумя знаками** (~1 км), ключ приложения в заголовке | **да** | `WeatherSource.swift:191-199`, `Weather/WeatherProxyConfig.swift:9` |
| 4 | `functions.yandexcloud.net/d4e9…` (наша читалка) | доска Pinterest и картинка по ссылке, если напрямую не открылась | **ссылка**, которую вставил человек; больше ничего | **да** | `LightPlanData/.../Pinterest/PinterestReader.swift:9`, `ImageLink/ImageLinkReader.swift:212` |
| 5 | `tiles-a…d.basemaps.cartocdn.com` | плитки карты «OpenStreetMap» | номера плиток → видно, **какой район смотрят** | нет | `LightPlanUI/Sources/LightPlanMapCanvas/Resources/style_light.json`, `style_dark.json` |
| 6 | `tiles.basemaps.cartocdn.com` | значки и шрифты подписей карты | ничего личного | нет | те же файлы стиля |
| 7 | `router.project-osrm.org` | дорога машиной между точками | точки маршрута, 5 знаков | нет | `LightPlanUI/Sources/LightPlanMapCanvas/RoadServers.swift:57` |
| 8 | `routing.openstreetmap.de` | дорога машиной и пешком | точки маршрута | нет | `RoadServers.swift:63` |
| 9 | `valhalla1.openstreetmap.de` | дорога пешком | точки маршрута | нет | `RoadServers.swift:68-73` |
| 10 | `djlorenz.github.io` | атлас засветки неба | номер квадрата 5°×5° (≈ область, не точка) | нет | `LightPlanData/.../Glow/GlowAtlas.swift:19` |
| 11 | `tomson-auth.alexeynovopashin.workers.dev` (Cloudflare) | «Связать с бронью» студии | **номера телефонов всех участников съёмки**, дата и часы ячейки, ключ студии; только по нажатию | нет | `LightPlanData/.../Studio/BookingMatch.swift:43-57`, вызов `LightPlanUI/.../App/AppModel+FormTrip.swift:102-121` |
| — | Apple: геокодер, карты, маршрут | имя места, поиск города и адреса; холст «Apple»; дорога на холсте «Apple» | координаты или текст поиска; район карты; точки маршрута | нет | `Location/ReverseGeocoding.swift:49`, `Location/PlaceSearch.swift:35`, `Location/CityLookup.swift:40`, `LightPlanMapCanvas/MapKitCanvas.swift`, `RoadRouter.swift:75` |
| — | любой адрес картинки, который вставит человек | картинка в мудборд напрямую | только сам запрос картинки | нет | `ImageLink/ImageLinkReader.swift:122-133` |

Итого: **10 адресов** (№ 1–11, где № 1а — тот же хост, а № 3 и № 4 — один хост с двумя функциями), плюс службы
Apple и произвольные адреса картинок. Каждый запрос видит IP-адрес телефона — так устроен интернет.

Что делает фон: «Прогноз переменился» при закрытом приложении запрашивает погоду для мест ближайших съёмок
теми же путями № 1–3 (`Notify/WeatherRefreshTask.swift`, `AppModel+WeatherWatch.swift:275`).

Ссылки, которые приложение **не запрашивает, а открывает** по нажатию в Safari или другом приложении: `t.me`
(в том числе канал `t.me/lightplan_app`), `wa.me`, `vk.me`, `ig.me`, Pinterest, Яндекс Музыка, Spotify, Apple Music,
страница опросника `alexeynovopashin-lab.github.io/Light-Plan/quest/wedding.html` (в ссылке только знак записи
из латиницы и цифр, `LightPlanDomain/.../Rules/QuestFlow.swift:7`), `openstreetmap.org/fixthemap`, `tel:`.
Это не сбор данных приложением.

### 2.2 Наши серверы: что они хранят

- **Сервер погоды** (`light_plan:Light_Plan/yandex/lightplanweather/index.js`): держит ответы Open-Meteo в памяти
  до часа (кэш по округлённой точке), в журнал своих строк не пишет. Хранит ли сама платформа Yandex Cloud адреса
  запросов с координатами в журнале вызовов — из кода не ясно.
- **Читалка** (`light_plan:Light_Plan/yandex/lightplanogreader/index.js:339`): пишет в журнал режим, код ответа и
  время в миллисекундах — без ссылки.
- **Шлюз студии** `tomson-auth` — его кода нет ни в одном из двух репозиториев. Пишет ли он номера телефонов
  в журнал или базу — **из кода не ясно**. Алексей, это ваш шлюз (адрес на вашем аккаунте Cloudflare) — нужен
  ваш ответ (§ 7, вопрос 3).
- Ключи серверов в репозиторий не попадают: фаза сборки кладёт их в приложение из файлов на Mac
  (`Tools/weather_key.sh`, `carto_key.sh`, `og_key.sh`). Внутри собранного приложения ключ можно достать — это
  ограничение по дневному потолку, а не секрет (`DAILY_CAP` в функции погоды).

### 2.3 Ответы для App Store Connect → «Конфиденциальность приложения»

Определение Apple (правила, не код): данные «собираются», если уходят с устройства и **вы или ваши партнёры
можете хранить их дольше, чем нужно, чтобы ответить на запрос**. Отслеживание — связывание с чужими данными для
рекламы или передача брокерам.

| Вопрос App Store Connect | Ответ по коду | Основание |
|---|---|---|
| Отслеживание (tracking) | **Нет** | рекламы, аналитики, ATT, рекламного идентификатора нет; единственный сторонний пакет — MapLibre (`LightPlanUI/Package.swift:18`, `Package.resolved`) |
| Аналитика, сбои, диагностика | **Не собираются** | сторонних SDK нет; отзыв уходит системным «Поделиться» туда, куда человек выберет сам (`SettingsPieces.swift:60-100`) |
| Контактная информация пользователя, имя, почта | **Не собираются** | регистрации и учётных записей нет |
| Содержимое (фото, заметки, документы, съёмки, клиенты) | **Не собираются** | хранятся на устройстве; ни один сетевой вызов из § 2.1 их не несёт |
| Календарь, Контакты | **Не собираются** | EventKit и Contacts работают только локально (§ 2.1) |
| **Геопозиция — точная** | **Рекомендую указать**: «Точная геопозиция → Функциональность приложения → Не связана с личностью → Не для отслеживания» | точные координаты уходят Open-Meteo (`WeatherSource.swift:145-146`) и серверам маршрутов (`RoadServers.swift:57-73`); хранят ли эти партнёры их у себя — из кода не ясно, поэтому честнее указать (§ 7, вопрос 2) |
| **Телефоны** (участников съёмки) | **зависит от шлюза студии**: если `tomson-auth` номера не хранит — «не собираются», если хранит — «Контактная информация → Номер телефона → Функциональность → Связана» | `BookingMatch.swift:53`; § 7, вопрос 3 |
| Ссылки Pinterest и картинок | «Не собираются» | читалка не пишет ссылку в журнал (§ 2.2) |

---

## 3. Страница конфиденциальности (черновик)

Совпадает с § 2 слово в слово по смыслу. Если по вопросу 3 шлюз студии номера хранит — пункт про студию
дописать («хранит … дней»).

### Русский

> **Light Plan — конфиденциальность**
>
> Light Plan не требует регистрации, не показывает рекламу и не следит за вами. Ваши съёмки, клиенты, заметки,
> документы, фото для референсов и настройки хранятся только на вашем iPhone. Мы их не получаем.
>
> Чтобы приложение работало, некоторые запросы уходят в интернет:
>
> - **Погода.** Координаты места съёмки уходят в Open-Meteo. Если Open-Meteo недоступен, запрос идёт через наш
>   сервер погоды в Yandex Cloud — туда координаты попадают округлёнными примерно до километра. Сервер
>   хранит готовый прогноз не дольше часа и не знает, кто спросил.
> - **Карта и маршруты.** Карта OpenStreetMap загружается у CARTO — CARTO видит, какой район вы смотрите. Дорогу
>   между точками считают открытые серверы маршрутов OpenStreetMap (OSRM, FOSSGIS); на карте Apple — Apple.
> - **Название места и поиск адреса** — Apple.
> - **Засветка неба** — атлас Дэвида Лоренца; он получает только номер большого квадрата карты.
> - **Картинки по ссылке и доски Pinterest.** Ссылку, которую вы вставили, приложение открывает само или через наш
>   сервер в Yandex Cloud. Сервер ссылку не сохраняет.
> - **Связь со студией.** Только когда вы нажимаете «Связать с бронью», номера телефонов участников съёмки, дата и
>   время уходят студии, чтобы найти вашу бронь.
>
> Календарь и Контакты iPhone приложение использует только на самом телефоне: ничего из них никуда не отправляется.
> Камера нужна для режима AR; кадры не сохраняются и не отправляются.
>
> Каждый сервис видит IP-адрес телефона, как при открытии любого сайта. Их правила — на их сайтах.
>
> Вопросы: Telegram-канал t.me/lightplan_app. Обновлено: <дата>.

### English

> **Light Plan — Privacy**
>
> Light Plan needs no account, shows no ads and does not track you. Your shoots, clients, notes, documents,
> reference photos and settings are stored only on your iPhone. We never receive them.
>
> For the app to work, some requests go to the internet:
>
> - **Weather.** The coordinates of a shoot location go to Open-Meteo. If Open-Meteo is unreachable, the request goes
>   through our weather server in Yandex Cloud, which receives the coordinates rounded to about one kilometre. It
>   keeps the ready forecast for up to an hour and does not know who asked.
> - **Map and routes.** The OpenStreetMap map is loaded from CARTO, which sees the area you are viewing. Road routes
>   between points are computed by open OpenStreetMap routing servers (OSRM, FOSSGIS); on the Apple map, by Apple.
> - **Place names and address search** — Apple.
> - **Sky glow** — David Lorenz’s light-pollution atlas; it receives only the number of a large map square.
> - **Pictures from links and Pinterest boards.** A link you paste is opened by the app itself or through our server
>   in Yandex Cloud. The server does not store the link.
> - **Studio booking.** Only when you tap “Link to booking”, the phone numbers of the shoot’s participants, the date
>   and the hours go to the studio to find your booking.
>
> The app uses your iPhone Calendar and Contacts on the phone only; nothing from them is sent anywhere. The camera
> is used for the AR view; frames are not saved or sent.
>
> Every service sees your phone’s IP address, as with any website. Their own policies are on their websites.
>
> Questions: Telegram channel t.me/lightplan_app. Last updated: <date>.

Строку в приложении `set.privacy` («Съёмки, места и настройки хранятся на устройстве. На наш сервер не уходит
ничего — его нет.», вывод — `SettingsChapterView.swift:378`) надо заменить: серверы есть (§ 2.1, № 3, 4, 11).
Предложение: «Съёмки, клиенты и заметки хранятся только на iPhone. В интернет уходят лишь координаты мест — за
погодой, картой и маршрутом — и, по вашему нажатию, номера для связи со студией. Подробно — на странице
конфиденциальности.» То же неверное «На наш сервер не уходит ничего» есть в `tour.cloud`, но знакомство в нативе
не перенесено (строка `tour.row` приглушена, `SettingsChapterView.swift:375`) — поправить, когда будут переносить.

---

## 4. Правовая информация

Сейчас в «О приложении» строка «Правовая информация» — **приглушённая заглушка без содержимого**
(`SettingsChapterView.swift:377` → `foreign()`, :472). Строки для неё уже переведены (`lg.*` в
`LightPlanUI/Sources/LightPlanUI/Resources/Localizable.xcstrings`), но из Swift не вызываются ни разу. Кредиты,
которые видны сегодня: плашка карты, «fix the map», Gaia (выключена), панорама ESO.

| Что | Где в приложении | Лицензия / условия | Обязательная подпись | Показано сейчас |
|---|---|---|---|---|
| Данные OpenStreetMap (в плитках CARTO и в маршрутах) | карта, маршруты | ODbL 1.0 (правила, не код) | «© участники OpenStreetMap» со ссылкой openstreetmap.org/copyright | на карте «© CARTO · © OpenStreetMap» — `LightPlanUI/.../Screens/Map/MapScreenView.swift:238`, только на холсте OSM; в листе места карты плашки нет (grep `© CARTO` — одно место); слова «участники» и ссылки нет |
| Плитки, значки, шрифты подписей CARTO (Voyager) | карта | условия CARTO Basemaps: бесплатно ограниченно, коммерческое использование — по договору (правила, не код; условия ключа CARTO из кода не ясны) | «© CARTO» | да, `MapScreenView.swift:238` |
| MapLibre Native iOS 6.31.0 | движок карты | BSD 2-Clause (правила, не код) | текст лицензии и копирайт в документации или в «Правовой информации» | нет; логотип и кнопка атрибуции движка скрыты (`MapLibreCanvas.swift:34,36`) — это допустимо, если подпись стоит своя |
| Прогноз Open-Meteo | «Свет», телеметрия, уведомления | данные CC BY 4.0; бесплатный API — только некоммерческое использование, до ~10 000 запросов в день (правила, не код) | «Weather data by Open-Meteo.com» со ссылкой | частично: строка «Источник» — «Open-Meteo · прогноз» (`LightPlanUI/.../Screens/Light/LightTelemetry.swift:344`); видна ли она в режиме «Просто» — из кода не ясно |
| Качество воздуха Open-Meteo (данные CAMS, Copernicus) | дымка и пыль | по моим знаниям — подпись Copernicus Atmosphere Monitoring Service (правила, не код, проверить на странице Air Quality API) | «Contains Copernicus Atmosphere Monitoring Service information» | нет |
| Атлас засветки Дэвида Лоренца (по VIIRS, NOAA) | строка «засветка» | лицензии нет (`license: null`, `light_plan:Light_Plan/SWIFT_MIGRATION_PLAN.md:2464`), автор просит писать ему; письмо — решение 23.09 (`DECISIONS.md:21901` веба). Ответ автора — из кода не ясно | готовая строка `lg.glowTail`: «Дэвид Лоренц · по снимкам VIIRS (NOAA)» | нет (`lg.glowTail` не используется) |
| Яркие звёзды: Yale Bright Star Catalogue 5th ed. (CDS VizieR V/50), имена МАС WGSN (CC BY), русские имена Wikidata (CC0) | AR, небо | свободно при ссылке на источник (`Tools/bright_stars/README.md:31-61`) | «Данные звёзд: Yale Bright Star Catalogue, 5th ed. (Hoffleit & Warren 1991), CDS VizieR; имена звёзд: IAU WGSN» | нет |
| Gaia DR3 (ESA, Gaia DPAC) | слой «Млечный Путь» — **сейчас выключен** (`MilkyWayGaiaRenderer.swift:496`, `useGaia = false`) | **CC BY-NC 3.0 IGO, некоммерческая** (`LightPlanUI/Sources/LightPlanUI/MilkyWayData/README.md:14-24`) | `set.creditGaia` | нет: подпись показывается только при `useGaia` (`SettingsChapterView.swift:380`), **но файлы всё равно едут в приложении** (`LightPlanUI/Package.swift:31`, `.copy("MilkyWayData")`) — § 7, вопрос 4 |
| Панорама Млечного Пути eso0932a, ESO/S. Brunier | слой «Млечный Путь» | CC BY 4.0 (README :26-37) | «ESO/S. Brunier — панорама изменена (обрезка, градиенты)» | **да**: `SettingsChapterView.swift:382` и под слоем в AR (`SunARMilkyWayNotes.swift:16`) |
| Затмения — каталог NASA до 2030 | строка затмения | данные NASA, по моим знаниям свободны; NASA просит подпись «Eclipse Predictions by Fred Espenak, NASA’s GSFC» (правила, не код) | см. слева | нет (`LightPlanCore/.../Eclipse/EclipseTable.swift:25`) |
| Солнце и луна — своя модель по алгоритмам NOAA | всё приложение | алгоритмы общедоступны | не обязательна; строка `lg.sunMoonV` готова | нет |
| Серверы маршрутов: OSRM demo, FOSSGIS OSRM, FOSSGIS Valhalla | дороги на холсте OSM | демо-серверы: тестовое и некоммерческое использование, не для приложений в магазине (комментарий в коде `RoadRouter.swift:44-48`, справка 24а; условия на сайтах — правила, не код) | FOSSGIS: источник и ссылка «fix the map» | «fix the map» — да, `MapScreenView.swift:251-252`; подпись источника маршрута — нет |
| Карты, маршруты и геокодер Apple | холст «Apple» | условия Apple | системный значок «Правовая информация» на самой карте Apple — не скрывать | системный, из кода не скрыт |
| Звуки `click.wav`, `shutter.wav`, `trash.wav` | щелчки, затвор, корзина | `click.wav` побайтно из беты веба (`DECISIONS.md:23795` веба); откуда `shutter.wav` и `trash.wav` — **из кода не ясно** | — | — |
| Значки | весь интерфейс | собраны из `beta/icons.js` веба (`IconLibrary.generated.swift:2`); пометок о стороннем наборе нет — похоже на свои, но из кода не ясно | — | — |
| Шрифты | интерфейс | своих шрифтов в сборке нет (ни одного `.ttf`/`.otf`), интерфейс на системных; подписи карты — шрифты CARTO с их серверов | — | — |
| Telegram-ссылка | «О приложении» → «Обратная связь» → «Наш Telegram» | — | — | **да**, `t.me/lightplan_app`, `SettingsPieces.swift:72,95` |

Ссылки на пожертвования в коде нет (grep `donat|boosty|patreon|…` — ноль); `StoreKit` не подключён — покупок
внутри нет. Это совпадает с планом «бесплатно, без доната в сборках магазина».

Предлагаемый текст страницы «Правовая информация» (ru; en — по строкам `lg.*` и по образцу):

> **Карта** — © участники OpenStreetMap (openstreetmap.org/copyright), © CARTO. Движок карты — MapLibre Native,
> лицензия BSD 2-Clause.
> **Маршруты** — OSRM, FOSSGIS (routing.openstreetmap.de); данные © участники OpenStreetMap. Нашли ошибку на карте —
> openstreetmap.org/fixthemap.
> **Погода** — Open-Meteo.com (CC BY 4.0). Качество воздуха — Copernicus Atmosphere Monitoring Service.
> **Засветка неба** — Дэвид Лоренц, по снимкам VIIRS (NOAA).
> **Солнце и луна** — своя модель по алгоритмам NOAA. **Затмения** — Fred Espenak, NASA GSFC.
> **Звёзды** — Yale Bright Star Catalogue, 5th ed. (Hoffleit & Warren 1991), CDS VizieR; имена — IAU WGSN.
> **Млечный Путь** — ESO/S. Brunier, панорама изменена (обрезка, градиенты), CC BY 4.0.
> **Карта Apple, маршруты и названия мест** — Apple.

---

## 5. Описание для App Store (черновик)

Только то, что есть в `main` сегодня. Режим «Про» в `main` ещё нет (настройки: «переключатель Просто/Астро»,
`LightPlanUI/.../Screens/Settings/SettingsView.swift:7`) — добавить в текст, когда сольют.

### Русский

- **Название:** Light Plan
- **Подзаголовок (23 из 30):** Свет и съёмки фотографа
- **Промо-текст (149 из 170):** Где будет солнце, какой будет свет и что с облаками — на день съёмки и на точное
  место. Календарь съёмок, клиенты и напоминания — в одном приложении.
- **Описание:**

  Light Plan — планировщик для фотографа, который снимает при естественном свете.

  • Свет. Путь солнца и луны на куполе, золотой час, закат, сумерки, высота солнца и длина тени. Ползунок времени
  пересчитывает всё на нужную минуту.
  • Погода к съёмке. Облачность по ярусам — низкие, средние, высокие облака, — ветер, осадки, дымка на 16 дней
  вперёд.
  • Карта. Откуда светит солнце и куда ложится тень в выбранной точке; дорога между точками съёмки.
  • AR. Путь солнца и Млечный Путь поверх кадра камеры.
  • Засветка неба — для ночной съёмки.
  • Съёмки. Календарь на день, неделю, месяц и год; карточка съёмки с местом, временем, клиентом, референсами
  и документами; итоги года по жанрам.
  • Клиенты. Телефоны, мессенджеры, дни рождения; по желанию — в Контакты iPhone и в отдельный календарь
  «Light Plan».
  • Напоминания о съёмке, «прогноз переменился», виджет и плашка на экране блокировки во время съёмки.

  Режимы «Просто» и «Астро». Без регистрации и рекламы, бесплатно. Съёмки и клиенты хранятся на вашем iPhone.

- **Ключевые слова (94 из 100):** золотой час,закат,восход,солнце,луна,фотограф,календарь,клиенты,прогноз,облака,млечный путь,AR

### English

- **Name:** Light Plan
- **Subtitle (23 of 30):** Light, weather & shoots
- **Promotional text (156 of 170):** Where the sun will be, what the light will do and how the clouds look — for your
  shoot day and exact spot. Shoot calendar, clients and reminders in one app.
- **Description:**

  Light Plan is a planner for photographers who work with natural light.

  • Light. The path of the sun and moon on a dome, golden hour, sunset, twilight, sun height and shadow length.
  The time slider recalculates everything for the minute you choose.
  • Weather for the shoot. Cloud cover by layer — low, mid and high — wind, rain and haze, 16 days ahead.
  • Map. Where the light comes from and where shadows fall at the spot you pick; road routes between shoot spots.
  • AR. The sun’s path and the Milky Way over the camera view.
  • Sky glow for night photography.
  • Shoots. Day, week, month and year calendar; a shoot card with place, time, client, references and documents;
  a yearly summary by genre.
  • Clients. Phones, messengers, birthdays; optionally saved to iPhone Contacts and to a separate “Light Plan”
  calendar.
  • Shoot reminders, “forecast changed” alerts, a widget and a Lock Screen banner while you shoot.

  Simple and Astro modes. No account, no ads, free. Your shoots and clients stay on your iPhone.

- **Keywords (93 of 100):** golden hour,sunset,sunrise,sun,moon,photographer,planner,clients,forecast,clouds,milky way,AR

Откуда пункты (чтобы проверить, что всё есть в `main`): купол, ползунок, телеметрия — `Screens/Light/`; ярусы
облаков, 16 дней, дымка — `WeatherSource.swift:130-148,164`; карта и маршрут — `Screens/Map/`, `RoadRouter.swift`;
AR и Млечный Путь — `Screens/SunAR/`; засветка — `Glow/GlowAtlas.swift`; календарь день/неделя/месяц/год и
итоги — `Screens/Planner/` (`PlannerDayView`, `PlannerWeekView`, `PlannerMonthView`, `PlannerYearView`,
`PlannerStatsView`); референсы — `Screens/Moodboard/`; документы — `Screens/Docs/`; клиенты — `Screens/Org/`;
дни рождения — `AppModel+Greetings.swift:1`; напоминания — `AppModel+ShootReminder.swift:1`; «прогноз
переменился» — `AppModel+WeatherWatch.swift:1`; виджет и плашка — `LightPlanWidget/`. Слово «сумерки» — из
пояснения режима «Астро» (`tour.mode.d`); «синего часа» в тексте нет нарочно — его наличия в коде я не проверял.

---

## 6. Что сделать Алексею руками

Это то, что могу сделать только вы: вход под вашим Apple ID, деньги, телефон в руках.

**Apple Developer Program**

- [ ] Вступить в Apple Developer Program (платная, по моим знаниям $99 в год). Сейчас сборка подписывается
  бесплатной командой: комментарии в `Config/Info-iOS.plist` и `WeatherSource.swift:113-114` говорят «бесплатная
  команда», а TestFlight на ней недоступен. Оплата картой из России может не пройти — заранее решите, чем платить.
- [ ] После вступления проверить, что в Xcode у проекта та же команда (`DEVELOPMENT_TEAM` в `Config/Shared.xcconfig`).
  Если номер команды сменится — его поменяет кодовая сессия, не вы.

**App Store Connect**

- [ ] Создать запись приложения: название «Light Plan» (если занято — § 7, вопрос 6), основной язык, идентификатор
  `Novopashin.LightPlan`, артикул (любое слово, например `lightplan`).
- [ ] Категория: «Фото и видео» (вторая — «Погода» или «Производительность»).
- [ ] Возрастной рейтинг: анкета — всё «нет» (по коду нет ничего, что его поднимает).
- [ ] «Конфиденциальность приложения» — заполнить по § 2.3.
- [ ] Ссылка на политику конфиденциальности — по § 7, вопрос 5.
- [ ] Ссылка поддержки — страница с контактом (Telegram-канал или та же страница, что и политика).
- [ ] Copyright: «© 2026 Алексей Новопашин» (или как вы хотите).
- [ ] Для ЕС: статус торговца (DSA). Бесплатное приложение частного лица — «не торговец»; если отметить «торговец»,
  Apple покажет ваш адрес и телефон (правила, не код).
- [ ] Цена: бесплатно; покупок внутри не заводить.
- [ ] Страны: по умолчанию все — решите, нужна ли Россия (App Store там работает, но платёжные вопросы есть).

**TestFlight**

- [ ] Внутреннее тестирование (до 100 человек из вашей команды App Store Connect) — без проверки Apple.
- [ ] Внешнее тестирование (по ссылке, до 10 000) — первая сборка проходит проверку Apple. Нужны: описание бета-версии
  (можно промо-текст из § 5), почта для отзывов, «что проверить».
- [ ] Перед каждой загрузкой номер сборки должен расти (`CURRENT_PROJECT_VERSION = 1` в `Config/Shared.xcconfig`,
  руками) — попросите кодовую сессию поднять.

**Ваш Mac перед сборкой Archive**

- [ ] Файлы ключей на месте: `~/.config/lightplan/weather_key`, `carto_key`, `og_key`. Без них сборка соберётся,
  но тихо останется без сервера погоды, ключа CARTO и Pinterest (`Tools/weather_key.sh:7-12`) — тестировщики из
  России останутся без прогноза.
- [ ] Собирать с идентификатором основного «Light Plan» (`Novopashin.LightPlan`), не слотом: иначе на значке будет «α»
  (`Config/iOS.xcconfig`, `LP_APPICON`) и не включится запись в Контакты.

**Страница конфиденциальности**

- [ ] Выбрать, где она живёт (§ 7, вопрос 5), и выложить текст § 3 (ru + en).

**Снимки экрана — на телефоне**

- [ ] Приложение только для iPhone (`TARGETED_DEVICE_FAMILY = 1`) — снимки iPad не нужны.
- [ ] Нужен набор под самый большой iPhone (6,9″, 1320 × 2868, правила, не код); остальные размеры App Store
  уменьшит сам. 3–10 снимков на язык.
- [ ] Что снять (предложение): купол «Света» на закате, телеметрия с облаками по ярусам, карта с лучом солнца,
  AR с дугой солнца, календарь месяца со съёмками, карточка съёмки, виджет на главном экране.
- [ ] Данные на снимках — выдуманные клиенты, без настоящих телефонов и имён.

**Письма**

- [ ] Ответ Дэвида Лоренца про атлас засветки — есть ли? (§ 7, вопрос 7).
- [ ] Шлюз студии: проверить в Cloudflare, не пишет ли `tomson-auth` номера в журнал (§ 7, вопрос 3).

**Что сделает кодовая сессия по этой справке (не вы, но после вашего «да»)**

- поправить строки Календаря и геопозиции (§ 1.6) и `set.privacy` (§ 3);
- добавить `PrivacyInfo.xcprivacy` и `ITSAppUsesNonExemptEncryption = NO` (§ 1.4);
- наполнить «Правовую информацию» (§ 4);
- сделать с маршрутами и файлами Gaia то, что вы выберете (§ 7, вопросы 1 и 4).

---

## 7. Открытые вопросы

**1. Дороги на карте OpenStreetMap идут через бесплатные демо-серверы, которые не разрешают приложение в магазине.**
В коде прямо написано: «к выпуску нужен свой или платный» (`RoadRouter.swift:44-48`). На карте Apple дорогу
считает Apple — там вопроса нет.

- А. В сборке для TestFlight и App Store дорога строится только на карте Apple; на карте OSM — без дорожной линии,
  с честной подписью. Плюс: ничего не стоит, условия соблюдены, это не новая функция (подходит под заморозку
  с 31.10). Минус: на карте OSM пропадает линия дороги.
- Б. Свой сервер маршрутов в Yandex Cloud (OSRM или Valhalla). Плюс: всё остаётся как сейчас. Минус: деньги и
  уход за сервером; противоречит курсу «своих серверов нет».
- В. Платный сервис маршрутов. Плюс: быстро. Минус: счёт и ключ; бесплатный год перестаёт быть бесплатным для вас.

Мой выбор — **А**: условие демо-серверов нарушать нельзя даже в TestFlight (внешний TestFlight — уже раздача),
а маршрут на карте Apple остаётся.

**2. Указывать ли геопозицию в «Конфиденциальности приложения».**

- А. «Данные не собираются». Плюс: чистая карточка в магазине. Минус: Open-Meteo и серверы маршрутов получают
  точные координаты, и хранят ли они их в журналах, мы не знаем; если хранят — ответ неверен.
- Б. «Точная геопозиция — функциональность — не связана с личностью — не для отслеживания». Плюс: верно при любом
  ответе партнёров; так делают большинство погодных приложений. Минус: в карточке появляется строчка «Геопозиция».

Мой выбор — **Б**. Он честен без проверки чужих журналов.

**3. Шлюз студии `tomson-auth` получает номера телефонов участников съёмки.** Его кода нет в репозиториях.

- А. Вы проверяете в Cloudflare, что шлюз номера не хранит (не пишет в журнал и базу) → в App Store Connect
  «не собираются», на странице конфиденциальности — пункт «Связь со студией» как в § 3. Плюс: честно и просто.
  Минус: нужна ваша проверка.
- Б. Хранит → указываем «Номер телефона — функциональность — связан» и пишем срок хранения. Плюс: честно. Минус:
  заметная строка в карточке ради функции одной студии.
- В. Скрыть «Связать с бронью» в сборке магазина. Плюс: вопроса нет. Минус: ваша студия теряет функцию;
  и это правка кода.

Мой выбор — **А**, если шлюз действительно ничего не хранит; иначе — Б.

**4. Файлы Gaia с некоммерческой лицензией едут в приложении, хотя слой их не рисует** (`useGaia = false`), а
подпись ESA из-за этого не показывается.

- А. Убрать три файла Gaia из сборки. Плюс: нет некоммерческих данных, приложение легче. Минус: правка пакета
  (маленькая); вернуть Gaia — вернуть файлы.
- Б. Оставить файлы и показывать подпись ESA всегда. Плюс: без правки данных. Минус: некоммерческие данные
  в приложении, которое однажды может стать платным.
- В. Оставить как есть. Минус: данные едут без обязательной подписи — нарушение лицензии.

Мой выбор — **А**.

**5. Где разместить страницу конфиденциальности.**

- А. GitHub Pages веб-репозитория (рядом с опросником, `alexeynovopashin-lab.github.io/Light-Plan/privacy.html`).
  Плюс: бесплатно, уже работает. Минус: из России github.io открывается не всегда (для проверки Apple не важно).
- Б. Пост в Telegram-канале. Плюс: ваш канал. Минус: выглядит не как документ, правку трудно отследить.
- В. Свой домен. Плюс: солидно. Минус: деньги и настройка.

Мой выбор — **А**. Правка — коммит в веб-репозиторий; это документ, не код.

**6. Имя «Light Plan» в App Store может быть занято** (из кода не узнать).

- А. «Light Plan». Плюс: совпадает со значком. Минус: может быть занято.
- Б. «Light Plan — планер фотографа» / «Light Plan: Photo Planner». Плюс: почти наверняка свободно, слова
  работают на поиск. Минус: длинное.

Мой выбор — пробовать **А**, при отказе — **Б**. Имя под значком на телефоне остаётся «Light Plan» в любом случае.

**7. Атлас засветки: ответил ли Дэвид Лоренц?** Лицензии у атласа нет.

- А. Ответил «можно» → показываем подпись `lg.glowTail` в «Правовой информации».
- Б. Не ответил → показываем подпись и пишем ещё раз; если откажет — убрать строку «засветка». Плюс: функция
  остаётся. Минус: правовой риск до ответа.
- В. Не ответил → выключить засветку в сборке магазина. Плюс: риска нет. Минус: ночники теряют функцию.

Мой выбор — **Б** для TestFlight, решение для App Store — по ответу.

**8. Open-Meteo бесплатно — только для некоммерческого использования.** Пока приложение бесплатное и без рекламы,
по решению веба условие соблюдено (`DECISIONS.md:23473` веба). Не вопрос сейчас — напоминание: при первой
платной функции нужен платный тариф Open-Meteo, и то же — проверить для CARTO.

**9. Pinterest: читалка открывает публичные доски через наш сервер.** Условия Pinterest запрещают
автоматическое чтение сайта без разрешения (правила, не код).

- А. Оставить. Плюс: функция работает. Минус: риск, что Pinterest закроет доступ; Apple на это обычно не смотрит.
- Б. В сборке магазина оставить только ссылку на доску без чтения пинов. Плюс: риска нет. Минус: мудборд из
  Pinterest придётся собирать руками.

Мой выбор — **А** для TestFlight; вернуться к вопросу, если Pinterest начнёт отказывать.
