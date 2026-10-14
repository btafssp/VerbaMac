import Foundation

/// Latin-only Whitaker’s WORDS fallback parser (SPEC).
///
/// Uses the bundled / override WORDS **binary** (`VERBAMAC_WORDS` or
/// `Resources/WORDS/bin/words`) — stdout parsed by `WordsOutputParser`.
/// No binary or no hit → no analyses.
///
/// Never used for Greek. Glosses are secondary (`Analysis.gloss`); L&S via
/// `LexiconStore` is the definition. Do **not** present the Ada console as UI.
struct WordsParser: Parser {
    /// Optional absolute path to a WORDS executable (tests / injection).
    let binaryURLOverride: URL?

    init(binaryURLOverride: URL? = nil) {
        self.binaryURLOverride = binaryURLOverride
    }

    var isBinaryAvailable: Bool {
        Self.resolveBinaryURL(override: binaryURLOverride) != nil
    }

    var availabilityNote: String {
        if isBinaryAvailable {
            return "WORDS binary ready"
        }
        return "WORDS unavailable — no binary"
    }

    func parse(_ query: String, language: Language) async -> [Analysis] {
        // Latin only — never Greek.
        switch language {
        case .greek:
            return []
        case .latin, .both:
            break
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // If Both and the query is clearly Greek, skip.
        if language == .both, MorphPreprocess.looksGreek(trimmed) {
            return []
        }

        let (stem, _) = MorphPreprocess.stripLatinEnclitic(trimmed)
        let key = MorphPreprocess.latinLookupKey(stem)

        // 1) External / bundled WORDS binary
        if let bin = Self.resolveBinaryURL(override: binaryURLOverride) {
            do {
                let stdout = try await Self.runWords(binary: bin, word: stem)
                let parsed = WordsOutputParser.parse(stdout: stdout, surfaceForm: key)
                if !parsed.isEmpty { return parsed }
            } catch {
                return []
            }
        }
        return []
    }


    // MARK: - Binary

    static func runWords(binary: URL, word: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let text = try launchWords(binary: binary, word: word)
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func launchWords(binary: URL, word: String) throws -> String {
        let process = Process()
        process.executableURL = binary
        // Most WORDS ports accept the word as argv[1]; Ada WORDS is interactive.
        // Prefer non-interactive: word on argv, or stdin. Try argv first.
        process.arguments = [word]
        // Run with cwd = binary’s directory so DICTFILE.GEN etc. resolve.
        process.currentDirectoryURL = binary.deletingLastPathComponent()

        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        // stderr is discarded; a pipe nobody drains concurrently could fill and block the child.
        process.standardError = FileHandle.nullDevice

        // A child that exits before reading stdin would raise SIGPIPE on write and
        // silently terminate the app (no crash report). Ignore it; write throws instead.
        signal(SIGPIPE, SIG_IGN)
        try process.run()

        // Also feed stdin for interactive Ada WORDS (`word` then blank / #).
        if let data = (word + "\n\n").data(using: .utf8) {
            try? stdin.fileHandleForWriting.write(contentsOf: data)
        }
        try? stdin.fileHandleForWriting.close()

        // Bound wait: Ada WORDS may wait for more input.
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            process.waitUntilExit()
            group.leave()
        }
        _ = group.wait(timeout: .now() + 3.0)
        if process.isRunning {
            process.terminate()
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: outData, encoding: .utf8)
            ?? String(data: outData, encoding: .isoLatin1)
            ?? ""
    }

    // MARK: - Path resolution

    static func resolveBinaryURL(override: URL?) -> URL? {
        let fm = FileManager.default
        if let override, fm.isExecutableFile(atPath: override.path) {
            return override
        }
        if let env = ProcessInfo.processInfo.environment["VERBAMAC_WORDS"], !env.isEmpty {
            let url = URL(fileURLWithPath: env)
            if fm.isExecutableFile(atPath: url.path) { return url }
        }
        for root in bundledWORDSRoots() {
            for name in ["words", "WORDS", "whitakers-words"] {
                let bin = root.appendingPathComponent("bin/\(name)", isDirectory: false)
                if fm.isExecutableFile(atPath: bin.path) { return bin }
            }
        }
        return nil
    }

    private static func bundledWORDSRoots() -> [URL] {
        var roots: [URL] = []
        if let res = Bundle.main.resourceURL {
            roots.append(res.appendingPathComponent("WORDS", isDirectory: true))
            roots.append(res)
        }
        #if SWIFT_PACKAGE
        roots.append(Bundle.module.bundleURL.appendingPathComponent("WORDS", isDirectory: true))
        #endif
        if let exec = Bundle.main.executableURL {
            var dir = exec.deletingLastPathComponent()
            for _ in 0..<6 {
                roots.append(dir.appendingPathComponent("Resources/WORDS", isDirectory: true))
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path { break }
                dir = parent
            }
        }
        return roots
    }
}

enum WordsError: Error, LocalizedError {
    case binaryFailed(status: Int32)

    var errorDescription: String? {
        switch self {
        case .binaryFailed(let status):
            return "WORDS exited with status \(status)"
        }
    }
}
