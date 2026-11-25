import Foundation
import CoreGraphics
import AppKit

// MARK: - Themes & Settings

enum KeyboardTheme: String, CaseIterable {
    case classicMilk = "经典奶白暖黄 (原版)"
    case midnightHacker = "暗夜极客黑"
    case retroCream = "复古奶油灰"
}

enum EyeColorTheme: String, CaseIterable {
    case neonChartreuse = "经典荧光黄绿 (原版)"
    case siameseBlue = "暹罗宝石蓝 (暹罗标配)"
    case warmAmber = "琥珀金瞳"
    case iceCyan = "冰晶浅蓝"
    case softAmber = "柔和琥珀"
    case referenceHazel = "淡金青绿"

    static func saved(_ raw: String) -> Self {
        raw == "淡金青绿（参考图）" ? .referenceHazel : (Self(rawValue: raw) ?? .neonChartreuse)
    }

    var primaryColor: NSColor {
        switch self {
        case .neonChartreuse: return NSColor(calibratedRed: 0.79, green: 0.95, blue: 0.25, alpha: 1.0) // #C9F240
        case .siameseBlue:    return NSColor(calibratedRed: 0.69, green: 0.855, blue: 0.95, alpha: 1.0) // #B0DAF2 通透浅淡冰蓝
        case .warmAmber:      return NSColor(calibratedRed: 0.98, green: 0.76, blue: 0.22, alpha: 1.0)
        case .iceCyan:        return NSColor(calibratedRed: 0.45, green: 0.92, blue: 0.96, alpha: 1.0)
        case .referenceHazel: return NSColor(calibratedRed: 218.0/255, green: 178.0/255, blue: 87.0/255, alpha: 1)
        case .softAmber: return NSColor(calibratedRed: 217.0/255, green: 173.0/255, blue: 85.0/255, alpha: 1)
        }
    }

    var glowColor: NSColor {
        switch self {
        case .neonChartreuse: return NSColor(calibratedRed: 0.77, green: 0.95, blue: 0.24, alpha: 0.85)
        case .siameseBlue:    return NSColor(calibratedRed: 0.68, green: 0.85, blue: 0.95, alpha: 0.80)
        case .warmAmber:      return NSColor(calibratedRed: 0.98, green: 0.74, blue: 0.20, alpha: 0.85)
        case .iceCyan:        return NSColor(calibratedRed: 0.42, green: 0.90, blue: 0.98, alpha: 0.85)
        case .referenceHazel: return NSColor(calibratedRed: 218.0/255, green: 178.0/255, blue: 87.0/255, alpha: 0.85)
        case .softAmber: return NSColor(calibratedRed: 217.0/255, green: 173.0/255, blue: 85.0/255, alpha: 0.85)
        }
    }
}

final class CatSettings {
    static let shared = CatSettings()

    var showKeyBadges: Bool {
        didSet { UserDefaults.standard.set(showKeyBadges, forKey: "KuroCat.ShowKeyBadges") }
    }
    var showMouseBadges: Bool {
        didSet { UserDefaults.standard.set(showMouseBadges, forKey: "KuroCat.ShowMouseBadges") }
    }
    var showKeyLegends: Bool {
        didSet { UserDefaults.standard.set(showKeyLegends, forKey: "KuroCat.ShowKeyLegends") }
    }
    var footEasterEgg: Bool {
        didSet { UserDefaults.standard.set(footEasterEgg, forKey: "KuroCat.FootEasterEgg") }
    }
    /// Xiaohei has no limbs; floating detached paws are a derived, switchable adaptation (default on).
    var xiaoheiPaws: Bool {
        didSet { UserDefaults.standard.set(xiaoheiPaws, forKey: "Xiaohei.FloatingPaws") }
    }
    var tailEasterEgg: Bool {
        didSet { UserDefaults.standard.set(tailEasterEgg, forKey: "KuroCat.TailEasterEgg") }
    }
    var keyboardMarquee: Bool {
        didSet { UserDefaults.standard.set(keyboardMarquee, forKey: "KuroCat.KeyboardMarquee") }
    }
    /// 0 = normal desktop overlay, 1 = OBS transparent window capture, 2 = OBS green screen (#00FF00)
    var obsCaptureMode: Int {
        didSet { UserDefaults.standard.set(obsCaptureMode, forKey: "KuroCat.OBSCaptureMode") }
    }
    /// When true in OBS mode, hide cat behind desktop/offscreen while OBS still captures live frames
    var obsHideDesktop: Bool {
        didSet { UserDefaults.standard.set(obsHideDesktop, forKey: "KuroCat.OBSHideDesktop") }
    }
    /// Automatically hide the pet when another app enters fullscreen
    var autoHideFullscreen: Bool {
        didSet { UserDefaults.standard.set(autoHideFullscreen, forKey: "KuroCat.AutoHideFullscreen") }
    }
    /// 0 = Auto-detect graphics tablet/stylus, 1 = Always show tablet, 2 = Always show mouse
    var tabletMode: Int {
        didSet { UserDefaults.standard.set(tabletMode, forKey: "KuroCat.TabletMode") }
    }
    var flipHorizontal: Bool {
        didSet { UserDefaults.standard.set(flipHorizontal, forKey: "KuroCat.FlipHorizontal") }
    }
    /// "zh" or "en"
    var language: String {
        didSet { UserDefaults.standard.set(language, forKey: "KuroCat.Language") }
    }
    var isEnglish: Bool { language == "en" }
    /// Runtime-only interactive resize & flip bounding box (toggled via double-click or menu)
    var isEditMode: Bool = false
    var petInteraction: Bool {
        didSet { UserDefaults.standard.set(petInteraction, forKey: "KuroCat.PetInteraction") }
    }
    var fullClickThrough: Bool {
        didSet { UserDefaults.standard.set(fullClickThrough, forKey: "KuroCat.FullClickThrough") }
    }
    var fullScreenOverlay: Bool {
        didSet { UserDefaults.standard.set(fullScreenOverlay, forKey: "KuroCat.FullScreenOverlay") }
    }
    var scale: CGFloat {
        didSet { UserDefaults.standard.set(Double(scale), forKey: "KuroCat.Scale") }
    }
    var keyboardTheme: KeyboardTheme {
        didSet { UserDefaults.standard.set(keyboardTheme.rawValue, forKey: "KuroCat.KeyboardTheme") }
    }
    var eyeTheme: EyeColorTheme {
        didSet { UserDefaults.standard.set(eyeTheme.rawValue, forKey: "KuroCat.EyeTheme") }
    }
    private init() {
        let d = UserDefaults.standard
        showKeyBadges = d.object(forKey: "KuroCat.ShowKeyBadges") as? Bool ?? true
        showMouseBadges = d.object(forKey: "KuroCat.ShowMouseBadges") as? Bool ?? true
        showKeyLegends = d.object(forKey: "KuroCat.ShowKeyLegends") as? Bool ?? true
        footEasterEgg = d.object(forKey: "KuroCat.FootEasterEgg") as? Bool ?? true
        tailEasterEgg = d.object(forKey: "KuroCat.TailEasterEgg") as? Bool ?? true
        xiaoheiPaws = d.object(forKey: "Xiaohei.FloatingPaws") as? Bool ?? true
        keyboardMarquee = d.object(forKey: "KuroCat.KeyboardMarquee") as? Bool ?? true
        obsCaptureMode = d.object(forKey: "KuroCat.OBSCaptureMode") as? Int ?? 0
        obsHideDesktop = d.object(forKey: "KuroCat.OBSHideDesktop") as? Bool ?? false
        autoHideFullscreen = d.object(forKey: "KuroCat.AutoHideFullscreen") as? Bool ?? false
        tabletMode = d.object(forKey: "KuroCat.TabletMode") as? Int ?? 0
        flipHorizontal = d.object(forKey: "KuroCat.FlipHorizontal") as? Bool ?? false
        language = d.string(forKey: "KuroCat.Language") ?? "zh"
        petInteraction = d.object(forKey: "KuroCat.PetInteraction") as? Bool ?? true
        fullClickThrough = d.object(forKey: "KuroCat.FullClickThrough") as? Bool ?? false
        fullScreenOverlay = d.object(forKey: "KuroCat.FullScreenOverlay") as? Bool ?? true
        let savedScale = d.double(forKey: "KuroCat.Scale")
        scale = savedScale > 0.3 ? CGFloat(savedScale) : 1.0
        keyboardTheme = KeyboardTheme(rawValue: d.string(forKey: "KuroCat.KeyboardTheme") ?? "") ?? .classicMilk
        let savedEye = d.string(forKey: "KuroCat.EyeTheme") ?? ""
        eyeTheme = EyeColorTheme.saved(savedEye)
    }
}

