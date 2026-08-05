import Foundation

/// issue #22 (вариант B): умная по-словная конверсия ВЫДЕЛЕННОГО текста.
///
/// Обычный путь конвертирует всё выделение в одну сторону (по активной раскладке), поэтому
/// mixed-мусор «ghtlkj d ьшчув» чинится лишь наполовину. Здесь решаем ПО КАЖДОМУ СЛОВУ:
/// переворачиваем слово только если оно «мусор в своей письменности, но валидное слово после
/// флипа» (по системному словарю). Так mixed-мусор чинится целиком, а намеренное «iPhone
/// стоит»/«стоит,» остаются нетронутыми.
///
/// Точность важнее полноты (скептик #22):
/// • 2-буквенные — только через частотный ShortWords (NSSpellChecker на длине 2 ненадёжен);
/// • ALL-CAPS акронимы и camelCase/смешанные — пропускаем (те же гейты, что в decide);
/// • одиночную букву флипаем ТОЛЬКО в сторону реально флипнутых соседей — «z yt vjue»→
///   «я не могу» (вся фраза — не та раскладка), но «витамин c»/«число e» не трогаем (сосед
///   валиден и остался), т.к. «c»/«e» — научный символ, а не мусор.
///
/// Тумблер «Конвертировать по тексту» (A) идёт мимо — тотальный флип
/// (DynamicKeyMapping.convertBidirectional). Пары не «латиница+кириллица» — обычный путь.
enum SmartConvert {
    private enum Script { case cyr, lat, other, mixed }
    private enum WordDecision { case keep, flip(String, Script) }

    // Частотные однобуквенные слова — позитивный сигнал для одиночных букв.
    private static let cyr1: Set<Character> = ["я", "в", "с", "к", "о", "у", "а", "и"]
    private static let lat1: Set<Character> = ["a", "i"]

    /// Умная по-словная конверсия выделения. Возвращает обычную одностороннюю конверсию, если
    /// пара не латиница+кириллица или словари недоступны.
    @MainActor
    static func selection(_ text: String) -> String {
        guard let (latLang, cyrLang) = classifyPair(),
              Dict.isAvailable(latLang), Dict.isAvailable(cyrLang) else {
            return DynamicKeyMapping.convert(text)   // не Lat+Cyr пара — обычный путь
        }
        let toks = tokenize(text)
        var results = [String?](repeating: nil, count: toks.count)
        var lonePending: [Int] = []              // индексы одиночных букв — решаем в пасе 2
        var flippedCyr = 0, flippedLat = 0

        // Пас 1 — многобуквенные слова.
        for (i, tok) in toks.enumerated() {
            guard tok.isWord else { results[i] = tok.str; continue }
            if isSingleLetterCandidate(tok.str) { lonePending.append(i); continue }
            switch decideWord(tok.str, latLang: latLang, cyrLang: cyrLang) {
            case .keep:
                results[i] = tok.str
            case let .flip(s, toScript):
                results[i] = s
                if toScript == .cyr { flippedCyr += 1 } else if toScript == .lat { flippedLat += 1 }
            }
        }

        // Сигнал для одиночных букв — направление РЕАЛЬНО флипнутых соседей (не оставленных
        // валидными): «z yt vjue»→«я не могу» (все флипнулись), но «витамин c» не трогаем
        // (витамин валиден, остался). Разнобой (оба скрипта флипались) → сигнала нет.
        let target: Script? = (flippedCyr > 0 && flippedLat == 0) ? .cyr
                            : (flippedLat > 0 && flippedCyr == 0) ? .lat : nil

        // Пас 2 — одиночные буквы.
        for i in lonePending { results[i] = resolveLone(toks[i].str, target: target) }
        return results.map { $0 ?? "" }.joined()
    }

    /// Токен, чьё буквенное ядро — ровно одна буква латиницы/кириллицы.
    private static func isSingleLetterCandidate(_ w: String) -> Bool {
        let core = letterCore(w)
        guard core.count == 1 else { return false }
        let sc = dominantScript(core)
        return sc == .cyr || sc == .lat
    }

    /// Решение по слову (>=2 букв). .flip несёт письменность РЕЗУЛЬТАТА (сигнал для пасса 2).
    @MainActor
    private static func decideWord(_ w: String, latLang: String, cyrLang: String) -> WordDecision {
        let core = letterCore(w)
        let script = dominantScript(core)
        guard core.count >= 2, script == .cyr || script == .lat else { return .keep }
        // Акронимы и код — как в LayoutDetector.decide.
        if LayoutDetector.isAllCaps(core) || LayoutDetector.looksLikeCodeIdentifier(core) { return .keep }

        let wordLang = (script == .cyr) ? cyrLang : latLang
        let flipLang = (script == .cyr) ? latLang : cyrLang
        let flippedScript: Script = (script == .cyr) ? .lat : .cyr

        // 2 буквы — только частотный список (NSSpellChecker на длине 2 ненадёжен), как decide.
        if core.count == 2 {
            if let cur = ShortWords.common(wordLang), cur.contains(core.lowercased()) { return .keep }
            let whole = DynamicKeyMapping.convertBidirectional(w)
            let wc = letterCore(whole)
            if wc.count == 2, let oth = ShortWords.common(flipLang), oth.contains(wc.lowercased()) {
                return .flip(whole, flippedScript)
            }
            return .keep
        }

        // 3+ — словарь. Уже валидное слово своего языка → не трогаем (iPhone, стоит).
        if Dict.isValidWord(core.lowercased(), lang: wordLang) { return .keep }
        // (1) флип целиком — ловит «ёлка» (`krf), «делю» (ltk.), «продолжение».
        let whole = DynamicKeyMapping.convertBidirectional(w)
        let wc = letterCore(whole)
        if wc.count >= 2, wc.allSatisfy({ $0.isLetter }), Dict.isValidWord(wc.lowercased(), lang: flipLang) {
            return .flip(whole, flippedScript)
        }
        // (2) со снятым хвостом реальной пунктуации — «ghtlkj;tybt,» → «продолжение» + «,».
        let (body, suffix) = splitTrailingNonLetters(w)
        if !suffix.isEmpty, !body.isEmpty {
            let bflip = DynamicKeyMapping.convertBidirectional(body)
            let bc = letterCore(bflip)
            if bc.count >= 2, bc.allSatisfy({ $0.isLetter }), Dict.isValidWord(bc.lowercased(), lang: flipLang) {
                return .flip(bflip + suffix, flippedScript)
            }
        }
        return .keep   // не разрешилось — как есть (имя/бренд)
    }

