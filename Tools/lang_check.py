#!/usr/bin/env python3
"""Translation consistency check for Light Plan native (stdlib only, read-only).

Where the words live (measured, see Tools/lang2xcstrings.js):

  Fixtures/lang.json                  words of the web (beta/lang.js): 1542 keys,
                                      langs ru en en-GB en-US es ja zh, parallel
                                      arrays `t` in the order of `keys`
  Tools/lang_native.json              words only the phone says: {lang: {key: str | [forms]}},
                                      langs ru en es ja zh; a list = word by number forms
                                      (ru 3, en/es 2, ja/zh 1)
  .../Resources/Localizable.xcstrings the String Catalog GENERATED from both (never
                                      hand-edited): web keys + native keys, disjoint.
                                      Plural keys are stored as CLDR variations whose forms
                                      read `%lld` + U+2063 + word.

Checks (category letters follow the task):

  a  keys missing in some language            (catalog, native, en-US delta)
  b  Cyrillic left in a non-Russian value     (whitelist below)
  c  placeholder mismatch against Russian     ({name}, %lld, %@, %d, ${...}, \\(...))
  d  plural / format mismatch                 (forms vs CLDR categories, U+2063 mark,
                                               edge whitespace, line breaks, plural-ness)
  e  empty values
  f  key sets / values that drifted between the three sources

Exit code: 0 clean, 1 findings, 2 a data file could not be read.

Usage:
  python3 Tools/lang_check.py                  report in Markdown on stdout
  python3 Tools/lang_check.py > Tools/lang_check_report.md
  python3 Tools/lang_check.py --root <repo>    another checkout
"""
import argparse
import collections
import json
import os
import re
import sys

# ---------------------------------------------------------------- configuration

CATALOG_REL = "Packages/LightPlanUI/Sources/LightPlanUI/Resources/Localizable.xcstrings"
NATIVE_REL = "Tools/lang_native.json"
WEB_REL = "Fixtures/lang.json"

BASE_LANGS = ["ru", "en", "es", "ja", "zh"]   # full sets
DELTA_LANGS = ["en-US"]                       # overrides of `en` only
MARK = "⁣"                               # between number and word in plural forms

# Plural categories per language, as lang2xcstrings.js writes them.
CATEGORIES = {
    "ru": ["one", "few", "many"],
    "en": ["one", "other"],
    "es": ["one", "other"],
    "ja": ["other"],
    "zh": ["other"],
    "en-US": ["one", "other"],
}
# Languages that decline words by number. ja/zh do not, so a plain string there is fine.
DECLINING = ["ru", "en", "es"]
# CJK text is set without spaces around words and dots: edge whitespace differs from ru by design.
CJK = ["ja", "zh"]

# Cyrillic is allowed in a non-Russian value when the letters belong to a proper name or a
# credit that is not translated. Nothing needs it today (measured: the Milky Way credit
# `ar.mwPano` is translated in every language). Both lists stay for the day it does:
#   KEY_WHITELIST   {key: reason} — the whole key is exempt
#   TERM_WHITELIST  substrings removed from the value before looking for Cyrillic
CYRILLIC_KEY_WHITELIST = {
    # "some.key": "why the Russian name stays in every language",
}
CYRILLIC_TERM_WHITELIST = (
    # "Яндекс",
)
CYRILLIC = re.compile("[Ѐ-ӿԀ-ԯ]")

# Placeholder styles found in the data: `{name}` (Lexicon.t, the web's style) and `%lld`
# (plural forms only). The rest are looked for on purpose: if one ever appears, it is
# compared like the others.
PLACEHOLDER = re.compile(
    r"\$\{[^{}]*\}"                                   # ${expr}
    r"|\\\([^()]*\)"                                  # \(expr)  Swift interpolation
    r"|\{[A-Za-z_][A-Za-z0-9_]*\}"                    # {name}
    r"|%(?:\d+\$)?[-+0#]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?[@dDiuUxXoOfeEgGcCsSp]"  # printf
)

