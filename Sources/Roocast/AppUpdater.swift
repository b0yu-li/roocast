import AppKit
import Foundation
import CryptoKit
import Security

/// Downloads, verifies, and installs a notarized Roocast DMG over the running bundle.
///
/// User-initiated only — never called from launch/timers. No Sparkle.
enum AppUpdater {
    enum UpdaterError: LocalizedError {
        case badFeed
        case downloadFailed
        case cancelled
        case sha256Mismatch
        case mountFailed
        case appNotFoundInDMG
        case codeInvalid
        case teamMismatch
        case bundleIDMismatch
        case helperFailed(String)

        var errorDescription: String? {
            switch self {
            case .badFeed: return "The update feed is incomplete or unsigned."
            case .downloadFailed: return "The download failed."
            case .cancelled: return "The update was cancelled."
            case .sha256Mismatch: return "The downloaded file failed its integrity check."
            case .mountFailed: return "Couldn’t open the disk image."
            case .appNotFoundInDMG: return "Roocast.app was not found in the disk image."
            case .codeInvalid: return "The update’s code signature is invalid."
            case .teamMismatch: return "The update was not signed by Rooby Studio."
            case .bundleIDMismatch: return "The update has the wrong application identity."
            case .helperFailed(let detail): return detail
            }
        }
    }

    /// Progress 0…1 while downloading.
    typealias ProgressHandler = @Sendable (Double) -> Void

    // MARK: - SHA-256

    nonisolated static func sha256Hex(ofFile url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func verifySHA256(file: URL, expectedHex: String) throws {
        let actual = try sha256Hex(ofFile: file)
        guard actual.lowercased() == expectedHex.lowercased() else {
            throw UpdaterError.sha256Mismatch
        }
    }

    // MARK: - Download

    static func download(
        from remote: URL,
        to local: URL,
        session: URLSession = .shared,
        progress: ProgressHandler? = nil
    ) async throws {
        try FileManager.default.createDirectory(
            at: local.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: local.path) {
            try FileManager.default.removeItem(at: local)
        }

        let (byteStream, response) = try await session.bytes(for: URLRequest(url: remote))
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw UpdaterError.downloadFailed
        }
        let expected = response.expectedContentLength
        FileManager.default.createFile(atPath: local.path, contents: nil)
        let handle = try FileHandle(forWritingTo: local)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        var written: Int64 = 0
        for try await byte in byteStream {
            try Task.checkCancellation()
            buffer.append(byte)
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if let progress, expected > 0 {
                    progress(min(1, Double(written) / Double(expected)))
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
        }
        progress?(1)
        guard written > 0 else { throw UpdaterError.downloadFailed }
    }

    // MARK: - Mount

    nonisolated static func mountAndLocateApp(dmgURL: URL) throws -> (mountPoint: URL, appURL: URL) {
        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("roocast-upd-mnt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        let attach = Process()
        attach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attach.arguments = [
            "attach", dmgURL.path,
            "-nobrowse", "-readonly",
            "-mountpoint", mountPoint.path,
        ]
        attach.standardOutput = FileHandle.nullDevice
        attach.standardError = FileHandle.nullDevice
        try attach.run()
        attach.waitUntilExit()
        guard attach.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: mountPoint)
            throw UpdaterError.mountFailed
        }

        let appURL = mountPoint.appendingPathComponent("Roocast.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            detach(mountPoint: mountPoint)
            throw UpdaterError.appNotFoundInDMG
        }
        return (mountPoint, appURL)
    }

    nonisolated static func detach(mountPoint: URL) {
        let detach = Process()
        detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        detach.arguments = ["detach", mountPoint.path, "-quiet"]
        detach.standardOutput = FileHandle.nullDevice
        detach.standardError = FileHandle.nullDevice
        try? detach.run()
        detach.waitUntilExit()
    }

    // MARK: - Code signing

    nonisolated static func runningTeamID() -> String? {
        teamID(for: Bundle.main.bundleURL)
    }

