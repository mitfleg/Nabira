import AppKit
import CryptoKit
import Foundation

enum SageModelInstallState: Equatable {
    case notInstalled
    case downloading(completed: Int, total: Int)
    case checking
    case installed
    case failed(String)
}

private struct SageAsset: Sendable {
    let name: String
    let size: Int64
    let sha256: String
}

enum SageModelFiles {
    static let version = "sage-fredt5-95m-fp16-v1"
    static let downloadSizeBytes: Int64 = 262_896_057
    static let baseURL = "https://nabira.site/downloads/models/sage-fredt5-95m-fp16/v1"
    fileprivate static let assets: [SageAsset] = [
        .init(name: "encoder_model.onnx", size: 97_863_391, sha256: "0181db616a7336b163d5796b8c3975756234357233e1595722b34831483b747a"),
        .init(name: "decoder_model.onnx", size: 162_149_131, sha256: "142f189f6a4483b15bab972ce6ea80db9846350b68051dd0852b40341962f96e"),
        .init(name: "vocab.json", size: 1_612_610, sha256: "a7be5387908a52936262a09514bf0a9327ff17981097b6b2225c67120fd905a5"),
        .init(name: "merges.txt", size: 1_270_925, sha256: "bd05ba8658a199897510cd84cd98ec1424c812259db6e03319c33a5bfcac2b90"),
    ]

    static var directory: URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["NABIRA_SAGE_MODEL_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        #endif
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Nabira/Models/SageFredT5-95M/\(version)", isDirectory: true)
    }

    static var encoder: URL { directory.appendingPathComponent("encoder_model.onnx") }
    static var decoder: URL { directory.appendingPathComponent("decoder_model.onnx") }
    static var vocab: URL { directory.appendingPathComponent("vocab.json") }
    static var merges: URL { directory.appendingPathComponent("merges.txt") }

    static var isInstalled: Bool {
        assets.allSatisfy { asset in
            guard let attributes = try? FileManager.default.attributesOfItem(
                atPath: directory.appendingPathComponent(asset.name).path
            ), let size = attributes[.size] as? NSNumber else { return false }
            return size.int64Value == asset.size
        }
    }
}

@MainActor
final class SageModelManager: ObservableObject {
    static let shared = SageModelManager()

    @Published private(set) var state: SageModelInstallState
    private var operation: Task<Void, Never>?

    private init() {
        state = SageModelFiles.isInstalled ? .installed : .notInstalled
    }

    func connect() {
        guard operation == nil, !SageModelFiles.isInstalled else { return }
        state = .downloading(completed: 0, total: SageModelFiles.assets.count)
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                try await Self.install { completed, total in
                    await MainActor.run { self.state = .downloading(completed: completed, total: total) }
                }
                self.state = .installed
            } catch is CancellationError {
                self.state = SageModelFiles.isInstalled ? .installed : .notInstalled
            } catch {
                self.state = .failed(NabiraCopy.text(
                    "Не удалось скачать модель. Проверьте интернет и повторите.",
                    "The model could not be downloaded. Check your connection and try again."
                ))
                nabiraLog("sage install failed: \(String(describing: type(of: error)))")
            }
            self.operation = nil
        }
    }

    func verify() {
        guard operation == nil, SageModelFiles.isInstalled else { return }
        state = .checking
        operation = Task { [weak self] in
            guard let self else { return }
            let valid = await Task.detached(priority: .utility) { Self.verifyFiles() }.value
            self.state = valid ? .installed : .failed(NabiraCopy.text(
                "Файлы модели повреждены. Удалите её и подключите заново.",
                "The model files are damaged. Remove and reconnect the model."
            ))
            self.operation = nil
        }
    }

    func remove() {
        operation?.cancel()
        operation = nil
        let directory = SageModelFiles.directory
        try? FileManager.default.removeItem(at: directory)
        state = .notInstalled
        Task { await SageCorrectionService.shared.reset() }
    }

    private static func install(progress: @escaping @Sendable (Int, Int) async -> Void) async throws {
        let fm = FileManager.default
        let root = SageModelFiles.directory.deletingLastPathComponent()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(".download-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        do {
            for (index, asset) in SageModelFiles.assets.enumerated() {
                try Task.checkCancellation()
                await progress(index, SageModelFiles.assets.count)
                let encodedName = asset.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? asset.name
                guard let source = URL(string: "\(SageModelFiles.baseURL)/\(encodedName)") else {
                    throw URLError(.badURL)
                }
                let (temporary, response) = try await URLSession.shared.download(from: source)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                let destination = staging.appendingPathComponent(asset.name)
                try fm.moveItem(at: temporary, to: destination)
                let attributes = try fm.attributesOfItem(atPath: destination.path)
                guard (attributes[.size] as? NSNumber)?.int64Value == asset.size,
                      try sha256(of: destination) == asset.sha256 else {
                    throw CocoaError(.fileReadCorruptFile)
                }
            }
            await progress(SageModelFiles.assets.count, SageModelFiles.assets.count)
            if fm.fileExists(atPath: SageModelFiles.directory.path) {
                try fm.removeItem(at: SageModelFiles.directory)
            }
            try fm.moveItem(at: staging, to: SageModelFiles.directory)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    private nonisolated static func verifyFiles() -> Bool {
        guard SageModelFiles.isInstalled else { return false }
        return SageModelFiles.assets.allSatisfy { asset in
            (try? sha256(of: SageModelFiles.directory.appendingPathComponent(asset.name))) == asset.sha256
        }
    }

    private nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            guard let data = try? handle.read(upToCount: 1024 * 1024), !data.isEmpty else { return false }
            hasher.update(data: data)
            return true
        }) { }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

