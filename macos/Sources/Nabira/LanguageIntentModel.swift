import Foundation

struct LanguageIntentScores: Equatable, Sendable {
    let unavailable: Double
    let english: Double
    let hebrew: Double
    let russian: Double

    func confidence(for language: String) -> Double {
        switch String(language.lowercased().prefix(2)) {
        case "en": return english
        case "he", "iw": return hebrew
        case "ru": return russian
        default: return 0
        }
    }
}

/// Чистая политика поверх нейросетевых оценок. Модель не получает права обходить
/// словари и защитные гейты: она разрешает только словарную коллизию в уже
/// установленном контексте другого языка.
enum LanguageIntentPolicy {
    static func refine(
        base: LayoutVerdict,
        currentLanguage: String,
        otherLanguage: String,
        dominantLanguage: String?,
        typedIsValid: Bool,
        convertedIsValid: Bool,
        typedScores: LanguageIntentScores?,
        convertedScores: LanguageIntentScores?
    ) -> LayoutVerdict {
        guard base == .keep,
              dominantLanguage == String(otherLanguage.lowercased().prefix(2)),
              typedIsValid, convertedIsValid,
              let typedScores, let convertedScores else { return base }

        let sourceConfidence = typedScores.confidence(for: currentLanguage)
        let targetConfidence = convertedScores.confidence(for: otherLanguage)
        guard convertedScores.unavailable <= 0.20,
              targetConfidence >= 0.90,
              sourceConfidence <= 0.65,
              targetConfidence - sourceConfidence >= 0.25 else { return base }
        return .switchToConverted
    }
}

@MainActor
final class LanguageIntentModel {
    static let shared = LanguageIntentModel()

    private var characterIDs: [Character: Int64]?
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var bufferedOutput = Data()
    private var disabled = false

    func warmUp() {
        _ = scores(for: "hello")
    }

    func scores(for text: String) -> LanguageIntentScores? {
        guard !disabled, let ids = encode(text), ids.filter({ $0 != 0 }).count >= 2 else { return nil }
        do {
            if process?.isRunning != true { try launch() }
            guard let input, let output else { return nil }
            let request = ids.map(String.init).joined(separator: ",") + "\n"
            try input.write(contentsOf: Data(request.utf8))
            let values = try readLine(from: output).split(separator: ",").compactMap { Double($0) }
            guard values.count == 4 else { throw CocoaError(.coderInvalidValue) }
            return LanguageIntentScores(
                unavailable: values[0], english: values[1], hebrew: values[2], russian: values[3]
            )
        } catch {
            nabiraLog("intent-model: disabled after helper failure")
            stop()
            disabled = true
            return nil
        }
    }

    func stop() {
        try? input?.close()
        try? output?.close()
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        process = nil
        input = nil
        output = nil
        bufferedOutput.removeAll(keepingCapacity: false)
    }

    private func encode(_ text: String) -> [Int64]? {
        if characterIDs == nil {
            guard let url = Bundle.module.url(
                forResource: "language_intent_dictionary", withExtension: "json"
            ),
            let data = try? Data(contentsOf: url),
            let raw = try? JSONDecoder().decode([String: Int64].self, from: data) else { return nil }
            characterIDs = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
                guard key.count == 1, let character = key.first else { return nil }
                return (character, value)
            })
        }
        guard let characterIDs else { return nil }
        // Модель обучена на окне 45 символов. Берём конец фразы: там находится
        // проверяемое слово, а перед ним помещаются два последних слова контекста.
        var ids = text.suffix(45).compactMap { characterIDs[$0] }
        if ids.count < 45 { ids.append(contentsOf: repeatElement(0, count: 45 - ids.count)) }
        if ids.count > 45 { ids = Array(ids.suffix(45)) }
        return ids
    }

    private func launch() throws {
        guard let modelURL = Bundle.module.url(forResource: "language_intent", withExtension: "onnx") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let bundle = Bundle.main.bundleURL
        let helperURL = ProcessInfo.processInfo.environment["NABIRA_LANGUAGE_HELPER"]
            .map(URL.init(fileURLWithPath:))
            ?? bundle.appendingPathComponent("Contents/Helpers/NabiraSageHelper")
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw CocoaError(.executableNotLoadable)
        }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let task = Process()
        task.executableURL = helperURL
        task.arguments = ["--language", modelURL.path]
        task.standardInput = stdinPipe
        task.standardOutput = stdoutPipe
        task.standardError = FileHandle.nullDevice
        try task.run()
        process = task
        input = stdinPipe.fileHandleForWriting
        output = stdoutPipe.fileHandleForReading
    }

    private func readLine(from handle: FileHandle) throws -> String {
        while true {
            if let newline = bufferedOutput.firstRange(of: Data([0x0A])) {
                let line = bufferedOutput[..<newline.lowerBound]
                bufferedOutput.removeSubrange(..<newline.upperBound)
                let result = String(decoding: line, as: UTF8.self)
                if result.hasPrefix("ERR:") { throw CocoaError(.coderInvalidValue) }
                return result
            }
            let chunk = handle.availableData
            guard !chunk.isEmpty else { throw CocoaError(.executableNotLoadable) }
            bufferedOutput.append(chunk)
        }
    }
}
