import Foundation

/// issue #22 (вариант B): умная по-словная конверсия ВЫДЕЛЕННОГО текста.
///
/// Обычный путь конвертирует всё выделение в одну сторону (по активной раскладке), поэтому
/// mixed-мусор «ghtlkj d ьшчув» чинится лишь наполовину, а застрявшее слово («z» вместо «я»)
/// не исправить вовсе. Здесь решаем ПО КАЖДОМУ СЛОВУ: переворачиваем слово только если оно
/// «мусор в своей письменности, но валидное слово после флипа» (по системному словарю).
/// Так «z не могу» → «я не могу», mixed-мусор чинится целиком, а намеренное «iPhone стоит»
/// остаётся нетронутым (оба — реальные слова).
///
/// Тумблер «Конвертировать по тексту» (вариант A) идёт мимо этого — там тотальный флип
/// (DynamicKeyMapping.convertBidirectional). Пары не «латиница+кириллица» (иврит и т.п.) сюда
/// не попадают — вызывающий откатывается на обычный однонаправленный путь.
enum SmartConvert {
    private enum Script { case cyr, lat, other, mixed }

    /// Умная по-словная конверсия выделения. Возвращает исходный текст без изменений, если
    /// пара не латиница+кириллица или словари недоступны (тогда вызывающий берёт обычный путь).
    @MainActor
    static func selection(_ text: String) -> String {
        guard let (latLang, cyrLang) = classifyPair(),
              Dict.isAvailable(latLang), Dict.isAvailable(cyrLang) else {
            return DynamicKeyMapping.convert(text)   // не Lat+Cyr пара — обычный путь
        }

        let tokens = tokenize(text)

        // --- Пас 1: решение по каждому слову ---
        enum Decision {
            case text(String, script: Script)          // готово (keep или flip), с письменностью результата
            case ambiguousShort(orig: String)          // 1 буква — решаем в пасе 2 по доминанте
            case verbatim(String)                      // разделитель / без букв / mixed
        }
        var decisions: [Decision] = []
        for tok in tokens {
            guard tok.isWord else { decisions.append(.verbatim(tok.str)); continue }
            let w = tok.str
            let core = letterCore(w)
            let script = dominantScript(core)
            guard core.count >= 1, script == .cyr || script == .lat else {
                decisions.append(.verbatim(w)); continue
            }
            let wordLang = (script == .cyr) ? cyrLang : latLang
            let flipLang = (script == .cyr) ? latLang : cyrLang
            let flippedScript: Script = (script == .cyr) ? .lat : .cyr

            // Уже валидное слово своего языка → не трогаем (iPhone, стоит).
            if core.count >= 2, Dict.isValidWord(core.lowercased(), lang: wordLang) {
                decisions.append(.text(w, script: script)); continue
            }
            // 2-буквенное частое слово своего языка → не трогаем.
            if core.count == 2, let cur = ShortWords.common(wordLang),
               cur.contains(core.lowercased()) {
                decisions.append(.text(w, script: script)); continue
            }

            // Кандидат на флип. (1) целиком — ловит и «ёлка» (`krf), и «делю» (ltk.).
            let whole = DynamicKeyMapping.convertBidirectional(w)
            let wholeCore = letterCore(whole)
            if wholeCore.count >= 2, wholeCore.allSatisfy({ $0.isLetter }),
               Dict.isValidWord(wholeCore.lowercased(), lang: flipLang) {
                decisions.append(.text(whole, script: flippedScript)); continue
            }
            // (2) со снятым хвостом реальной пунктуации: «ghtlkj;tybt,» → «продолжение» + «,».
            let (body, suffix) = splitTrailingNonLetters(w)
            if !suffix.isEmpty, !body.isEmpty {
                let bflip = DynamicKeyMapping.convertBidirectional(body)
                let bflipCore = letterCore(bflip)
                if bflipCore.count >= 2, bflipCore.allSatisfy({ $0.isLetter }),
                   Dict.isValidWord(bflipCore.lowercased(), lang: flipLang) {
                    decisions.append(.text(bflip + suffix, script: flippedScript)); continue
                }
            }
            // Не разрешилось. 1 буква → в пас 2 (по доминанте). Иначе — как есть (имя/бренд).
            if core.count == 1 {
                decisions.append(.ambiguousShort(orig: w))
            } else {
                decisions.append(.verbatim(w))
            }
        }

        // --- Пас 2: доминирующая письменность результата → одиночные буквы ---
        var cyrCount = 0, latCount = 0
        for d in decisions {
            if case let .text(_, script) = d {
                if script == .cyr { cyrCount += 1 } else if script == .lat { latCount += 1 }
            }
        }
        let dominant: Script? = cyrCount > latCount ? .cyr : (latCount > cyrCount ? .lat : nil)

        var out = ""
        for d in decisions {
            switch d {
            case let .text(s, _): out += s
            case let .verbatim(s): out += s
            case let .ambiguousShort(orig):
                out += resolveShort(orig, dominant: dominant, latLang: latLang, cyrLang: cyrLang)
            }
        }
        return out
    }

    // MARK: - Одиночные буквы

    // Частотные однобуквенные слова — только позитивный сигнал для пасса доминанты.
    private static let cyr1: Set<Character> = ["я", "в", "с", "к", "о", "у", "а", "и"]
    private static let lat1: Set<Character> = ["a", "i"]

    /// Флипаем одиночную букву к доминирующей письменности, только если её флип — частотное
    /// однобуквенное слово этой стороны («z»→«я»). Иначе оставляем как есть (нет сигнала).
    private static func resolveShort(_ orig: String, dominant: Script?,
                                     latLang: String, cyrLang: String) -> String {
        guard let dominant else { return orig }
        let flipped = DynamicKeyMapping.convertBidirectional(orig)
        guard let fch = letterCore(flipped).first else { return orig }
        let common = (dominant == .cyr) ? cyr1 : lat1
        let flippedScript = dominantScript(String(fch))
        guard flippedScript == dominant, common.contains(Character(fch.lowercased())) else {
            return orig
        }
        return flipped
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
    // Латинская письменность = не кириллица, не иврит, не греческий/армянский/грузинский/арабский.
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
