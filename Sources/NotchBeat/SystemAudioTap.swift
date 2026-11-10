import CoreAudio
import Foundation

final class SystemAudioTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private var started = false

    func start(processIDs: [AudioObjectID]? = nil) throws -> AudioAnalysis {
        do {
            let description: CATapDescription
            if let processIDs {
                guard !processIDs.isEmpty else { throw CaptureError(message: "No audio processes for this app") }
                description = CATapDescription(stereoMixdownOfProcesses: processIDs)
            } else {
                description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
            }
            description.name = processIDs == nil ? "NotchBeat System Audio" : "NotchBeat App Audio"
            description.isPrivate = true
            description.muteBehavior = .unmuted
            try check(AudioHardwareCreateProcessTap(description, &tapID), "Create system audio tap")

            var format = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioTapPropertyFormat,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format), "Read system audio format")
            guard format.mFormatID == kAudioFormatLinearPCM,
                  format.mBitsPerChannel == 32,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mSampleRate.isFinite, format.mSampleRate > 0 else {
                throw CaptureError(message: "Unsupported system audio format")
            }

            let properties: [String: Any] = [
                kAudioAggregateDeviceNameKey: "NotchBeat Audio Input",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [
                    [kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]
                ]
            ]
            try check(AudioHardwareCreateAggregateDevice(properties as CFDictionary, &deviceID), "Create private audio input")
            let analysis = AudioAnalysis(sampleRate: format.mSampleRate)
            try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, deviceID, nil) { _, input, _, _, _ in
                analysis.append(input)
            }, "Connect system audio")
            guard let ioProc else { throw CaptureError(message: "Could not connect system audio") }
            try check(AudioDeviceStart(deviceID, ioProc), "Start system audio")
            started = true
            return analysis
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if let ioProc {
            if started { AudioDeviceStop(deviceID, ioProc) }
            AudioDeviceDestroyIOProcID(deviceID, ioProc)
        }
        ioProc = nil
        started = false
        if deviceID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(deviceID) }
        deviceID = kAudioObjectUnknown
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = kAudioObjectUnknown
    }

    deinit { stop() }

    private func check(_ result: OSStatus, _ operation: String) throws {
        if result != noErr { throw CaptureError(message: "\(operation) failed (\(result))") }
    }
}

struct CaptureError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
