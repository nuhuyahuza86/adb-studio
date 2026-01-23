import Foundation

struct DiscoveredDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let host: String
    var services: [ServiceInfo]
    var isPaired: Bool
    var isConnecting: Bool = false

    struct ServiceInfo: Equatable {
        let type: ServiceType
        let port: Int
    }

    enum ServiceType: String {
        case adbTlsConnect = "_adb-tls-connect._tcp."
        case adbTlsPairing = "_adb-tls-pairing._tcp."
        case adbLegacy = "_adb._tcp."

        var displayName: String {
            switch self {
            case .adbTlsConnect: return "Wireless Debug"
            case .adbTlsPairing: return "Pairing Mode"
            case .adbLegacy: return "Legacy ADB"
            }
        }

        var priority: Int {
            switch self {
            case .adbTlsConnect: return 0
            case .adbTlsPairing: return 1
            case .adbLegacy: return 2
            }
        }
    }

    var connectService: ServiceInfo? {
        services.first { $0.type == .adbTlsConnect } ?? services.first { $0.type == .adbLegacy }
    }

    var pairingService: ServiceInfo? {
        services.first { $0.type == .adbTlsPairing }
    }

    var connectAddress: String? {
        guard let service = connectService else { return nil }
        return "\(host):\(service.port)"
    }

    var pairingAddress: String? {
        guard let service = pairingService else { return nil }
        return "\(host):\(service.port)"
    }

    var displayAddress: String {
        if let connect = connectService {
            return "\(host):\(connect.port)"
        }
        if let pairing = pairingService {
            return "\(host):\(pairing.port)"
        }
        return host
    }

    var statusText: String {
        if pairingService != nil && connectService == nil {
            return "Ready to pair"
        }
        if connectService != nil {
            return "Ready to connect"
        }
        return "Available"
    }

    var canConnect: Bool {
        connectService != nil
    }

    var canPair: Bool {
        pairingService != nil
    }

    var serviceTypesDisplay: String {
        services.sorted { $0.type.priority < $1.type.priority }
            .map { $0.type.displayName }
            .joined(separator: " • ")
    }
}
