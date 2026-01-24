import Foundation

protocol ADBService {
    func isADBAvailable() async -> Bool
    func listDevices() async throws -> [Device]
    func connect(to address: String) async throws
    func disconnect(from address: String) async throws
    func pair(address: String, code: String) async throws
    func getProperty(_ property: String, deviceId: String) async throws -> String
    func getProperties(_ properties: [String], deviceId: String) async throws -> [String: String]
    func shell(_ command: String, deviceId: String) async throws -> String
    func takeScreenshot(deviceId: String) async throws -> Data
    func inputText(_ text: String, deviceId: String) async throws
    func inputKeyEvent(_ keyCode: Int, deviceId: String) async throws
    func listReverseForwards(deviceId: String) async throws -> [PortForward]
    func createReverseForward(localPort: Int, remotePort: Int, deviceId: String) async throws
    func removeReverseForward(localPort: Int, deviceId: String) async throws
    func removeAllReverseForwards(deviceId: String) async throws
    func enableTcpip(port: Int, deviceId: String) async throws
    func installAPK(path: URL, deviceId: String, onStart: @escaping (APKInstallHandle) -> Void, onProgress: @escaping (String) -> Void) async throws
}

final class APKInstallHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var _process: Process?

    func setProcess(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        _process = process
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        guard let process = _process, process.isRunning else { return }
        process.terminate()
    }
}

enum AndroidKeyCode: Int {
    case back = 4
    case home = 3
    case menu = 82
    case volumeUp = 24
    case volumeDown = 25
    case power = 26
    case enter = 66
    case delete = 67
    case tab = 61
}
