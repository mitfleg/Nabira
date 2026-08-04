import Foundation

/// issue #22 (вариант B): умная по-словная конверсия ВЫДЕЛЕННОГО текста.
///
/// Обычный путь конвертирует всё выделение в одну сторону (по активной раскладке), поэтому
/// mixed-мусор «ghtlkj d ьшчув» чинится лишь наполовину. Здесь решаем ПО КАЖДОМУ СЛОВУ:
/// переворачиваем слово только если оно «мусор в своей письменности, но валидное слово после
/// флипа» (по системному словарю). Так mixed-мусор чинится целиком, а намеренное «iPhone
/// стоит» и «стоит,» остаются нетронутыми.
///
/// Точность важнее полноты (скептик #22):
/// • 1-буквенные НЕ трогаем вовсе — «c» (витамин C), «e» (число e) неотличимы от мусора «z»;
/// • 2-буквенные — только через частотный ShortWords (NSSpellChecker на длине 2 ненадёжен),
///   как в LayoutDetector.decide;
/// • ALL-CAPS акронимы и camelCase/смешанные — пропускаем (те же гейты, что в decide).
///
/// Тумблер «Конвертировать по тексту» (вариант A) идёт мимо этого — там тотальный флип
/// (DynamicKeyMapping.convertBidirectional). Пары не «латиница+кириллица» (иврит и т.п.) сюда
/// не попадают — вызывающий откатывается на обычный однонаправленный путь.
enum SmartConvert {
    private enum Script { case cyr, lat, other, mixed }

    /// Умная по-словная конверсия выделения. Возвращает обычную одностороннюю конверсию, если
    /// пара не латиница+кириллица или словари недоступны.
    @MainActor
    static func selection(_ text: String) -> String {
        guard let (latLang, cyrLang) = classifyPair(),
              Dict.isAvailable(latLang), Dict.isAvailable(cyrLang) else {
            return DynamicKeyMapping.convert(text)   // не Lat+Cyr пара — обычный путь
        }
        var out = ""
        for tok in tokenize(text) {
            out += tok.isWord ? convertWord(tok.str, latLang: latLang, cyrLang: cyrLang) : tok.str
        }
        return out
    }

    /// Решение по одному слову (токен без пробелов, может нести пунктуацию).
    @MainActor
    private static func convertWord(_ w: String, latLang: String, cyrLang: String) -> String {
        let core = letterCore(w)
        let script = dominantScript(core)
        guard core.count >= 1, script == .cyr || script == .lat else { return w }
        // Акронимы и код — как в LayoutDetector.decide.
        if LayoutDetector.isAllCaps(core) || LayoutDetector.looksLikeCodeIdentifier(core) { return w }

        let wordLang = (script == .cyr) ? cyrLang : latLang
        let flipLang = (script == .cyr) ? latLang : cyrLang

        // 1 буква — не трогаем: флип валиден в обе стороны («z»→«я», но и «c»→«с», «e»→«у»),
        // отличить намеренный научный символ от мусора нельзя (скептик #22).
        if core.count == 1 { return w }

        // 2 буквы — только частотный список (NSSpellChecker на длине 2 ненадёжен), как decide.
        if core.count == 2 {
            if let cur = ShortWords.common(wordLang), cur.contains(core.lowercased()) { return w }
            let whole = DynamicKeyMapping.convertBidirectional(w)
            let wc = letterCore(whole)
            if wc.count == 2, let oth = ShortWords.common(flipLang), oth.contains(wc.lowercased()) {
                return whole
            }
            return w
        }

        // 3+ — словарь. Уже валидное слово своего языка → не трогаем (iPhone, стоит).
        if Dict.isValidWord(core.lowercased(), lang: wordLang) { return w }
        // (1) флип целиком — ловит «ёлка» (`krf), «делю» (ltk.), «продолжение».
        let whole = DynamicKeyMapping.convertBidirectional(w)
        let wc = letterCore(whole)
        if wc.count >= 2, wc.allSatisfy({ $0.isLetter }), Dict.isValidWord(wc.lowercased(), lang: flipLang) {
            return whole
        }
        // (2) со снятым хвостом реальной пунктуации — «ghtlkj;tybt,» → «продолжение» + «,».
        let (body, suffix) = splitTrailingNonLetters(w)
        if !suffix.isEmpty, !body.isEmpty {
            let bflip = DynamicKeyMapping.convertBidirectional(body)
            let bc = letterCore(bflip)
            if bc.count >= 2, bc.allSatisfy({ $0.isLetter }), Dict.isValidWord(bc.lowercased(), lang: flipLang) {
                return bflip + suffix
            }
        }
        return w   // не разрешилось — как есть (имя/бренд)
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
