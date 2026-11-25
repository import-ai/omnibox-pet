import Foundation
import CoreGraphics
import AppKit

enum CatHitZone {
    case none
    case head
    case body
    case permissionPill
}

enum CatRenderer {

    private static func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(calibratedRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }

    static let permissionPillRect = CGRect(x: 92, y: 294, width: 176, height: 22)
    static let editFlipButtonRect = CGRect(x: 94, y: 12, width: 82, height: 24)
    static let editDoneButtonRect = CGRect(x: 184, y: 12, width: 82, height: 24)
    static let editCorners: [CGPoint] = [
        CGPoint(x: 10, y: 10),   // 0: top-left
        CGPoint(x: 350, y: 10),  // 1: top-right
        CGPoint(x: 10, y: 310),  // 2: bottom-left
        CGPoint(x: 350, y: 310)  // 3: bottom-right
    ]

    /// Edit-mode hit test in unflipped 360x320 canvas coordinates:
    /// 0..3 = corner resize handles, 10 = flip button, 11 = done button, 12 = inside edit box, -1 = outside.
    static func hitTestEditOverlay(point p: CGPoint) -> Int {
        if editFlipButtonRect.insetBy(dx: -2, dy: -2).contains(p) { return 10 }
        if editDoneButtonRect.insetBy(dx: -2, dy: -2).contains(p) { return 11 }
        for (idx, c) in editCorners.enumerated() {
            if hypot(p.x - c.x, p.y - c.y) <= 18.0 { return idx }
        }
        if CGRect(x: 6, y: 6, width: 348, height: 308).contains(p) { return 12 }
        return -1
    }

    /// Hit test in 360x320 logical canvas coordinates for smart click-through & petting.
    static func hitTest(point p: CGPoint, physics: CatPhysics, showPermissionPill: Bool) -> CatHitZone {
        if showPermissionPill && permissionPillRect.insetBy(dx: -4, dy: -4).contains(p) {
            return .permissionPill
        }

        if XiaoheiRenderer.hitTestHead(point: p, physics: physics, showPaws: CatSettings.shared.xiaoheiPaws) {
            return .head
        }

        // Mini keyboard & mouse area (allows dragging by grabbing keyboard too)
        let kbRect = CGRect(x: 58, y: 232, width: 236, height: 64)
        if kbRect.contains(p) {
            return .body
        }

        return .none
    }

    /// Main 60fps draw routine in flipped 360x320 logical coordinate space.
    static func draw(in ctx: CGContext, physics: CatPhysics, showPermissionPill: Bool,
                     permissionPillText: String = "点击开启全局/游戏键盘监听 🔑") {
        ctx.saveGState()
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        let settings = CatSettings.shared
        if settings.obsCaptureMode == 2 {
            ctx.setFillColor(NSColor(calibratedRed: 0.0, green: 1.0, blue: 0.0, alpha: 1.0).cgColor)
            ctx.fill(CGRect(origin: .zero, size: CatPhysics.canvasSize))
        }
        let flipped = settings.flipHorizontal
        if flipped {
            ctx.saveGState()
            ctx.translateBy(x: CatPhysics.canvasSize.width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
        let scruff = max(0, min(1, physics.scruffDrag.value))
        let lie = max(0, min(1, physics.lieIntensity.value))
        let dizzy = max(0, min(1, physics.dizzyIntensity.value))
        let showPaws = settings.xiaoheiPaws

        // Peeking layout: Xiaohei hides behind the keyboard, so draw the head first, then the
        // mouse/keyboard in front of it (covering the lower head), and finally the floating paws.
        XiaoheiRenderer.drawHead(in: ctx, physics: physics, showPaws: showPaws)

        // 1. Mini White Mouse OR Graphics Tablet (when drawing tablet/stylus is connected!)
        if physics.isTabletActive {
            drawTablet(in: ctx, physics: physics, theme: settings.keyboardTheme, eyeTheme: settings.eyeTheme)
            if !showPaws || !physics.leftPawOnMouse || scruff > 0.25 || dizzy > 0.35 || lie > 0.45 {
                drawParkedStylus(in: ctx, theme: settings.keyboardTheme, eyeTheme: settings.eyeTheme)
            }
        } else {
            drawMouse(in: ctx, physics: physics, theme: settings.keyboardTheme)
        }

        // 2. Mini Angled 65% Mechanical Keyboard + Dynamic Keycap Glow
        drawKeyboard(in: ctx, physics: physics, theme: settings.keyboardTheme, eyeTheme: settings.eyeTheme, showLegends: settings.showKeyLegends, flipped: flipped, marquee: settings.keyboardMarquee)

        // 3. Detached floating paws on the keyboard and mouse (derived design, switchable).
        if showPaws {
            XiaoheiRenderer.drawPaws(in: ctx, physics: physics)
            if physics.isTabletActive && physics.leftPawOnMouse && scruff <= 0.25 && dizzy <= 0.35 && lie <= 0.45 {
                drawHeldStylus(in: ctx, physics: physics, theme: settings.keyboardTheme, eyeTheme: settings.eyeTheme)
            }
        }
        XiaoheiRenderer.drawEasterEggImpacts(in: ctx, physics: physics)

        // Upright orbiting golden dizzy stars floating right above the head
        if dizzy > 0.10 {
            let head = XiaoheiRenderer.headCenter(physics, showPaws: showPaws)
            let worldHeadX = head.x
            let worldHeadY = head.y
            let dAlpha = min(1.0, (dizzy - 0.10) / 0.22)
            let starLift: CGFloat = XiaoheiRenderer.starLift
            ctx.saveGState()
            ctx.translateBy(x: worldHeadX, y: worldHeadY - starLift)
            for i in 0..<3 {
                let ang = physics.dizzyPhase * 0.85 + CGFloat(i) * (.pi * 2.0 / 3.0)
                let sx = cos(ang) * 26.0
                let sy = sin(ang) * 6.5
                let r: CGFloat = 4.4 * (0.75 + 0.25 * sin(ang))
                ctx.saveGState()
                ctx.translateBy(x: sx, y: sy)
                ctx.rotate(by: physics.dizzyPhase + CGFloat(i))
                ctx.setFillColor(NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.22, alpha: 0.96 * dAlpha).cgColor)
                let star = CGMutablePath()
                for k in 0..<8 {
                    let rad = (k % 2 == 0) ? r : r * 0.42
                    let a = CGFloat(k) * .pi * 0.25
                    let pt = CGPoint(x: cos(a) * rad, y: sin(a) * rad)
                    if k == 0 { star.move(to: pt) } else { star.addLine(to: pt) }
                }
                star.closeSubpath()
                ctx.addPath(star)
                ctx.fillPath()
                ctx.restoreGState()
            }
            ctx.restoreGState()
        }

        // 8. Floating Mechanical Keycap Badges (keyboard + mouse clicks)
        if !physics.floatingKeycaps.isEmpty {
            drawFloatingKeycaps(in: ctx, physics: physics)
        }

        // 9. Subtle Petting Sparkles / Sleep Z
        drawSparkles(in: ctx, physics: physics, eyeTheme: settings.eyeTheme)

        if flipped {
            ctx.restoreGState()
        }

        // 10. Interactive Resize & Flip Edit Box (drawn unflipped on top)
        if settings.isEditMode {
            drawEditOverlay(in: ctx, isEnglish: settings.isEnglish, scale: settings.scale)
        }

        // 11. Optional non-intrusive Permission Pill if global monitoring not yet granted
        if showPermissionPill {
            drawPermissionPill(in: ctx, text: permissionPillText)
        }

        ctx.restoreGState()
    }

    private static func drawEditOverlay(in ctx: CGContext, isEnglish: Bool, scale: CGFloat) {
        ctx.saveGState()
        let boxRect = CGRect(x: 10, y: 10, width: 340, height: 300)
        let boxPath = CGPath(roundedRect: boxRect, cornerWidth: 12, cornerHeight: 12, transform: nil)

        ctx.setFillColor(NSColor(calibratedRed: 0.16, green: 0.56, blue: 0.98, alpha: 0.07).cgColor)
        ctx.addPath(boxPath)
        ctx.fillPath()

        ctx.setStrokeColor(NSColor(calibratedRed: 0.20, green: 0.62, blue: 1.0, alpha: 0.92).cgColor)
        ctx.setLineWidth(1.8)
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        ctx.addPath(boxPath)
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])

