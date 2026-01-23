import SwiftUI

struct WiFiConnectionSheet: View {
    @EnvironmentObject private var deviceManager: DeviceManager
    @Environment(\.dismiss) private var dismiss

    let settingsStore: SettingsStore
    let discoveryService: DeviceDiscoveryService
    let adbService: ADBService

    @State private var selectedTab: ConnectionTab = .scan
    @State private var ipAddress = ""
    @State private var port = ""
    @State private var connectionError: String?
    @State private var isConnecting = false
    @State private var pairingDevice: DiscoveredDevice?

    enum ConnectionTab {
        case scan
        case manual
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Picker("", selection: $selectedTab) {
                Text("Scan").tag(ConnectionTab.scan)
                Text("Manual").tag(ConnectionTab.manual)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            Divider()

            switch selectedTab {
            case .scan:
                scanView
            case .manual:
                manualView
            }

            Spacer()
            bottomBar
        }
        .frame(width: 480, height: 500)
        .onAppear {
            port = String(settingsStore.settings.defaultTcpipPort)
            discoveryService.startScanning()
        }
        .onDisappear {
            discoveryService.stopScanning()
        }
        .sheet(item: $pairingDevice) { device in
            PairingSheet(
                device: device,
                adbService: adbService,
                discoveryService: discoveryService,
                deviceManager: deviceManager,
                onDismiss: { pairingDevice = nil }
            )
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "wifi")
                .font(.title2)
                .foregroundColor(.accentColor)
            Text("Connect via WiFi")
                .font(.title2)
                .fontWeight(.semibold)
        }
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private var scanView: some View {
        VStack(spacing: 0) {
            HStack {
                if discoveryService.isScanning {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning for devices...")
                        .foregroundColor(.secondary)
                } else {
                    Text("Found \(discoveryService.discoveredDevices.count) device(s)")
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { discoveryService.startScanning() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(discoveryService.isScanning)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            if discoveryService.discoveredDevices.isEmpty {
                emptyDiscoveryView
            } else {
                deviceList
            }

            if let error = discoveryService.scanError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 24)
            }

            if let error = connectionError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            }
        }
    }

    private var emptyDiscoveryView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("No devices found")
                .font(.headline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("To discover devices:")
                    .font(.subheadline)
                    .fontWeight(.medium)

                VStack(alignment: .leading, spacing: 4) {
                    Text("1. Enable Developer Options on your Android device")
                    Text("2. Enable Wireless Debugging")
                    Text("3. Ensure both devices are on the same network")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private var deviceList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(discoveryService.discoveredDevices) { device in
                    DiscoveredDeviceRow(
                        device: device,
                        onConnect: { connectToDevice(device) },
                        onPair: { pairingDevice = device }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
    }

    private var manualView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("To connect wirelessly:")
                    .fontWeight(.medium)

                VStack(alignment: .leading, spacing: 4) {
                    Text("1. Enable Wireless Debugging or enable TCP/IP from a USB device")
                    Text("2. Get the IP from Settings > About phone > IP address")
                    Text("3. Enter the IP and port below")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("IP Address")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    TextField("192.168.1.100", text: $ipAddress)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Port")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    TextField("5555", text: $port)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }
            .padding(.horizontal, 24)

            if let error = connectionError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 24)
            }

            HStack {
                Spacer()
                Button("Connect") {
                    Task { await connectManually() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(ipAddress.isEmpty || port.isEmpty || isConnecting)
            }
            .padding(.horizontal, 24)
        }
    }

    private var bottomBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
        }
        .padding(24)
    }

    private func connectToDevice(_ device: DiscoveredDevice) {
        guard let address = device.connectAddress else {
            connectionError = "No connection address available"
            return
        }

        Task {
            discoveryService.markDeviceConnecting(device, true)
            connectionError = nil

            do {
                try await deviceManager.connect(to: address)
                dismiss()
            } catch let error as ADBError {
                connectionError = error.localizedDescription
            } catch {
                connectionError = error.localizedDescription
            }

            discoveryService.markDeviceConnecting(device, false)
        }
    }

