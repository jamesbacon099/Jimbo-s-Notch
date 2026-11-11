import AppKit
import CoreGraphics

enum IslandFootprint {
    static let hasPROLEDDisplay: Bool = {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return false }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return false }
        return ["Mac17,10", "Mac17,11", "Mac17,12", "Mac17,13"].contains(String(cString: bytes))
    }()

    // The native compact Now Playing pill measures about 138 pt in the reference
    // display capture. Keep a little extra space when the system exposes no frame.
    static let compactSystemWidth: CGFloat = 148

    struct Window {
        let frame: CGRect
        let level: Int
        var ownerName: String? = nil
        var isJimboMusic = false
    }

    static func current(in space: MenuBarSpace) -> CGRect? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }

        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)
        let musicPIDs = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "local.jimbo.music")
            .map { Int($0.processIdentifier) })
        guard space.hasNotch || !musicPIDs.isEmpty else { return nil }
        let candidates: [Window] = windows.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int, pid != ownPID,
                  let level = info[kCGWindowLayer as String] as? Int, level > CGWindowLevelForKey(.normalWindow),
                  let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0.01,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"] else { return nil }
            return Window(
                frame: CGRect(x: x, y: space.windowOriginY - y - height, width: width, height: height),
                level: level,
                ownerName: info[kCGWindowOwnerName as String] as? String,
                isJimboMusic: musicPIDs.contains(pid)
            )
        }
        return footprint(in: space, windows: candidates)
    }

    static func footprint(in space: MenuBarSpace, windows: [Window]) -> CGRect? {
        let leftEdge = space.leftArea.maxX
        let rightEdge = space.rightArea.minX
        let center = (leftEdge + rightEdge) / 2
        let barTop = space.leftArea.maxY
        let barBottom = space.leftArea.minY
        let fullWidth = space.rightArea.maxX - space.leftArea.minX
        let minimumWidth = space.hasSystemIsland
            ? max(compactSystemWidth, rightEdge - leftEdge) * 0.65
            : rightEdge - leftEdge - 8
        let barHeight = space.leftArea.height
        let compactExtension = barHeight * 1.25
        let compactArea = CGRect(x: leftEdge - compactExtension, y: barBottom,
                                 width: rightEdge - leftEdge + 2 * compactExtension, height: barHeight)

        // A notch overlay sits at the top edge, straddles the camera, and takes up
        // only part of the screen. Ignore normal app windows and the full menu bar.
        return windows.reduce(nil) { footprint, window in
            let rect = window.frame
            guard window.level > CGWindowLevelForKey(.normalWindow),
                  rect.width >= minimumWidth,
                  rect.width <= min(720, fullWidth * 0.53),
                  rect.height >= 10, rect.height <= 420,
                  rect.minX < center, rect.maxX > center,
                  abs(rect.midX - center) <= min(65, rect.width * 0.18),
                  abs(rect.maxY - barTop) <= 12, rect.maxY > barBottom,
                  rect.minY < barTop - 7 else { return footprint }
            let bounds: CGRect
            if window.isJimboMusic || space.hasSystemIsland {
                bounds = rect
            } else if !space.hasNotch {
                return footprint
            } else if window.ownerName == "NotchBox" {
                // Its compact controls can occupy only part of a much wider transparent window.
                bounds = rect.intersection(compactArea)
            } else {
                guard rect.width <= compactArea.width, rect.height <= barHeight * 2 else { return footprint }
                bounds = rect
            }
            return footprint?.union(bounds) ?? bounds
        }
    }
}
