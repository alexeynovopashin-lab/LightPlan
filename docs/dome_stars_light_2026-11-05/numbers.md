# Dome in the light theme, 30в.9 (2026-11-05)

Simulator `LP wt-30v-9-dome-stars-light` (iPhone 17 Pro Max model, 3 px per pt), «Астро», Барнаул 23.09.2026, rain forecast from `Fixtures/shots`.
Frames are cut to the dome: `<time>_<theme>_<before|after>.png`. `stars_was_will.png`, `stars_zoom.png`: the options shown to Alexey before he chose white.

Alexey: «звезды должны быть светлыми и никак иначе, даже ценой, что их не будет видно»; «закат пусть просто обесцвечивается, серый градиент из центра и голубые края выглядят неестественно».

## Stars at 23:00 (strongest star, opacity 0.42, read at its computed place)

| theme | before | after |
|---|---|---|
| light | (149,151,156) on (250,248,243), contrast 2.75, darker than the paper | (252,251,248) on (250,248,243), contrast 1.03, lighter than the paper |
| dark | (93,97,104) on (15,14,12), contrast 3.10 | (93,97,104) on (15,14,12), contrast 3.10 |

Dark theme, dome area of the frame, before against after at 23:00, 20:12, 19:56 in «Астро» and 23:00, 19:56 in «Просто»: 0 pixels differ.

## Grey forecast, 19:56, light theme, «Астро»

| place on the dome | before | after |
|---|---|---|
| edge at the horizon | (141,161,185) | (162,168,178) |
| centre at the horizon | (129,138,150) | (165,168,173) |

Worst darkening from any height to any lower one on the dome's centre line, grey forecast, all sun heights −12…+6°: 2.33 times before (computed by the formula), under 1.03 after (test `greyForecastDoesNotDarkenTheLightDomeTowardTheHorizon`).
