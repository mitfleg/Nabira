import AppKit
import CoreGraphics

/// issue #16: Spotlight «съедает» первый Backspace серого автодополнения, из-за чего
/// обычная конверсия (стирание клавишами) оставляет лишнюю букву. Spotlight — защищённая
/// поверхность: не отдаётся как frontmost-приложение и не участвует в system-wide AX-фокусе,
/// НО его ОКНО детектится в CGWindowList по owner "Spotlight" (проверено живым захватом
/// 2026-08-01). Этого достаточно, чтобы включить особый путь конверсии (Cmd+A + буфер,
/// без Backspace — см. TextConverter.convertSpotlight).
enum SpotlightAX {
    /// Открыт ли сейчас Spotlight (по окну в CGWindowList).
    static func isActive() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return list.contains { ($0[kCGWindowOwnerName as String] as? String) == "Spotlight" }
    }
}