# Differences that were read against the Swift call sites and are intended. They are still
# listed in the report (section "Allowed exceptions"), but do not count as findings and do
# not turn the exit code red. {(category, key, lang): reason}. A new exception needs a reason
# a reader can check; do not add one just to get a green run.
ALLOWED = {
    ("c", "dur.hours", "zh"): "zh writes 小时 itself: Chinese has no plural word to pass as {hourWord}",
    ("c", "dur.overHours", "en"): "no Swift call site uses this key (grep); the web writes the word «hours» out instead of {w}",
    ("c", "dur.overHours", "es"): "no Swift call site uses this key (grep); the web writes the word «horas» out instead of {w}",
    ("c", "dur.overHours", "zh"): "zh writes 小时 itself: Chinese has no plural word to pass as {w}",
    ("c", "rep.payFirst", "zh"): "Swift passes both `n` (number + word) and `k` (bare number); zh needs the bare one before 次",
    ("c", "rep.sum", "zh"): "same: zh takes the bare number `k`",
    ("c", "rep.sumMore", "zh"): "same: zh takes the bare number `k`",
    ("d", "lg.osmTail", "en"): "text fragment glued to the map credit: the space is part of the English wording",
    ("d", "lg.osmTail", "es"): "text fragment glued to the map credit: the space is part of the Spanish wording",
    ("d", "rep.week2", "zh"): "每两周: zh writes the number 2 as 两",
}

# Notes on findings that are NOT fixed by editing a translation, or that a person has to decide.
# Printed in the report only while the key still has a finding. {key: text}
REVIEW_NOTES = {
    "light.waitedSunset": (
        "Swift (`AppModel+CardLight.swift`, `cardSays`, case `.badSky`) passes only `cond` and `cloud`. "
        "`Lexicon.substitute` leaves an unknown `{name}` as written, so on the en/es/ja/zh card the text starts "
        "with a literal «{name}». ru has no `{name}`; the web's substitution list for this key includes `name`. "
        "Two fixes, and the data cannot say which one is meant: pass `\"name\": name(p)` in Swift (the point "
        "is already known in `.badSky(let p, _)`), or drop `{name}` from the four texts to match ru. "
        "No fix proposed in `lang_check_proposed_fixes.json`."),
    "week.wx": (
        "zh only. Swift (`PlannerWeekView.swift`) passes `cloud` and `wind`, so the zh week row would show a "
        "literal «{cond}». ru, en, es and ja have no `{cond}`. A fix is in `lang_check_proposed_fixes.json` "
        "(drop `{cond}·`). The key comes from the web's `lang.js`, and `lang_native.json` cannot carry a key the "
        "web has (`lang2xcstrings.js` refuses it), so the word is changed on the web side and brought in by `make lang`."),
}

CATEGORY_TITLES = collections.OrderedDict([
    ("a", "Keys missing in some language"),
    ("b", "Cyrillic left in a non-Russian value"),
    ("c", "Placeholder mismatch against Russian"),
    ("d", "Plural / format mismatch"),
    ("e", "Empty values"),
    ("f", "Key or value drift between lang_native.json, Fixtures/lang.json and the catalog"),
])


# ---------------------------------------------------------------------- loading

class DataError(Exception):
    pass


def load_json(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError) as err:
        raise DataError("%s: %s" % (path, err))


class Entry(object):
    """One language of one key. `forms` is {category: text}; a plain string is {'-': text}."""
    __slots__ = ("plural", "forms", "marked")

    def __init__(self, plural, forms, marked=True):
        self.plural = plural
        self.forms = forms
        self.marked = marked      # every plural form had `%lld` + MARK in front

    def texts(self):
        return [self.forms[c] for c in sorted(self.forms)]


def read_catalog(path):
    raw = load_json(path)
    out = {}
    for key, rec in raw.get("strings", {}).items():
        langs = {}
        for lang, loc in rec.get("localizations", {}).items():
            if "stringUnit" in loc:
                langs[lang] = Entry(False, {"-": loc["stringUnit"].get("value", "")})
            elif "variations" in loc:
                forms, marked = {}, True
                for cat, sub in loc["variations"].get("plural", {}).items():
                    value = sub.get("stringUnit", {}).get("value", "")
                    head = "%lld" + MARK
                    if value.startswith(head):
                        value = value[len(head):]
                    else:
                        marked = False
                    forms[cat] = value
                langs[lang] = Entry(True, forms, marked)
        out[key] = langs
    return out, raw.get("sourceLanguage")


