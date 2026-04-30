import Foundation
import CryptoKit

private nonisolated final class LANProcessCaptureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Data()

    func store(_ newValue: Data) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func load() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// File/folder packaging helpers for LAN transfer.
///
/// We intentionally rely on `/usr/bin/ditto` because it:
/// - Supports directories/app bundles/packages reliably on macOS.
/// - Preserves resource forks / extended attributes when asked.
/// - Is available on every macOS install.
nonisolated enum LANFileArchiver {
    nonisolated static let extractionStagingPrefix = ".lan-extracting-"

    private struct ArchiveEntry {
        let rawPath: String
        let normalizedPath: String
        let isSymbolicLink: Bool
    }

    private struct ExtractionDestinationState {
        let existed: Bool
        let wasEmptyDirectory: Bool
    }

    // MARK: - Sanitization

    nonisolated static func safeTransferComponent(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))

        var scalars: [UnicodeScalar] = []
        scalars.reserveCapacity(trimmed.unicodeScalars.count)
        for scalar in trimmed.unicodeScalars {
            scalars.append(allowed.contains(scalar) ? scalar : "_")
        }

        var sanitized = String(String.UnicodeScalarView(scalars))
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "._-"))

        if sanitized.isEmpty { sanitized = "transfer" }
        if sanitized.count > 64 { sanitized = String(sanitized.prefix(64)) }

        if sanitized != trimmed {
            let digest = SHA256.hash(data: Data(trimmed.utf8))
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            sanitized += "-" + hex.prefix(8)
        }
        return sanitized
    }

    nonisolated static func safeFileName(_ raw: String, defaultName: String = "payload.bin") -> String {
        let fallbackRaw = defaultName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = (fallbackRaw.isEmpty || fallbackRaw == "." || fallbackRaw == "..") ? "payload.bin" : fallbackRaw

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_. "))
        var scalars: [UnicodeScalar] = []
        scalars.reserveCapacity(trimmed.unicodeScalars.count)
        for scalar in trimmed.unicodeScalars {
            scalars.append(allowed.contains(scalar) ? scalar : "_")
        }

        var sanitized = String(String.UnicodeScalarView(scalars))
        sanitized = sanitized.replacingOccurrences(of: "..", with: "_")
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
        if sanitized.isEmpty || sanitized == "." { return fallback }
        if sanitized.count > 128 { sanitized = String(sanitized.prefix(128)) }
        return sanitized
    }

    nonisolated private static func isSubpath(_ url: URL, of base: URL) -> Bool {
        let basePath = base.standardizedFileURL.path
        let targetPath = url.standardizedFileURL.path
        if targetPath == basePath { return true }
        let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"
        return targetPath.hasPrefix(prefix)
    }

    @discardableResult
    nonisolated private static func validateArchiveEntries(at archiveURL: URL) throws -> [ArchiveEntry] {
        let entries = try readArchiveEntries(at: archiveURL)
        let symlinkEntries = entries.filter(\.isSymbolicLink)
        var seenPaths = Set<String>()

        for entry in entries {
            guard seenPaths.insert(entry.normalizedPath).inserted else {
                throw NSError(
                    domain: "LANFileArchiver",
                    code: -30,
                    userInfo: [NSLocalizedDescriptionKey: "Archive contains duplicate entry path: \(entry.rawPath)"]
                )
            }
        }

        for entry in entries {
            for symlink in symlinkEntries where entry.normalizedPath != symlink.normalizedPath {
                let prefix = symlink.normalizedPath + "/"
                guard !entry.normalizedPath.hasPrefix(prefix) else {
                    throw NSError(
                        domain: "LANFileArchiver",
                        code: -27,
                        userInfo: [NSLocalizedDescriptionKey: "Archive entry would be written through a symlink: \(entry.rawPath)"]
                    )
                }
            }
        }

        return entries
    }

    nonisolated private static func readArchiveEntries(at archiveURL: URL) throws -> [ArchiveEntry] {
        var lastErrorMessage = "No available archive listing tool"

        if FileManager.default.fileExists(atPath: "/usr/bin/zipinfo") {
            do {
                let output = try runProcessAndCaptureStdout(
                    executablePath: "/usr/bin/zipinfo",
                    arguments: ["-l", archiveURL.path]
                )
                let entries = try parseZipInfoLongListing(output)
                if !entries.isEmpty {
                    return entries
                }
            } catch {
                lastErrorMessage = String(describing: error)
            }
        }

        let candidateTools: [(path: String, args: [String])] = [
            ("/usr/bin/zipinfo", ["-1", archiveURL.path]),
            ("/usr/bin/unzip", ["-Z1", archiveURL.path])
        ]

        for tool in candidateTools where FileManager.default.fileExists(atPath: tool.path) {
            do {
                let output = try runProcessAndCaptureStdout(executablePath: tool.path, arguments: tool.args)
                return try output
                    .split(whereSeparator: \.isNewline)
                    .map { raw in
                        let rawPath = String(raw)
                        let normalizedPath = try normalizeArchiveEntryPath(rawPath)
                        return ArchiveEntry(
                            rawPath: rawPath,
                            normalizedPath: normalizedPath,
                            isSymbolicLink: false
                        )
                    }
            } catch {
                lastErrorMessage = String(describing: error)
            }
        }

        if FileManager.default.fileExists(atPath: "/usr/bin/zipinfo") ||
            FileManager.default.fileExists(atPath: "/usr/bin/unzip") {
            throw NSError(
                domain: "LANFileArchiver",
                code: -21,
                userInfo: [NSLocalizedDescriptionKey: "Failed to inspect archive entries: \(lastErrorMessage)"]
            )
        }

        throw NSError(
            domain: "LANFileArchiver",
            code: -21,
            userInfo: [NSLocalizedDescriptionKey: "Failed to inspect archive entries: \(lastErrorMessage)"]
        )
    }

    nonisolated private static func parseZipInfoLongListing(_ output: String) throws -> [ArchiveEntry] {
        var entries: [ArchiveEntry] = []

        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            let parts = line.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: true)
            guard parts.count == 10 else { continue }

            let permissions = String(parts[0])
            guard permissions.count == 10,
                  let kind = permissions.first,
                  kind == "-" || kind == "d" || kind == "l" else { continue }

            let rawPath = String(parts[9])
            let normalizedPath = try normalizeArchiveEntryPath(rawPath)
            entries.append(
                ArchiveEntry(
                    rawPath: rawPath,
                    normalizedPath: normalizedPath,
                    isSymbolicLink: kind == "l"
                )
            )
        }

        return entries
    }

    nonisolated private static func normalizeArchiveEntryPath(_ rawPath: String) throws -> String {
        let normalized = rawPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
            .replacingOccurrences(of: "\\", with: "/")

        if normalized.isEmpty ||
            normalized.hasPrefix("/") ||
            normalized.hasPrefix("~") ||
            normalized.contains("\0") {
            throw NSError(
                domain: "LANFileArchiver",
                code: -22,
                userInfo: [NSLocalizedDescriptionKey: "Unsafe archive entry path: \(rawPath)"]
            )
        }

        let components = normalized.split(separator: "/", omittingEmptySubsequences: true)
        if components.isEmpty ||
            components.contains(".") ||
            components.contains("..") {
            throw NSError(
                domain: "LANFileArchiver",
                code: -23,
                userInfo: [NSLocalizedDescriptionKey: "Archive entry contains path traversal: \(rawPath)"]
            )
        }

        return components.joined(separator: "/")
    }

    @discardableResult
    nonisolated private static func validateSymlinkTarget(
        _ rawTarget: String,
        linkArchivePath: String,
        errorCode: Int,
        errorDescription: String
    ) throws -> String {
        guard !rawTarget.contains("\0"),
              !rawTarget.contains("\r"),
              !rawTarget.contains("\n") else {
            throw NSError(
                domain: "LANFileArchiver",
                code: errorCode,
                userInfo: [NSLocalizedDescriptionKey: errorDescription]
            )
        }

        let target = rawTarget.replacingOccurrences(of: "\\", with: "/")

        guard !target.isEmpty,
              !target.hasPrefix("/"),
              !target.hasPrefix("~"),
              !target.contains("\0") else {
            throw NSError(
                domain: "LANFileArchiver",
                code: errorCode,
                userInfo: [NSLocalizedDescriptionKey: errorDescription]
            )
        }

        var normalizedComponents = linkArchivePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .dropLast()
            .map(String.init)

        for component in target.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
            if component.isEmpty || component == "." {
                continue
            }
            if component == ".." {
                guard !normalizedComponents.isEmpty else {
                    throw NSError(
                        domain: "LANFileArchiver",
                        code: errorCode,
                        userInfo: [NSLocalizedDescriptionKey: errorDescription]
                    )
                }
                normalizedComponents.removeLast()
                continue
            }
            normalizedComponents.append(component)
        }

        return normalizedComponents.joined(separator: "/")
    }

    nonisolated private static func validateExtractedTree(at destinationDirectory: URL) throws {
        let base = destinationDirectory.standardizedFileURL
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: destinationDirectory,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ) else { return }

        for case let itemURL as URL in enumerator {
            let standardized = itemURL.standardizedFileURL
            guard isSubpath(standardized, of: base) else {
                throw NSError(
                    domain: "LANFileArchiver",
                    code: -24,
                    userInfo: [NSLocalizedDescriptionKey: "Extracted file escaped destination directory"]
                )
            }

            let values = try? standardized.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                let basePath = base.path
                let itemPath = standardized.path
                let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"
                let relativePath = itemPath.hasPrefix(prefix) ? String(itemPath.dropFirst(prefix.count)) : standardized.lastPathComponent
                let target = try fm.destinationOfSymbolicLink(atPath: standardized.path)
                try validateSymlinkTarget(
                    target,
                    linkArchivePath: relativePath,
                    errorCode: -25,
                    errorDescription: "Unsafe symlink detected in extracted archive"
                )
            }
        }
    }

    // MARK: - Paths

    nonisolated private static var baseTempDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("deck-lan-transfer", isDirectory: true)
    }

    nonisolated private static func ensureBaseTempDirectory() throws {
        let dir = baseTempDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Public API

    /// Creates a zip archive containing the provided file/folder paths.
    /// Returns the URL to the zip file.
    nonisolated static func createArchive(fromPaths paths: [String], transferId: String) throws -> URL {
        try ensureBaseTempDirectory()

        let workDir = baseTempDirectory.appendingPathComponent(safeTransferComponent(transferId), isDirectory: true)
        let payloadDir = workDir.appendingPathComponent("payload", isDirectory: true)

        // Clean old artifacts if any.
        if FileManager.default.fileExists(atPath: workDir.path) {
            try? FileManager.default.removeItem(at: workDir)
        }

        try FileManager.default.createDirectory(at: payloadDir, withIntermediateDirectories: true)

        // Stage files into a single folder so we can archive multiple items.
        for rawPath in paths {
            let srcURL = URL(fileURLWithPath: rawPath)
            let dstURL = uniqueDestination(for: srcURL, in: payloadDir)
            try copyItem(at: srcURL, to: dstURL)
        }

        let zipURL = workDir.appendingPathComponent("payload.zip")

        // `ditto -c -k` creates zip. `--sequesterRsrc` keeps resource forks separate.
        // We intentionally DO NOT use `--keepParent` so the zip root contains the items directly.
        try runDitto(arguments: ["-c", "-k", "--sequesterRsrc", payloadDir.path, zipURL.path])

        return zipURL
    }

    /// Extract a zip archive into destination directory.
    nonisolated static func extractArchive(at archiveURL: URL, to destinationDirectory: URL) throws {
        let fm = FileManager.default
        let destination = destinationDirectory.standardizedFileURL
        let parent = destination.deletingLastPathComponent()
        let destinationState = try inspectExtractionDestination(destination)
        var stagingDirectory: URL?

        do {
            try validateArchiveEntries(at: archiveURL)
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)

            let staging = uniqueExtractionStagingDirectory(in: parent, destinationName: destination.lastPathComponent)
            stagingDirectory = staging
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)

            try runDitto(arguments: ["-x", "-k", archiveURL.path, staging.path])
            try validateExtractedTree(at: staging)
            try promoteExtractedStaging(staging, to: destination)
        } catch {
            if let stagingDirectory {
                removeItemReportingFailure(stagingDirectory, context: "staging extraction after failed archive receive")
            }
            cleanupDestinationAfterFailedExtraction(destination, state: destinationState)
            throw error
        }
    }

    /// Writes bytes to a temp file inside a per-transfer working directory.
    nonisolated static func writeTempFile(_ data: Data, transferId: String, fileName: String = "payload.bin") throws -> URL {
        try ensureBaseTempDirectory()

        let workDir = baseTempDirectory.appendingPathComponent(safeTransferComponent(transferId), isDirectory: true)
        if !FileManager.default.fileExists(atPath: workDir.path) {
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        }

        let fileURL = workDir.appendingPathComponent(safeFileName(fileName, defaultName: "payload.bin"))
        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    /// Moves MCSession's received temp file to a stable temp folder we control.
    ///
    /// MCSession may remove `localURL` after the delegate callback returns, so we must claim it.
    nonisolated static func claimReceivedResource(at localURL: URL, transferId: String) throws -> URL {
        try ensureBaseTempDirectory()

        let safeTransferId = safeTransferComponent(transferId)
        let workDir = baseTempDirectory.appendingPathComponent("received-\(safeTransferId)", isDirectory: true)
        if FileManager.default.fileExists(atPath: workDir.path) {
            try? FileManager.default.removeItem(at: workDir)
        }
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let destURL = workDir.appendingPathComponent(safeFileName(localURL.lastPathComponent, defaultName: "payload.bin"))
        if FileManager.default.fileExists(atPath: destURL.path) {
            try? FileManager.default.removeItem(at: destURL)
        }

        try FileManager.default.moveItem(at: localURL, to: destURL)
        return destURL
    }

    /// Best-effort cleanup. If the artifact is in our temp base directory, we delete the whole per-transfer folder.
    nonisolated static func cleanupTempArtifact(at artifactURL: URL) throws {
        let base = baseTempDirectory.standardizedFileURL
        let artifact = artifactURL.standardizedFileURL
        let dir = artifact.deletingLastPathComponent().standardizedFileURL

        if isSubpath(dir, of: base), dir.path != base.path {
            try? FileManager.default.removeItem(at: dir)
            return
        }
        if isSubpath(artifact, of: base) {
            try? FileManager.default.removeItem(at: artifact)
            return
        }
        try? FileManager.default.removeItem(at: artifactURL)
    }

    nonisolated static func cleanupFailedReceiveDirectory(at directoryURL: URL, context: String) {
        removeItemReportingFailure(directoryURL, context: context)
    }

    // MARK: - Internals

    nonisolated private static func uniqueDestination(for srcURL: URL, in directory: URL) -> URL {
        let fm = FileManager.default
        let baseName = srcURL.lastPathComponent

        var candidate = directory.appendingPathComponent(baseName)
        if !fm.fileExists(atPath: candidate.path) {
            return candidate
        }

        let ext = srcURL.pathExtension
        let stem = (ext.isEmpty ? baseName : String(baseName.dropLast(ext.count + 1)))

        var i = 2
        while true {
            let name = ext.isEmpty ? "\(stem)-\(i)" : "\(stem)-\(i).\(ext)"
            candidate = directory.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            i += 1
        }
    }

    nonisolated private static func copyItem(at source: URL, to destination: URL) throws {
        // `ditto` copies both files and directories recursively.
        try runDitto(arguments: [source.path, destination.path])
    }

    nonisolated private static func inspectExtractionDestination(_ destination: URL) throws -> ExtractionDestinationState {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        let existed = fm.fileExists(atPath: destination.path, isDirectory: &isDirectory)
        guard existed, isDirectory.boolValue else {
            return ExtractionDestinationState(existed: existed, wasEmptyDirectory: false)
        }

        let contents = try fm.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: nil,
            options: []
        )
        return ExtractionDestinationState(existed: true, wasEmptyDirectory: contents.isEmpty)
    }

    nonisolated private static func uniqueExtractionStagingDirectory(in parent: URL, destinationName: String) -> URL {
        parent.appendingPathComponent(
            "\(extractionStagingPrefix)\(safeTransferComponent(destinationName))-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    nonisolated private static func promoteExtractedStaging(_ staging: URL, to destination: URL) throws {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: destination.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw NSError(
                    domain: "LANFileArchiver",
                    code: -28,
                    userInfo: [NSLocalizedDescriptionKey: "Archive extraction destination is not a directory"]
                )
            }

            let contents = try fm.contentsOfDirectory(
                at: destination,
                includingPropertiesForKeys: nil,
                options: []
            )
            guard contents.isEmpty else {
                throw NSError(
                    domain: "LANFileArchiver",
                    code: -29,
                    userInfo: [NSLocalizedDescriptionKey: "Archive extraction destination is not empty"]
                )
            }
            try fm.removeItem(at: destination)
        }

        try fm.moveItem(at: staging, to: destination)
    }

    nonisolated private static func cleanupDestinationAfterFailedExtraction(
        _ destination: URL,
        state: ExtractionDestinationState
    ) {
        guard !state.existed || state.wasEmptyDirectory else { return }
        removeItemReportingFailure(destination, context: "failed archive receive destination")
    }

    nonisolated private static func removeItemReportingFailure(_ url: URL, context: String) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Task { @MainActor in
                await log.warn("LANFileArchiver: failed to remove \(context) at \(url.path): \(error.localizedDescription)")
            }
        }
    }

    nonisolated private static func runDitto(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments

        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errString = String(data: errData, encoding: .utf8) ?? "Unknown error"
            throw NSError(
                domain: "LANFileArchiver",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "ditto failed (\(process.terminationStatus)): \(errString)"]
            )
        }
    }

    nonisolated private static func runProcessAndCaptureStdout(executablePath: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let stdoutHandle = stdout.fileHandleForReading
        let stderrHandle = stderr.fileHandleForReading
        let maxCaptureBytes = 8 * 1024 * 1024  // 8 MB
        let outData = LANProcessCaptureBox()
        let errData = LANProcessCaptureBox()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            var local = Data()
            while true {
                let chunk = stdoutHandle.availableData
                if chunk.isEmpty { break }
                if local.count < maxCaptureBytes {
                    let remaining = maxCaptureBytes - local.count
                    if remaining > 0 {
                        local.append(chunk.prefix(remaining))
                    }
                }
                // Drain to EOF even after reaching the capture cap.
            }
            outData.store(local)
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            var local = Data()
            while true {
                let chunk = stderrHandle.availableData
                if chunk.isEmpty { break }
                if local.count < maxCaptureBytes {
                    let remaining = maxCaptureBytes - local.count
                    if remaining > 0 {
                        local.append(chunk.prefix(remaining))
                    }
                }
                // Drain to EOF even after reaching the capture cap.
            }
            errData.store(local)
            group.leave()
        }

        do {
            try process.run()
        } catch {
            try? stdout.fileHandleForWriting.close()
            try? stderr.fileHandleForWriting.close()
            group.wait()
            try? stdoutHandle.close()
            try? stderrHandle.close()
            throw error
        }

        try? stdout.fileHandleForWriting.close()
        try? stderr.fileHandleForWriting.close()
        process.waitUntilExit()
        group.wait()
        try? stdoutHandle.close()
        try? stderrHandle.close()

        if process.terminationStatus != 0 {
            let errString = String(data: errData.load(), encoding: .utf8) ?? "Unknown error"
            throw NSError(
                domain: "LANFileArchiver",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "\(executablePath) failed (\(process.terminationStatus)): \(errString)"]
            )
        }
        return String(data: outData.load(), encoding: .utf8) ?? ""
    }
}
