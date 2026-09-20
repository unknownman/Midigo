import Cocoa
import CoreMIDI
import FlutterMacOS

final class CoreMIDIAdapter: NSObject, FlutterPlugin, FlutterStreamHandler {
    static let channelName = "piano_midi/macos"
    static let eventChannelName = "piano_midi/macos/events"
    static let listMidiSourcesMethod = "listMidiSources"
    static let connectMidiSourceMethod = "connectMidiSource"
    static let disconnectMidiSourceMethod = "disconnectMidiSource"

    static let errorNoSource = "NO_SOURCE"
    static let errorAlreadyConnected = "ALREADY_CONNECTED"
    static let errorNotConnected = "NOT_CONNECTED"
    static let errorConnectionFailed = "CONNECTION_FAILED"
    static let errorDisconnectFailed = "DISCONNECT_FAILED"
    static let errorInvalidRequest = "INVALID_REQUEST"
    static let errorUnknown = "UNKNOWN"

    private var connectionTracker = MidiConnectionTracker()

    // MARK: - Capture state

    /// Serializes access to capture state that is read from the CoreMIDI
    /// callback thread and written from the platform (main) thread.
    private let stateLock = NSLock()
    private var eventSink: FlutterEventSink?
    private var captureSession: MidiConnectionSession?
    private var captureSeq: UInt64 = 0
    private var decodeStatus: UInt8?
    private var midiClient: MIDIClientRef?
    private var inputPort: MIDIPortRef?
    private var connectedEndpoint: MIDIEndpointRef?