def read_native(path):
    raw = load_json(path)
    out = {}
    for lang, words in raw.items():
        for key, value in words.items():
            if isinstance(value, list):
                langs = out.setdefault(key, {})
                langs[lang] = ("list", value)
            else:
                out.setdefault(key, {})[lang] = ("str", value)
    return out, sorted(raw.keys())


def read_web(path):
    raw = load_json(path)
    keys = raw["keys"]
    plural = set(raw.get("pluralKeys", []))
    langs = {}
    for lang, rec in raw["langs"].items():
        t = rec["t"]
        langs[lang] = {"t": t, "plural": rec.get("plural", {})}
    return keys, plural, langs


# ------------------------------------------------------------------ small tools

def prefix_of(key):
    return key.split(".", 1)[0] if "." in key else "(no prefix)"


def placeholders(text):
    return collections.Counter(PLACEHOLDER.findall(text))


def short(text, limit=110):
    text = text.replace("\n", "\\n")
    return text if len(text) <= limit else text[:limit - 1] + "…"


def numbers(text):
    """Digit runs outside placeholders; decimal comma = point. Only ru numbers missing elsewhere
    are reported (ja/zh say «1日» where ru says «день», that is not an error)."""
    text = PLACEHOLDER.sub(" ", text)
    text = re.sub(r"(?<=\d),(?=\d)", ".", text)
    return collections.Counter(re.findall(r"\d+(?:\.\d+)?", text))


def literal_percent(text):
    return PLACEHOLDER.sub("", text).count("%")


def edge(text):
    return (text[:len(text) - len(text.lstrip())], text[len(text.rstrip()):])


class Findings(object):
    def __init__(self):
        self.items = {c: [] for c in CATEGORY_TITLES}
        self.allowed = []     # (cat, key, lang, kind, detail, reason)

    def add(self, cat, key, lang, kind, detail):
        reason = None
        for lg in (lang or "").split(","):
            reason = ALLOWED.get((cat, key, lg))
        if reason:
            self.allowed.append((cat, key, lang or "", kind, detail, reason))
            return
        self.items[cat].append((key, lang or "", kind, detail))

    def count(self, cat):
        return len(self.items[cat])

    def total(self):
        return sum(len(v) for v in self.items.values())


# ----------------------------------------------------------------------- checks