final class SageTokenizer {
    static let bosID: Int64 = 50357
    static let padID: Int64 = 0
    static let eosID: Int64 = 2

    private let vocab: [String: Int]
    private let tokens: [Int: String]
    private let mergeRanks: [String: Int]
    private let byteEncoder: [UInt8: UnicodeScalar]
    private let byteDecoder: [UnicodeScalar: UInt8]
    private var cache: [String: [String]] = [:]

    init(vocabURL: URL, mergesURL: URL) throws {
        let data = try Data(contentsOf: vocabURL)
        vocab = try JSONDecoder().decode([String: Int].self, from: data)
        tokens = Dictionary(uniqueKeysWithValues: vocab.map { ($0.value, $0.key) })
        var ranks: [String: Int] = [:]
        let merges = try String(contentsOf: mergesURL, encoding: .utf8)
        var rank = 0
        for rawLine in merges.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count == 2 {
                ranks[Self.pairKey(String(parts[0]), String(parts[1]))] = rank
                rank += 1
            }
        }
        mergeRanks = ranks
        byteEncoder = Self.makeByteEncoder()
        byteDecoder = Dictionary(uniqueKeysWithValues: byteEncoder.map { ($0.value, $0.key) })
    }

    func encode(_ text: String) throws -> [Int64] {
        let pattern = "'s|'t|'re|'ve|'m|'ll|'d| ?\\p{L}+| ?\\p{N}+| ?[^\\s\\p{L}\\p{N}]+|\\s+(?!\\S)|\\s+"
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var result = [Self.bosID]
        for match in regex.matches(in: text, range: range) {
            guard let swiftRange = Range(match.range, in: text) else { continue }
            let bytes = String(text[swiftRange]).utf8
            let encoded = String(String.UnicodeScalarView(bytes.compactMap { byteEncoder[$0] }))
            for token in bpe(encoded) {
                guard let id = vocab[token] else { throw CocoaError(.fileReadCorruptFile) }
                result.append(Int64(id))
            }
        }
        return result
    }

    func decode(_ ids: [Int64]) -> String {
        var bytes: [UInt8] = []
        for id in ids where id != Self.bosID && id != Self.padID && id != Self.eosID {
            guard let token = tokens[Int(id)] else { continue }
            bytes.append(contentsOf: token.unicodeScalars.compactMap { byteDecoder[$0] })
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func bpe(_ token: String) -> [String] {
        if let cached = cache[token] { return cached }
        var word = token.unicodeScalars.map(String.init)
        while word.count > 1 {
            var best: (rank: Int, left: String, right: String)?
            for index in 0..<(word.count - 1) {
                guard let rank = mergeRanks[Self.pairKey(word[index], word[index + 1])] else { continue }
                if best == nil || rank < best!.rank { best = (rank, word[index], word[index + 1]) }
            }
            guard let best else { break }
            var merged: [String] = []
            var index = 0
            while index < word.count {
                if index + 1 < word.count, word[index] == best.left, word[index + 1] == best.right {
                    merged.append(best.left + best.right)
                    index += 2
                } else {
                    merged.append(word[index])
                    index += 1
                }
            }
            word = merged
        }
        cache[token] = word
        return word
    }

    private static func pairKey(_ left: String, _ right: String) -> String { left + "\0" + right }

    private static func makeByteEncoder() -> [UInt8: UnicodeScalar] {
        var bytes = Array(33...126) + Array(161...172) + Array(174...255)
        var scalars = bytes
        var extra = 0
        for value in 0...255 where !bytes.contains(value) {
            bytes.append(value)
            scalars.append(256 + extra)
            extra += 1
        }
        var result: [UInt8: UnicodeScalar] = [:]
        for index in bytes.indices {
            result[UInt8(bytes[index])] = UnicodeScalar(scalars[index])!
        }
        return result
    }
}

struct SageTextSegment: Equatable {
    let text: String
    let shouldCorrect: Bool
}

enum SageTextPolicy {
    private static let protectedPattern = "(?i)(?:https?://|www\\.)\\S+|[\\w.+-]+@[\\w.-]+\\.[A-Za-z]{2,}|`[^`\\r\\n]+`|[A-Za-z][A-Za-z0-9_./:@#%+\\-]*"

    static func split(_ text: String) -> [SageTextSegment] {
        guard let regex = try? NSRegularExpression(pattern: protectedPattern) else {
            return [.init(text: text, shouldCorrect: hasCorrectableCyrillic(text))]
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var result: [SageTextSegment] = []
        var cursor = text.startIndex
        for match in regex.matches(in: text, range: range) {
            guard let matchRange = Range(match.range, in: text) else { continue }
            appendCandidate(String(text[cursor..<matchRange.lowerBound]), to: &result)
            result.append(.init(text: String(text[matchRange]), shouldCorrect: false))
            cursor = matchRange.upperBound
        }
        appendCandidate(String(text[cursor...]), to: &result)
        return result
    }

    private static func appendCandidate(_ text: String, to result: inout [SageTextSegment]) {
        guard !text.isEmpty else { return }
        result.append(.init(text: text, shouldCorrect: hasCorrectableCyrillic(text)))
    }

    private static func hasCorrectableCyrillic(_ text: String) -> Bool {
        text.unicodeScalars.lazy.filter { scalar in
            (0x0400...0x052F).contains(Int(scalar.value))
        }.prefix(3).count == 3
    }
}

private actor SageHelperClient {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var bufferedOutput = Data()

    func generate(inputIDs: [Int64]) throws -> [Int64] {
        if process?.isRunning != true { try launch() }
        guard let input, let output else { throw CocoaError(.executableNotLoadable) }
        let request = inputIDs.map(String.init).joined(separator: ",") + "\n"
        try input.write(contentsOf: Data(request.utf8))
        let line = try readLine(from: output)
        if line.hasPrefix("ERR:") { throw CocoaError(.coderInvalidValue) }
        return line.split(separator: ",").compactMap { Int64($0) }
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

    private func launch() throws {
        let bundle = Bundle.main.bundleURL
        let helperURL = ProcessInfo.processInfo.environment["NABIRA_SAGE_HELPER"].map(URL.init(fileURLWithPath:))
            ?? bundle.appendingPathComponent("Contents/Helpers/NabiraSageHelper")
        guard FileManager.default.isExecutableFile(atPath: helperURL.path), SageModelFiles.isInstalled else {
            throw CocoaError(.executableNotLoadable)
        }
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let task = Process()
        task.executableURL = helperURL
        task.arguments = [SageModelFiles.encoder.path, SageModelFiles.decoder.path]
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
                return String(decoding: line, as: UTF8.self)
            }
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                throw NSError(domain: "Nabira.SageHelper", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "AI helper stopped unexpectedly"])
            }
            bufferedOutput.append(chunk)
        }
    }
}

actor SageCorrectionService {
    static let shared = SageCorrectionService()
    private let helper = SageHelperClient()
    private var tokenizer: SageTokenizer?

    func correct(_ text: String) async throws -> String {
        guard SageModelFiles.isInstalled else { throw CocoaError(.fileNoSuchFile) }
        let tokenizer = try tokenizer ?? SageTokenizer(vocabURL: SageModelFiles.vocab, mergesURL: SageModelFiles.merges)
        self.tokenizer = tokenizer
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        var correctedLines: [String] = []
        correctedLines.reserveCapacity(lines.count)
        for line in lines {
            var corrected = ""
            for segment in SageTextPolicy.split(String(line)) {
                if segment.shouldCorrect {
                    let ids = try tokenizer.encode(segment.text)
                    if ids.count <= 220 {
                        let generated = try await helper.generate(inputIDs: ids)
                        let value = tokenizer.decode(generated)
                        corrected += value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? segment.text : value
                    } else {
                        corrected += segment.text
                    }
                } else {
                    corrected += segment.text
                }
            }
            correctedLines.append(corrected)
        }
        return correctedLines.joined(separator: "\n")
    }

    func reset() async {
        tokenizer = nil
        await helper.stop()
    }
}