    internal var hasActiveInputResources: Bool {
        inputPort != nil
    }

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger
        )
        let eventChannel = FlutterEventChannel(
            name: eventChannelName,
            binaryMessenger: registrar.messenger
        )
        let instance = CoreMIDIAdapter()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
    }

    // MARK: - Method channel

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case Self.listMidiSourcesMethod:
            result(Self.listMidiSources())
        case Self.connectMidiSourceMethod:
            connectMidiSource(call, result: result)
        case Self.disconnectMidiSourceMethod:
            disconnectMidiSource(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Event channel

    func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        stateLock.lock()
        eventSink = events
        stateLock.unlock()
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        stateLock.lock()
        eventSink = nil
        stateLock.unlock()
        return nil
    }

    // MARK: - Connection lifecycle

    /// Establishes a connection to the MIDI source identified by the
    /// invocation's `id` argument and wires up the CoreMIDI capture path.
    ///
    /// On success the result is a map with `sessionId`, `deviceId`, and
    /// `connectionType` ("USB"). A fresh UUID session ID is produced for every
    /// successful connect and is never reused. The CoreMIDI client, input port,
    /// and source connection are created only after the logical session is
    /// accepted; if the event path cannot be established the session is rolled
    /// back and a structured CONNECTION_FAILED error is returned instead of a
    /// fabricated CONNECTED state.
    private func connectMidiSource(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        let deviceID: String
        if let arguments = call.arguments as? [String: Any],
           let id = arguments["id"] as? String {
            deviceID = id
        } else {
            deviceID = ""
        }

        switch connectionTracker.connect(
            deviceID: deviceID,
            sourceExists: { Self.sourceExists(uniqueID: $0) }
        ) {
        case .invalidRequest:
            result(FlutterError(
                code: Self.errorInvalidRequest,
                message: "Missing or invalid device id.",
                details: nil
            ))
        case .alreadyConnected:
            result(FlutterError(
                code: Self.errorAlreadyConnected,
                message: "A MIDI source is already connected.",
                details: nil
            ))
        case .noSource:
            result(FlutterError(
                code: Self.errorNoSource,
                message: "No MIDI source matches id \(deviceID).",
                details: nil
            ))
        case let .success(session):
            guard let endpoint = Self.sourceEndpoint(uniqueID: session.deviceId) else {
                connectionTracker.disconnect()
                result(FlutterError(
                    code: Self.errorConnectionFailed,
                    message: "Could not locate the MIDI source endpoint.",
                    details: nil
                ))
                return
            }
            guard setupCapture(for: session, source: endpoint) else {
                connectionTracker.disconnect()
                result(FlutterError(
                    code: Self.errorConnectionFailed,
                    message: "Could not establish the MIDI event capture path.",
                    details: nil
                ))
                return
            }
            result(session.asPlatformMap)
        }
    }

    /// Tears down the connection and the CoreMIDI capture path.
    ///
    /// Idempotent: disconnecting when there is no active session succeeds
    /// without error. In-flight packets arriving after the source is
    /// disconnected are dropped because captureSession is cleared first.
    private func disconnectMidiSource(result: @escaping FlutterResult) {
        connectionTracker.disconnect()
        tearDownCapture()
        result(nil)
    }

    // MARK: - Capture setup / teardown

    /// Creates the CoreMIDI client and input port for the session and connects
    /// them to the given source endpoint.
    ///
    /// The capture session snapshot and sequence counter are installed before
    /// the source is connected so that no packet is dropped mid-setup. If
    /// anything fails, any partially created resources are disposed and no
    /// session state is left behind.
    private func setupCapture(
        for session: MidiConnectionSession,
        source: MIDIEndpointRef
    ) -> Bool {
        var client = MIDIClientRef()
        let clientStatus = MIDIClientCreateWithBlock(
            "piano_tutor_midi_client" as CFString,
            nil,
            &client
        )

        guard clientStatus == noErr else { return false }

        var port = MIDIPortRef()
        let portStatus = MIDIInputPortCreateWithBlock(
            client,
            "piano_tutor_midi_input" as CFString
        ) { [weak self] packetList, _, _ in
            self?.handlePacketList(packetList)
        } &port

        guard portStatus == noErr else {
            MIDIClientDispose(client)
            return false
        }

        stateLock.lock()
        captureSession = session
        captureSeq = 0
        decodeStatus = nil
        midiClient = client
        inputPort = port
        stateLock.unlock()

        let connectStatus = MIDIPortConnectSource(port, source, nil)
        guard connectStatus == noErr else {
            tearDownCapture()
            return false
        }
        connectedEndpoint = source
        return true
    }

    /// Disconnects the source port and disposes all native capture resources.
    /// Safe to call repeatedly and from any thread relative to packet delivery:
    /// captureSession is cleared under the lock first, so any concurrent or
    /// in-flight callback finds no active capture and drops its packets.
    private func tearDownCapture() {
        stateLock.lock()
        captureSession = nil
        captureSeq = 0
        decodeStatus = nil
        let port = inputPort
        let endpoint = connectedEndpoint
        stateLock.unlock()

        if let port, let endpoint {
            MIDIPortDisconnectSource(port, endpoint)
        }
        if let port {
            MIDIEndpointDispose(port)
        }
        if let client = midiClient {
            MIDIClientDispose(client)
        }

        stateLock.lock()
        inputPort = nil
        midiClient = nil
        connectedEndpoint = nil
        stateLock.unlock()
    }

    // MARK: - Packet handling

    /// CoreMIDI read callback (background serial thread).
    ///
    /// Work here is intentionally small: snapshot the active session, decode
    /// the packet bytes into raw messages, assign per-session sequence numbers,
    /// and forward each message to the Dart event sink. No UI, blocking I/O, or
    /// Flutter channel calls are performed on this thread.
    private func handlePacketList(_ packetList: UnsafePointer<MIDIPacketList>) {
        stateLock.lock()
        guard let session = captureSession, let sink = eventSink else {
            stateLock.unlock()
            return
        }
        let sessionId = session.sessionId
        let deviceId = session.deviceId
        let nowMs = Self.monotonicMilliseconds()

        var decoded: [RawMidiMessage] = []
        var status = decodeStatus
        var packet = packetList.pointee.packet
        for _ in 0..<packetList.pointee.numPackets {
            decoded.append(contentsOf: Self.parseMessages(
                Self.packetBytes(packet),
                runningStatus: &status
            ))
            packet = MIDIPacketNext(&packet).pointee
        }
        decodeStatus = status
        stateLock.unlock()

        for message in decoded {
            stateLock.lock()
            guard let currentSink = eventSink, captureSession != nil else {
                stateLock.unlock()
                return
            }
            let seq = captureSeq
            captureSeq += 1
            stateLock.unlock()
            currentSink(Self.eventPayload(
                sessionId: sessionId,
                deviceId: deviceId,
                connectionType: "USB",
                seq: seq,
                appMonotonicTsMs: nowMs,
                message: message
            ))
        }
    }

    // MARK: - Packet decoding

    /// Raw MIDI message produced by decoding, preserving the exact incoming
    /// bytes without any musical interpretation or normalization.
    struct RawMidiMessage: Equatable {
        var messageType: String
        var channel: Int?
        var note: Int?
        var velocity: Int?
        var rawBytes: [UInt8]
    }

    /// Decodes the byte stream of a CoreMIDI packet into individual MIDI
    /// messages.
    ///
    /// Supports running status within the packet. Note-On (status 0x9n) is
    /// always reported as `note_on` including when velocity == 0; velocity-0
    /// normalization is deliberately not applied (H2 concern). System messages
    /// (status 0xF0-0xF7) are not reassembled across packets and are emitted as
    /// single-byte `other` events; this representation limitation is documented
    /// in the H1.3 report. Trailing short data is dropped without producing a
    /// partial event.
    static func parseMessages(
        _ data: [UInt8],
        runningStatus: inout UInt8?
    ) -> [RawMidiMessage] {
        guard !data.isEmpty else { return [] }
        var messages: [RawMidiMessage] = []
        var index = 0
        while index < data.count {
            let firstByte = data[index]
            var status: UInt8
            if firstByte & 0x80 == 0 {
                guard let previous = runningStatus else {
                    index += 1
                    continue
                }
                status = previous
            } else {
                status = firstByte
                index += 1
            }

            let dataLength: Int
            switch status & 0xF0 {
            case 0xC0, 0xD0:
                dataLength = 1
            case 0xF0:
                dataLength = 0
            default:
                dataLength = 2
            }

            let endIndex = index + dataLength
            guard endIndex <= data.count else {
                break
            }
            let dataBytes = Array(data[index..<endIndex])
            index = endIndex

            if status < 0xF0 {
                runningStatus = status
            }

            let rawBytes = dataBytes.isEmpty ? [status] : [status] + dataBytes
            messages.append(makeRawMidiMessage(status: status, dataBytes: dataBytes, rawBytes: rawBytes))
        }
        return messages
    }

    private static func makeRawMidiMessage(
        status: UInt8,
        dataBytes: [UInt8],
        rawBytes: [UInt8]
    ) -> RawMidiMessage {
        let channel = status & 0x0F
        switch status & 0xF0 {
        case 0x90:
            return RawMidiMessage(
                messageType: "note_on",
                channel: Int(channel),
                note: dataBytes.count > 0 ? Int(dataBytes[0]) : nil,
                velocity: dataBytes.count > 1 ? Int(dataBytes[1]) : nil,
                rawBytes: rawBytes
            )
        case 0x80:
            return RawMidiMessage(
                messageType: "note_off",
                channel: Int(channel),
                note: dataBytes.count > 0 ? Int(dataBytes[0]) : nil,
                velocity: dataBytes.count > 1 ? Int(dataBytes[1]) : nil,
                rawBytes: rawBytes
            )
        default:
            return RawMidiMessage(
                messageType: "other",
                channel: status < 0xF0 ? Int(channel) : nil,
                note: nil,
                velocity: nil,
                rawBytes: rawBytes
            )
        }
    }

    /// Copies the bytes of an individual CoreMIDI packet so the packet buffer
    /// is never referenced after the callback returns.
    static func packetBytes(_ packet: MIDIPacket) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(Int(packet.length))
        withUnsafePointer(to: packet.data) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: Int(packet.length)) { buffer in
                bytes.append(contentsOf: UnsafeBufferPointer(start: buffer, count: Int(packet.length)))
            }
        }
        return bytes
    }

    static func eventPayload(
        sessionId: String,
        deviceId: String,
        connectionType: String,
        seq: UInt64,
        appMonotonicTsMs: UInt64,
        message: RawMidiMessage
    ) -> [String: Any] {
        [
            "sessionId": sessionId,
            "deviceId": deviceId,
            "connectionType": connectionType,
            "seq": seq as NSNumber,
            "appMonotonicTsMs": appMonotonicTsMs as NSNumber,
            "messageType": message.messageType,
            "channel": message.channel.map { $0 as Any } ?? NSNull(),
            "note": message.note.map { $0 as Any } ?? NSNull(),
            "velocity": message.velocity.map { $0 as Any } ?? NSNull(),
            "rawBytes": message.rawBytes,
        ]
    }

    /// Application monotonic receive timestamp in milliseconds. Backed by
    /// mach_absolute_time via DispatchTime; it is the moment the application
    /// processed the packet, not a physical key-onset reference.
    static func monotonicMilliseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds / 1_000_000
    }

    // MARK: - CoreMIDI enumeration

    /// Enumerates the currently available CoreMIDI input source endpoints and
    /// converts each one into a Dart/JSON-serializable dictionary.
    static func listMidiSources() -> [[String: Any]] {
        let sourceCount = MIDIGetNumberOfSources()
        guard sourceCount > 0 else { return [] }

        var sources: [[String: Any]] = []
        sources.reserveCapacity(sourceCount)
        for index in 0..<sourceCount {
            let endpoint = MIDIGetSource(index)
            sources.append(sourceMetadata(for: endpoint))
        }
        return sources
    }

    static func sourceExists(uniqueID: String) -> Bool {
        sourceEndpoint(uniqueID: uniqueID) != nil
    }

    static func sourceEndpoint(uniqueID: String) -> MIDIEndpointRef? {
        let sourceCount = MIDIGetNumberOfSources()
        guard sourceCount > 0 else { return nil }
        for index in 0..<sourceCount {
            let endpoint = MIDIGetSource(index)
            if let value = integerProperty(endpoint, kMIDIPropertyUniqueID),
               String(value) == uniqueID {
                return endpoint
            }
        }
        return nil
    }

    private static func sourceMetadata(for endpoint: MIDIEndpointRef) -> [String: Any] {
        let name = stringProperty(endpoint, kMIDIPropertyName) ?? ""
        let manufacturer = stringProperty(endpoint, kMIDIPropertyManufacturer) ?? ""
        let uniqueID = integerProperty(endpoint, kMIDIPropertyUniqueID) ?? 0
        return [
            "id": uniqueID,
            "name": name,
            "manufacturer": manufacturer,
        ]
    }

    private static func stringProperty(
        _ object: MIDIObjectRef,
        _ propertyID: CFString
    ) -> String? {
        var value: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(object, propertyID, &value)
        guard status == noErr, let retained = value?.takeRetainedValue() else {
            return nil
        }
        return retained as String
    }

    private static func integerProperty(
        _ object: MIDIObjectRef,
        _ propertyID: CFString
    ) -> Int32? {
        var value: Int32 = 0
        let status = MIDIObjectGetIntegerProperty(object, propertyID, &value)
        guard status == noErr else { return nil }
        return value
    }
}

