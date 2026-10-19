import CoreAudio
import XCTest
@testable import MischpultCore

final class BluetoothCallModeTests: XCTestCase {
    let airpods = AudioDevice(id: 10, uid: "airpods", name: "AirPods", hasOutput: true, hasInput: true,
                              transportType: kAudioDeviceTransportTypeBluetooth)
    let builtInMic = AudioDevice(id: 11, uid: "mic", name: "MacBook-Mikrofon", hasOutput: false, hasInput: true,
                                 transportType: kAudioDeviceTransportTypeBuiltIn)
    let usbMic = AudioDevice(id: 12, uid: "usb", name: "USB-Mikrofon", hasOutput: false, hasInput: true,
                             transportType: kAudioDeviceTransportTypeUSB)

    private func group(_ name: String, recordingFrom devices: [AudioObjectID]) -> AudioAppGroup {
        AudioAppGroup(id: name, name: name, bundleID: nil, appPID: 1, isRegularApp: true, processes: [
            AudioProcess(objectID: 1, pid: 1, bundleID: nil, isRunningOutput: true,
                         isRunningInput: !devices.isEmpty, inputDeviceIDs: devices),
        ])
    }

    func testDetectsAppRecordingFromBluetoothMicrophone() {
        let status = BluetoothCallMode.detect(groups: [group("Discord", recordingFrom: [10]),
                                                       group("Safari", recordingFrom: [])],
                                              devices: [airpods, builtInMic], defaultInputID: 10)
        XCTAssertEqual(status?.deviceName, "AirPods")
        XCTAssertEqual(status?.appNames, ["Discord"])
        XCTAssertEqual(status?.defaultInputIsBluetooth, true)
    }

    func testNoCallModeWhenRecordingFromBuiltInMicrophone() {
        XCTAssertNil(BluetoothCallMode.detect(groups: [group("Discord", recordingFrom: [11])],
                                              devices: [airpods, builtInMic], defaultInputID: 11))
    }

    func testExplicitBluetoothMicrophoneIsReportedAsSuch() {
        let status = BluetoothCallMode.detect(groups: [group("Zoom", recordingFrom: [10])],
                                              devices: [airpods, builtInMic], defaultInputID: 11)
        XCTAssertEqual(status?.defaultInputIsBluetooth, false)
    }

    func testReplacementPrefersBuiltInMicrophone() {
        XCTAssertEqual(AudioDevices.inputAvoidingBluetooth([airpods, usbMic, builtInMic])?.id, 11)
        XCTAssertEqual(AudioDevices.inputAvoidingBluetooth([airpods, usbMic])?.id, 12)
        XCTAssertNil(AudioDevices.inputAvoidingBluetooth([airpods]))
    }
}