    private func connectManually() async {
        let trimmedIP = ipAddress.trimmingCharacters(in: .whitespaces)
        let trimmedPort = port.trimmingCharacters(in: .whitespaces)

        guard !trimmedIP.isEmpty else {
            connectionError = "Please enter an IP address"
            return
        }

        guard !trimmedPort.isEmpty, let portNum = Int(trimmedPort), portNum > 0, portNum <= 65535 else {
            connectionError = "Please enter a valid port (1-65535)"
            return
        }

        isConnecting = true
        connectionError = nil

        do {
            try await deviceManager.connect(to: "\(trimmedIP):\(trimmedPort)")
            dismiss()
        } catch let error as ADBError {
            connectionError = error.localizedDescription
        } catch {
            connectionError = error.localizedDescription
        }

        isConnecting = false
    }
}

// MARK: - DiscoveredDeviceRow

struct DiscoveredDeviceRow: View {
    let device: DiscoveredDevice
    let onConnect: () -> Void
    let onPair: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: deviceIcon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(device.host)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(device.serviceTypesDisplay)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if device.isConnecting {
                ProgressView()
                    .controlSize(.small)
            } else {
                HStack(spacing: 8) {
                    if device.canConnect && device.canPair {
                        Button("Connect") { onConnect() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }

                    if device.canPair {
                        Button("Pair") { onPair() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    } else if device.canConnect {
                        Button("Connect") { onConnect() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var deviceIcon: String {
        if device.canPair { return "lock.open.fill" }
        if device.canConnect { return "wifi" }
        return "antenna.radiowaves.left.and.right"
    }

    private var iconColor: Color {
        if device.canPair { return .orange }
        if device.canConnect { return .green }
        return .blue
    }
}

// MARK: - PairingSheet

struct PairingSheet: View {
    let device: DiscoveredDevice
    let adbService: ADBService
    let discoveryService: DeviceDiscoveryService
    let deviceManager: DeviceManager
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var pairingCode = ""
    @State private var isPairing = false
    @State private var isConnecting = false
    @State private var error: String?
    @State private var pairingSucceeded = false

    private var pairingAddress: String {
        device.pairingAddress ?? device.displayAddress
    }

    private var isWorking: Bool {
        isPairing || isConnecting
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            VStack(spacing: 2) {
                Text("Pair with \(device.name)")
                    .font(.headline)
                Text(pairingAddress)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 4) {
                Text("Enter the 6-digit pairing code shown on your device")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Text("Note: Pairing codes expire quickly. Enter the code promptly.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            TextField("000000", text: $pairingCode)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 24, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.center)
                .frame(width: 150)
                .onChange(of: pairingCode) { _, newValue in
                    pairingCode = String(newValue.filter { $0.isNumber }.prefix(6))
                }

            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if isConnecting {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Connecting...")
                        .foregroundColor(.secondary)
                }
            } else if pairingSucceeded {
                Label("Paired successfully!", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }

            HStack(spacing: 16) {
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)

                if !pairingSucceeded {
                    Button(isPairing ? "Pairing..." : "Pair") {
                        Task { await pairAndConnect() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pairingCode.count != 6 || isWorking)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(32)
        .frame(width: 340)
    }

    private func pairAndConnect() async {
        isPairing = true
        error = nil

        do {
            try await adbService.pair(address: pairingAddress, code: pairingCode)
            await discoveryService.markDevicePaired(device)
            isPairing = false

            isConnecting = true
            await deviceManager.refresh()

            // Wait for device to advertise connect service
            try await Task.sleep(nanoseconds: 500_000_000)

            let connectAddress = device.connectAddress ?? "\(device.host):5555"
            try await deviceManager.connect(to: connectAddress)

            pairingSucceeded = true
            isConnecting = false

            try await Task.sleep(nanoseconds: 500_000_000)
            onDismiss()
            dismiss()

        } catch let err as ADBError {
            error = err.localizedDescription
            isPairing = false
            isConnecting = false
        } catch {
            self.error = error.localizedDescription
            isPairing = false
            isConnecting = false
        }
    }
}

// MARK: - Preview

#Preview {
    let settingsStore = SettingsStore()
    let historyStore = DeviceHistoryStore()
    let adbService = ADBServiceImpl(settingsStore: settingsStore)
    return WiFiConnectionSheet(
        settingsStore: settingsStore,
        discoveryService: DeviceDiscoveryService(historyStore: historyStore),
        adbService: adbService
    )
    .environmentObject(DeviceManager(
        adbService: adbService,
        deviceIdentifier: DeviceIdentifier(adbService: adbService),
        historyStore: historyStore,
        settingsStore: settingsStore
    ))
}