// MARK: - Spring Primitives

struct Spring1D {
    var value: CGFloat
    var velocity: CGFloat = 0
    var target: CGFloat

    init(_ initial: CGFloat) {
        self.value = initial
        self.target = initial
    }

    mutating func step(dt: CGFloat, stiffness: CGFloat = 260, damping: CGFloat = 22) {
        let force = (target - value) * stiffness
        let damp = velocity * damping
        velocity += (force - damp) * dt
        value += velocity * dt
    }
}

struct Spring2D {
    var x: Spring1D
    var y: Spring1D

    init(_ pt: CGPoint) {
        self.x = Spring1D(pt.x)
        self.y = Spring1D(pt.y)
    }

    var point: CGPoint { CGPoint(x: x.value, y: y.value) }
    var target: CGPoint {
        get { CGPoint(x: x.target, y: y.target) }
        set { x.target = newValue.x; y.target = newValue.y }
    }

    mutating func step(dt: CGFloat, stiffness: CGFloat = 340, damping: CGFloat = 25) {
        x.step(dt: dt, stiffness: stiffness, damping: damping)
        y.step(dt: dt, stiffness: stiffness, damping: damping)
    }
}

// MARK: - Particles

struct FloatingKeycap {
    let id: Int
    let label: String
    var position: CGPoint
    var velocity: CGPoint
    var age: CGFloat = 0
    let lifetime: CGFloat = 1.25
    var rotation: CGFloat
}

struct PurrSparkle {
    var position: CGPoint
    var velocity: CGPoint
    var age: CGFloat = 0
    let lifetime: CGFloat = 0.9
    let isSleepZ: Bool
}

struct ScriptedFrameInput {
    var now: CFTimeInterval
    var activeKeys: Set<PhysicalKey>
    var orderedKeys: [PhysicalKey]
    var mouseScreenPos: CGPoint
    var mouseVelocity: CGVector
    var leftMouseDown: Bool
    var rightMouseDown: Bool
    var lastMouseMoveTime: CFTimeInterval
    var lastMouseClickTime: CFTimeInterval
    var lastKeyActivityTime: CFTimeInterval
}

// MARK: - Cat Physics & Procedural Animation State

final class CatPhysics {
    // Logical canvas dimensions
    static let canvasSize = CGSize(width: 360, height: 320)

    // Rest positions
    static let seatAnchor = CGPoint(x: 184, y: 226)
    static let leftPawRest = CGPoint(x: 164, y: 235)
    static let rightPawRest = CGPoint(x: 204, y: 235)
    static let hindFootRest = CGPoint(x: 214, y: 234)
    static let mouseBaseCenter = CGPoint(x: 78, y: 258)

    // Springs
    var leftPaw = Spring2D(leftPawRest)
    var rightPaw = Spring2D(rightPawRest)
    var hindFoot = Spring2D(hindFootRest)
    var hindFootActive = Spring1D(0) // 0 = tucked, 1 = kicking 3rd key
    var tailTip = Spring2D(CGPoint(x: 275, y: 196))
    var tailTyping = Spring1D(0)
    var tailFlick = Spring2D(.zero)
    var tailCurl = Spring1D(0)
    var tailAgility = Spring1D(0)
    private var tailFlickHold: CGFloat = 0
    private var tailFlickCooldown: CGFloat = 0
    // Keyboard marquee: normalized position (0..1) of the light head, plus its speed boost.
    var marqueePhase: CGFloat = 0
    var marqueeBoost = Spring1D(0)

    var bodyShiftX = Spring1D(0)
    var bodyTilt = Spring1D(0)       // radians
    var bodySquash = Spring1D(1.0)
    var headTilt = Spring1D(0)       // radians (roll)
    var headYaw = Spring1D(0)        // -1 (turn left) ... +1 (turn right)
    var headPitch = Spring1D(0)      // -1 (look up)   ... +1 (look down)
    var headOffsetY = Spring1D(0)
    var earFold = Spring1D(0)        // 0 = alert, 1 = relaxed petting ears
    var earTwitch = Spring1D(0)