    nonisolated static func teamID(for appURL: URL) -> String? {
        var staticCode: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode)
        guard status == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &info
        )
        guard infoStatus == errSecSuccess,
              let dict = info as? [String: Any],
              let team = dict[kSecCodeInfoTeamIdentifier as String] as? String
        else {
            return nil
        }
        return team
    }

    nonisolated static func verifyIncomingApp(_ appURL: URL) throws {
        var staticCode: SecStaticCode?
        let create = SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode)
        guard create == errSecSuccess, let staticCode else {
            throw UpdaterError.codeInvalid
        }
        let validity = SecStaticCodeCheckValidity(
            staticCode,
            SecCSFlags(rawValue: kSecCSCheckAllArchitectures),
            nil
        )
        guard validity == errSecSuccess else {
            throw UpdaterError.codeInvalid
        }

        // Identity must match *this* running build — no hardcoded bundle id / Team ID in source.
        guard let expectedID = Bundle.main.bundleIdentifier,
              let incomingID = Bundle(url: appURL)?.bundleIdentifier,
              incomingID == expectedID
        else {
            throw UpdaterError.bundleIDMismatch
        }

        // Production builds always have a Team ID; require the update match it.
        // Adhoc/dev builds (no Team ID) skip this check — code validity + bundle id remain.
        if let expectedTeam = runningTeamID() {
            guard let incomingTeam = teamID(for: appURL), incomingTeam == expectedTeam else {
                throw UpdaterError.teamMismatch
            }
        }
    }

    // MARK: - Writability

    nonisolated static func installNeedsAdmin(destApp: URL) -> Bool {
        let parent = destApp.deletingLastPathComponent()
        let probe = parent.appendingPathComponent(".roocast-write-probe-\(UUID().uuidString)")
        do {
            try Data().write(to: probe)
            try FileManager.default.removeItem(at: probe)
            return false
        } catch {
            return true
        }
    }

    // MARK: - Cache paths

    nonisolated static var updatesDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Roocast/updates", isDirectory: true)
    }

    // MARK: - Helper + quit

    nonisolated static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated static func makeReplaceScript(
        pid: Int32,
        sourceApp: String,
        destApp: String,
        mountPoint: String,
        dmgFile: String,
        logPath: String,
        needsAdmin: Bool
    ) -> String {
        let src = shellQuote(sourceApp)
        let dest = shellQuote(destApp)
        let mount = shellQuote(mountPoint)
        let dmg = shellQuote(dmgFile)
        let log = shellQuote(logPath)
        let destNext = shellQuote(destApp + ".next")
        let destBak = shellQuote(destApp + ".bak")

        let swapLine =
            "rm -rf \(destNext) \(destBak); "
            + "/usr/bin/ditto \(src) \(destNext); "
            + "if [ -e \(dest) ]; then mv \(dest) \(destBak); fi; "
            + "mv \(destNext) \(dest); "
            + "xattr -dr com.apple.quarantine \(dest) 2>/dev/null || true; "
            + "rm -rf \(destBak)"

        let swapBlock: String
        if needsAdmin {
            let escaped = swapLine
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            swapBlock = """
            if ! /usr/bin/osascript -e "do shell script \\"\(escaped)\\" with administrator privileges"; then
              echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) admin swap failed" >> \(log)
              if [ -d \(destBak) ]; then rm -rf \(dest); mv \(destBak) \(dest); fi
              /usr/bin/open \(dest) || true
              /usr/bin/hdiutil detach \(mount) -quiet 2>/dev/null || true
              rm -f \(dmg)
              exit 1
            fi
            """
        } else {
            swapBlock = """
            if ! (\(swapLine)); then
              echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) swap failed" >> \(log)
              if [ -d \(destBak) ]; then rm -rf \(dest); mv \(destBak) \(dest); fi
              /usr/bin/open \(dest) || true
              /usr/bin/hdiutil detach \(mount) -quiet 2>/dev/null || true
              rm -f \(dmg)
              exit 1
            fi
            """
        }

        return """
        #!/bin/bash
        set -euo pipefail
        mkdir -p "$(dirname \(log))"
        for _ in $(seq 1 100); do
          if ! kill -0 \(pid) 2>/dev/null; then break; fi
          sleep 0.1
        done
        sleep 0.3
        \(swapBlock)
        /usr/bin/hdiutil detach \(mount) -quiet 2>/dev/null || true
        rm -f \(dmg)
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) update installed" >> \(log)
        /usr/bin/open \(dest)
        rm -f "$0"
        """
    }

    /// Writes the post-quit helper and launches it, then terminates this process.
    @MainActor
    static func scheduleReplaceAndTerminate(
        sourceApp: URL,
        destApp: URL,
        mountPoint: URL,
        dmgFile: URL,
        needsAdmin: Bool
    ) throws {
        let dir = updatesDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let scriptURL = dir.appendingPathComponent(
            "replace-\(ProcessInfo.processInfo.processIdentifier).sh"
        )
        let logURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Roocast/update.log")

        let script = makeReplaceScript(
            pid: ProcessInfo.processInfo.processIdentifier,
            sourceApp: sourceApp.path,
            destApp: destApp.path,
            mountPoint: mountPoint.path,
            dmgFile: dmgFile.path,
            logPath: logURL.path,
            needsAdmin: needsAdmin
        )
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        NSApplication.shared.terminate(nil)
    }

    /// Full install pipeline after the user confirms Install Update.
    @MainActor
    static func install(
        latest: String,
        dmgURL: URL,
        expectedSHA256: String,
        progress: ProgressHandler? = nil
    ) async throws {
        let dmgLocal = updatesDirectory.appendingPathComponent("Roocast-\(latest).dmg")
        do {
            try await download(from: dmgURL, to: dmgLocal, progress: progress)
            try verifySHA256(file: dmgLocal, expectedHex: expectedSHA256)
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: dmgLocal)
            throw UpdaterError.cancelled
        }

        let (mountPoint, appURL) = try mountAndLocateApp(dmgURL: dmgLocal)
        do {
            try verifyIncomingApp(appURL)
        } catch {
            detach(mountPoint: mountPoint)
            throw error
        }

        let dest = Bundle.main.bundleURL
        let needsAdmin = installNeedsAdmin(destApp: dest)
        try scheduleReplaceAndTerminate(
            sourceApp: appURL,
            destApp: dest,
            mountPoint: mountPoint,
            dmgFile: dmgLocal,
            needsAdmin: needsAdmin
        )
    }
}