    /// Одиночную букву флипаем ТОЛЬКО в сторону флипнутых соседей (target) и только если её
    /// флип — частотное однобуквенное слово этой стороны. Пунктуацию вокруг сохраняем (флипаем
    /// лишь саму букву): «z,»→«я,» при наличии сигнала, иначе «z,» как есть.
    private static func resolveLone(_ orig: String, target: Script?) -> String {
        guard let target else { return orig }
        var lead = "", trail = ""
        var letter: Character? = nil
        for ch in orig {
            if ch.isLetter, letter == nil { letter = ch }
            else if letter == nil { lead.append(ch) } else { trail.append(ch) }
        }
        guard let l = letter else { return orig }
        let flipped = DynamicKeyMapping.convertBidirectional(String(l))
        guard let fch = flipped.first, dominantScript(String(fch)) == target else { return orig }
        let common = (target == .cyr) ? cyr1 : lat1
        guard common.contains(Character(fch.lowercased())) else { return orig }
        return lead + flipped + trail
    }

    // MARK: - Helpers

    /// Классификация пары раскладок: (латинский язык, кириллический язык) или nil, если пара
    /// не «латиница+кириллица» (тогда умный путь неприменим).
    @MainActor
    private static func classifyPair() -> (latLang: String, cyrLang: String)? {
        guard let (a, b) = LayoutSwitcher.currentAndOppositeLanguage() else { return nil }
        let aCyr = isCyrillicLang(a), bCyr = isCyrillicLang(b)
        let aLat = isLatinLang(a), bLat = isLatinLang(b)
        if aCyr && bLat { return (b, a) }
        if bCyr && aLat { return (a, b) }
        return nil
    }

    private static let cyrillicLangs: Set<String> = ["ru", "uk", "be", "bg", "sr", "mk", "kk", "ky", "mn", "tg"]
    private static func isCyrillicLang(_ lang: String) -> Bool {
        cyrillicLangs.contains(String(lang.lowercased().prefix(2)))
    }
    // Латинская письменность = не кириллица и не иврит/греческий/армянский/грузинский/арабский.
    private static let nonLatinLangs: Set<String> = ["he", "iw", "el", "hy", "ka", "ar", "fa", "yi"]
    private static func isLatinLang(_ lang: String) -> Bool {
        let two = String(lang.lowercased().prefix(2))
        return !cyrillicLangs.contains(two) && !nonLatinLangs.contains(two)
    }

    private static func dominantScript(_ s: String) -> Script {
        var cyr = 0, lat = 0
        for u in s.unicodeScalars {
            if u.value >= 0x0400 && u.value <= 0x04FF { cyr += 1 }
            else if (u.value >= 0x41 && u.value <= 0x5A) || (u.value >= 0x61 && u.value <= 0x7A) { lat += 1 }
        }
        if cyr > 0 && lat > 0 { return .mixed }
        if cyr > 0 { return .cyr }
        if lat > 0 { return .lat }
        return .other
    }

    /// Слово без окружающих не-букв (для проверки по словарю). «`krf»→«krf», «дел.»→«дел».
    private static func letterCore(_ s: String) -> String {
        var chars = Array(s)
        while let f = chars.first, !f.isLetter { chars.removeFirst() }
        while let l = chars.last, !l.isLetter { chars.removeLast() }
        return String(chars)
    }

    /// Отделяет хвост НЕ-букв (реальную пунктуацию) от тела слова: «прод,»→(«прод»,«,»).
    private static func splitTrailingNonLetters(_ s: String) -> (body: String, suffix: String) {
        var body = Array(s); var suffix = ""
        while let l = body.last, !l.isLetter { suffix = String(l) + suffix; body.removeLast() }
        return (String(body), suffix)
    }

    /// Разбивает текст на чередующиеся куски: слова (не-пробелы) и разделители (пробелы),
    /// сохраняя всё — сборка обратно даёт исходную длину.
    private static func tokenize(_ s: String) -> [(isWord: Bool, str: String)] {
        var out: [(Bool, String)] = []
        var cur = ""
        var curWS: Bool? = nil
        for ch in s {
            let ws = ch.isWhitespace
            if let w = curWS {
                if ws == w { cur.append(ch) }
                else { out.append((!w, cur)); cur = String(ch); curWS = ws }
            } else {
                curWS = ws; cur = String(ch)
            }
        }
        if let w = curWS, !cur.isEmpty { out.append((!w, cur)) }
        return out
    }
}