def check_catalog(catalog, found):
    keys = sorted(catalog)
    for key in keys:
        langs = catalog[key]

        # a — every base language present
        for lang in BASE_LANGS:
            if lang not in langs:
                found.add("a", key, lang, "catalog: no localization", "")
        for lang in DELTA_LANGS:
            if lang in langs and "en" not in langs:
                found.add("a", key, lang, "catalog: delta without base", "`en` is missing")

        # d — plural-ness agrees across languages that decline
        plural_langs = sorted(l for l in BASE_LANGS if l in langs and langs[l].plural)
        flat_langs = sorted(l for l in BASE_LANGS if l in langs and not langs[l].plural)
        if plural_langs and flat_langs:
            found.add("d", key, ",".join(flat_langs), "plural in %s but plain in" % ",".join(plural_langs), "")

        for lang, entry in sorted(langs.items()):
            # e — empty values
            if entry.plural:
                for cat, text in sorted(entry.forms.items()):
                    if not text.strip():
                        found.add("e", key, lang, "catalog: empty plural form `%s`" % cat, "")
            elif not entry.forms["-"].strip():
                found.add("e", key, lang, "catalog: empty value", "")

            # d — plural shape
            if entry.plural:
                want = CATEGORIES.get(lang)
                got = sorted(entry.forms)
                if want is not None:
                    need = set(want) | {"other"}
                    if set(got) != need:
                        found.add("d", key, lang, "plural categories",
                                  "have %s, CLDR for this language needs %s" % (",".join(got), ",".join(sorted(need))))
                if not entry.marked:
                    found.add("d", key, lang, "plural form without `%lld` + U+2063 head", "")
                if lang == "ru" and "many" in entry.forms and "other" in entry.forms \
                        and entry.forms["many"] != entry.forms["other"]:
                    found.add("d", key, lang, "ru `other` differs from `many`",
                              "`%s` vs `%s`" % (entry.forms["other"], entry.forms["many"]))

            # b — Cyrillic outside Russian
            if lang != "ru" and key not in CYRILLIC_KEY_WHITELIST:
                for text in entry.texts():
                    probe = text
                    for term in CYRILLIC_TERM_WHITELIST:
                        probe = probe.replace(term, "")
                    if CYRILLIC.search(probe):
                        found.add("b", key, lang, "catalog", short(text))
                        break

        # c / d — placeholders and format against Russian
        ru = langs.get("ru")
        if ru is None:
            continue
        for lang, entry in sorted(langs.items()):
            if lang == "ru":
                continue
            # en-US is a delta of `en`, the others compare with ru
            ref = langs["en"] if lang == "en-US" and "en" in langs else ru
            ref_name = "en" if ref is not ru else "ru"
            pairs = []
            if entry.plural == ref.plural:
                if not entry.plural:
                    pairs.append(("", ref.forms["-"], entry.forms["-"]))
                else:
                    # compare each language's forms joined: a plural word may drop a number
                    # placeholder in one form and keep it in another, so the set over all forms
                    pairs.append(("", " ".join(ref.texts()), " ".join(entry.texts())))
            else:
                pairs.append(("", " ".join(ref.texts()), " ".join(entry.texts())))
            for _, a, b in pairs:
                pa, pb = placeholders(a), placeholders(b)
                if set(pa) != set(pb):
                    miss = sorted(set(pa) - set(pb))
                    extra = sorted(set(pb) - set(pa))
                    found.add("c", key, lang, "set differs from %s" % ref_name,
                              "missing %s · extra %s · value `%s`" % (miss or "-", extra or "-", short(b)))
                elif pa != pb and not entry.plural:
                    found.add("c", key, lang, "repeat count differs from %s" % ref_name,
                              "%s vs %s · value `%s`" % (dict(pa), dict(pb), short(b)))
            if entry.plural or ref.plural:
                continue
            a, b = ref.forms["-"], entry.forms["-"]
            if not a.strip() or not b.strip():
                continue
            if edge(a) != edge(b) and lang not in CJK and lang != "en-US":
                found.add("d", key, lang, "edge whitespace differs from %s" % ref_name,
                          "%r vs %r · value `%s`" % (edge(a), edge(b), short(b)))
            na, nb = numbers(a), numbers(b)
            if any(nb[x] < na[x] for x in na):
                found.add("d", key, lang, "literal number of ru missing", "ru %s · here %s · value `%s`" % (dict(na), dict(nb), short(b)))
            if literal_percent(a) != literal_percent(b):
                found.add("d", key, lang, "`%%` count differs from %s" % ref_name,
                          "%d vs %d · value `%s`" % (literal_percent(a), literal_percent(b), short(b)))
            if a.count("\n") != b.count("\n"):
                found.add("d", key, lang, "line break count differs from %s" % ref_name,
                          "%d vs %d" % (a.count("\n"), b.count("\n")))


