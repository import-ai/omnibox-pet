import AppKit

final class InputMonitoringGuide: NSPanel {
    private var followTimer: Timer?
    private var lastSettingsWindowTime = ProcessInfo.processInfo.systemUptime

    init(isEnglish: Bool) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 332, height: 82),
                   styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        title = isEnglish ? "OmniBox Pet · Input Monitoring" : "桌宠小黑 · 输入监控"

        let icon = DraggableAppIcon(frame: NSRect(x: 12, y: 13, width: 56, height: 56))
        icon.image = Bundle.main.url(forResource: "InputMonitoringAvatar", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) } ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityLabel(isEnglish ? "OmniBox Pet app icon" : "桌宠小黑应用图标")
        icon.toolTip = isEnglish ? "Drag to the Input Monitoring list" : "拖入「输入监控」列表"
        contentView?.addSubview(icon)

        let instructions = NSTextField(wrappingLabelWithString: isEnglish
            ? "Drag the icon into the Input Monitoring list and turn on its switch. Already listed? Just turn it on."
            : "把小黑图标拖进列表，再打开开关。\n列表里已有小黑？直接打开开关。")
        instructions.frame = NSRect(x: 78, y: 12, width: 240, height: 58)
        instructions.font = .systemFont(ofSize: 13)
        contentView?.addSubview(instructions)

        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.followSystemSettings()
        }
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
    }

    override func close() {
        followTimer?.invalidate()
        followTimer = nil
        super.close()
    }

    private func followSystemSettings() {
        let settingsID = "com.apple.systempreferences"
        let screens = NSScreen.screens
        let now = ProcessInfo.processInfo.systemUptime
        guard let settings = NSRunningApplication.runningApplications(withBundleIdentifier: settingsID).first,
              let desktopTop = screens.first?.frame.maxY,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                        kCGNullWindowID) as? [[String: Any]] else {
            orderOut(nil)
            if now - lastSettingsWindowTime > 5 { close() }
            return
        }

        // Window bounds are available before the app has any privacy grants.
        let settingsFrame = windows.lazy.compactMap { window -> CGRect? in
            guard window[kCGWindowOwnerPID as String] as? pid_t == settings.processIdentifier,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width >= 450, rect.height >= 320 else { return nil }
            return CGRect(x: rect.minX, y: desktopTop - rect.maxY, width: rect.width, height: rect.height)
        }.first

        guard let settingsFrame else {
            orderOut(nil)
            if now - lastSettingsWindowTime > 5 { close() }
            return
        }
        lastSettingsWindowTime = now
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == settings.processIdentifier,
              let screen = screens.first(where: { $0.frame.contains(CGPoint(x: settingsFrame.midX, y: settingsFrame.midY)) })
                ?? NSScreen.main else {
            orderOut(nil)
            return
        }

        let visible = screen.visibleFrame
        let gap: CGFloat = 8
        let besideY = settingsFrame.maxY - 52 - frame.height
        let right = settingsFrame.maxX + gap
        let below = settingsFrame.minY - frame.height - gap
        let left = settingsFrame.minX - gap - frame.width
        let x: CGFloat
        let y: CGFloat
        if right + frame.width <= visible.maxX {
            (x, y) = (right, besideY)
        } else if below >= visible.minY {
            (x, y) = (settingsFrame.maxX - frame.width, below)
        } else if left >= visible.minX {
            (x, y) = (left, besideY)
        } else {
            (x, y) = (settingsFrame.maxX - frame.width, settingsFrame.minY + gap)
        }
        let origin = CGPoint(x: max(visible.minX, min(x, visible.maxX - frame.width)),
                             y: max(visible.minY, min(y, visible.maxY - frame.height)))
        if frame.origin != origin { setFrameOrigin(origin) }
        if !isVisible { orderFrontRegardless() }
    }
}

private final class DraggableAppIcon: NSImageView, NSDraggingSource {
    private var mouseDownEvent: NSEvent?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent, let image,
              hypot(event.locationInWindow.x - start.locationInWindow.x,
                    event.locationInWindow.y - start.locationInWindow.y) >= 3 else { return }
        mouseDownEvent = nil
        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
