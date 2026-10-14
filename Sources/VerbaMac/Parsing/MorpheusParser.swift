import Foundation

/// Primary morphological parser: launches bundled (or override) `cruncher`.
///
/// Invocation (SPEC):
/// - Latin: `cruncher -L -S`
/// - Greek: `cruncher -S` (+ `-n` when ignore-accents preference is on)
///
/// Environment:
/// - `MORPHLIB` → directory containing `Latin/` and `Greek/` stemlibs
/// - `VERBAMAC_MORPHEUS` → optional absolute path to `cruncher` (dev override)
///
/// Greek Unicode input is converted to Beta Code before stdin; lemmas are
/// converted back for display.
struct MorpheusParser: Parser {
    let preferences: ParserPreferences
    /// Optional explicit binary URL (tests / injection).
    let cruncherURLOverride: URL?
    /// Optional explicit MORPHLIB directory.
    let morphlibURLOverride: URL?

    init(
        preferences: ParserPreferences = .default,
        cruncherURLOverride: URL? = nil,
        morphlibURLOverride: URL? = nil
    ) {
        self.preferences = preferences
        self.cruncherURLOverride = cruncherURLOverride
        self.morphlibURLOverride = morphlibURLOverride
    }

    /// Whether a usable cruncher + stemlib appear present (for pipeline gating).
    var isAvailable: Bool {
        Self.resolveCruncherURL(override: cruncherURLOverride) != nil
            && Self.resolveMorphlibURL(override: morphlibURLOverride) != nil
    }

    var availabilityNote: String {
        var missing: [String] = []
        if Self.resolveCruncherURL(override: cruncherURLOverride) == nil {
            missing.append("cruncher binary")
        }
        if Self.resolveMorphlibURL(override: morphlibURLOverride) == nil {
            missing.append("stemlib (Latin/Greek)")
        }
        if missing.isEmpty { return "Morpheus ready" }
        return "Morpheus unavailable — missing: \(missing.joined(separator: ", ")). See Resources/Morpheus/README.md"
    }

    func parse(_ query: String, language: Language) async -> [Analysis] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        guard let cruncher = Self.resolveCruncherURL(override: cruncherURLOverride),
              let morphlib = Self.resolveMorphlibURL(override: morphlibURLOverride) else {
            return []
        }

        let targets = Self.languagesToTry(query: trimmed, filter: language)
        var combined: [Analysis] = []