    var eyeGaze = Spring2D(.zero)    // normalized [-1..1, -1..1]
    var pupilScale = Spring1D(1.0)
    var huntIntensity = Spring1D(0)  // 0 = normal slit pupils, 1 = full hunting crouch + big round boba pupils!
    var scruffDrag = Spring1D(0)     // 0 = seated, 1 = picked up by neck scruff
    var scruffSwing = Spring1D(0)    // pendulum sway while dragged horizontally
    var lieIntensity = Spring1D(0)   // 0 = sitting, 1 = lying cozily on keyboard while idle
    var angerIntensity = Spring1D(0) // 0 = calm, 1 = angry from very fast typing
    var dizzyIntensity = Spring1D(0) // 0 = clear, 1 = dizzy spiral eyes + slumped beside keyboard
    private(set) var dizzyPhase: CGFloat = 0
    private var isScruffDragging = false
    private var scruffDragDx: CGFloat = 0
    private var fastMouseDuration: CGFloat = 0
    private var dizzyTimer: CGFloat = 0
    var mouseOffset = Spring2D(.zero)
    var mousePressLeft = Spring1D(0)
    var mousePressRight = Spring1D(0)

    // Graphics Tablet & Stylus state (auto-activates when a tablet/pen is connected or forced on!)
    static func tabletQuadPoint(u: CGFloat, v: CGFloat) -> CGPoint {
        let tl = CGPoint(x: 18, y: 235), tr = CGPoint(x: 94, y: 240)
        let bl = CGPoint(x: 13, y: 284), br = CGPoint(x: 91, y: 289)
        let topX = tl.x + (tr.x - tl.x) * u
        let topY = tl.y + (tr.y - tl.y) * u
        let botX = bl.x + (br.x - bl.x) * u
        let botY = bl.y + (br.y - bl.y) * u
        return CGPoint(x: topX + (botX - topX) * v, y: topY + (botY - topY) * v)
    }

    struct TabletStrokePoint {
        var point: CGPoint
        var age: CGFloat
    }

    private(set) var isTabletActive = false
    var tabletNib = Spring2D(CGPoint(x: 60, y: 261))
    var tabletPenPress = Spring1D(0)
    var tabletPenTilt = Spring1D(0)
    var tabletTrail: [TabletStrokePoint] = []

    // Paw mode flags (for crisp outline & posture rendering)
    private(set) var leftPawOnMouse = false
    private(set) var leftPawTyping = false
    private(set) var rightPawTyping = false

    // Keycap glow & press depths
    var keyGlow: [PhysicalKey: CGFloat] = [:]
    var floatingKeycaps: [FloatingKeycap] = []
    var sparkles: [PurrSparkle] = []
    private var nextBadgeID = 1
    private var badgeCascadeIndex = 0
    private var lastBadgeTime: CFTimeInterval = 0

    // Time & blink
    private(set) var time: CGFloat = 0
    private(set) var tailPhase: CGFloat = 0
    private var nextBlinkTime: CGFloat = 3.2
    private var blinkProgress: CGFloat = 0 // 0 = open, 1 = closed
    private(set) var isBlinking = false
    private var blinkTimer: CGFloat = 0

    // Petting state
    private(set) var petHeadIntensity: CGFloat = 0  // 0..1 -> happy closed lime lines
    private(set) var petBodyIntensity: CGFloat = 0  // 0..1 -> blissful half-squint
    private(set) var totalPetSessions: Int = UserDefaults.standard.integer(forKey: "KuroCat.PetCount")
    private var petStrokeAccumulator: CGFloat = 0
    private var lastPetTime: CFTimeInterval = 0
    private var isCurrentlyPetting = false
    private var petCursorCanvasPos: CGPoint = .zero
    private var petSparkleCooldown: CGFloat = 0

    // Sleepy idle state
    private(set) var sleepiness: CGFloat = 0 // 0 = awake, 1 = napping
    private(set) var yawnAmount: CGFloat = 0 // 0 = closed, 1 = peak wide yawn before sleep
    private var yawnTimer: CGFloat = 0
    private(set) var isYawning = false
    private var hasYawnedThisIdle = false
    private var sleepZCooldown: CGFloat = 0

    // Recent key memory so fast single taps linger visibly (~140ms)
    private var recentLeftKey: (key: PhysicalKey, time: CFTimeInterval)?
    private var recentRightKey: (key: PhysicalKey, time: CFTimeInterval)?
    private var lastTypedPoint: CGPoint?

    // Computed eye closure (0 = wide open, 0.55 = half squint, 1 = fully closed)
    var effectiveEyeClosure: CGFloat {
        let petClose = max(petHeadIntensity * 1.0, petBodyIntensity * 0.62)
        let sleepClose = max(sleepiness * 0.92, yawnAmount * 0.96)
        return min(1.0, max(blinkProgress, max(petClose, sleepClose)))
    }

    var breathingOffset: CGFloat { sin(time * 2.1) * 1.6 }

    /// True when eyes should draw the signature glowing lime horizontal closed-eye lines
    var isHappyClosedEyes: Bool {
        petHeadIntensity > 0.45
    }

    var isBlissfulSquint: Bool {
        petBodyIntensity > 0.35 && !isHappyClosedEyes
    }

    /// Headless preview hook (render-xiaohei-preview only); never called by the live app.
    func setPreviewMoods(sleepiness s: CGFloat = 0, petBody b: CGFloat = 0, dizzyPhase d: CGFloat = 0) {
        sleepiness = s
        petBodyIntensity = b
        dizzyPhase = d
    }

    // MARK: - Input Hooks

    func triggerKeyDown(_ key: PhysicalKey, at timestamp: CFTimeInterval? = nil) {
        let now = timestamp ?? CACurrentMediaTime()
        let vk = key.visualKey
        keyGlow[vk] = 1.0

        let pt = KeyboardLayout.canvasPoint(for: vk)
        lastTypedPoint = pt

        // Snap memory to the appropriate paw with lively bounce velocity
        let active = InputEngine.shared.activeKeys
        let leftHeld = active.contains { $0.prefersLeftPaw }
        let rightHeld = active.contains { !$0.prefersLeftPaw }

        if key.prefersLeftPaw {
            recentLeftKey = (vk, now)
            leftPaw.y.velocity -= 180
        } else if !rightHeld || !leftHeld {
            recentRightKey = (vk, now)
            rightPaw.y.velocity -= 180
        } else {
            recentRightKey = (vk, now)
            rightPaw.y.velocity -= 180
        }

        // Expressive micro-reactions
        bodySquash.velocity -= 1.3
        earTwitch.velocity += (key.prefersLeftPaw ? -3.8 : 3.8)
        headTilt.velocity += (key.prefersLeftPaw ? -1.4 : 1.4)
        pupilScale.target = 1.16

        // Wake up immediately
        sleepiness = 0

        // Spawn floating keycap badge
        if CatSettings.shared.showKeyBadges {
            spawnFloatingKeycap(label: key.badgeLabel, near: pt, now: now)
        }
    }

