import Foundation

final class ADBServiceImpl: ADBService {
    private let shell: ShellExecuting
    private let settingsStore: SettingsStore
    private var cachedADBPath: String?

    init(shell: ShellExecuting = ShellExecutor(), settingsStore: SettingsStore) {
        self.shell = shell
        self.settingsStore = settingsStore
        self.cachedADBPath = ShellExecutor.findADBPath()
    }

    private func getADBPath() throws -> String {
        if let customPath = settingsStore.settings.effectiveADBPath {
            return customPath
        }
        if let path = cachedADBPath { return path }
        if let path = ShellExecutor.findADBPath() {
            cachedADBPath = path
            return path
        }
        throw ADBError.adbNotFound
    }

    private func adb(_ arguments: [String], timeout: TimeInterval = 30) async throws -> ShellResult {
        let path = try getADBPath()
        return try await shell.execute(path, arguments: arguments, timeout: timeout)
    }

    private func adb(deviceId: String, _ arguments: [String], timeout: TimeInterval = 30) async throws -> ShellResult {
        return try await adb(["-s", deviceId] + arguments, timeout: timeout)
    }

    func isADBAvailable() async -> Bool {
        do {
            let _ = try getADBPath()
            let result = try await adb(["version"])
            return result.isSuccess
        } catch {
            return false
        }
    }

    func listDevices() async throws -> [Device] {
        let result = try await adb(["devices", "-l"])
        guard result.isSuccess else {
            throw ADBError.commandFailed("devices -l", result.exitCode)
        }
        return ADBOutputParser.parseDevicesList(result.output)
    }

    func connect(to address: String) async throws {
        let result = try await adb(["connect", address], timeout: 10)

        if result.output.contains("connected to") || result.output.contains("already connected") {
            return
        }

        if result.output.contains("failed") || result.output.contains("unable") {
            throw ADBError.connectionFailed(result.output)
        }

        if !result.isSuccess {
            throw ADBError.connectionFailed(result.combinedOutput)
        }
    }

    func disconnect(from address: String) async throws {
        let result = try await adb(["disconnect", address])
        if !result.isSuccess && !result.output.contains("disconnected") {
            throw ADBError.commandFailed("disconnect", result.exitCode)
        }
    }

    func pair(address: String, code: String) async throws {
        let result = try await adb(["pair", address, code], timeout: 30)
        let output = result.combinedOutput

        if output.contains("Successfully paired") {
            return
        }

        // Protocol fault = code expired or connection dropped
        if output.contains("protocol fault") || output.contains("couldn't read status") {
            throw ADBError.pairingFailed("Pairing code expired or connection interrupted. Please generate a new code on your device and try again.")
        }

        if output.contains("wrong password") || output.contains("incorrect") {
            throw ADBError.pairingFailed("Incorrect pairing code. Please check the code and try again.")
        }

        if output.contains("Connection refused") {
            throw ADBError.pairingFailed("Connection refused. Ensure Wireless Debugging is enabled and the device is in pairing mode.")
        }

        if output.contains("No route to host") || output.contains("Network is unreachable") {
            throw ADBError.pairingFailed("Cannot reach device. Ensure both devices are on the same network.")
        }

        if output.contains("Failed") || output.contains("failed") || output.contains("error") {
            throw ADBError.pairingFailed(output)
        }

        if !result.isSuccess {
            throw ADBError.pairingFailed(output)
        }
    }

    func getProperty(_ property: String, deviceId: String) async throws -> String {
        let result = try await adb(deviceId: deviceId, ["shell", "getprop", property])
        if !result.isSuccess {
            throw ADBError.commandFailed("getprop \(property)", result.exitCode)
        }
        return result.output
    }

    func getProperties(_ properties: [String], deviceId: String) async throws -> [String: String] {
        var results: [String: String] = [:]

        try await withThrowingTaskGroup(of: (String, String).self) { group in
            for property in properties {
                group.addTask {
                    let value = try await self.getProperty(property, deviceId: deviceId)
                    return (property, value)
                }
            }
            for try await (property, value) in group {
                results[property] = value
            }
        }

        return results
    }

    func shell(_ command: String, deviceId: String) async throws -> String {
        let result = try await adb(deviceId: deviceId, ["shell", command])
        if !result.isSuccess {
            throw ADBError.commandFailed("shell \(command)", result.exitCode)
        }
        return result.output
    }

    func takeScreenshot(deviceId: String) async throws -> Data {
        let path = try getADBPath()
        let data = try await shell.executeRaw(path, arguments: ["-s", deviceId, "exec-out", "screencap", "-p"], timeout: 30)

        if data.isEmpty {
            throw ADBError.commandFailed("screencap", -1)
        }

        return data
    }

    func inputText(_ text: String, deviceId: String) async throws {
        // Escape special shell chars for `input text`
        let escaped = text
            .replacingOccurrences(of: " ", with: "%s")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "&", with: "\\&")
            .replacingOccurrences(of: "<", with: "\\<")
            .replacingOccurrences(of: ">", with: "\\>")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")

        let result = try await adb(deviceId: deviceId, ["shell", "input", "text", escaped])
        if !result.isSuccess {
            throw ADBError.commandFailed("input text", result.exitCode)
        }
    }

    func inputKeyEvent(_ keyCode: Int, deviceId: String) async throws {
        let result = try await adb(deviceId: deviceId, ["shell", "input", "keyevent", String(keyCode)])
        if !result.isSuccess {
            throw ADBError.commandFailed("input keyevent \(keyCode)", result.exitCode)
        }
    }

    func listReverseForwards(deviceId: String) async throws -> [PortForward] {
        let result = try await adb(deviceId: deviceId, ["reverse", "--list"])
        if !result.isSuccess && !result.output.isEmpty {
            throw ADBError.commandFailed("reverse --list", result.exitCode)
        }
        return ADBOutputParser.parseReverseList(result.output, deviceId: deviceId)
    }

    func createReverseForward(localPort: Int, remotePort: Int, deviceId: String) async throws {
        let result = try await adb(deviceId: deviceId, ["reverse", "tcp:\(localPort)", "tcp:\(remotePort)"])
        if !result.isSuccess {
            throw ADBError.commandFailed("reverse tcp:\(localPort) tcp:\(remotePort)", result.exitCode)
        }
    }

    func removeReverseForward(localPort: Int, deviceId: String) async throws {
        let result = try await adb(deviceId: deviceId, ["reverse", "--remove", "tcp:\(localPort)"])
        if !result.isSuccess {
            throw ADBError.commandFailed("reverse --remove tcp:\(localPort)", result.exitCode)
        }
    }

    func removeAllReverseForwards(deviceId: String) async throws {
        let result = try await adb(deviceId: deviceId, ["reverse", "--remove-all"])
        if !result.isSuccess {
            throw ADBError.commandFailed("reverse --remove-all", result.exitCode)
        }
    }

    func enableTcpip(port: Int, deviceId: String) async throws {
        let result = try await adb(deviceId: deviceId, ["tcpip", String(port)])
        if !result.isSuccess {
            throw ADBError.commandFailed("tcpip \(port)", result.exitCode)
        }
    }
}
