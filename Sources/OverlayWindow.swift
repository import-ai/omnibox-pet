import Foundation
import AppKit
import ApplicationServices

private struct RenderedPose {
    struct Appearance: Equatable {
        let keyboard: KeyboardTheme
        let eyes: EyeColorTheme
        let showsLegends: Bool
        let size: CGSize
        let flipped: Bool
        let captureMode: Int
        let showEditControls: Bool
        let englishLabels: Bool
        let showsPaws: Bool
    }

    let appearance: Appearance
    let hasEffects: Bool
    let head: CGPoint
    let leftPaw: CGPoint
    let rightPaw: CGPoint
    let eyeClosure: CGFloat
    let headTurn: CGPoint
    let headTilt: CGFloat
    let eyeGaze: CGPoint
    let mouseOffset: CGPoint
    let pawOnMouse: Bool

    init(physics: CatPhysics, settings: CatSettings, size: CGSize) {
        appearance = Appearance(keyboard: settings.keyboardTheme, eyes: settings.eyeTheme,
                                showsLegends: settings.showKeyLegends, size: size, flipped: settings.flipHorizontal,
                                captureMode: settings.obsCaptureMode, showEditControls: settings.isEditMode,
                                englishLabels: settings.isEnglish, showsPaws: settings.xiaoheiPaws)
        hasEffects = settings.keyboardMarquee || !physics.sparkles.isEmpty
            || !physics.floatingKeycaps.isEmpty || !physics.keyGlow.isEmpty
            || physics.angerIntensity.value > 0.02 || physics.dizzyIntensity.value > 0.02
            || physics.scruffDrag.value > 0.02 || physics.isChangingLie
        head = XiaoheiRenderer.headCenter(physics, showPaws: settings.xiaoheiPaws)
        leftPaw = physics.leftPaw.point
        rightPaw = physics.rightPaw.point
        eyeClosure = physics.effectiveEyeClosure
        headTurn = CGPoint(x: physics.headYaw.value, y: physics.headPitch.value)
        headTilt = physics.headTilt.value
        eyeGaze = physics.eyeGaze.point
        mouseOffset = physics.mouseOffset.point
        pawOnMouse = physics.leftPawOnMouse
    }

    func visiblyDiffers(from previous: RenderedPose) -> Bool {
        if appearance != previous.appearance || hasEffects || previous.hasEffects
            || pawOnMouse != previous.pawOnMouse { return true }
        func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
        // Estimate how far visible features moved in canvas coordinates, then convert to screen points.
        let movement = max(distance(head, previous.head),
                           distance(leftPaw, previous.leftPaw), distance(rightPaw, previous.rightPaw),
                           abs(eyeClosure - previous.eyeClosure) * 40, distance(headTurn, previous.headTurn) * 24,
                           abs(headTilt - previous.headTilt) * 52, distance(eyeGaze, previous.eyeGaze) * 10,
                           distance(mouseOffset, previous.mouseOffset))
        let scale = max(appearance.size.width / CatPhysics.canvasSize.width,
                        appearance.size.height / CatPhysics.canvasSize.height)
        return movement * scale >= 0.65
    }
}

final class CatCanvasView: NSView {
    let physics = CatPhysics()
    var onRequestPermission: (() -> Void)?
    var onRightClickMenu: ((NSEvent) -> Void)?

    private var lastHoverCanvasPt: CGPoint?
    private var isDragging = false
    private var activeResizeCorner: Int = -1 // -1 = none, 0=TL, 1=TR, 2=BL, 3=BR
    private var resizeAnchorScreenPt: CGPoint = .zero
    private var resizeStartFrame: CGRect = .zero
    private var dragStartScreenPt: CGPoint = .zero
    private var dragStartWindowOrigin: CGPoint = .zero
    private var isShowingOpenHand = false
    private var lastDrawnPose: RenderedPose?