    func triggerMouseClick(button: Int, isDown: Bool) {
        sleepiness = 0
        if isDown {
            let now = CACurrentMediaTime()
            if button == 0 {
                mousePressLeft.target = 1.0
                leftPaw.y.velocity += 130
            } else {
                mousePressRight.target = 1.0
                leftPaw.y.velocity += 110
            }
            pupilScale.target = 1.12
            earTwitch.velocity -= 2.2
            if CatSettings.shared.showKeyBadges {
                let en = CatSettings.shared.isEnglish
                let label = button == 0 ? (en ? "LMB" : "左键") : (button == 1 ? (en ? "RMB" : "右键") : (en ? "MMB" : "中键"))
                let pt = CGPoint(
                    x: CatPhysics.mouseBaseCenter.x + mouseOffset.point.x,
                    y: CatPhysics.mouseBaseCenter.y + mouseOffset.point.y - 6
                )
                spawnFloatingKeycap(label: label, near: pt, now: now)
            }
        } else {
            if button == 0 { mousePressLeft.target = 0 }
            else { mousePressRight.target = 0 }
        }
    }

    /// Called by OverlayWindow when the user drags the cat window (triggers scruff-pickup posture!).
    func setDragging(_ dragging: Bool, dragDx: CGFloat = 0) {
        isScruffDragging = dragging
        if dragging {
            scruffDragDx = dragDx
            sleepiness = 0
            dizzyTimer = 0
            fastMouseDuration = 0
        } else {
            scruffDragDx = 0
            // Cute soft squash bounce when set back down
            bodySquash.velocity -= 1.8
        }
    }

    /// Called by the overlay window when cursor hovers near the cat's tail: whips away flexibly!
    func updateTailHover(canvasPoint cp: CGPoint?) {
        guard let cp, tailTyping.value < 0.25 else { return }
        let seatX = CatPhysics.seatAnchor.x + bodyShiftX.value
        let seatY = CatPhysics.seatAnchor.y
        let hunt = max(0, min(1, huntIntensity.value))
        let agility = max(0, min(1, tailAgility.value))
        let wag1 = sin(tailPhase) * (8.0 + hunt * 5.5 + agility * 4.0)
        let wag2 = cos(tailPhase * 1.3) * (6.0 + hunt * 4.5 + agility * 3.5)
        let huntDrop = hunt * 14.0
        let fx = tailFlick.point.x
        let fy = tailFlick.point.y
        let curl = tailCurl.value

        let root = CGPoint(x: seatX + 34, y: seatY - 6)
        let c1 = CGPoint(x: seatX + 64 + fx * 0.25, y: seatY + 2 + wag1 * 0.35 + huntDrop * 0.4 + fy * 0.22 + curl * 0.35)
        let c2 = CGPoint(x: seatX + 66 + wag2 * 0.4 + fx * 0.65 - curl * 0.45, y: seatY - 26 + wag1 * 0.7 + huntDrop + fy * 0.60 - curl * 0.55)
        let tip = CGPoint(x: seatX + 91 + wag2 * 0.5 + fx, y: seatY - 30 + wag1 * 0.85 + huntDrop + fy)

        var bestDist: CGFloat = .greatestFiniteMagnitude
        var bestPt = tip
        for t: CGFloat in [0.35, 0.58, 0.80, 1.0] {
            let u = 1 - t
            let pt = CGPoint(
                x: u*u*u*root.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*tip.x,
                y: u*u*u*root.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*tip.y
            )
            let d = hypot(pt.x - cp.x, pt.y - cp.y)
            if d < bestDist {
                bestDist = d
                bestPt = pt
            }
        }

        if bestDist < 24.0 {
            var ax = bestPt.x - cp.x
            var ay = bestPt.y - cp.y
            let len = hypot(ax, ay)
            if len < 1.0 {
                ax = 0.35
                ay = -0.94
            } else {
                ax /= len
                ay /= len
            }
            let targetX = max(-24.0, min(36.0, ax * 32.0 + (ax >= 0 ? 6.0 : -4.0)))
            let targetY = max(-44.0, min(38.0, ay * 40.0 + (ay < 0 ? -8.0 : 6.0)))
            tailFlick.target = CGPoint(x: targetX, y: targetY)
            tailCurl.target = ay >= 0 ? -18.0 : 20.0
            if tailFlickCooldown <= 0 {
                tailFlick.x.velocity += ax * 240.0
                tailFlick.y.velocity += ay * 280.0
                tailCurl.velocity += (ay >= 0 ? -150.0 : 170.0)
                earTwitch.velocity += 1.4
                tailFlickCooldown = 0.16
            }
            tailFlickHold = 0.30
            tailAgility.target = 1.0
            sleepiness = max(0, sleepiness - 0.15)
        }
    }

    /// Called by the overlay window when cursor strokes across the cat's head or body.
    func registerPetStroke(canvasPoint: CGPoint, delta: CGFloat, isHead: Bool, at timestamp: CFTimeInterval? = nil) {
        guard CatSettings.shared.petInteraction else { return }
        let now = timestamp ?? CACurrentMediaTime()
        lastPetTime = now
        petCursorCanvasPos = canvasPoint
        sleepiness = 0

        let energy = min(delta / 26.0, 0.35)
        if isHead {
            petHeadIntensity = min(1.0, petHeadIntensity + energy + 0.08)
            petBodyIntensity = max(petBodyIntensity, petHeadIntensity * 0.6)
        } else {
            petBodyIntensity = min(1.0, petBodyIntensity + energy + 0.07)
        }

        petStrokeAccumulator += delta
        if !isCurrentlyPetting && petStrokeAccumulator > 45 {
            isCurrentlyPetting = true
            totalPetSessions += 1
            UserDefaults.standard.set(totalPetSessions, forKey: "KuroCat.PetCount")
        }

        // Gentle nuzzle toward cursor
        let dx = (canvasPoint.x - CatPhysics.seatAnchor.x) / 60.0
        headTilt.target = max(-0.18, min(0.18, dx * 0.16))
        headOffsetY.velocity += 18
    }

    private func spawnFloatingKeycap(label: String, near pt: CGPoint, now: CFTimeInterval) {
        if now - lastBadgeTime < 0.38 {
            badgeCascadeIndex = (badgeCascadeIndex + 1) % 6
        } else {
            badgeCascadeIndex = 0
        }
        lastBadgeTime = now

        // Spread fast bursts gracefully so they stay readable like "F O J F E A"
        let spreadOffsets: [CGFloat] = [-10, 14, -22, 26, 2, 36]
        let dx = spreadOffsets[badgeCascadeIndex] + CGFloat.random(in: -3...3)
        let startX = max(55, min(315, pt.x + dx * 0.45))
        let startY = pt.y - 26 - CGFloat(badgeCascadeIndex % 2) * 8

        let badge = FloatingKeycap(
            id: nextBadgeID,
            label: label,
            position: CGPoint(x: startX, y: startY),
            velocity: CGPoint(x: dx * 0.65, y: -36 - CGFloat.random(in: 0...14)),
            rotation: CGFloat.random(in: -0.07...0.07)
        )
        nextBadgeID += 1
        floatingKeycaps.append(badge)
        if floatingKeycaps.count > 16 {
            floatingKeycaps.removeFirst(floatingKeycaps.count - 16)
        }
    }