        for lang in targets {
            let prepared = Self.prepareInput(trimmed, language: lang)
            do {
                let stdout = try await Self.runCruncher(
                    cruncher: cruncher,
                    morphlib: morphlib,
                    language: lang,
                    input: prepared.cruncherInput,
                    ignoreAccents: lang == .greek && preferences.greekIgnoreAccents
                )
                let parsed = MorpheusOutputParser.parse(
                    stdout: stdout,
                    language: lang,
                    surfaceForm: prepared.surfaceForJoin
                )
                combined.append(contentsOf: parsed)
                // Both mode: stop at the first language that parses (Latin wins for "amo").
                if language == .both && !combined.isEmpty { break }
            } catch {
                // Swallow per-language failures; pipeline may fall back.
                continue
            }
        }
        return combined
    }

    // MARK: - Prepare input

    struct PreparedInput: Sendable {
        /// Bytes / string fed to cruncher stdin.
        let cruncherInput: String
        /// Surface used for lexicon join / enclitic awareness.
        let surfaceForJoin: String
    }

    static func prepareInput(_ raw: String, language: LexiconLanguage) -> PreparedInput {
        switch language {
        case .latin:
            let (stem, _) = MorphPreprocess.stripLatinEnclitic(raw)
            // Cruncher wants the surface form (often with original v/j); we still
            // strip enclitics so *que* etc. parse as the host word.
            let input = stem.trimmingCharacters(in: .whitespacesAndNewlines)
            return PreparedInput(cruncherInput: input, surfaceForJoin: MorphPreprocess.latinLookupKey(stem))
        case .greek:
            let nfc = MorphPreprocess.greekNFC(raw)
            let beta = BetaCode.fromGreek(nfc)
            return PreparedInput(cruncherInput: beta, surfaceForJoin: MorphPreprocess.greekBase(nfc))
        }
    }

    static func languagesToTry(query: String, filter: Language) -> [LexiconLanguage] {
        switch filter {
        case .latin: return [.latin]
        case .greek: return [.greek]
        case .both:
            if MorphPreprocess.looksGreek(query) { return [.greek] }
            // Beta Code diacritics ( ) / \\ = | can't be Latin.
            if query.contains(where: { ")(/\\=|".contains($0) }) { return [.greek] }
            // Plain ASCII ("oida", "amo"): Latin first, Greek (Beta Code) if Latin finds nothing.
            return [.latin, .greek]
        }
    }

    // MARK: - Process

    static func runCruncher(
        cruncher: URL,
        morphlib: URL,
        language: LexiconLanguage,
        input: String,
        ignoreAccents: Bool
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try launch(
                        cruncher: cruncher,
                        morphlib: morphlib,
                        language: language,
                        input: input,
                        ignoreAccents: ignoreAccents
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func launch(
        cruncher: URL,
        morphlib: URL,
        language: LexiconLanguage,
        input: String,
        ignoreAccents: Bool
    ) throws -> String {
        let process = Process()
        process.executableURL = cruncher
        var args = ["-S"]
        if language == .latin { args.insert("-L", at: 0) }
        if ignoreAccents { args.append("-n") }
        process.arguments = args
        process.environment = ProcessInfo.processInfo.environment.merging([
            "MORPHLIB": morphlib.path
        ]) { _, new in new }

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

        if let data = (input + "\n").data(using: .utf8) {
            try? stdin.fileHandleForWriting.write(contentsOf: data)
        }
        try? stdin.fileHandleForWriting.close()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        // Non-zero exit can still produce useful stdout; only fail if empty + failed.
        let text = String(data: outData, encoding: .utf8)
            ?? String(data: outData, encoding: .isoLatin1)
            ?? ""
        if process.terminationStatus != 0 && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MorpheusError.cruncherFailed(status: process.terminationStatus)
        }
        return text
    }

    // MARK: - Path resolution

    /// Resolve cruncher: override → `VERBAMAC_MORPHEUS` → bundle `Morpheus/bin/cruncher` → sibling Resources.
    static func resolveCruncherURL(override: URL?) -> URL? {
        if let override, FileManager.default.isExecutableFile(atPath: override.path) {
            return override
        }
        if let env = ProcessInfo.processInfo.environment["VERBAMAC_MORPHEUS"], !env.isEmpty {
            let url = URL(fileURLWithPath: env)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        for candidate in bundledMorpheusRoots() {
            let bin = candidate.appendingPathComponent("bin/cruncher", isDirectory: false)
            if FileManager.default.isExecutableFile(atPath: bin.path) { return bin }
        }
        return nil
    }

    /// Resolve MORPHLIB root (parent of `Latin/` and `Greek/`).
    static func resolveMorphlibURL(override: URL?) -> URL? {
        if let override, hasStemlibs(at: override) { return override }
        if let env = ProcessInfo.processInfo.environment["MORPHLIB"], !env.isEmpty {
            let url = URL(fileURLWithPath: env)
            if hasStemlibs(at: url) { return url }
        }
        // Also allow VERBAMAC_MORPHLIB
        if let env = ProcessInfo.processInfo.environment["VERBAMAC_MORPHLIB"], !env.isEmpty {
            let url = URL(fileURLWithPath: env)
            if hasStemlibs(at: url) { return url }
        }
        for candidate in bundledMorpheusRoots() {
            let stem = candidate.appendingPathComponent("stemlib", isDirectory: true)
            if hasStemlibs(at: stem) { return stem }
        }
        return nil
    }

    private static func hasStemlibs(at url: URL) -> Bool {
        let fm = FileManager.default
        let latin = url.appendingPathComponent("Latin", isDirectory: true)
        let greek = url.appendingPathComponent("Greek", isDirectory: true)
        var isDir: ObjCBool = false
        // Accept if at least one language tree exists (dev may ship one first).
        let latinOK = fm.fileExists(atPath: latin.path, isDirectory: &isDir) && isDir.boolValue
        isDir = false
        let greekOK = fm.fileExists(atPath: greek.path, isDirectory: &isDir) && isDir.boolValue
        return latinOK || greekOK
    }

    private static func bundledMorpheusRoots() -> [URL] {
        var roots: [URL] = []
        // App bundle Resources/Morpheus
        if let res = Bundle.main.resourceURL {
            roots.append(res.appendingPathComponent("Morpheus", isDirectory: true))
            roots.append(res) // in case Morpheus contents are flattened
        }
        // SPM Bundle.module (if resource copied)
        #if SWIFT_PACKAGE
        roots.append(Bundle.module.bundleURL.appendingPathComponent("Morpheus", isDirectory: true))
        #endif
        // Dev: walk up from executable toward repo Resources/Morpheus
        if let exec = Bundle.main.executableURL {
            var dir = exec.deletingLastPathComponent()
            for _ in 0..<6 {
                let candidate = dir.appendingPathComponent("Resources/Morpheus", isDirectory: true)
                roots.append(candidate)
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path { break }
                dir = parent
            }
        }
        return roots
    }
}

enum MorpheusError: Error, LocalizedError {
    case cruncherFailed(status: Int32)
    case missingBinary
    case missingStemlib

    var errorDescription: String? {
        switch self {
        case .cruncherFailed(let status):
            return "cruncher exited with status \(status)"
        case .missingBinary:
            return "cruncher binary not found"
        case .missingStemlib:
            return "MORPHLIB / stemlib not found"
        }
    }
}
