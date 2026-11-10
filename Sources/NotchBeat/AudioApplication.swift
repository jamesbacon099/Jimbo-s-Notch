import AppKit
import CoreAudio
import Darwin

struct AudioApplication: Hashable, Identifiable {
    let name: String
    let bundlePath: String
    let bundleID: String?

    var id: String { bundlePath }

    @MainActor
    static func choices() -> [AudioApplication] {
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> AudioApplication? in
            guard !app.isTerminated, app.activationPolicy == .regular,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  let path = bundlePath(of: app) else { return nil }
            return AudioApplication(name: app.localizedName ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                                    bundlePath: path, bundleID: app.bundleIdentifier)
        }
        return Array(Set(apps)).sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.bundlePath < $1.bundlePath : order == .orderedAscending
        }
    }

    @MainActor
    func audioProcesses() throws -> (isRunning: Bool, ids: [AudioObjectID]) {
        let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let appPIDs = Set(running.filter { Self.bundlePath(of: $0) == bundlePath }.map(\.processIdentifier))
        guard !appPIDs.isEmpty else { return (false, []) }
        let uniqueBundleID = bundleID != nil && !running.contains {
            $0.bundleIdentifier == bundleID && !appPIDs.contains($0.processIdentifier)
        }

        let ids = try AudioProcessCatalog.objectIDs().filter { object in
            guard let pid = AudioProcessCatalog.pid(of: object) else { return false }
            if appPIDs.contains(pid) { return true }
            return matchesHelper(executable: AudioProcessCatalog.executable(of: pid),
                                 audioBundleID: uniqueBundleID ? AudioProcessCatalog.bundleID(of: object) : nil)
        }
        return (true, ids.sorted())
    }

    func matchesHelper(executable: String?, audioBundleID: String?) -> Bool {
        if let executable, executable.hasPrefix(bundlePath + "/Contents/") { return true }
        return bundleID != nil && bundleID == audioBundleID
    }

    private static func bundlePath(of app: NSRunningApplication) -> String? {
        app.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path
    }
}

private enum AudioProcessCatalog {
    static func objectIDs() throws -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size)
        guard status == noErr else { throw CaptureError(message: "Could not read audio processes (\(status))") }
        let stride = MemoryLayout<AudioObjectID>.stride
        let count = Int(size) / stride
        guard count > 0 else { return [] }

        var ids = [AudioObjectID](repeating: kAudioObjectUnknown, count: count)
        status = ids.withUnsafeMutableBufferPointer { buffer in
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, buffer.baseAddress!)
        }
        guard status == noErr else { throw CaptureError(message: "Could not read audio processes (\(status))") }
        return ids.prefix(Int(size) / stride).filter { $0 != kAudioObjectUnknown }
    }

    static func pid(of object: AudioObjectID) -> pid_t? {
        var address = address(kAudioProcessPropertyPID)
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &pid) == noErr, pid > 0 else { return nil }
        return pid
    }

    static func bundleID(of object: AudioObjectID) -> String? {
        var address = address(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout.size(ofValue: value))
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func executable(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let capacity = UInt32(buffer.count)
        guard proc_pidpath(pid, &buffer, capacity) > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}