        for c in editCorners {
            let r: CGFloat = 6.5
            let hRect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: hRect)
            ctx.setStrokeColor(NSColor(calibratedRed: 0.14, green: 0.52, blue: 0.96, alpha: 1.0).cgColor)
            ctx.setLineWidth(2.0)
            ctx.strokeEllipse(in: hRect)
        }

        func drawBtn(_ rect: CGRect, title: String, primary: Bool) {
            let p = CGPath(roundedRect: rect, cornerWidth: 11, cornerHeight: 11, transform: nil)
            let fill = primary
                ? NSColor(calibratedRed: 0.16, green: 0.54, blue: 0.96, alpha: 0.95)
                : NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.19, alpha: 0.88)
            ctx.setFillColor(fill.cgColor)
            ctx.addPath(p)
            ctx.fillPath()
            ctx.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.28).cgColor)
            ctx.setLineWidth(0.9)
            ctx.addPath(p)
            ctx.strokePath()

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let ns = NSAttributedString(string: title, attributes: attrs)
            let sz = ns.size()
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            ns.draw(at: CGPoint(x: rect.midX - sz.width * 0.5, y: rect.midY - sz.height * 0.5))
            NSGraphicsContext.restoreGraphicsState()
        }

        drawBtn(editFlipButtonRect, title: isEnglish ? "⇄ Flip" : "⇄ 翻转", primary: false)
        drawBtn(editDoneButtonRect, title: isEnglish ? "✓ Done" : "✓ 完成", primary: true)

        let scaleStr = String(format: "%.0f%%", scale * 100)
        let sAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let sns = NSAttributedString(string: scaleStr, attributes: sAttrs)
        let ssz = sns.size()
        let pill = CGRect(x: 180 - (ssz.width + 12) * 0.5, y: 298 - (ssz.height + 4) * 0.5, width: ssz.width + 12, height: ssz.height + 4)
        ctx.setFillColor(NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.16, alpha: 0.82).cgColor)
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 6, cornerHeight: 6, transform: nil))
        ctx.fillPath()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        sns.draw(at: CGPoint(x: pill.midX - ssz.width * 0.5, y: pill.midY - ssz.height * 0.5))
        NSGraphicsContext.restoreGraphicsState()

        ctx.restoreGState()
    }

    // MARK: - Mini White Mouse

    private static func drawMouse(in ctx: CGContext, physics: CatPhysics, theme: KeyboardTheme) {
        let center = CGPoint(
            x: CatPhysics.mouseBaseCenter.x + physics.mouseOffset.point.x,
            y: CatPhysics.mouseBaseCenter.y + physics.mouseOffset.point.y
        )
        let pressShift = max(physics.mousePressLeft.value, physics.mousePressRight.value) * 1.6

        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y + pressShift)
        ctx.rotate(by: 0.22) // angled naturally for the cat's right paw (facing the cat!)

        // Soft underside shadow
        ctx.saveGState()
        ctx.setFillColor(NSColor(calibratedWhite: 0.0, alpha: 0.24).cgColor)
        ctx.fillEllipse(in: CGRect(x: -13.5, y: -13.5 + 4.0, width: 27, height: 31))
        ctx.restoreGState()

        let bodyRect = CGRect(x: -13.5, y: -16.5, width: 27, height: 33)
        let bodyColor: NSColor
        let borderColor: NSColor
        let wheelColor: NSColor
        switch theme {
        case .classicMilk:
            bodyColor = NSColor(calibratedRed: 0.955, green: 0.950, blue: 0.925, alpha: 1.0)
            borderColor = NSColor(calibratedRed: 0.14, green: 0.14, blue: 0.16, alpha: 1.0)
            wheelColor = NSColor(calibratedRed: 0.96, green: 0.69, blue: 0.16, alpha: 1.0)
        case .midnightHacker:
            bodyColor = NSColor(calibratedRed: 0.20, green: 0.21, blue: 0.24, alpha: 1.0)
            borderColor = NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
            wheelColor = NSColor(calibratedRed: 0.78, green: 0.95, blue: 0.25, alpha: 1.0)
        case .retroCream:
            bodyColor = NSColor(calibratedRed: 0.89, green: 0.87, blue: 0.82, alpha: 1.0)
            borderColor = NSColor(calibratedRed: 0.20, green: 0.19, blue: 0.18, alpha: 1.0)
            wheelColor = NSColor(calibratedRed: 0.88, green: 0.42, blue: 0.24, alpha: 1.0)
        }

        // Mouse body (palm-rest dome toward cat at top, click buttons & scroll wheel away from cat at bottom!)
        ctx.setFillColor(bodyColor.cgColor)
        ctx.fillEllipse(in: bodyRect)

        // Subtle click flash highlight (cat-facing: left button = inner right side, right button = outer left side!)
        if physics.mousePressLeft.value > 0.05 {
            ctx.saveGState()
            ctx.addEllipse(in: bodyRect)
            ctx.clip()
            ctx.setFillColor(NSColor(calibratedRed: 0.79, green: 0.95, blue: 0.25, alpha: 0.38 * physics.mousePressLeft.value).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 14, height: 17))
            ctx.restoreGState()
        }
        if physics.mousePressRight.value > 0.05 {
            ctx.saveGState()
            ctx.addEllipse(in: bodyRect)
            ctx.clip()
            ctx.setFillColor(NSColor(calibratedRed: 0.79, green: 0.95, blue: 0.25, alpha: 0.38 * physics.mousePressRight.value).cgColor)
            ctx.fill(CGRect(x: -14, y: 0, width: 14, height: 17))
            ctx.restoreGState()
        }

        // Button split seam pointing forward (bottom, away from cat!)
        ctx.setStrokeColor(borderColor.withAlphaComponent(0.32).cgColor)
        ctx.setLineWidth(1.05)
        ctx.move(to: CGPoint(x: 0, y: 16))
        ctx.addLine(to: CGPoint(x: 0, y: 1.5))
        ctx.strokePath()

        // Signature amber scroll wheel on the front (bottom) half facing away from cat
        let wheelRect = CGRect(x: -1.9, y: 2.5, width: 3.8, height: 8.5)
        let wheelPath = CGPath(roundedRect: wheelRect, cornerWidth: 1.9, cornerHeight: 1.9, transform: nil)
        ctx.setFillColor(wheelColor.cgColor)
        ctx.addPath(wheelPath)
        ctx.fillPath()

        // Outer crisp outline
        ctx.setStrokeColor(borderColor.cgColor)
        ctx.setLineWidth(1.7)
        ctx.strokeEllipse(in: bodyRect)

        ctx.restoreGState()
    }

    // MARK: - Mini 2.5D Graphics Tablet & Stylus (数位板与触控笔)

    private static func drawTablet(in ctx: CGContext, physics: CatPhysics, theme: KeyboardTheme, eyeTheme: EyeColorTheme) {
        let tl = CatPhysics.tabletQuadPoint(u: 0, v: 0)
        let tr = CatPhysics.tabletQuadPoint(u: 1, v: 0)
        let bl = CatPhysics.tabletQuadPoint(u: 0, v: 1)
        let br = CatPhysics.tabletQuadPoint(u: 1, v: 1)
        let depth: CGFloat = 3.6

        let baseColor: NSColor
        let bodyColor: NSColor
        let padColor: NSColor
        let keyColor: NSColor
        let accentColor: NSColor
        switch theme {
        case .classicMilk:
            baseColor = NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)
            bodyColor = NSColor(calibratedRed: 0.17, green: 0.18, blue: 0.21, alpha: 1.0)
            padColor  = NSColor(calibratedRed: 0.23, green: 0.24, blue: 0.28, alpha: 1.0)
            keyColor  = NSColor(calibratedRed: 0.30, green: 0.32, blue: 0.37, alpha: 1.0)
            accentColor = NSColor(calibratedRed: 0.96, green: 0.69, blue: 0.16, alpha: 1.0)
        case .midnightHacker:
            baseColor = NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)
            bodyColor = NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.15, alpha: 1.0)
            padColor  = NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.21, alpha: 1.0)
            keyColor  = NSColor(calibratedRed: 0.24, green: 0.25, blue: 0.30, alpha: 1.0)
            accentColor = NSColor(calibratedRed: 0.78, green: 0.95, blue: 0.25, alpha: 1.0)
        case .retroCream:
            baseColor = NSColor(calibratedRed: 0.22, green: 0.21, blue: 0.19, alpha: 1.0)
            bodyColor = NSColor(calibratedRed: 0.33, green: 0.31, blue: 0.28, alpha: 1.0)
            padColor  = NSColor(calibratedRed: 0.42, green: 0.39, blue: 0.35, alpha: 1.0)
            keyColor  = NSColor(calibratedRed: 0.54, green: 0.50, blue: 0.45, alpha: 1.0)
            accentColor = NSColor(calibratedRed: 0.88, green: 0.42, blue: 0.24, alpha: 1.0)
        }

        // Ambient drop shadow beneath tablet
        ctx.saveGState()
        let shadowPath = roundedQuadPath(
            tl: CGPoint(x: tl.x, y: tl.y + depth + 2.0),
            tr: CGPoint(x: tr.x, y: tr.y + depth + 2.0),
            br: CGPoint(x: br.x, y: br.y + depth + 2.6),
            bl: CGPoint(x: bl.x, y: bl.y + depth + 2.6),
            radius: 5.5
        )
        ctx.setFillColor(NSColor(calibratedWhite: 0, alpha: 0.22).cgColor)
        ctx.addPath(shadowPath)
        ctx.fillPath()
        ctx.restoreGState()

        // 3D lower slab lip
        let lowerPath = roundedQuadPath(
            tl: CGPoint(x: tl.x, y: tl.y + depth),
            tr: CGPoint(x: tr.x, y: tr.y + depth),
            br: CGPoint(x: br.x, y: br.y + depth),
            bl: CGPoint(x: bl.x, y: bl.y + depth),
            radius: 5.0
        )
        ctx.setFillColor(baseColor.cgColor)
        ctx.addPath(lowerPath)
        ctx.fillPath()

        // Main slate tablet deck
        let topPath = roundedQuadPath(tl: tl, tr: tr, br: br, bl: bl, radius: 4.5)
        ctx.setFillColor(bodyColor.cgColor)
        ctx.addPath(topPath)
        ctx.fillPath()

        // Crisp subtle bezel rim
        ctx.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.14).cgColor)
        ctx.setLineWidth(0.9)
        ctx.addPath(topPath)
        ctx.strokePath()

        // Active drawing surface recessed pad
        let pTL = CatPhysics.tabletQuadPoint(u: 0.21, v: 0.11)
        let pTR = CatPhysics.tabletQuadPoint(u: 0.94, v: 0.11)
        let pBR = CatPhysics.tabletQuadPoint(u: 0.94, v: 0.89)
        let pBL = CatPhysics.tabletQuadPoint(u: 0.21, v: 0.89)
        let padPath = roundedQuadPath(tl: pTL, tr: pTR, br: pBR, bl: pBL, radius: 2.6)
        ctx.setFillColor(padColor.cgColor)
        ctx.addPath(padPath)
        ctx.fillPath()

        // Minimalist active-area corner L-brackets ([ ])
        ctx.saveGState()
        ctx.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.34).cgColor)
        ctx.setLineWidth(0.95)
        ctx.setLineCap(.round)
        let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0.24, 0.15,  0.07,  0.11),
            (0.91, 0.15, -0.07,  0.11),
            (0.24, 0.85,  0.07, -0.11),
            (0.91, 0.85, -0.07, -0.11)
        ]
        for (cu, cv, du, dv) in corners {
            let c = CatPhysics.tabletQuadPoint(u: cu, v: cv)
            let h = CatPhysics.tabletQuadPoint(u: cu + du, v: cv)
            let v = CatPhysics.tabletQuadPoint(u: cu, v: cv + dv)
            ctx.move(to: h); ctx.addLine(to: c); ctx.addLine(to: v)
        }
        ctx.strokePath()
        ctx.restoreGState()

        // 4 miniature ExpressKeys along outer-left bezel + status LED
        let ledPt = CatPhysics.tabletQuadPoint(u: 0.105, v: 0.14)
        let ledCol = physics.tabletPenPress.value > 0.15 ? eyeTheme.primaryColor : accentColor
        drawRadialGlow(in: ctx, center: ledPt, radius: 4.5, color: ledCol.withAlphaComponent(0.55))
        ctx.setFillColor(ledCol.cgColor)
        ctx.fillEllipse(in: CGRect(x: ledPt.x - 1.35, y: ledPt.y - 1.35, width: 2.7, height: 2.7))

        for kv: CGFloat in [0.28, 0.44, 0.60, 0.76] {
            let kTL = CatPhysics.tabletQuadPoint(u: 0.06, v: kv - 0.05)
            let kTR = CatPhysics.tabletQuadPoint(u: 0.15, v: kv - 0.05)
            let kBR = CatPhysics.tabletQuadPoint(u: 0.15, v: kv + 0.05)
            let kBL = CatPhysics.tabletQuadPoint(u: 0.06, v: kv + 0.05)
            let kp = roundedQuadPath(tl: kTL, tr: kTR, br: kBR, bl: kBL, radius: 1.2)
            ctx.setFillColor(keyColor.cgColor)
            ctx.addPath(kp)
            ctx.fillPath()
        }

        // Live fading glowing ink trail on the active drawing surface!
        if physics.tabletTrail.count >= 2 {
            ctx.saveGState()
            ctx.addPath(padPath)
            ctx.clip()
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            let inkCol = eyeTheme.primaryColor
            for i in 1..<physics.tabletTrail.count {
                let a = physics.tabletTrail[i - 1]
                let b = physics.tabletTrail[i]
                if hypot(b.point.x - a.point.x, b.point.y - a.point.y) > 22.0 { continue }
                let life = max(0.0, 1.0 - b.age / 0.72)
                if life <= 0.01 { continue }
                ctx.setStrokeColor(inkCol.withAlphaComponent(life * 0.88).cgColor)
                ctx.setLineWidth(1.2 + life * 1.4)
                ctx.move(to: a.point)
                ctx.addLine(to: b.point)
                ctx.strokePath()
            }
            ctx.restoreGState()
        }

        // Subtle glowing nib contact halo when drawing on the pad
        if physics.leftPawOnMouse && physics.tabletPenPress.value > 0.08 {
            let nib = physics.tabletNib.point
            drawRadialGlow(
                in: ctx,
                center: nib,
                radius: 7.5 + physics.tabletPenPress.value * 4.0,
                color: eyeTheme.primaryColor.withAlphaComponent(0.45 * physics.tabletPenPress.value)
            )
        }
    }

    /// Draws a sleek stylus oriented along +X from tip (0,0) to rounded cap (len,0).
    private static func drawStylusBody(in ctx: CGContext, length: CGFloat, theme: KeyboardTheme, eyeTheme: EyeColorTheme, pressed: CGFloat) {
        let barrelCol: NSColor
        let gripCol: NSColor
        let ringCol: NSColor
        switch theme {
        case .classicMilk:
            barrelCol = NSColor(calibratedRed: 0.18, green: 0.19, blue: 0.23, alpha: 1.0)
            gripCol   = NSColor(calibratedRed: 0.28, green: 0.30, blue: 0.35, alpha: 1.0)
            ringCol   = NSColor(calibratedRed: 0.96, green: 0.69, blue: 0.16, alpha: 1.0)
        case .midnightHacker:
            barrelCol = NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.17, alpha: 1.0)
            gripCol   = NSColor(calibratedRed: 0.22, green: 0.24, blue: 0.29, alpha: 1.0)
            ringCol   = NSColor(calibratedRed: 0.78, green: 0.95, blue: 0.25, alpha: 1.0)
        case .retroCream:
            barrelCol = NSColor(calibratedRed: 0.28, green: 0.26, blue: 0.24, alpha: 1.0)
            gripCol   = NSColor(calibratedRed: 0.42, green: 0.39, blue: 0.35, alpha: 1.0)
            ringCol   = NSColor(calibratedRed: 0.88, green: 0.42, blue: 0.24, alpha: 1.0)
        }

        // Tapered pen silhouette (nib at x=0 -> tapered cone x=7 -> ergonomic barrel -> rounded eraser cap at x=length)
        let penPath = CGMutablePath()
        penPath.move(to: CGPoint(x: 0.0, y: 0.0))
        penPath.addLine(to: CGPoint(x: 7.5, y: -2.4))
        penPath.addLine(to: CGPoint(x: length - 3.0, y: -2.6))
        penPath.addQuadCurve(to: CGPoint(x: length, y: 0.0), control: CGPoint(x: length, y: -2.4))
        penPath.addQuadCurve(to: CGPoint(x: length - 3.0, y: 2.6), control: CGPoint(x: length, y: 2.4))
        penPath.addLine(to: CGPoint(x: 7.5, y: 2.4))
        penPath.closeSubpath()

        // Crisp subtle bright outer halo so stylus reads cleanly over dark fur/backgrounds
        ctx.saveGState()
        ctx.setStrokeColor(NSColor(calibratedWhite: 0.96, alpha: 0.80).cgColor)
        ctx.setLineWidth(1.6)
        ctx.setLineJoin(.round)
        ctx.addPath(penPath)
        ctx.strokePath()
        ctx.restoreGState()

        ctx.setFillColor(barrelCol.cgColor)
        ctx.addPath(penPath)
        ctx.fillPath()

        // Rubberized grip sleeve + dual side-button rocker
        ctx.saveGState()
        ctx.addPath(penPath)
        ctx.clip()
        ctx.setFillColor(gripCol.cgColor)
        ctx.fill(CGRect(x: 7.5, y: -3.0, width: 11.5, height: 6.0))
        // Signature metallic accent ring between grip & upper barrel
        ctx.setFillColor(ringCol.cgColor)
        ctx.fill(CGRect(x: 19.0, y: -3.0, width: 2.4, height: 6.0))
        // Fine light stylus nib tip (glows slightly in eye theme color when pressing down!)
        let nibCol = pressed > 0.15 ? eyeTheme.primaryColor : NSColor(calibratedWhite: 0.94, alpha: 1.0)
        ctx.setFillColor(nibCol.cgColor)
        ctx.fill(CGRect(x: -0.5, y: -1.5, width: 3.4, height: 3.0))
        // Subtle specular sheen along upper barrel
        ctx.setFillColor(NSColor(calibratedWhite: 1.0, alpha: 0.24).cgColor)
        ctx.fill(CGRect(x: 8.0, y: -1.9, width: length - 12.0, height: 1.1))
        ctx.restoreGState()

        // Side shortcut rocker button
        let btn = CGPath(roundedRect: CGRect(x: 11.0, y: -3.1, width: 6.0, height: 1.4), cornerWidth: 0.7, cornerHeight: 0.7, transform: nil)
        ctx.setFillColor(NSColor(calibratedWhite: 0.78, alpha: 0.90).cgColor)
        ctx.addPath(btn)
        ctx.fillPath()
    }

    private static func drawParkedStylus(in ctx: CGContext, theme: KeyboardTheme, eyeTheme: EyeColorTheme) {
        // Neatly parked horizontally along the top bezel of the graphics tablet while typing/sleeping
        let nib = CatPhysics.tabletQuadPoint(u: 0.88, v: -0.02)
        let tail = CatPhysics.tabletQuadPoint(u: 0.18, v: -0.02)
        let ang = atan2(tail.y - nib.y, tail.x - nib.x)
        let len = hypot(tail.x - nib.x, tail.y - nib.y)

        ctx.saveGState()
        // Subtle resting shadow
        ctx.saveGState()
        ctx.translateBy(x: nib.x, y: nib.y + 2.2)
        ctx.rotate(by: ang)
        ctx.setFillColor(NSColor(calibratedWhite: 0, alpha: 0.22).cgColor)
        ctx.fill(CGRect(x: 2, y: -2.0, width: len - 4, height: 4.5))
        ctx.restoreGState()

        ctx.translateBy(x: nib.x, y: nib.y)
        ctx.rotate(by: ang)
        drawStylusBody(in: ctx, length: len, theme: theme, eyeTheme: eyeTheme, pressed: 0)
        ctx.restoreGState()
    }

    private static func drawHeldStylus(in ctx: CGContext, physics: CatPhysics, theme: KeyboardTheme, eyeTheme: EyeColorTheme) {
        let lPos = physics.leftPaw.point
        let press = max(0, min(1, physics.tabletPenPress.value))
        // Nib rests right at the front-bottom tip of the paw touching the tablet surface;
        // shaft angles cleanly upward-left away from the cat's arm so it's 100% crisp and clear!
        let nib = CGPoint(x: lPos.x - 5.5, y: lPos.y + 7.0 + press * 1.4)
        let angle: CGFloat = -2.18 + physics.tabletPenTilt.value

        ctx.saveGState()
        ctx.translateBy(x: nib.x, y: nib.y)
        ctx.rotate(by: angle)
        drawStylusBody(in: ctx, length: 35.0, theme: theme, eyeTheme: eyeTheme, pressed: press)
        ctx.restoreGState()
    }

    // MARK: - Mini Angled 65% Mechanical Keyboard (facing the cat!)

    private struct KeyboardBitmap {
        let image: CGImage
        let bounds: CGRect

        init?(bounds: CGRect, scale: CGSize, draw: (CGContext) -> Void) {
            let pixels = CGRect(x: bounds.minX * scale.width, y: bounds.minY * scale.height,
                                width: bounds.width * scale.width, height: bounds.height * scale.height).integral
            guard let ctx = CGContext(data: nil, width: Int(pixels.width), height: Int(pixels.height),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.translateBy(x: -pixels.minX, y: pixels.maxY)
            ctx.scaleBy(x: scale.width, y: -scale.height)
            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)
            draw(ctx)
            guard let image = ctx.makeImage() else { return nil }
            self.image = image
            self.bounds = CGRect(x: pixels.minX / scale.width, y: pixels.minY / scale.height,
                                 width: pixels.width / scale.width, height: pixels.height / scale.height)
        }

        func draw(in ctx: CGContext) {
            ctx.saveGState()
            ctx.translateBy(x: bounds.minX, y: bounds.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(origin: .zero, size: bounds.size))
            ctx.restoreGState()
        }
    }

    private struct KeyboardStyle: Equatable {
        let theme: KeyboardTheme
        let showLegends: Bool
        let flipped: Bool
        let scale: CGSize
    }

    private struct KeyboardArtwork {
        let style: KeyboardStyle
        let chassis: KeyboardBitmap?
        let idle: KeyboardBitmap?
        let keys: [KeyboardKeyArtwork]
        let deckPath: CGPath
        let deckStart: CGPoint
        let deckEnd: CGPoint
    }

    private struct KeyboardKeyArtwork {
        let key: PhysicalKey
        let center: CGPoint
        let path: CGPath
        let fill: NSColor
        let border: CGColor
        let legend: KeyboardBitmap?
        let resting: KeyboardBitmap?
    }

    // Keep only the currently displayed keyboard. Retina scale can change when the window moves screens.
    private static var keyboardArtwork: KeyboardArtwork?

    private static func drawKeyboard(
        in ctx: CGContext,
        physics: CatPhysics,
        theme: KeyboardTheme,
        eyeTheme: EyeColorTheme,
        showLegends: Bool,
        flipped: Bool,
        marquee: Bool
    ) {
        let transform = ctx.userSpaceToDeviceSpaceTransform
        // Round up in quarter steps so dragging a resize handle does not rebuild the cache every tick.
        func rasterScale(_ value: CGFloat) -> CGFloat { min(4, max(1, (value * 4).rounded(.up) / 4)) }
        let scale = CGSize(width: rasterScale(hypot(transform.a, transform.b)),
                           height: rasterScale(hypot(transform.c, transform.d)))
        let style = KeyboardStyle(theme: theme, showLegends: showLegends, flipped: flipped, scale: scale)
        if keyboardArtwork?.style != style {
            keyboardArtwork = makeKeyboardArtwork(style: style)
        }
        guard let artwork = keyboardArtwork else { return }

        let glowBaseColor = eyeTheme.glowColor
        if !marquee, physics.keyGlow.isEmpty, let idle = artwork.idle {
            idle.draw(in: ctx)
        } else {
            artwork.chassis?.draw(in: ctx)
            let phase = physics.marqueePhase.truncatingRemainder(dividingBy: 1)
            let backlight = marquee
                ? KeyboardMarquee(phase: phase, color: hsvColor(hue: phase + 0.52, saturation: 0.55, value: 1),
                                  start: artwork.deckStart, end: artwork.deckEnd)
                : nil
            if let backlight { drawMarquee(backlight, in: ctx, clippedTo: artwork.deckPath) }
            for key in artwork.keys {
                drawKeyboardKey(key, in: ctx, glow: physics.keyGlow[key.key] ?? 0,
                                glowColor: glowBaseColor, backlight: backlight)
            }
        }

        // Signature soft chartreuse backlit glow halos on active keys!
        for (key, glow) in physics.keyGlow where glow > 0.05 {
            let center = KeyboardLayout.canvasPoint(for: key)
            drawRadialGlow(in: ctx, center: center, radius: 17.0 + glow * 6.0,
                           color: glowBaseColor.withAlphaComponent(0.36 * glow))
        }
    }

    private static func makeKeyboardArtwork(style: KeyboardStyle) -> KeyboardArtwork {
        let tl = KeyboardLayout.screenQuadPoint(su: -0.012, sv: -0.04)
        let tr = KeyboardLayout.screenQuadPoint(su: 1.012, sv: -0.04)
        let bl = KeyboardLayout.screenQuadPoint(su: -0.016, sv: 1.04)
        let br = KeyboardLayout.screenQuadPoint(su: 1.016, sv: 1.04)

        let caseDepth: CGFloat = 4.5

        let shadowPath = roundedQuadPath(
            tl: CGPoint(x: tl.x, y: tl.y + caseDepth + 2),
            tr: CGPoint(x: tr.x, y: tr.y + caseDepth + 2),
            br: CGPoint(x: br.x, y: br.y + caseDepth + 3),
            bl: CGPoint(x: bl.x, y: bl.y + caseDepth + 3),
            radius: 6
        )

        // Dark 3D chassis lower lip
        let baseColor: NSColor
        let deckColor: NSColor
        let keyColor: NSColor
        let keyBorderColor: NSColor
        let accentColor: NSColor

        switch style.theme {
        case .classicMilk:
            baseColor = NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)
            deckColor = NSColor(calibratedRed: 0.14, green: 0.14, blue: 0.16, alpha: 1.0)
            keyColor = NSColor(calibratedRed: 0.968, green: 0.964, blue: 0.942, alpha: 1.0)
            keyBorderColor = NSColor(calibratedRed: 0.78, green: 0.77, blue: 0.74, alpha: 0.75)
            accentColor = NSColor(calibratedRed: 0.97, green: 0.70, blue: 0.16, alpha: 1.0)
        case .midnightHacker:
            baseColor = NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.08, alpha: 1.0)
            deckColor = NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.13, alpha: 1.0)
            keyColor = NSColor(calibratedRed: 0.21, green: 0.22, blue: 0.25, alpha: 1.0)
            keyBorderColor = NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 0.95)
            accentColor = NSColor(calibratedRed: 0.77, green: 0.94, blue: 0.25, alpha: 1.0)
        case .retroCream:
            baseColor = NSColor(calibratedRed: 0.25, green: 0.24, blue: 0.22, alpha: 1.0)
            deckColor = NSColor(calibratedRed: 0.38, green: 0.36, blue: 0.33, alpha: 1.0)
            keyColor = NSColor(calibratedRed: 0.90, green: 0.88, blue: 0.82, alpha: 1.0)
            keyBorderColor = NSColor(calibratedRed: 0.68, green: 0.65, blue: 0.60, alpha: 0.85)
            accentColor = NSColor(calibratedRed: 0.88, green: 0.42, blue: 0.24, alpha: 1.0)
        }

        let lowerChassis = roundedQuadPath(
            tl: CGPoint(x: tl.x, y: tl.y + caseDepth),
            tr: CGPoint(x: tr.x, y: tr.y + caseDepth),
            br: CGPoint(x: br.x, y: br.y + caseDepth),
            bl: CGPoint(x: bl.x, y: bl.y + caseDepth),
            radius: 5.5
        )
        let topChassis = roundedQuadPath(tl: tl, tr: tr, br: br, bl: bl, radius: 5.0)
        let bounds = shadowPath.boundingBoxOfPath.union(lowerChassis.boundingBoxOfPath)
            .union(topChassis.boundingBoxOfPath).insetBy(dx: -2, dy: -2)
        let chassis = KeyboardBitmap(bounds: bounds, scale: style.scale) { ctx in
            ctx.setFillColor(NSColor(calibratedWhite: 0, alpha: 0.22).cgColor)
            ctx.addPath(shadowPath)
            ctx.fillPath()
            ctx.setFillColor(baseColor.cgColor)
            ctx.addPath(lowerChassis)
            ctx.fillPath()
            ctx.setFillColor(deckColor.cgColor)
            ctx.addPath(topChassis)
            ctx.fillPath()
        }

        // Individual keycaps — tight clean mechanical spacing matching the reference video
        let padU: CGFloat = 0.0028
        let padV: CGFloat = 0.014
        let border = keyBorderColor.cgColor

        let keys = KeyboardLayout.keycaps.map { cap in
            // 180° rotated to face the cat: su = 1 - u, sv = 1 - v
            let su0 = (1.0 - (cap.xUnits + cap.widthUnits)) + padU
            let su1 = (1.0 - cap.xUnits) - padU
            let sv0 = (1.0 - CGFloat(cap.row + 1) / 5.0) + padV
            let sv1 = (1.0 - CGFloat(cap.row) / 5.0) - padV

            let kTL = KeyboardLayout.screenQuadPoint(su: su0, sv: sv0)
            let kTR = KeyboardLayout.screenQuadPoint(su: su1, sv: sv0)
            let kBR = KeyboardLayout.screenQuadPoint(su: su1, sv: sv1)
            let kBL = KeyboardLayout.screenQuadPoint(su: su0, sv: sv1)

            let kPath = roundedQuadPath(tl: kTL, tr: kTR, br: kBR, bl: kBL, radius: 1.6)
            let center = CGPoint(x: (kTL.x + kTR.x + kBR.x + kBL.x) * 0.25,
                                 y: (kTL.y + kTR.y + kBR.y + kBL.y) * 0.25)
            let fill = cap.isAmberAccent ? accentColor : keyColor
            let keyBounds = kPath.boundingBoxOfPath.insetBy(dx: -2, dy: -2)
            var legendBitmap: KeyboardBitmap?
            if style.showLegends {
                let isSpace = cap.key == .space
                let legend = isSpace ? "space" : keycapLegend(cap.key)
                if !legend.isEmpty {
                    var labelCenter = center
                    if isSpace {
                        // The spacebar sits right under the cat: its legs hide the middle, and an
                        // unlabeled visible end looked like an odd blank patch beside the cat.
                        // Label the end that stays visible instead.
                        labelCenter = KeyboardLayout.screenQuadPoint(su: su0 + (su1 - su0) * 0.82, sv: (sv0 + sv1) * 0.5)
                    }
                    let textColor: NSColor
                    if cap.isAmberAccent || style.theme != .midnightHacker {
                        textColor = NSColor(calibratedRed: 0.14, green: 0.14, blue: 0.16, alpha: 0.78)
                    } else {
                        textColor = NSColor(calibratedRed: 0.88, green: 0.90, blue: 0.92, alpha: 0.82)
                    }
                    let fontSize: CGFloat = legend.count <= 1 ? 5.2 : 4.2
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                        .foregroundColor: textColor
                    ]
                    let str = NSAttributedString(string: legend, attributes: attrs)
                    let size = str.size()
                    let textRect = CGRect(x: -size.width * 0.5, y: -size.height * 0.5,
                                          width: size.width, height: size.height)
                    // Keyboard faces the cat (180°), so legends read upright from the cat's seat.
                    var transform = CGAffineTransform(translationX: labelCenter.x, y: labelCenter.y).rotated(by: .pi + 0.052)
                    if style.flipped { transform = transform.scaledBy(x: -1, y: 1) }
                    legendBitmap = KeyboardBitmap(bounds: textRect.applying(transform).insetBy(dx: -2, dy: -2),
                                                  scale: style.scale) { ctx in
                        ctx.concatenate(transform)
                        NSGraphicsContext.saveGraphicsState()
                        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
                        str.draw(at: textRect.origin)
                        NSGraphicsContext.restoreGraphicsState()
                    }
                }
            }
            let restingBounds = legendBitmap.map { keyBounds.union($0.bounds) } ?? keyBounds
            let resting = KeyboardBitmap(bounds: restingBounds, scale: style.scale) { ctx in
                drawKeycap(in: ctx, path: kPath, fill: fill.cgColor, border: border)
                legendBitmap?.draw(in: ctx)
            }
            return KeyboardKeyArtwork(key: cap.key, center: center, path: kPath, fill: fill, border: border,
                                      legend: legendBitmap, resting: resting)
        }

        let idle = KeyboardBitmap(bounds: bounds, scale: style.scale) { ctx in
            chassis?.draw(in: ctx)
            for key in keys {
                drawKeyboardKey(key, in: ctx, glow: 0, glowColor: accentColor)
            }
        }
        return KeyboardArtwork(style: style, chassis: chassis, idle: idle, keys: keys,
                               deckPath: topChassis, deckStart: tl, deckEnd: br)
    }

    private static func drawKeyboardKey(_ key: KeyboardKeyArtwork, in ctx: CGContext, glow: CGFloat,
                                        glowColor: NSColor, backlight: KeyboardMarquee? = nil) {
        if backlight == nil, glow == 0, let resting = key.resting {
            resting.draw(in: ctx)
            return
        }

        let pressDepth = glow * 1.9
        let center = CGPoint(x: key.center.x, y: key.center.y + pressDepth)
        let illumination = backlight?.illumination(at: center) ?? 0
        var color = key.fill
        if let backlight, illumination > 0.015 {
            let lit = blendColor(backlight.color, .white, t: illumination * illumination * 0.5)
            color = blendColor(color, lit, t: illumination * 0.88)
        }
        if glow > 0.02 {
            color = blendColor(color, glowColor, t: glow * 0.55)
        }

        ctx.saveGState()
        ctx.translateBy(x: 0, y: pressDepth)
        if let backlight, illumination > 0.10 {
            let border = backlight.color.withAlphaComponent(illumination * 215.0 / 255.0).cgColor
            drawKeycap(in: ctx, path: key.path, fill: color.cgColor, border: border, borderWidth: 1.0)
        } else {
            drawKeycap(in: ctx, path: key.path, fill: color.cgColor, border: key.border)
        }
        if let backlight, illumination > 0.45 {
            ctx.saveGState()
            ctx.translateBy(x: key.center.x, y: key.center.y)
            ctx.scaleBy(x: 15.0, y: 10.5)
            let bloom = (illumination - 0.45) / 0.55
            drawRadialGlow(in: ctx, center: .zero, radius: 1.0,
                           color: backlight.color.withAlphaComponent(bloom * 135.0 / 255.0))
            ctx.restoreGState()
        }
        key.legend?.draw(in: ctx)
        ctx.restoreGState()
    }

    private static func drawKeycap(in ctx: CGContext, path: CGPath, fill: CGColor, border: CGColor,
                                   borderWidth: CGFloat = 0.65) {
        ctx.setFillColor(fill)
        ctx.setStrokeColor(border)
        ctx.setLineWidth(borderWidth)
        ctx.addPath(path)
        ctx.drawPath(using: .fillStroke)
    }

    private struct KeyboardMarquee {
        let phase: CGFloat
        let color: NSColor
        let start: CGPoint
        let end: CGPoint
        let dx: CGFloat
        let dy: CGFloat
        let lengthSquared: CGFloat

        init(phase: CGFloat, color: NSColor, start: CGPoint, end: CGPoint) {
            self.phase = phase
            self.color = color
            self.start = start
            self.end = end
            dx = end.x - start.x
            dy = end.y - start.y
            lengthSquared = dx * dx + dy * dy
        }

        func illumination(at center: CGPoint) -> CGFloat {
            let t = ((center.x - start.x) * dx + (center.y - start.y) * dy) / lengthSquared
            return wave(at: max(0, min(1, t)))
        }

        func wave(at t: CGFloat) -> CGFloat {
            let distance = phase - t
            return exp(-(distance < 0 ? distance + 1 : distance) / 0.125)
        }
    }

    private static func drawMarquee(_ light: KeyboardMarquee, in ctx: CGContext, clippedTo deck: CGPath) {
        ctx.saveGState()
        ctx.addPath(deck)
        ctx.clip()
        let stops = (0..<24).map { CGFloat($0) / 23 }
        let colors = stops.map { stop in
            light.color.withAlphaComponent(light.wave(at: stop) * 200.0 / 255.0).cgColor
        }
        if let band = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: stops) {
            ctx.drawLinearGradient(band, start: light.start, end: light.end,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        let head = CGPoint(x: light.start.x + light.dx * light.phase, y: light.start.y + light.dy * light.phase)
        drawRadialGlow(in: ctx, center: head, radius: 44.0,
                       color: NSColor(calibratedRed: 240.0 / 255, green: 252.0 / 255, blue: 1, alpha: 150.0 / 255))
        ctx.restoreGState()
    }

    // MARK: - Floating Mechanical Keycap Popups

    private static func drawFloatingKeycaps(in ctx: CGContext, physics: CatPhysics) {
        for badge in physics.floatingKeycaps {
            let progress = badge.age / badge.lifetime
            // Spring pop-in scale (starts crisp and readable immediately!)
            let scale: CGFloat
            if badge.age < 0.09 {
                let t = badge.age / 0.09
                scale = 0.72 + 0.38 * sin(t * .pi * 0.65)
            } else if badge.age < 0.18 {
                let t = (badge.age - 0.09) / 0.09
                scale = 1.10 - 0.10 * t
            } else {
                scale = 1.0
            }

            let alpha: CGFloat = progress < 0.62 ? 1.0 : max(0, 1.0 - (progress - 0.62) / 0.38)

            let charCount = badge.label.count
            let fontSize: CGFloat = charCount <= 1 ? 11.5 : 10.0
            let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
            ]
            let attrStr = NSAttributedString(string: badge.label, attributes: attrs)
            let strSize = attrStr.size()
            let w: CGFloat = max(23, ceil(strSize.width) + 12)
            let h: CGFloat = 22

            ctx.saveGState()
            ctx.setAlpha(alpha)
            ctx.translateBy(x: badge.position.x, y: badge.position.y)
            ctx.rotate(by: badge.rotation)
            ctx.scaleBy(x: CatSettings.shared.flipHorizontal ? -scale : scale, y: scale)

            // 3D bottom keycap edge / shadow
            let baseRect = CGRect(x: -w * 0.5, y: -h * 0.5 + 2.5, width: w, height: h)
            let basePath = CGPath(roundedRect: baseRect, cornerWidth: 5.5, cornerHeight: 5.5, transform: nil)
            ctx.setFillColor(NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.17, alpha: 0.95).cgColor)
            ctx.addPath(basePath)
            ctx.fillPath()

            // Crisp white mechanical keycap top face
            let faceRect = CGRect(x: -w * 0.5, y: -h * 0.5, width: w, height: h)
            let facePath = CGPath(roundedRect: faceRect, cornerWidth: 5.2, cornerHeight: 5.2, transform: nil)
            ctx.setFillColor(NSColor(calibratedRed: 0.975, green: 0.972, blue: 0.952, alpha: 1.0).cgColor)
            ctx.addPath(facePath)
            ctx.fillPath()

            ctx.setStrokeColor(NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.18, alpha: 1.0).cgColor)
            ctx.setLineWidth(1.45)
            ctx.addPath(facePath)
            ctx.strokePath()

            // Centered bold key label
            let drawPt = CGPoint(x: -strSize.width * 0.5, y: -strSize.height * 0.5 - 0.5)
            NSGraphicsContext.saveGraphicsState()
            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
            NSGraphicsContext.current = nsCtx
            attrStr.draw(at: drawPt)
            NSGraphicsContext.restoreGraphicsState()

            ctx.restoreGState()
        }
    }

    // MARK: - Subtle Petting Sparkles & Sleep Z

    private static func drawSparkles(in ctx: CGContext, physics: CatPhysics, eyeTheme: EyeColorTheme) {
        for sp in physics.sparkles {
            let p = sp.age / sp.lifetime
            let alpha = sin(min(1.0, p) * .pi)
            ctx.saveGState()
            ctx.setAlpha(alpha * 0.85)
            if sp.isSleepZ {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11 + p * 3, weight: .bold),
                    .foregroundColor: eyeTheme.primaryColor
                ]
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
                NSAttributedString(string: "z", attributes: attrs).draw(at: sp.position)
                NSGraphicsContext.restoreGraphicsState()
            } else {
                // Tiny glowing chartreuse 4-point star
                let r: CGFloat = 3.5 + p * 1.5
                ctx.translateBy(x: sp.position.x, y: sp.position.y)
                ctx.setFillColor(eyeTheme.primaryColor.cgColor)
                let star = CGMutablePath()
                star.move(to: CGPoint(x: 0, y: -r))
                star.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0.8, y: -0.8))
                star.addQuadCurve(to: CGPoint(x: 0, y: r), control: CGPoint(x: 0.8, y: 0.8))
                star.addQuadCurve(to: CGPoint(x: -r, y: 0), control: CGPoint(x: -0.8, y: 0.8))
                star.addQuadCurve(to: CGPoint(x: 0, y: -r), control: CGPoint(x: -0.8, y: -0.8))
                star.closeSubpath()
                ctx.addPath(star)
                ctx.fillPath()
            }
            ctx.restoreGState()
        }
    }

    // MARK: - Non-Intrusive Permission Pill

    private static func drawPermissionPill(in ctx: CGContext, text: String) {
        let r = permissionPillRect
        let path = CGPath(roundedRect: r, cornerWidth: 11, cornerHeight: 11, transform: nil)

        ctx.saveGState()
        ctx.setFillColor(NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 0.90).cgColor)
        ctx.addPath(path)
        ctx.fillPath()

        ctx.setStrokeColor(NSColor(calibratedRed: 0.79, green: 0.95, blue: 0.25, alpha: 0.90).cgColor)
        ctx.setLineWidth(1.2)
        ctx.addPath(path)
        ctx.strokePath()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 0.95, green: 0.97, blue: 0.90, alpha: 1.0)
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let sz = str.size()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        str.draw(at: CGPoint(x: r.midX - sz.width * 0.5, y: r.midY - sz.height * 0.5 - 0.5))
        NSGraphicsContext.restoreGraphicsState()

        ctx.restoreGState()
    }

    // MARK: - Geometry & Color Helpers

    private static func keycapLegend(_ key: PhysicalKey) -> String {
        switch key {
        case .escape: return "ESC"
        case .tab: return "⇥"
        case .capsLock: return "⇪"
        case .leftShift, .rightShift: return "⇧"
        case .leftControl, .rightControl: return "⌃"
        case .leftOption, .rightOption: return "⌥"
        case .leftCommand, .rightCommand: return "⌘"
        case .backspace: return "⌫"
        case .enter: return "↵"
        case .space: return ""
        default: return key.badgeLabel
        }
    }

    private static func quadPoint(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, t: CGFloat) -> CGPoint {
        let mt = 1 - t
        return CGPoint(
            x: mt * mt * p0.x + 2 * mt * t * p1.x + t * t * p2.x,
            y: mt * mt * p0.y + 2 * mt * t * p1.y + t * t * p2.y
        )
    }

    private static func quadTangent(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, t: CGFloat) -> CGPoint {
        let mt = 1 - t
        return CGPoint(
            x: 2 * mt * (p1.x - p0.x) + 2 * t * (p2.x - p1.x),
            y: 2 * mt * (p1.y - p0.y) + 2 * t * (p2.y - p1.y)
        )
    }

    private static func roundedQuadPath(
        tl: CGPoint, tr: CGPoint, br: CGPoint, bl: CGPoint, radius: CGFloat
    ) -> CGPath {
        let p = CGMutablePath()
        let midTop = CGPoint(x: (tl.x + tr.x) * 0.5, y: (tl.y + tr.y) * 0.5)
        p.move(to: midTop)
        p.addArc(tangent1End: tr, tangent2End: br, radius: radius)
        p.addArc(tangent1End: br, tangent2End: bl, radius: radius)
        p.addArc(tangent1End: bl, tangent2End: tl, radius: radius)
        p.addArc(tangent1End: tl, tangent2End: tr, radius: radius)
        p.closeSubpath()
        return p
    }

    /// HSV → RGB, used by the keyboard marquee for its one-hue-cycle-per-sweep backlight.
    private static func hsvColor(hue h: CGFloat, saturation s: CGFloat, value v: CGFloat) -> NSColor {
        var hue = h.truncatingRemainder(dividingBy: 1.0)
        if hue < 0 { hue += 1 }
        let c = v * s
        let x = c * (1 - abs((hue * 6.0).truncatingRemainder(dividingBy: 2.0) - 1))
        let m = v - c
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        switch Int(hue * 6.0) % 6 {
        case 0: r = c; g = x
        case 1: r = x; g = c
        case 2: g = c; b = x
        case 3: g = x; b = c
        case 4: r = x; b = c
        default: r = c; b = x
        }
        return NSColor(calibratedRed: r + m, green: g + m, blue: b + m, alpha: 1.0)
    }

    private static func blendColor(_ a: NSColor, _ b: NSColor, t: CGFloat) -> NSColor {
        let ca = a.usingColorSpace(.deviceRGB) ?? a
        let cb = b.usingColorSpace(.deviceRGB) ?? b
        let clamped = max(0, min(1, t))
        return NSColor(
            calibratedRed: ca.redComponent + (cb.redComponent - ca.redComponent) * clamped,
            green: ca.greenComponent + (cb.greenComponent - ca.greenComponent) * clamped,
            blue: ca.blueComponent + (cb.blueComponent - ca.blueComponent) * clamped,
            alpha: ca.alphaComponent + (cb.alphaComponent - ca.alphaComponent) * clamped
        )
    }

    private static func drawRadialGlow(in ctx: CGContext, center: CGPoint, radius: CGFloat, color: NSColor) {
        let cs = CGColorSpaceCreateDeviceRGB()
        let colors = [color.cgColor, color.withAlphaComponent(0.0).cgColor] as CFArray
        let locs: [CGFloat] = [0.0, 1.0]
        if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: locs) {
            ctx.saveGState()
            ctx.drawRadialGradient(
                grad,
                startCenter: center, startRadius: 0,
                endCenter: center, endRadius: radius,
                options: []
            )
            ctx.restoreGState()
        }
    }
}
