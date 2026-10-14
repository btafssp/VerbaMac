import Foundation
import Darwin

/// Decompress zstd article blobs (SPEC: trained dictionary per language).
///
/// Apple removed `COMPRESSION_ZSTD` from the public Compression.framework API
/// (macOS 27 / Xcode 27 SDK). Runtime decompress uses **libzstd** via `dlopen`
/// (the copy bundled in `Contents/Frameworks` first, then Homebrew/`/usr/local`
/// for development builds). Dictionary frames work when `dictionary` is the trained `zdicts` blob.
enum ZstdCodec: Sendable {
    static func decompress(_ data: Data, dictionary: Data?) -> Data? {
        if data.isEmpty { return nil }
        return LibZstd.shared.decompress(data, dictionary: dictionary)
    }
}

// MARK: - libzstd via dlopen

private final class LibZstd: @unchecked Sendable {
    static let shared = LibZstd()

    private let handle: UnsafeMutableRawPointer?
    private let zstdGetFrameContentSize: @convention(c) (UnsafeRawPointer?, Int) -> UInt64
    private let zstdDecompress: @convention(c) (UnsafeMutableRawPointer?, Int, UnsafeRawPointer?, Int) -> Int
    private let zstdCreateDDict: @convention(c) (UnsafeRawPointer?, Int) -> OpaquePointer?
    private let zstdFreeDDict: @convention(c) (OpaquePointer?) -> Void
    private let zstdDecompressUsingDDict: @convention(c) (
        OpaquePointer?, UnsafeMutableRawPointer?, Int, UnsafeRawPointer?, Int, OpaquePointer?
    ) -> Int
    private let zstdCreateDCtx: @convention(c) () -> OpaquePointer?
    private let zstdFreeDCtx: @convention(c) (OpaquePointer?) -> Void
    private let zstdIsError: @convention(c) (Int) -> UInt32

    private init() {
        // Bundled copy first (signed with the app's Team ID, so hardened-runtime
        // library validation accepts it); system copies only for dev builds.
        let candidates = [
            Bundle.main.privateFrameworksPath.map { $0 + "/libzstd.dylib" },
            Bundle.main.bundlePath + "/Contents/Frameworks/libzstd.dylib",
            Bundle.main.bundlePath + "/Contents/MacOS/libzstd.dylib",
            "/opt/homebrew/lib/libzstd.dylib",
            "/usr/local/lib/libzstd.dylib",
        ].compactMap { $0 }

        var loaded: UnsafeMutableRawPointer?
        for path in candidates {
            if let h = dlopen(path, RTLD_NOW | RTLD_LOCAL) {
                loaded = h
                break
            }
        }
        if loaded == nil {
            loaded = dlopen("libzstd.dylib", RTLD_NOW | RTLD_LOCAL)
        }
        self.handle = loaded

        func sym<T>(_ name: String, as type: T.Type) -> T? {
            guard let loaded else { return nil }
            guard let p = dlsym(loaded, name) else { return nil }
            return unsafeBitCast(p, to: type)
        }

        self.zstdGetFrameContentSize =
            sym("ZSTD_getFrameContentSize", as: (@convention(c) (UnsafeRawPointer?, Int) -> UInt64).self)
            ?? { _, _ in UInt64.max }
        self.zstdDecompress =
            sym("ZSTD_decompress", as: (@convention(c) (UnsafeMutableRawPointer?, Int, UnsafeRawPointer?, Int) -> Int).self)
            ?? { _, _, _, _ in -1 }
        self.zstdCreateDDict =
            sym("ZSTD_createDDict", as: (@convention(c) (UnsafeRawPointer?, Int) -> OpaquePointer?).self)
            ?? { _, _ in nil }
        self.zstdFreeDDict =
            sym("ZSTD_freeDDict", as: (@convention(c) (OpaquePointer?) -> Void).self)
            ?? { _ in }
        self.zstdDecompressUsingDDict =
            sym(
                "ZSTD_decompress_usingDDict",
                as: (@convention(c) (OpaquePointer?, UnsafeMutableRawPointer?, Int, UnsafeRawPointer?, Int, OpaquePointer?) -> Int).self
            ) ?? { _, _, _, _, _, _ in -1 }
        self.zstdCreateDCtx =
            sym("ZSTD_createDCtx", as: (@convention(c) () -> OpaquePointer?).self)
            ?? { nil }
        self.zstdFreeDCtx =
            sym("ZSTD_freeDCtx", as: (@convention(c) (OpaquePointer?) -> Void).self)
            ?? { _ in }
        self.zstdIsError =
            sym("ZSTD_isError", as: (@convention(c) (Int) -> UInt32).self)
            ?? { _ in 1 }
    }

    var isAvailable: Bool { handle != nil }

    func decompress(_ data: Data, dictionary: Data?) -> Data? {
        guard isAvailable else { return nil }

        let contentSize: UInt64 = data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return UInt64.max }
            return zstdGetFrameContentSize(base, data.count)
        }
        // ZSTD_CONTENTSIZE_UNKNOWN == UInt64.max - 1; ERROR == UInt64.max
        var dstCap: Int
        if contentSize < UInt64.max - 1 && contentSize > 0 {
            dstCap = Int(contentSize)
        } else {
            dstCap = max(data.count * 8, 64 * 1024)
        }
        let maxCap = 16 * 1024 * 1024

        while dstCap <= maxCap {
            if let out = decompressOnce(data, dictionary: dictionary, dstCap: dstCap) {
                return out
            }
            if contentSize < UInt64.max - 1 {
                return nil
            }
            dstCap *= 2
        }
        return nil
    }

    private func decompressOnce(_ data: Data, dictionary: Data?, dstCap: Int) -> Data? {
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: dstCap)
        defer { dst.deallocate() }

        let written: Int = data.withUnsafeBytes { srcRaw in
            guard let src = srcRaw.baseAddress else { return -1 }
            if let dictionary, !dictionary.isEmpty {
                return dictionary.withUnsafeBytes { dictRaw -> Int in
                    guard let dictBase = dictRaw.baseAddress else { return -1 }
                    guard let ddict = zstdCreateDDict(dictBase, dictionary.count) else { return -1 }
                    defer { zstdFreeDDict(ddict) }
                    guard let dctx = zstdCreateDCtx() else { return -1 }
                    defer { zstdFreeDCtx(dctx) }
                    return zstdDecompressUsingDDict(dctx, dst, dstCap, src, data.count, ddict)
                }
            }
            return zstdDecompress(dst, dstCap, src, data.count)
        }

        if zstdIsError(written) != 0 || written <= 0 { return nil }
        return Data(bytes: dst, count: written)
    }
}
