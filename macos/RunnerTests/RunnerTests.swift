import Cocoa
import FlutterMacOS
import XCTest

@testable import miditutor

class RunnerTests: XCTestCase {

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

}

final class CoreMIDIConnectionLifecycleTests: XCTestCase {

  private var tracker: MidiConnectionTracker!

  override func setUp() {
    super.setUp()
    tracker = MidiConnectionTracker()
  }

  func testConnectSuccessCreatesSession() throws {
    let request = tracker.connect(
      deviceID: "123456",
      sourceExists: { _ in true }
    )
    guard case let .success(session) = request else {
      return XCTFail("Expected success, got \(request)")
    }
    XCTAssertEqual(session.deviceId, "123456")
    XCTAssertEqual(session.connectionType, "USB")
    XCTAssertFalse(session.sessionId.isEmpty)
    XCTAssertNotNil(tracker.activeSession)
  }

  func testReconnectProducesFreshSessionID() throws {
    guard case let .success(first) = tracker.connect(
      deviceID: "1", sourceExists: { _ in true }
    ) else {
      return XCTFail("First connect failed")
    }
    tracker.disconnect()
    guard case let .success(second) = tracker.connect(
      deviceID: "1", sourceExists: { _ in true }
    ) else {
      return XCTFail("Second connect failed")
    }
    XCTAssertNotEqual(first.sessionId, second.sessionId)
  }

  func testConnectWhileConnectedIsRejected() throws {
    _ = tracker.connect(deviceID: "1", sourceExists: { _ in true })
    let request = tracker.connect(deviceID: "2", sourceExists: { _ in true })
    guard case .alreadyConnected = request else {
      return XCTFail("Expected alreadyConnected, got \(request)")
    }
    XCTAssertEqual(tracker.activeSession?.deviceId, "1")
  }

  func testConnectUnknownSourceIsRejected() throws {
    let request = tracker.connect(deviceID: "999", sourceExists: { _ in false })
    guard case .noSource = request else {
      return XCTFail("Expected noSource, got \(request)")
    }
    XCTAssertNil(tracker.activeSession)
  }

  func testConnectWithEmptyDeviceIDIsInvalid() throws {
    let request = tracker.connect(deviceID: "", sourceExists: { _ in true })
    guard case .invalidRequest = request else {
      return XCTFail("Expected invalidRequest, got \(request)")
    }
    XCTAssertNil(tracker.activeSession)
  }

  func testDisconnectClearsSession() throws {
    _ = tracker.connect(deviceID: "1", sourceExists: { _ in true })
    XCTAssertNotNil(tracker.activeSession)
    tracker.disconnect()
    XCTAssertNil(tracker.activeSession)
  }

  func testDisconnectIsIdempotent() throws {
    tracker.disconnect()
    tracker.disconnect()
    XCTAssertNil(tracker.activeSession)
  }

  func testAdapterRejectsUnknownSourceEndToEnd() {
    let adapter = CoreMIDIAdapter()
    let call = FlutterMethodCall(
      methodName: CoreMIDIAdapter.connectMidiSourceMethod,
      arguments: ["id": "definitely-not-a-real-source"]
    )
    var resultValue: Any?
    adapter.handle(call) { result in
      resultValue = result
    }
    guard let error = resultValue as? FlutterError else {
      return XCTFail("Expected FlutterError, got \(String(describing: resultValue))")
    }
    XCTAssertEqual(error.code, CoreMIDIAdapter.errorNoSource)
  }

  func testAdapterRejectsMissingIdEndToEnd() {
    let adapter = CoreMIDIAdapter()
    let call = FlutterMethodCall(
      methodName: CoreMIDIAdapter.connectMidiSourceMethod,
      arguments: ["name": "no id here"]
    )
    var resultValue: Any?
    adapter.handle(call) { result in
      resultValue = result
    }
    guard let error = resultValue as? FlutterError else {
      return XCTFail("Expected FlutterError, got \(String(describing: resultValue))")
    }
    XCTAssertEqual(error.code, CoreMIDIAdapter.errorInvalidRequest)
  }

  func testLiveDeviceConnectDisconnectRoundTrip() throws {
    let deviceID = "802739987"
    guard CoreMIDIAdapter.sourceExists(uniqueID: deviceID) else {
      throw XCTSkip("APC Key 25 (id \(deviceID)) is not connected.")
    }

    let adapter = CoreMIDIAdapter()
    var firstSessionID: String?
    var firstErrorCode: String?
    var secondSessionID: String?
    var secondErrorCode: String?

    let connectCall = FlutterMethodCall(
      methodName: CoreMIDIAdapter.connectMidiSourceMethod,
      arguments: ["id": deviceID]
    )
    adapter.handle(connectCall) { result in
      if let error = result as? FlutterError {
        firstErrorCode = error.code
      } else if let map = result as? [String: Any],
                let sessionID = map["sessionId"] as? String,
                (map["deviceId"] as? String) == deviceID,
                (map["connectionType"] as? String) == "USB" {
        firstSessionID = sessionID
      }
    }
    XCTAssertNil(firstErrorCode)
    let sessionOne = try XCTUnwrap(firstSessionID)
    XCTAssertFalse(sessionOne.isEmpty)

    let redundantCall = FlutterMethodCall(
      methodName: CoreMIDIAdapter.connectMidiSourceMethod,
      arguments: ["id": deviceID]
    )
    adapter.handle(redundantCall) { result in
      if let error = result as? FlutterError {
        secondErrorCode = error.code
      } else if let map = result as? [String: Any],
                let sessionID = map["sessionId"] as? String {
        secondSessionID = sessionID
      }
    }
    XCTAssertNil(secondSessionID)
    XCTAssertEqual(secondErrorCode, CoreMIDIAdapter.errorAlreadyConnected)

    let disconnectCall = FlutterMethodCall(
      methodName: CoreMIDIAdapter.disconnectMidiSourceMethod,
      arguments: nil
    )
    var disconnectSucceeded = false
    adapter.handle(disconnectCall) { result in
      disconnectSucceeded = result == nil
    }
    XCTAssertTrue(disconnectSucceeded)

    let reconnectCall = FlutterMethodCall(
      methodName: CoreMIDIAdapter.connectMidiSourceMethod,
      arguments: ["id": deviceID]
    )
    var thirdSessionID: String?
    adapter.handle(reconnectCall) { result in
      if let map = result as? [String: Any],
                let sessionID = map["sessionId"] as? String {
        thirdSessionID = sessionID
      }
    }
    XCTAssertNotNil(thirdSessionID)
    XCTAssertNotEqual(thirdSessionID, sessionOne)

    let cleanupCall = FlutterMethodCall(
      methodName: CoreMIDIAdapter.disconnectMidiSourceMethod,
      arguments: nil
    )
    adapter.handle(cleanupCall) { _ in }
  }

}