def check_native(native, native_langs, found):
    keys = sorted(native)
    base = [l for l in BASE_LANGS if l in native_langs]
    for key in keys:
        langs = native[key]
        for lang in base:
            if lang not in langs:
                found.add("a", key, lang, "lang_native.json: no key", "")
        # e — empty
        for lang, (kind, value) in sorted(langs.items()):
            parts = value if kind == "list" else [value]
            for i, part in enumerate(parts):
                if not isinstance(part, str) or not part.strip():
                    found.add("e", key, lang, "lang_native.json: empty value" + (" (form %d)" % i if kind == "list" else ""), "")
            # d — list length vs language
            if kind == "list":
                want = len(CATEGORIES.get(lang, []))
                if want and len(value) != want:
                    found.add("d", key, lang, "lang_native.json: %d forms" % len(value),
                              "language needs %d" % want)
            # b — Cyrillic
            if lang != "ru" and key not in CYRILLIC_KEY_WHITELIST:
                for part in parts:
                    probe = part if isinstance(part, str) else ""
                    for term in CYRILLIC_TERM_WHITELIST:
                        probe = probe.replace(term, "")
                    if CYRILLIC.search(probe):
                        found.add("b", key, lang, "lang_native.json", short(part))
                        break
        # d — a declining language gives a plain string while a sibling gives forms
        listed = sorted(l for l, (kind, _) in langs.items() if kind == "list")
        if listed:
            for lang in DECLINING:
                if lang in langs and langs[lang][0] == "str":
                    found.add("d", key, lang, "lang_native.json: plain string, but %s have forms" % ",".join(listed), "")
        # c — placeholders against ru
        if "ru" in langs:
            ru_kind, ru_val = langs["ru"]
            ru_text = " ".join(ru_val) if ru_kind == "list" else ru_val
            ph_ru = placeholders(ru_text)
            for lang, (kind, value) in sorted(langs.items()):
                if lang == "ru":
                    continue
                text = " ".join(value) if kind == "list" else value
                ph = placeholders(text)
                if set(ph) != set(ph_ru):
                    found.add("c", key, lang, "lang_native.json: set differs from ru",
                              "missing %s · extra %s · value `%s`" % (sorted(set(ph_ru) - set(ph)) or "-",
                                                                     sorted(set(ph) - set(ph_ru)) or "-", short(text)))
                elif ph != ph_ru and kind == "str" and ru_kind == "str":
                    found.add("c", key, lang, "lang_native.json: repeat count differs from ru",
                              "%s vs %s · value `%s`" % (dict(ph_ru), dict(ph), short(text)))


def check_web(web_keys, web_plural, web_langs, found):
    n = len(web_keys)
    for lang in sorted(web_langs):
        t = web_langs[lang]["t"]
        if len(t) != n:
            found.add("a", "(Fixtures/lang.json)", lang, "array length", "%d values for %d keys" % (len(t), n))
    for lang in BASE_LANGS:
        if lang not in web_langs:
            found.add("a", "(Fixtures/lang.json)", lang, "language missing", "")
    ru_t = web_langs.get("ru", {}).get("t", [])
    for i, key in enumerate(web_keys):
        for lang in sorted(web_langs):
            t = web_langs[lang]["t"]
            if i >= len(t):
                continue
            if not isinstance(t[i], str) or not t[i].strip():
                found.add("e", key, lang, "Fixtures/lang.json: empty value", "")
            if lang != "ru" and key not in CYRILLIC_KEY_WHITELIST and isinstance(t[i], str):
                probe = t[i]
                for term in CYRILLIC_TERM_WHITELIST:
                    probe = probe.replace(term, "")
                if CYRILLIC.search(probe):
                    found.add("b", key, lang, "Fixtures/lang.json", short(t[i]))
            if lang != "ru" and i < len(ru_t) and isinstance(t[i], str) and isinstance(ru_t[i], str):
                ref = ru_t[i]
                # the fixture keeps substitutions as <name>; plural keys carry the bare word in `t`
                pa = collections.Counter(re.findall(r"<[A-Za-z_][A-Za-z0-9_]*>", ref))
                pb = collections.Counter(re.findall(r"<[A-Za-z_][A-Za-z0-9_]*>", t[i]))
                if set(pa) != set(pb) and key not in web_plural:
                    found.add("c", key, lang, "Fixtures/lang.json: set differs from ru",
                              "missing %s · extra %s · value `%s`" % (sorted(set(pa) - set(pb)) or "-",
                                                                     sorted(set(pb) - set(pa)) or "-", short(t[i])))