/// In-memory record of an established MIDI connection. A session is created
/// only when a connect request succeeds and is discarded on disconnect.
struct MidiConnectionSession {
    let sessionId: String
    let deviceId: String
    let connectionType: String

    var asPlatformMap: [String: Any] {
        [
            "sessionId": sessionId,
            "deviceId": deviceId,
            "connectionType": connectionType,
        ]
    }
}

/// Outcome of a connect request, resolved without any I/O side effects.
enum ConnectionRequest {
    case invalidRequest
    case alreadyConnected
    case noSource
    case success(MidiConnectionSession)
}

/// Pure, hardware-free state machine for the logical MIDI connection lifecycle.
/// The adapter feeds it real CoreMIDI enumeration through `sourceExists`, while
/// tests can exercise every transition with a stub predicate.
struct MidiConnectionTracker {
    private(set) var activeSession: MidiConnectionSession?

    mutating func connect(
        deviceID: String,
        sourceExists: (String) -> Bool
    ) -> ConnectionRequest {
        guard !deviceID.isEmpty else { return .invalidRequest }
        guard activeSession == nil else { return .alreadyConnected }
        guard sourceExists(deviceID) else { return .noSource }
        let session = MidiConnectionSession(
            sessionId: UUID().uuidString,
            deviceId: deviceID,
            connectionType: "USB"
        )
        activeSession = session
        return .success(session)
    }

    mutating func disconnect() {
        activeSession = nil
    }
}