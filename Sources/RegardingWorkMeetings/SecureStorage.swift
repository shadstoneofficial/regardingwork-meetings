import Foundation
import Darwin

enum SecureStorage {
    static let directoryMode: Int = 0o700
    static let fileMode: Int = 0o600

    /// Atomically reserve a new audio path. Never truncate a recording or follow a symlink.
    static func reserveNewFile(_ url: URL) throws {
        let descriptor = open(url.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, mode_t(fileMode))
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        close(descriptor)
    }

    static func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: directoryMode)]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: directoryMode)],
            ofItemAtPath: url.path
        )
    }

    static func protectFile(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: fileMode)],
            ofItemAtPath: url.path
        )
    }

    static func write(_ data: Data, to url: URL, atomic: Bool = true) throws {
        try createDirectory(url.deletingLastPathComponent())
        try data.write(to: url, options: atomic ? .atomic : [])
        try protectFile(url)
    }

    static func append(_ data: Data, to url: URL) throws {
        try createDirectory(url.deletingLastPathComponent())
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(
                atPath: url.path,
                contents: nil,
                attributes: [.posixPermissions: NSNumber(value: fileMode)]
            )
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.close()
        try protectFile(url)
    }
}