def check_drift(catalog, native, native_langs, web_keys, web_plural, web_langs, found):
    cat_keys = set(catalog)
    nat_keys = set(native)
    web_set = set(web_keys)

    for key in sorted(nat_keys - cat_keys):
        found.add("f", key, "", "in lang_native.json, not in the catalog", "run `node Tools/lang2xcstrings.js`")
    for key in sorted(web_set - cat_keys):
        found.add("f", key, "", "in Fixtures/lang.json, not in the catalog", "run `node Tools/lang2xcstrings.js`")
    for key in sorted(cat_keys - nat_keys - web_set):
        found.add("f", key, "", "in the catalog, in neither lang_native.json nor Fixtures/lang.json",
                  "orphan: catalog was edited by hand, or a key was removed upstream")
    for key in sorted(nat_keys & web_set):
        found.add("f", key, "", "in both lang_native.json and Fixtures/lang.json",
                  "lang2xcstrings.js refuses this: the web word wins")

    # values: native vs catalog
    for key in sorted(nat_keys & cat_keys):
        for lang, (kind, value) in sorted(native[key].items()):
            entry = catalog[key].get(lang)
            if entry is None:
                continue
            if kind == "str":
                have = " ".join(entry.texts()) if entry.plural else entry.forms["-"]
                want = value
                if entry.plural:
                    # a plain string goes to `other` only; ja/zh stay one form
                    want = value
                    have = entry.forms.get("other", "")
                if have != want:
                    found.add("f", key, lang, "value differs: lang_native.json vs catalog",
                              "native `%s` · catalog `%s`" % (short(want), short(have)))
            else:
                cats = CATEGORIES.get(lang, [])
                if not entry.plural:
                    found.add("f", key, lang, "list in lang_native.json, plain string in catalog", "")
                    continue
                for i, cat in enumerate(cats):
                    if i < len(value) and entry.forms.get(cat) != value[i]:
                        found.add("f", key, lang, "plural form `%s` differs: lang_native.json vs catalog" % cat,
                                  "native `%s` · catalog `%s`" % (short(value[i]), short(entry.forms.get(cat, ""))))

    # values: web vs catalog (plain keys only; plural keys are compared by form below)
    index = dict((k, i) for i, k in enumerate(web_keys))
    for key in sorted(web_set & cat_keys):
        i = index[key]
        for lang in sorted(set(BASE_LANGS) | set(DELTA_LANGS)):
            if lang not in web_langs:
                continue
            entry = catalog[key].get(lang)
            if entry is None:
                # en-US exists in the catalog only where it differs from en: no entry is fine
                continue
            rec = web_langs[lang]
            if key in web_plural:
                p = rec["plural"].get(key)
                if not p or not entry.plural:
                    continue
                cats = CATEGORIES.get(lang, [])
                for word, form_index in zip(p.get("word", []), p.get("index", [])):
                    if form_index < len(cats):
                        have = entry.forms.get(cats[form_index], "")
                        if have != word:
                            found.add("f", key, lang, "plural form `%s` differs: Fixtures/lang.json vs catalog" % cats[form_index],
                                      "web `%s` · catalog `%s`" % (short(word), short(have)))
                            break
            else:
                if entry.plural or i >= len(rec["t"]):
                    continue
                web_value = rec["t"][i]
                if isinstance(web_value, str):
                    if entry.forms["-"] != web_value:
                        found.add("f", key, lang, "value differs: Fixtures/lang.json vs catalog",
                                  "web `%s` · catalog `%s`" % (short(web_value), short(entry.forms["-"])))

    # en-US / en-GB: where the web's value differs from `en`, the catalog must carry it. en-GB is
    # the base (`en`, British as on the web) so a difference there has no home in the catalog.
    for lang in ("en-US", "en-GB"):
        if lang not in web_langs or "en" not in web_langs:
            continue
        for i, key in enumerate(web_keys):
            if key in web_plural or key not in catalog:
                continue
            t, base = web_langs[lang]["t"], web_langs["en"]["t"]
            if i < len(t) and i < len(base) and t[i] != base[i]:
                have = catalog[key].get(lang)
                if have is None:
                    found.add("f", key, lang, "Fixtures/lang.json differs from en, the catalog has no %s entry" % lang,
                              "web `%s` · en `%s`" % (short(t[i]), short(base[i])))

    # catalog en-US: key must exist in en
    for key in sorted(catalog):
        if "en-US" in catalog[key] and "en" not in catalog[key]:
            found.add("f", key, "en-US", "delta without base", "")


# ----------------------------------------------------------------------- report