    // MARK: - 60 FPS Simulation Step

    func step(dt rawDt: CGFloat, windowFrameInScreen: CGRect, scripted: ScriptedFrameInput? = nil) {
        let dt = min(rawDt, 1.0 / 25.0)
        time += dt

        let engine = InputEngine.shared
        if scripted == nil {
            engine.pollMouse(dt: dt)
        }

        let now = scripted?.now ?? CACurrentMediaTime()
        let activeKeys = scripted?.activeKeys ?? engine.activeKeys
        let orderedKeys = scripted?.orderedKeys ?? engine.pressedOrder
        let curMouseVel = scripted?.mouseVelocity ?? engine.mouseVelocity
        let curMouseLoc = scripted?.mouseScreenPos ?? engine.lastMouseLocation
        let curLeftMouse = scripted?.leftMouseDown ?? engine.leftMouseDown
        let curRightMouse = scripted?.rightMouseDown ?? engine.rightMouseDown
        let curLastMouseMove = scripted?.lastMouseMoveTime ?? engine.lastMouseMoveTime
        let curLastMouseClick = scripted?.lastMouseClickTime ?? engine.lastMouseClickTime
        let curLastKeyTime = scripted?.lastKeyActivityTime ?? engine.lastKeyActivityTime

        // 1. Decay petting intensity gracefully when hand stops moving
        if now - lastPetTime > 0.28 {
            petHeadIntensity = max(0, petHeadIntensity - dt * 1.4)
            petBodyIntensity = max(0, petBodyIntensity - dt * 1.2)
            if petHeadIntensity < 0.05 && petBodyIntensity < 0.05 {
                isCurrentlyPetting = false
                petStrokeAccumulator = 0
            }
        } else if (petHeadIntensity > 0.55 || petBodyIntensity > 0.55) {
            petSparkleCooldown -= dt
            if petSparkleCooldown <= 0 {
                petSparkleCooldown = 0.42
                let sx = CatPhysics.seatAnchor.x + CGFloat.random(in: -44...44)
                let sy = 88 + CGFloat.random(in: -14...18)
                sparkles.append(PurrSparkle(
                    position: CGPoint(x: sx, y: sy),
                    velocity: CGPoint(x: CGFloat.random(in: -10...10), y: -24),
                    isSleepZ: false
                ))
            }
        }

        // 2. Sleepy idle detection (+ cute yawn right before drifting off to sleep!)
        let lastAnyActivity = max(curLastKeyTime, max(curLastMouseMove, lastPetTime))
        let idleSeconds = lastAnyActivity > 0 ? (now - lastAnyActivity) : 0
        if activeKeys.isEmpty && idleSeconds > 42 && !isYawning && !hasYawnedThisIdle {
            isYawning = true
            hasYawnedThisIdle = true
            yawnTimer = 0
        }
        if !activeKeys.isEmpty || idleSeconds < 5 {
            isYawning = false
            hasYawnedThisIdle = false
            yawnAmount = max(0, yawnAmount - dt * 6.0)
        } else if isYawning {
            yawnTimer += dt
            if yawnTimer < 0.65 {
                let u = yawnTimer / 0.65
                yawnAmount = u * u * (3 - 2 * u)
            } else if yawnTimer < 1.55 {
                yawnAmount = 1.0
            } else if yawnTimer < 2.35 {
                let u = (2.35 - yawnTimer) / 0.80
                yawnAmount = u * u * (3 - 2 * u)
            } else {
                yawnAmount = 0
                isYawning = false
            }
        } else {
            yawnAmount = max(0, yawnAmount - dt * 4.0)
        }
        if activeKeys.isEmpty && idleSeconds > 45 {
            let targetSleep = min(1.0, CGFloat((idleSeconds - 45) / 35.0))
            sleepiness += (targetSleep - sleepiness) * dt * 1.5
            if sleepiness > 0.8 {
                sleepZCooldown -= dt
                if sleepZCooldown <= 0 {
                    sleepZCooldown = 2.6
                    sparkles.append(PurrSparkle(
                        position: CGPoint(x: CatPhysics.seatAnchor.x + 42, y: 100),
                        velocity: CGPoint(x: 12, y: -18),
                        isSleepZ: true
                    ))
                }
            }
        } else {
            sleepiness = max(0, sleepiness - dt * 5.0)
        }

        // 2b. Fast Mouse Movement -> Hunting / Stalking Mode (dilated round boba pupils + low crouch!)
        // Sustained > 10s of rapid mouse shaking -> Dizzy spiral eyes & slump beside keyboard!
        let mouseSpeed = hypot(curMouseVel.dx, curMouseVel.dy)
        if !isScruffDragging && dizzyTimer <= 0 && mouseSpeed > 1500 && petHeadIntensity < 0.25 && petBodyIntensity < 0.25 {
            // Only rapid mouse shaking/flicking triggers hunting dilation (ignore casual movement)
            let boost = min(1.0, (mouseSpeed - 1500) / 1800.0)
            huntIntensity.target = min(1.0, huntIntensity.target + (0.40 + boost * 1.25) * dt)
            sleepiness = 0
        } else {
            // Calm down quickly once cursor stops darting
            huntIntensity.target = max(0.0, huntIntensity.target - dt * 1.15)
        }
        huntIntensity.step(dt: dt, stiffness: 85, damping: 16)
        let hunt = max(0, min(1, huntIntensity.value))

        if !isScruffDragging && dizzyTimer <= 0 && hunt > 0.42 {
            fastMouseDuration += dt
            if fastMouseDuration >= 10.0 {
                dizzyTimer = 6.0
                fastMouseDuration = 0
                huntIntensity.target = 0
                sleepiness = 0
            }
        } else if dizzyTimer <= 0 {
            fastMouseDuration = max(0, fastMouseDuration - dt * 1.5)
        }
        if dizzyTimer > 0 {
            dizzyTimer = max(0, dizzyTimer - dt)
            dizzyIntensity.target = 1.0
            dizzyPhase += dt * 7.5
        } else if fastMouseDuration > 6.8 {
            // Stage 2 (6.8s -> 10.0s): Pre-dizzy warning — stars appear first, then spiral eyes & upright wobble!
            let pre = min(1.0, (fastMouseDuration - 6.8) / 3.2)
            dizzyIntensity.target = pre * 0.48
            dizzyPhase += dt * 7.5
        } else {
            dizzyIntensity.target = 0.0
        }
        dizzyIntensity.step(dt: dt, stiffness: 75, damping: 14)
        let dizzy = max(0, min(1, dizzyIntensity.value))

        // 2c. Scruff-drag pickup, idle lie-on-keyboard, and fast-typing anger
        scruffDrag.target = isScruffDragging ? 1.0 : 0.0
        scruffSwing.target = isScruffDragging ? max(-0.34, min(0.34, -scruffDragDx * 0.018)) : 0.0
        scruffDragDx *= 0.82
        scruffDrag.step(dt: dt, stiffness: 170, damping: 16)
        scruffSwing.step(dt: dt, stiffness: 110, damping: 10)
        let scruff = max(0, min(1, scruffDrag.value))

        lieIntensity.target = (!isScruffDragging && dizzyTimer <= 0 && sleepiness > 0.65)
            ? min(1.0, (sleepiness - 0.65) / 0.30) : 0.0
        lieIntensity.step(dt: dt, stiffness: 55, damping: 14)
        let lie = max(0, min(1, lieIntensity.value))

        let kpm = CGFloat(engine.currentKPM)
        angerIntensity.target = (!isScruffDragging && dizzyTimer <= 0 && kpm >= 240)
            ? min(1.0, (kpm - 240.0) / 140.0) : 0.0
        angerIntensity.step(dt: dt, stiffness: 70, damping: 14)
        let anger = max(0, min(1, angerIntensity.value))

        // 3. Determine limb targets (Left Paw, Right Paw, 3rd-Key Hind Foot!)
        let tapHoldWindow: CFTimeInterval = 0.14
        let mouseRecent = (now - curLastMouseMove < 2.2) || curLeftMouse || curRightMouse
        let mouseActivelyUsed = (now - curLastMouseMove < 0.75) || curLeftMouse || curRightMouse

        // Partition active keys
        var leftCandidates: [PhysicalKey] = []
        var rightCandidates: [PhysicalKey] = []
        for k in orderedKeys {
            if k.prefersLeftPaw { leftCandidates.append(k) }
            else { rightCandidates.append(k) }
        }

        var leftKey: PhysicalKey? = leftCandidates.last
        var rightKey: PhysicalKey? = rightCandidates.last
        var footKey: PhysicalKey? = nil

        // If 2+ keys are pressed on the same side, let the free paw help —
        // UNLESS viewer-left paw (cat's right hand) is actively driving the mouse!
        if leftKey == nil && rightCandidates.count >= 2 && !mouseActivelyUsed {
            let sorted = rightCandidates.sorted {
                KeyboardLayout.canvasPoint(for: $0).x < KeyboardLayout.canvasPoint(for: $1).x
            }
            leftKey = sorted.first
            rightKey = sorted.last
        } else if rightKey == nil && leftCandidates.count >= 2 {
            let sorted = leftCandidates.sorted {
                KeyboardLayout.canvasPoint(for: $0).x < KeyboardLayout.canvasPoint(for: $1).x
            }
            leftKey = sorted.first
            rightKey = sorted.last
        }

        // 3+ simultaneous keys (or 2+ keys while other hand is busy on the mouse!) -> HIND FOOT EASTER EGG!!
        if CatSettings.shared.footEasterEgg {
            if orderedKeys.count >= 3 {
                footKey = orderedKeys.first { $0 != leftKey && $0 != rightKey }
            } else if mouseActivelyUsed && leftKey == nil && rightCandidates.count >= 2 {
                footKey = rightCandidates.first { $0 != rightKey }
            }
        }

        // Keep quick taps visible for a tiny snappy window
        if leftKey == nil, let rec = recentLeftKey, now - rec.time < tapHoldWindow {
            leftKey = rec.key
        }
        if rightKey == nil, let rec = recentRightKey, now - rec.time < tapHoldWindow {
            rightKey = rec.key
        }

        // Subtle mini-mouse movement driven by global cursor velocity
        let targetMouseDx = max(-5.5, min(5.5, curMouseVel.dx * 0.0045))
        let targetMouseDy = max(-4.5, min(4.5, -curMouseVel.dy * 0.0045))
        mouseOffset.target = CGPoint(x: targetMouseDx, y: targetMouseDy)
        mouseOffset.step(dt: dt, stiffness: 120, damping: 16)
        mousePressLeft.step(dt: dt, stiffness: 400, damping: 24)
        mousePressRight.step(dt: dt, stiffness: 400, damping: 24)

        let liveMouseCenter = CGPoint(
            x: CatPhysics.mouseBaseCenter.x + mouseOffset.point.x,
            y: CatPhysics.mouseBaseCenter.y + mouseOffset.point.y
        )

        // Graphics Tablet & Stylus mode (auto-switches when tablet/pen connected!)
        let tMode = CatSettings.shared.tabletMode
        isTabletActive = (tMode == 1) || (tMode == 0 && engine.isTabletConnected)
        if isTabletActive {
            let screenFrame = (NSScreen.screens.first { $0.frame.contains(curMouseLoc) } ?? NSScreen.main)?.frame
                ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            let nx = max(0, min(1, (curMouseLoc.x - screenFrame.minX) / max(1, screenFrame.width)))
            let ny = max(0, min(1, 1.0 - (curMouseLoc.y - screenFrame.minY) / max(1, screenFrame.height)))
            tabletNib.target = CatPhysics.tabletQuadPoint(u: 0.25 + nx * 0.64, v: 0.16 + ny * 0.68)
            tabletNib.step(dt: dt, stiffness: 240, damping: 20)
            let penDown = curLeftMouse || engine.penPressure > 0.02
            tabletPenPress.target = penDown ? max(0.65, min(1.0, engine.penPressure > 0.02 ? engine.penPressure : 0.85)) : 0.0
            tabletPenPress.step(dt: dt, stiffness: 360, damping: 22)
            tabletPenTilt.target = max(-0.22, min(0.22, curMouseVel.dx * 0.00018))
            tabletPenTilt.step(dt: dt, stiffness: 120, damping: 14)
        } else {
            tabletPenPress.target = 0
            tabletPenPress.step(dt: dt, stiffness: 300, damping: 22)
        }
        for i in stride(from: tabletTrail.count - 1, through: 0, by: -1) {
            tabletTrail[i].age += dt
            if tabletTrail[i].age >= 0.72 { tabletTrail.remove(at: i) }
        }

        // Left paw target (dangles limply during scruff pickup / sprawls when dizzy / tucks when lying)
        if scruff > 0.35 {
            leftPaw.target = CGPoint(x: CatPhysics.seatAnchor.x - 16 + scruffSwing.value * 26, y: CatPhysics.seatAnchor.y + 12)
            leftPawTyping = true
            leftPawOnMouse = false
        } else if dizzy > 0.35 {
            // Relaxed paws staying natural inside the toppled cat frame
            leftPaw.target = CatPhysics.leftPawRest
            leftPawTyping = false
            leftPawOnMouse = false
        } else if let lk = leftKey {
            leftPaw.target = KeyboardLayout.canvasPoint(for: lk)
            leftPawTyping = true
            leftPawOnMouse = false
        } else if (mouseRecent || (isTabletActive && engine.isPenInProximity)) && sleepiness < 0.3 {
            if isTabletActive {
                let nib = tabletNib.point
                leftPaw.target = CGPoint(x: nib.x + 6, y: nib.y - 7)
                if curLeftMouse || engine.penPressure > 0.02 {
                    let last = tabletTrail.last?.point
                    if last == nil || hypot(nib.x - last!.x, nib.y - last!.y) >= 1.8 {
                        tabletTrail.append(TabletStrokePoint(point: nib, age: 0))
                        if tabletTrail.count > 28 { tabletTrail.removeFirst() }
                    }
                }
            } else {
                leftPaw.target = CGPoint(x: liveMouseCenter.x + 2, y: liveMouseCenter.y - 3)
            }
            leftPawTyping = false
            leftPawOnMouse = true
        } else {
            // Keep paws tucked neatly in rest position when curling into a sleeping cat ball!
            leftPaw.target = CatPhysics.leftPawRest
            leftPawTyping = false
            leftPawOnMouse = false
        }

        // Right paw target
        if scruff > 0.35 {
            rightPaw.target = CGPoint(x: CatPhysics.seatAnchor.x + 16 + scruffSwing.value * 26, y: CatPhysics.seatAnchor.y + 12)
            rightPawTyping = true
        } else if dizzy > 0.35 {
            rightPaw.target = CatPhysics.rightPawRest
            rightPawTyping = false
        } else if let rk = rightKey {
            rightPaw.target = KeyboardLayout.canvasPoint(for: rk)
            rightPawTyping = true
        } else {
            rightPaw.target = CatPhysics.rightPawRest
            rightPawTyping = false
        }

        // Hind foot target (3rd simultaneous key!)
        if let fk = footKey {
            hindFoot.target = KeyboardLayout.canvasPoint(for: fk)
            hindFootActive.target = 1.0
        } else {
            hindFoot.target = CatPhysics.hindFootRest
            hindFootActive.target = 0.0
        }

        // Held physical keys determine the mode; repeats and mouse buttons do not count.
        tailTyping.target = (CatSettings.shared.tailEasterEgg && activeKeys.count == 4) ? 1 : 0
        tailTyping.step(dt: dt, stiffness: 180, damping: 24)
        // Marquee chase across the keyboard deck: steady sweep, faster while many keys are held.
        if CatSettings.shared.keyboardMarquee {
            marqueeBoost.target = max(0, min(1, (CGFloat(activeKeys.count) - 2) / 5))
            marqueeBoost.step(dt: dt, stiffness: 90, damping: 20)
            marqueePhase = (marqueePhase + dt * (0.42 + 0.40 * marqueeBoost.value)).truncatingRemainder(dividingBy: 1.0)
        }
        let tailKey = orderedKeys.first { $0 != leftKey && $0 != rightKey && $0 != footKey }
        var tip = tailTyping.target > 0 ? tailKey.map { KeyboardLayout.canvasPoint(for: $0) } ?? CGPoint(x: 275, y: 196) : CGPoint(x: 275, y: 196)
        tip.y -= tailTyping.target * (1 + sin(time * 18)) * 3
        tailTip.target = tip
        tailTip.step(dt: dt, stiffness: 280, damping: 26)

        tailFlickHold = max(0, tailFlickHold - dt)
        tailFlickCooldown = max(0, tailFlickCooldown - dt)
        if tailFlickHold <= 0 {
            tailFlick.target = .zero
            tailCurl.target = 0
            tailAgility.target = 0
        }
        tailFlick.step(dt: dt, stiffness: 150, damping: 12)
        tailCurl.step(dt: dt, stiffness: 135, damping: 10.5)
        tailAgility.step(dt: dt, stiffness: 40, damping: 10)

        leftPaw.step(dt: dt, stiffness: 360, damping: 24)
        rightPaw.step(dt: dt, stiffness: 360, damping: 24)
        hindFoot.step(dt: dt, stiffness: 320, damping: 22)
        hindFootActive.step(dt: dt, stiffness: 260, damping: 22)

        // 4. Expressive body lean, squash, head & ears
        var targetShiftX: CGFloat = 0
        var targetBodyTilt: CGFloat = 0
        if leftPawOnMouse && !rightPawTyping {
            targetShiftX = -10
            targetBodyTilt = -0.075
        } else if leftPawOnMouse && rightPawTyping {
            targetShiftX = -3
            targetBodyTilt = (rightPaw.point.x - 196) * 0.0008
        } else if leftPawTyping || rightPawTyping {
            let avgX = ((leftPawTyping ? leftPaw.point.x : 184) + (rightPawTyping ? rightPaw.point.x : 184)) * 0.5
            targetShiftX = (avgX - 184) * 0.14
            targetBodyTilt = (avgX - 184) * 0.0011
        }
        bodyShiftX.target = max(-16, min(16, targetShiftX))
        bodyTilt.target = max(-0.12, min(0.12, targetBodyTilt)) + scruffSwing.value * scruff
        // Keep body sleek & natural during lie/dizzy (zero fat distortion; renderer handles smooth rigid fall & forward sprawl!)
        bodySquash.target = 1.0 - hunt * 0.11 + scruff * 0.16

        headOffsetY.target = ((leftPawTyping || rightPawTyping) ? 3.5 : (sleepiness * 5.0 + hunt * 10.5))
            - scruff * 10.0
        earFold.target = max(petHeadIntensity * 0.7, petBodyIntensity * 0.45) + sleepiness * 0.25 - hunt * 0.18
            + scruff * 0.35 + anger * 0.45 + dizzy * 0.35
        earTwitch.target = 0

        bodyShiftX.step(dt: dt, stiffness: 140, damping: 18)
        bodyTilt.step(dt: dt, stiffness: 140, damping: 18)
        bodySquash.step(dt: dt, stiffness: 280, damping: 18)
        headOffsetY.step(dt: dt, stiffness: 180, damping: 19)
        earFold.step(dt: dt, stiffness: 120, damping: 16)
        earTwitch.step(dt: dt, stiffness: 320, damping: 16)

        // 5. 2.5D Head Turning (Yaw + Pitch) + Eye Tracking!
        // Head smoothly turns in pseudo-3D toward the mouse cursor (or subtly nods down toward keys while typing).
        let typingRecently = !activeKeys.isEmpty || (now - curLastKeyTime < 0.65)
        let mouseMovedRecently = (now - curLastMouseMove < 1.2)
        let eyeOriginCanvas = CGPoint(x: CatPhysics.seatAnchor.x + bodyShiftX.value, y: 124 + headOffsetY.value)

        // Compute normalized vector from cat head to real macOS screen cursor
        let scale = max(0.2, windowFrameInScreen.width / CatPhysics.canvasSize.width)
        let headScreenX = windowFrameInScreen.minX + eyeOriginCanvas.x * scale
        let headScreenY = windowFrameInScreen.maxY - eyeOriginCanvas.y * scale
        let cursor = curMouseLoc
        let curDx = (cursor.x - headScreenX) / 290.0
        let curDy = -(cursor.y - headScreenY) / 260.0
        let curMag = hypot(curDx, curDy)
        let clampedCur = min(1.0, curMag)
        let cursorNX = curMag > 0.001 ? (curDx / curMag) * clampedCur : 0
        let cursorNY = curMag > 0.001 ? (curDy / curMag) * clampedCur : 0

        let lookTargetX: CGFloat
        let lookTargetY: CGFloat
        if typingRecently && !mouseMovedRecently, let keyPt = lastTypedPoint {
            let kdx = max(-0.85, min(0.85, (keyPt.x - eyeOriginCanvas.x) / 95.0))
            let kdy = max(-0.3, min(0.92, (keyPt.y - eyeOriginCanvas.y) / 125.0))
            lookTargetX = kdx
            lookTargetY = kdy
        } else if typingRecently && mouseMovedRecently, let keyPt = lastTypedPoint {
            // Blend mouse & typing naturally when gaming with mouse + keyboard!
            let kdx = max(-0.85, min(0.85, (keyPt.x - eyeOriginCanvas.x) / 95.0))
            lookTargetX = cursorNX * 0.72 + kdx * 0.28
            lookTargetY = cursorNY * 0.72 + 0.25
        } else {
            lookTargetX = cursorNX
            lookTargetY = cursorNY
        }

        // Head turns smoothly in 2.5D (yaw & pitch) — locks on faster during hunting mode!
        if sleepiness > 0.45 {
            headYaw.target = 0
            headPitch.target = 0.45 * sleepiness
        } else {
            headYaw.target = max(-1.0, min(1.0, lookTargetX))
            headPitch.target = max(-1.0, min(1.0, lookTargetY))
        }
        let headStiff: CGFloat = 88 + hunt * 75
        let headDamp: CGFloat = 14.5 + hunt * 4.5
        headYaw.step(dt: dt, stiffness: headStiff, damping: headDamp)
        headPitch.step(dt: dt, stiffness: headStiff, damping: headDamp)

        // Subtle natural head roll coupled to head turning (curious tilt / locked-on hunt!)
        if now - lastPetTime > 0.28 {
            headTilt.target = bodyTilt.target * 0.45 + headYaw.value * (0.11 + hunt * 0.05) - headYaw.value * headPitch.value * 0.04 + lie * 0.12
        }
        headTilt.step(dt: dt, stiffness: 130, damping: 16)

        // Eyes lead slightly ahead of the 2.5D head turn
        eyeGaze.target = CGPoint(x: lookTargetX * 0.88, y: lookTargetY * 0.85)
        eyeGaze.step(dt: dt, stiffness: 210 + hunt * 80, damping: 21)

        // Pupil dilation
        if hindFootActive.value > 0.3 {
            pupilScale.target = 1.24
        } else if now - curLastKeyTime > 0.45 && now - curLastMouseClick > 0.45 {
            pupilScale.target = 1.0
        }
        pupilScale.step(dt: dt, stiffness: 150, damping: 18)

        // 6. Blinking (cats lock eyes without blinking during hunting mode!)
        if isBlinking {
            blinkTimer += dt
            let blinkDuration: CGFloat = 0.14
            if blinkTimer >= blinkDuration {
                isBlinking = false
                blinkProgress = 0
                nextBlinkTime = time + CGFloat.random(in: 2.6...5.6)
            } else {
                let p = blinkTimer / blinkDuration
                blinkProgress = sin(p * .pi)
            }
        } else if time >= nextBlinkTime && sleepiness < 0.5 && petHeadIntensity < 0.3 && hunt < 0.35 {
            isBlinking = true
            blinkTimer = 0
        }

        // 7. Tail wag speed reacts organically to energy / petting / hunting tension!
        let kpmBoost = min(2.4, CGFloat(engine.currentKPM) / 160.0)
        let petBoost = max(petHeadIntensity, petBodyIntensity) * 1.4
        let huntBoost = hunt * 2.8
        let agilityBoost = max(0, min(1, tailAgility.value)) * 3.2
        let angerBoost = anger * 3.5
        let tailSpeed: CGFloat = 1.85 + kpmBoost + petBoost + huntBoost + agilityBoost + angerBoost - sleepiness * 1.1
        tailPhase += dt * tailSpeed

        // 8. Update per-keycap glows
        let visualActive = Set(activeKeys.map { $0.visualKey })
        for (k, v) in keyGlow {
            if visualActive.contains(k) {
                keyGlow[k] = 1.0
            } else {
                let next = v - dt * 4.5
                if next <= 0.01 { keyGlow.removeValue(forKey: k) }
                else { keyGlow[k] = next }
            }
        }
        for vk in visualActive {
            keyGlow[vk] = 1.0
        }

        // 9. Update floating keycaps
        for i in floatingKeycaps.indices.reversed() {
            floatingKeycaps[i].age += dt
            floatingKeycaps[i].position.x += floatingKeycaps[i].velocity.x * dt
            floatingKeycaps[i].position.y += floatingKeycaps[i].velocity.y * dt
            floatingKeycaps[i].velocity.x *= (1.0 - dt * 2.4)
            floatingKeycaps[i].velocity.y *= (1.0 - dt * 1.6)
            if floatingKeycaps[i].age >= floatingKeycaps[i].lifetime {
                floatingKeycaps.remove(at: i)
            }
        }

        // 10. Update purr / sleep particles
        for i in sparkles.indices.reversed() {
            sparkles[i].age += dt
            sparkles[i].position.x += sparkles[i].velocity.x * dt
            sparkles[i].position.y += sparkles[i].velocity.y * dt
            if sparkles[i].age >= sparkles[i].lifetime {
                sparkles.remove(at: i)
            }
        }
    }
}