    var isDraggingOrResizing: Bool { isDragging || activeResizeCorner >= 0 }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)

        let scaleX = bounds.width / CatPhysics.canvasSize.width
        let scaleY = bounds.height / CatPhysics.canvasSize.height
        ctx.saveGState()
        ctx.scaleBy(x: scaleX, y: scaleY)

        let status = InputEngine.shared.status
        CatRenderer.draw(in: ctx, physics: physics, showPermissionPill: status.needsAttention,
                         permissionPillText: status.permissionPillText(isEnglish: CatSettings.shared.isEnglish))
        lastDrawnPose = RenderedPose(physics: physics, settings: CatSettings.shared, size: bounds.size)
        ctx.restoreGState()
    }

    func poseNeedsDisplay() -> Bool {
        guard let previous = lastDrawnPose else { return true }
        let current = RenderedPose(physics: physics, settings: CatSettings.shared, size: bounds.size)
        return current.visiblyDiffers(from: previous)
    }

    func canvasPoint(fromScreenPoint screenPt: CGPoint) -> CGPoint? {
        guard let win = window else { return nil }
        let frame = win.frame
        guard frame.contains(screenPt) else { return nil }
        let localX = (screenPt.x - frame.minX) / frame.width * CatPhysics.canvasSize.width
        // Convert bottom-up screen Y to flipped top-down canvas Y
        let localY = (frame.maxY - screenPt.y) / frame.height * CatPhysics.canvasSize.height
        return CGPoint(x: localX, y: localY)
    }

    /// Called on every 60fps tick to handle smart click-through AND petting strokes.
    func updateHoverAndClickThrough() {
        guard let win = window else { return }
        let screenPt = NSEvent.mouseLocation
        if isDraggingOrResizing {
            win.ignoresMouseEvents = false
            return
        }

        guard let pt = canvasPoint(fromScreenPoint: screenPt) else {
            lastHoverCanvasPt = nil
            if !win.ignoresMouseEvents {
                win.ignoresMouseEvents = true
            }
            resetCursorIfNeeded()
            return
        }

        if CatSettings.shared.isEditMode {
            let editHit = CatRenderer.hitTestEditOverlay(point: pt)
            win.ignoresMouseEvents = (editHit < 0)
            if editHit == 10 || editHit == 11 {
                NSCursor.pointingHand.set()
                isShowingOpenHand = false
            } else if editHit >= 0 && editHit <= 3 {
                NSCursor.crosshair.set()
                isShowingOpenHand = false
            } else if editHit == 12 {
                if !isShowingOpenHand {
                    NSCursor.openHand.set()
                    isShowingOpenHand = true
                }
            } else {
                resetCursorIfNeeded()
            }
            return
        }

        let catPt = CatSettings.shared.flipHorizontal
            ? CGPoint(x: CatPhysics.canvasSize.width - pt.x, y: pt.y)
            : pt
        let showPill = InputEngine.shared.status.needsAttention
        let zone = CatRenderer.hitTest(point: catPt, physics: physics, showPermissionPill: showPill)

        // Petting triggers strictly on the cat's head (never on keyboard or torso)!
        if zone == .head {
            if let prev = lastHoverCanvasPt {
                let delta = hypot(catPt.x - prev.x, catPt.y - prev.y)
                if delta > 1.2 && delta < 80 {
                    physics.registerPetStroke(canvasPoint: catPt, delta: delta, isHead: true)
                }
            }
            lastHoverCanvasPt = catPt
        } else {
            lastHoverCanvasPt = nil
        }

        // Smart Click-Through logic (hold Option ⌥ to temporarily unlock Full Click-Through!)
        let optionHeld = NSEvent.modifierFlags.contains(.option)
        if CatSettings.shared.fullClickThrough && !optionHeld {
            // Keep permission pill clickable only if permission isn't granted yet
            win.ignoresMouseEvents = (zone != .permissionPill)
            resetCursorIfNeeded()
        } else {
            let shouldCapture = (zone != .none)
            if win.ignoresMouseEvents == shouldCapture {
                win.ignoresMouseEvents = !shouldCapture
            }
            if zone == .head || zone == .body {
                if !isShowingOpenHand {
                    NSCursor.openHand.set()
                    isShowingOpenHand = true
                }
            } else if zone == .permissionPill {
                NSCursor.pointingHand.set()
                isShowingOpenHand = false
            } else {
                resetCursorIfNeeded()
            }
        }
    }

    private func resetCursorIfNeeded() {
        if isShowingOpenHand {
            NSCursor.arrow.set()
            isShowingOpenHand = false
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let win = window else { return }
        let screenPt = NSEvent.mouseLocation
        let showPill = InputEngine.shared.status.needsAttention

        if let pt = canvasPoint(fromScreenPoint: screenPt) {
            if CatSettings.shared.isEditMode {
                let hit = CatRenderer.hitTestEditOverlay(point: pt)
                if hit == 10 {
                    CatSettings.shared.flipHorizontal.toggle()
                    needsDisplay = true
                    return
                }
                if hit == 11 {
                    CatSettings.shared.isEditMode = false
                    needsDisplay = true
                    return
                }
                if hit >= 0 && hit <= 3 {
                    activeResizeCorner = hit
                    resizeStartFrame = win.frame
                    // Anchor the opposite corner in screen space (AppKit Y is bottom-up)
                    let f = win.frame
                    switch hit {
                    case 0: resizeAnchorScreenPt = CGPoint(x: f.maxX, y: f.minY) // dragging TL -> anchor BR
                    case 1: resizeAnchorScreenPt = CGPoint(x: f.minX, y: f.minY) // dragging TR -> anchor BL
                    case 2: resizeAnchorScreenPt = CGPoint(x: f.maxX, y: f.maxY) // dragging BL -> anchor TR
                    default: resizeAnchorScreenPt = CGPoint(x: f.minX, y: f.maxY) // dragging BR -> anchor TL
                    }
                    return
                }
            }

            let catPt = CatSettings.shared.flipHorizontal
                ? CGPoint(x: CatPhysics.canvasSize.width - pt.x, y: pt.y)
                : pt
            let zone = CatRenderer.hitTest(point: catPt, physics: physics, showPermissionPill: showPill)
            if zone == .permissionPill {
                onRequestPermission?()
                return
            }

            // Double-clicking the cat toggles the interactive resize & flip box!
            if event.clickCount == 2 && (zone == .head || zone == .body || CatSettings.shared.isEditMode) {
                CatSettings.shared.isEditMode.toggle()
                needsDisplay = true
                return
            }
        }

        isDragging = true
        dragStartScreenPt = screenPt
        dragStartWindowOrigin = win.frame.origin
        physics.setDragging(true, dragDx: 0)
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let win = window else { return }
        let currentScreenPt = NSEvent.mouseLocation
        if activeResizeCorner >= 0 {
            let dx = abs(currentScreenPt.x - resizeAnchorScreenPt.x)
            let dy = abs(currentScreenPt.y - resizeAnchorScreenPt.y)
            let sx = dx / CatPhysics.canvasSize.width
            let sy = dy / CatPhysics.canvasSize.height
            let newScale = max(0.45, min(2.50, max(sx, sy)))
            let newW = CatPhysics.canvasSize.width * newScale
            let newH = CatPhysics.canvasSize.height * newScale
            let originX = (activeResizeCorner == 0 || activeResizeCorner == 2)
                ? (resizeAnchorScreenPt.x - newW)
                : resizeAnchorScreenPt.x
            let originY = (activeResizeCorner == 2 || activeResizeCorner == 3)
                ? (resizeAnchorScreenPt.y - newH)
                : resizeAnchorScreenPt.y
            CatSettings.shared.scale = newScale
            win.setFrame(CGRect(x: originX, y: originY, width: newW, height: newH), display: true)
            return
        }
        guard isDragging else { return }
        let prevX = win.frame.origin.x
        let newOrigin = CGPoint(
            x: dragStartWindowOrigin.x + (currentScreenPt.x - dragStartScreenPt.x),
            y: dragStartWindowOrigin.y + (currentScreenPt.y - dragStartScreenPt.y)
        )
        let stepDx = newOrigin.x - prevX
        physics.setDragging(true, dragDx: CatSettings.shared.flipHorizontal ? -stepDx : stepDx)
        win.setFrameOrigin(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        guard let win = window as? OverlayWindow else { return }
        if activeResizeCorner >= 0 {
            activeResizeCorner = -1
            win.saveDisplayPosition()
            return
        }
        guard isDragging else { return }
        isDragging = false
        physics.setDragging(false)
        NSCursor.openHand.set()
        if win.frame.origin != dragStartWindowOrigin {
            win.saveDisplayPosition(preferDisplay: true)
        }
    }

    func cancelPositionAdjustment() {
        guard isDraggingOrResizing else { return }
        activeResizeCorner = -1
        isDragging = false
        physics.setDragging(false)
        NSCursor.arrow.set()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClickMenu?(event)
    }

}

final class OverlayWindow: NSPanel {
    let catView = CatCanvasView()

    init() {
        let scale = CatSettings.shared.scale
        let size = CGSize(
            width: CatPhysics.canvasSize.width * scale,
            height: CatPhysics.canvasSize.height * scale
        )
        let origin = PetPlacement.restoredOrigin(size: size, displays: PetPlacement.connectedDisplays)
            ?? PetPlacement.defaultOrigin(size: size, within: CGRect(x: 0, y: 0, width: 1440, height: 900))

        super.init(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true

        applyWindowLevelAndBehavior()
        applyOBSMode()

        catView.frame = CGRect(origin: .zero, size: size)
        catView.autoresizingMask = [.width, .height]
        contentView = catView
    }

    func applyOBSMode() {
        let mode = CatSettings.shared.obsCaptureMode
        let hideDesktop = (mode > 0 && CatSettings.shared.obsHideDesktop)
        title = "桌宠小黑"
        sharingType = .readOnly
        if mode == 2 {
            isOpaque = true
            backgroundColor = NSColor(calibratedRed: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)
        } else {
            isOpaque = false
            backgroundColor = .clear
        }
        if hideDesktop {
            // Tuck behind desktop/all apps while staying rendered so OBS Window Capture stays live!
            level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
            collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            ignoresMouseEvents = true
        } else {
            applyWindowLevelAndBehavior()
        }
        catView.needsDisplay = true
    }

    func applyWindowLevelAndBehavior() {
        if CatSettings.shared.fullScreenOverlay {
            // popUpMenuWindow (101) stays reliably above WPS/Keynote slideshows, fullscreen apps and Dock
            // while remaining below Spotlight and system Force Quit dialogs.
            level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        } else {
            level = .floating
            collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        }
    }

    func applyScale(_ newScale: CGFloat) {
        CatSettings.shared.scale = newScale
        let oldFrame = frame
        let newSize = CGSize(
            width: CatPhysics.canvasSize.width * newScale,
            height: CatPhysics.canvasSize.height * newScale
        )
        // Anchor bottom-center so scaling feels grounded
        let newOrigin = CGPoint(
            x: oldFrame.midX - newSize.width * 0.5,
            y: oldFrame.minY
        )
        setFrame(CGRect(origin: newOrigin, size: newSize), display: true)
        saveDisplayPosition()
    }

    func resetPosition() {
        guard let display = PetPlacement.fallbackDisplay(in: PetPlacement.connectedDisplays) else { return }
        setFrameOrigin(PetPlacement.defaultOrigin(size: frame.size, within: display.visibleFrame))
        saveDisplayPosition(preferDisplay: true)
    }

    func saveDisplayPosition(preferDisplay: Bool = false) {
        PetPlacement.save(frame: frame, displays: PetPlacement.connectedDisplays, preferDisplay: preferDisplay)
    }

    func restoreDisplayPosition() {
        guard let origin = PetPlacement.restoredOrigin(size: frame.size, displays: PetPlacement.connectedDisplays),
              origin != frame.origin else { return }
        catView.cancelPositionAdjustment()
        setFrameOrigin(origin)
    }
}

enum PetPlacement {
    struct Display {
        let id: String?
        let frame: CGRect
        let visibleFrame: CGRect
        let isBuiltIn: Bool
    }

    private static let positionsKey = "KuroCat.DisplayPositions"
    private static let preferredKey = "KuroCat.PreferredDisplay"

    static var connectedDisplays: [Display] {
        NSScreen.screens.map { screen in
            let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let id = screenNumber?.uint32Value
            let uuid = id.flatMap { CGDisplayCreateUUIDFromDisplayID($0)?.takeRetainedValue() }
            return Display(id: uuid.map { CFUUIDCreateString(nil, $0) as String },
                           frame: screen.frame, visibleFrame: screen.visibleFrame,
                           isBuiltIn: id.map { CGDisplayIsBuiltin($0) != 0 } ?? false)
        }
    }

    static func fallbackDisplay(in displays: [Display]) -> Display? {
        displays.first(where: { $0.isBuiltIn }) ?? displays.first
    }

    static func save(frame: CGRect, displays: [Display], preferDisplay: Bool, defaults: UserDefaults = .standard) {
        guard let display = displayContaining(frame, in: displays), let id = display.id else { return }
        let bounds = display.visibleFrame
        var positions = defaults.dictionary(forKey: positionsKey) ?? [:]
        positions[id] = [
            fraction(frame.minX - bounds.minX, travel: bounds.width - frame.width),
            fraction(frame.minY - bounds.minY, travel: bounds.height - frame.height)
        ]
        defaults.set(positions, forKey: positionsKey)
        if preferDisplay { defaults.set(id, forKey: preferredKey) }
    }

    static func restoredOrigin(size: CGSize, displays: [Display], defaults: UserDefaults = .standard) -> CGPoint? {
        guard let fallback = fallbackDisplay(in: displays) else { return nil }
        if defaults.string(forKey: preferredKey) == nil,
           let x = defaults.object(forKey: "KuroCat.PosX") as? NSNumber,
           let y = defaults.object(forKey: "KuroCat.PosY") as? NSNumber,
           x.doubleValue.isFinite, y.doubleValue.isFinite {
            let oldFrame = CGRect(origin: CGPoint(x: x.doubleValue, y: y.doubleValue), size: size)
            save(frame: oldFrame, displays: displays, preferDisplay: true, defaults: defaults)
        }
        let preferredID = defaults.string(forKey: preferredKey)
        let display = displays.first { preferredID != nil && $0.id == preferredID } ?? fallback
        let bounds = display.visibleFrame
        guard let id = display.id,
              let position = defaults.dictionary(forKey: positionsKey)?[id] as? [Double],
              position.count == 2, position.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            return defaultOrigin(size: size, within: bounds)
        }
        return CGPoint(x: bounds.minX + max(0, bounds.width - size.width) * position[0],
                       y: bounds.minY + max(0, bounds.height - size.height) * position[1])
    }

    static func defaultOrigin(size: CGSize, within bounds: CGRect) -> CGPoint {
        CGPoint(x: bounds.minX + max(0, bounds.width - size.width - 28),
                y: bounds.minY + min(18, max(0, bounds.height - size.height)))
    }

    private static func displayContaining(_ frame: CGRect, in displays: [Display]) -> Display? {
        displays.filter { !$0.frame.intersection(frame).isEmpty }.max { first, second in
            let a = first.frame.intersection(frame)
            let b = second.frame.intersection(frame)
            return a.width * a.height < b.width * b.height
        }
    }

    private static func fraction(_ offset: CGFloat, travel: CGFloat) -> Double {
        travel > 0 ? Double(max(0, min(1, offset / travel))) : 0
    }
}