def render(found, stats):
    out = []
    w = out.append
    w("# Light Plan native · translation consistency report")
    w("")
    w("Generated by `python3 Tools/lang_check.py` (read-only, deterministic). "
      "Re-run it to refresh this file; do not edit by hand.")
    w("")
    w("## Data checked")
    w("")
    for line in stats:
        w("- " + line)
    w("")
    w("## Counts per category")
    w("")
    w("| | Category | Findings | Keys |")
    w("|---|---|---:|---:|")
    for cat, title in CATEGORY_TITLES.items():
        keys = set(k for k, _, _, _ in found.items[cat])
        w("| %s | %s | %d | %d |" % (cat, title, found.count(cat), len(keys)))
    w("| | **Total** | **%d** | |" % found.total())
    w("")
    w("Not counted: %d allowed exceptions, read against the Swift call sites (last section)." % len(found.allowed))
    w("")
    for cat, title in CATEGORY_TITLES.items():
        w("## %s) %s" % (cat, title))
        w("")
        rows = found.items[cat]
        if not rows:
            w("None.")
            w("")
            continue
        by_kind = collections.Counter(k for _, _, k, _ in rows)
        w("By kind: " + "; ".join("%s — %d" % (k, n) for k, n in sorted(by_kind.items())))
        w("")
        groups = collections.OrderedDict()
        for row in sorted(rows):
            groups.setdefault(prefix_of(row[0]), []).append(row)
        for prefix, items in groups.items():
            w("### `%s.*` (%d)" % (prefix, len(items)))
            w("")
            for key, lang, kind, detail in items:
                line = "- `%s`" % key
                if lang:
                    line += " [%s]" % lang
                line += " — " + kind
                if detail:
                    line += " — " + detail
                w(line)
            w("")
    live = set(k for rows in found.items.values() for k, _, _, _ in rows)
    notes = [(k, REVIEW_NOTES[k]) for k in sorted(REVIEW_NOTES) if k in live]
    w("## Notes on findings that need a decision (%d)" % len(notes))
    w("")
    if not notes:
        w("None.")
        w("")
    for key, text in notes:
        w("- `%s` — %s" % (key, text))
    if notes:
        w("")
    w("## Allowed exceptions (%d)" % len(found.allowed))
    w("")
    w("Differences the script would report, kept by hand in `ALLOWED` inside `Tools/lang_check.py` "
      "with the reason. They do not turn the exit code red.")
    w("")
    for cat, key, lang, kind, detail, reason in sorted(found.allowed):
        w("- (%s) `%s` [%s] — %s — %s" % (cat, key, lang, kind, reason))
    w("")
    return "\n".join(out).rstrip() + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--root", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."),
                        help="repository root (default: the one this script lives in)")
    args = parser.parse_args(argv)
    root = os.path.abspath(args.root)

    try:
        catalog, source_lang = read_catalog(os.path.join(root, CATALOG_REL))
        native, native_langs = read_native(os.path.join(root, NATIVE_REL))
        web_keys, web_plural, web_langs = read_web(os.path.join(root, WEB_REL))
    except DataError as err:
        sys.stderr.write("lang_check: %s\n" % err)
        return 2

    found = Findings()
    check_catalog(catalog, found)
    check_native(native, native_langs, found)
    check_web(web_keys, web_plural, web_langs, found)
    check_drift(catalog, native, native_langs, web_keys, web_plural, web_langs, found)

    plural_catalog = sum(1 for k in catalog if any(e.plural for e in catalog[k].values()))
    stats = [
        "`%s`: %d keys (%d plural), languages %s, sourceLanguage `%s`" % (
            os.path.basename(CATALOG_REL), len(catalog), plural_catalog,
            " ".join(sorted(set(l for k in catalog for l in catalog[k]))), source_lang),
        "`%s`: %d keys, languages %s" % (NATIVE_REL, len(native), " ".join(native_langs)),
        "`%s`: %d keys (%d plural), languages %s" % (WEB_REL, len(web_keys), len(web_plural), " ".join(sorted(web_langs))),
        "Cyrillic whitelist: %d keys, %d terms" % (len(CYRILLIC_KEY_WHITELIST), len(CYRILLIC_TERM_WHITELIST)),
    ]
    sys.stdout.write(render(found, stats))
    return 1 if found.total() else 0


if __name__ == "__main__":
    sys.exit(main())
