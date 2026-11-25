import AppKit
import CoreGraphics

/// Draws Xiaohei, the head-only black cat of 小黑 OmniBox, in place of the KuroCat body.
///
/// Xiaohei's base design is a head with two ears and two round eyes.
/// No nose, mouth, muzzle, whiskers, body, neck, tail, eyebrows or pupil highlights are ever drawn.
/// Emotions use gaze, eye shape, tilt and external symbols only.
///
/// Desktop-pet adaptation (derived design, draft, requested by the project owner): Xiaohei peeks out
/// from behind the keyboard, which hides the lower half of the head. Two detached floating paws press
/// the keys and the mouse; they follow the floating paw language of the 「记笔记」/「赶工」 stickers and
/// never connect to the head. They can be switched off, leaving just the peeking head, which then nods
/// toward the keys.
enum XiaoheiRenderer {
    static let ink = CGColor(srgbRed: 23.0 / 255.0, green: 23.0 / 255.0, blue: 23.0 / 255.0, alpha: 1)
    static let cream = CGColor(srgbRed: 254.0 / 255.0, green: 246.0 / 255.0, blue: 236.0 / 255.0, alpha: 1)

    /// SVG units -> logical canvas points. The 486-unit-wide head becomes ~146 pt on the 360x320 canvas.
    static let k: CGFloat = 0.30
    /// Head pivot in SVG space (horizontal centre, vertical centre of the head without ears).
    private static let svgPivot = CGPoint(x: 320, y: 413)
    private static let svgChinY: CGFloat = 594
    /// Canvas Y of the head pivot at rest: the eyes sit just above the keyboard, the chin hides behind it.
    private static let restHeadY: CGFloat = 208
    /// Lift of the dizzy stars above the head pivot.
    static let starLift: CGFloat = 92

    // MARK: - Keyboard occlusion

    /// Far (top) edge of the keyboard chassis, matching `CatRenderer.makeKeyboardArtwork`.
    private static let kbEdgeLeft = KeyboardLayout.screenQuadPoint(su: -0.012, sv: -0.04)
    private static let kbEdgeRight = KeyboardLayout.screenQuadPoint(su: 1.012, sv: -0.04)

    /// Canvas Y of the keyboard's far edge (extended as a line) at `x`; the head is hidden below it.
    static func keyboardEdgeY(at x: CGFloat) -> CGFloat {
        let t = (x - kbEdgeLeft.x) / (kbEdgeRight.x - kbEdgeLeft.x)
        return kbEdgeLeft.y + (kbEdgeRight.y - kbEdgeLeft.y) * t
    }

    // MARK: - Geometry (parsed once from the generated V14 path data)

    private static let earRight = parse(XiaoheiArt.earRightD)
    private static let earLeft = parse(XiaoheiArt.earLeftD)
    private static let headPath = parse(XiaoheiArt.headD)
    private static let mirror = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 640, ty: 0)
    private static let eyeWhiteRight = transformed(parse(XiaoheiArt.eyeWhiteD), XiaoheiArt.rightEyeTransform)
    private static let pupilRight = transformed(parse(XiaoheiArt.pupilD), XiaoheiArt.rightEyeTransform)
    private static let eyeWhiteLeft = transformed(eyeWhiteRight, mirror)
    private static let pupilLeft = transformed(pupilRight, mirror)

    private struct EyeGeometry {
        let white: CGPath
        let whiteBounds: CGRect
        let pupil: CGPath
        let center: CGPoint
        let radius: CGFloat
        let pupilCenter: CGPoint
        let pupilRadius: CGFloat
        let side: CGFloat // -1 = viewer-left eye, +1 = viewer-right eye
    }

    private static func eye(white: CGPath, pupil: CGPath, side: CGFloat) -> EyeGeometry {
        let wb = white.boundingBoxOfPath
        let pb = pupil.boundingBoxOfPath
        return EyeGeometry(white: white, whiteBounds: wb, pupil: pupil,
                           center: CGPoint(x: wb.midX, y: wb.midY), radius: (wb.width + wb.height) * 0.25,
                           pupilCenter: CGPoint(x: pb.midX, y: pb.midY), pupilRadius: (pb.width + pb.height) * 0.25,
                           side: side)
    }

    private static let eyes: [EyeGeometry] = [
        eye(white: eyeWhiteLeft, pupil: pupilLeft, side: -1),
        eye(white: eyeWhiteRight, pupil: pupilRight, side: 1),
    ]

    // MARK: - Pose

    private static func clamp01(_ v: CGFloat) -> CGFloat { max(0, min(1, v)) }
    private static func smooth(_ v: CGFloat) -> CGFloat { let t = clamp01(v); return t * t * (3 - 2 * t) }

    /// World (canvas) position of the head pivot. Shared by drawing, hit testing and overlay effects.
    static func headCenter(_ p: CatPhysics, showPaws: Bool) -> CGPoint {
        let scruff = clamp01(p.scruffDrag.value)
        let lie = smooth(p.lieIntensity.value)
        let hunt = clamp01(p.huntIntensity.value)
        let dizzyFall = smooth((p.dizzyIntensity.value - 0.5) / 0.5)
        let x = CatPhysics.seatAnchor.x + p.bodyShiftX.value + p.bodyTilt.value * 30 + p.headYaw.value * 4
        // Sink behind the keyboard when stalking, dozing or slumped; rise when the window is carried.
        var y = restHeadY + p.headOffsetY.value * 0.8 + p.headPitch.value * 3 + p.breathingOffset * 1.4
            + hunt * 5 + p.sleepiness * 6 + lie * 8 + dizzyFall * 14 - scruff * 24

        // 3-key easter egg: a quick head-bonk nod toward the third key.
        y += 8 * clamp01(p.hindFootActive.value)

        // Paws off: nod toward the key being typed.
        if !showPaws {
            let r = p.rightPaw.point
            var dy = r.y - CatPhysics.rightPawRest.y
            if !p.leftPawOnMouse { dy = max(dy, p.leftPaw.point.y - CatPhysics.leftPawRest.y) }
            y += min(8, max(0, dy) * 0.25)
        }
        return CGPoint(x: x, y: y)
    }

    private static func headRotation(_ p: CatPhysics, center: CGPoint) -> CGFloat {
        let lie = smooth(p.lieIntensity.value)
        let bonk = clamp01(p.hindFootActive.value)
        let bonkDir: CGFloat = p.hindFoot.x.value >= center.x ? 1 : -1
        let dizzy = clamp01(p.dizzyIntensity.value)
        let dizzyFall = smooth((dizzy - 0.5) / 0.5)
        let wobble = clamp01((dizzy - 0.12) / 0.38) * (1 - dizzyFall)
        return p.headTilt.value + p.bodyTilt.value * 0.5 - lie * 0.12
            + p.scruffSwing.value * 0.6 + bonk * 0.12 * bonkDir
            + sin(p.time * 9.5) * 0.16 * wobble - dizzyFall * 0.30
    }

    // MARK: - Hit testing

    static func hitTestHead(point pt: CGPoint, physics: CatPhysics, showPaws: Bool) -> Bool {
        guard pt.y < keyboardEdgeY(at: pt.x) else { return false }
        let c = headCenter(physics, showPaws: showPaws)
        // Ears + head span SVG y 148...594; the ellipse covers both with a small margin.
        let cy = c.y + (371 - svgPivot.y) * k
        let dx = (pt.x - c.x) / (252 * k)
        let dy = (pt.y - cy) / (228 * k)
        return dx * dx + dy * dy <= 1
    }

    // MARK: - Drawing

    /// Head only, clipped at the keyboard's far edge; the keyboard drawn afterwards sits in front of it.
    static func drawHead(in ctx: CGContext, physics p: CatPhysics, showPaws: Bool) {
        let center = headCenter(p, showPaws: showPaws)

        ctx.saveGState()
        let w = CatPhysics.canvasSize.width
        let visible = CGMutablePath()
        visible.move(to: .zero)
        visible.addLine(to: CGPoint(x: w, y: 0))
        visible.addLine(to: CGPoint(x: w, y: keyboardEdgeY(at: w)))
        visible.addLine(to: CGPoint(x: 0, y: keyboardEdgeY(at: 0)))
        visible.closeSubpath()
        ctx.addPath(visible)
        ctx.clip()
        let sq = p.bodySquash.value
        let sx = 1 + (1 - sq) * 0.25
        let sy = 1 - (1 - sq) * 0.45
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: headRotation(p, center: center))
        // Squash and stretch around the chin so typing bounces stay grounded.
        let chin = (svgChinY - svgPivot.y) * k
        ctx.translateBy(x: 0, y: chin)
        ctx.scaleBy(x: k * sx, y: k * sy)
        ctx.translateBy(x: -svgPivot.x, y: -svgChinY)

        let yaw = max(-1, min(1, p.headYaw.value))
        let pitch = max(-1, min(1, p.headPitch.value))
        let earL = earPath(earLeft, side: -1, yaw: yaw, pitch: pitch, physics: p)
        let earR = earPath(earRight, side: 1, yaw: yaw, pitch: pitch, physics: p)
        var headShift = CGAffineTransform(translationX: yaw * 8, y: 0)
        let head = headPath.copy(using: &headShift) ?? headPath

        // Light sticker rim so the black head stays readable on dark wallpapers (not part of the character).
        ctx.setStrokeColor(cream.copy(alpha: 0.92) ?? cream)
        ctx.setLineWidth(15)
        ctx.setLineJoin(.round)
        for path in [earL, earR, head] { ctx.addPath(path) }
        ctx.strokePath()

        ctx.setFillColor(ink)
        for path in [earL, earR, head] { ctx.addPath(path); ctx.fillPath() }

        drawEyes(in: ctx, physics: p, yaw: yaw, pitch: pitch)
        drawAngerMark(in: ctx, physics: p, yaw: yaw)
        ctx.restoreGState()
    }

    private static func earPath(_ ear: CGPath, side s: CGFloat, yaw: CGFloat, pitch: CGFloat, physics p: CatPhysics) -> CGPath {
        let root = CGPoint(x: 320 + s * 150, y: 268)
        let turnNear = max(0, s * yaw), turnFar = max(0, -s * yaw)
        let scaleX = 1 - 0.22 * turnNear + 0.06 * turnFar
        let fold = max(-0.3, min(1, p.earFold.value))
        let rot = s * fold * 0.32 + p.earTwitch.value * 0.05
        var t = CGAffineTransform(translationX: root.x + yaw * 30, y: root.y - pitch * 10)
        t = t.rotated(by: rot)
        t = t.scaledBy(x: scaleX, y: 1 - max(0, fold) * 0.10)
        t = t.translatedBy(x: -root.x, y: -root.y)
        return ear.copy(using: &t) ?? ear
    }

    // MARK: Eyes

    private static func drawEyes(in ctx: CGContext, physics p: CatPhysics, yaw: CGFloat, pitch: CGFloat) {
        let dizzy = clamp01(p.dizzyIntensity.value)
        let scruff = clamp01(p.scruffDrag.value)
        let hunt = clamp01(p.huntIntensity.value)
        let anger = clamp01((p.angerIntensity.value - 0.15) / 0.6)
        let closure = p.effectiveEyeClosure
        let yawRad = yaw * 0.32
        let pitchRad = pitch * (pitch > 0 ? 0.12 : 0.26)
        let R: CGFloat = 250, Rv: CGFloat = 230

        for e in eyes {
            // Spherical projection: features slide across the head and foreshorten near its edge.
            let th0 = asin(max(-0.95, min(0.95, (e.center.x - svgPivot.x) / R)))
            let th = th0 + yawRad
            let ph0 = asin(max(-0.95, min(0.95, (e.center.y - svgPivot.y) / Rv)))
            let ph = ph0 + pitchRad
            let nc = CGPoint(x: svgPivot.x + R * sin(th) + yaw * 8, y: svgPivot.y + Rv * sin(ph))
            let wide = 1 + hunt * 0.07
            let fx = max(0.35, min(1.15, cos(th) / cos(th0))) * wide
            let fy = max(0.6, min(1.1, cos(ph) / cos(ph0))) * wide

            ctx.saveGState()
            ctx.translateBy(x: nc.x, y: nc.y)
            ctx.scaleBy(x: fx, y: fy)
            ctx.translateBy(x: -e.center.x, y: -e.center.y)

            ctx.addPath(e.white)
            ctx.clip()
            ctx.setFillColor(cream)
            ctx.fill(e.whiteBounds)

            if dizzy > 0.25 {
                drawSpiral(in: ctx, eye: e, phase: p.dizzyPhase, alpha: clamp01((dizzy - 0.25) / 0.2))
            } else if scruff > 0.35 {
                drawSqueeze(in: ctx, eye: e)
            } else if p.isHappyClosedEyes {
                drawClosedLine(in: ctx, eye: e, happy: true)
            } else {
                if closure > 0.86 {
                    drawClosedLine(in: ctx, eye: e, happy: false)
                } else {
                    drawPupil(in: ctx, eye: e, physics: p, hunt: hunt)
                }
                let lid = max(closure, anger * 0.42)
                if lid > 0.01 {
                    drawUpperLid(in: ctx, eye: e, lid: lid, anger: anger)
                }
            }
            ctx.restoreGState()
        }
    }

    private static func drawUpperLid(in ctx: CGContext, eye e: EyeGeometry, lid: CGFloat, anger: CGFloat) {
        let bounds = e.whiteBounds
        // Leave a narrow band for the closed-eye line at the bottom of the opening.
        let edge = bounds.minY + min(lid, 0.64) * bounds.height
        let innerX = e.side > 0 ? bounds.minX : bounds.maxX
        let outerX = e.side > 0 ? bounds.maxX : bounds.minX
        ctx.move(to: CGPoint(x: innerX, y: edge + anger * 0.20 * e.radius))
        ctx.addLine(to: CGPoint(x: outerX, y: edge - anger * 0.08 * e.radius))
        ctx.addLine(to: CGPoint(x: outerX, y: bounds.minY - 1))
        ctx.addLine(to: CGPoint(x: innerX, y: bounds.minY - 1))
        ctx.closePath()
        ctx.setFillColor(ink)
        ctx.fillPath()
    }

    private static func drawPupil(in ctx: CGContext, eye e: EyeGeometry, physics p: CatPhysics, hunt: CGFloat) {
        let r = e.radius
        let ps = max(0.8, min(1.3, p.pupilScale.value)) * (1 + hunt * 0.30)
        let pr = e.pupilRadius * ps
        let travel = max(0, (r - pr) * 0.85)
        var g = p.eyeGaze.point
        let gl = hypot(g.x, g.y)
        if gl > 1 { g = CGPoint(x: g.x / gl, y: g.y / gl) }
        let pc = CGPoint(x: e.pupilCenter.x + g.x * travel, y: e.pupilCenter.y + g.y * travel * 0.9)

        var t = CGAffineTransform(translationX: pc.x, y: pc.y)
        t = t.scaledBy(x: ps, y: ps)
        t = t.translatedBy(x: -e.pupilCenter.x, y: -e.pupilCenter.y)
        ctx.setFillColor(ink)
        if let pupil = e.pupil.copy(using: &t) { ctx.addPath(pupil) }
        ctx.fillPath()
    }

    private static func strokeInk(_ ctx: CGContext, width: CGFloat) {
        ctx.setStrokeColor(ink)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }

    /// Closed pupils drawn on the white: `^` when happily petted, a gentle `︶` when blinking or sleeping.
    private static func drawClosedLine(in ctx: CGContext, eye e: EyeGeometry, happy: Bool) {
        let r = e.radius, c = e.center
        if happy {
            ctx.move(to: CGPoint(x: c.x - 0.62 * r, y: c.y + 0.22 * r))
            ctx.addQuadCurve(to: CGPoint(x: c.x + 0.62 * r, y: c.y + 0.22 * r), control: CGPoint(x: c.x, y: c.y - 0.55 * r))
        } else {
            let y = c.y + 0.48 * r
            ctx.move(to: CGPoint(x: c.x - 0.52 * r, y: y))
            ctx.addQuadCurve(to: CGPoint(x: c.x + 0.52 * r, y: y), control: CGPoint(x: c.x, y: y + 0.32 * r))
        }
        strokeInk(ctx, width: 18)
    }

    /// `> <` squeezed eyes (「加油」/「赞」 stickers) while being carried around.
    private static func drawSqueeze(in ctx: CGContext, eye e: EyeGeometry) {
        let r = e.radius, c = e.center
        let s = -e.side // left eye ">" points right, right eye "<" points left
        ctx.move(to: CGPoint(x: c.x - s * 0.45 * r, y: c.y - 0.42 * r))
        ctx.addLine(to: CGPoint(x: c.x + s * 0.42 * r, y: c.y))
        ctx.addLine(to: CGPoint(x: c.x - s * 0.45 * r, y: c.y + 0.42 * r))
        strokeInk(ctx, width: 18)
    }

    private static func drawSpiral(in ctx: CGContext, eye e: EyeGeometry, phase: CGFloat, alpha: CGFloat) {
        let r = e.radius, c = e.center
        let path = CGMutablePath()
        let steps = 60
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let a = t * 2.4 * 2 * .pi + phase * 1.6 * e.side
            let rad = (0.08 + 0.78 * t) * r
            let pt = CGPoint(x: c.x + cos(a) * rad, y: c.y + sin(a) * rad)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        ctx.addPath(path)
        ctx.setStrokeColor(ink.copy(alpha: alpha) ?? ink)
        ctx.setLineWidth(12)
        ctx.setLineCap(.round)
        ctx.strokePath()
    }

    /// External anger symbol (💢) floating beside the head; Xiaohei itself gains no new features.
    private static func drawAngerMark(in ctx: CGContext, physics p: CatPhysics, yaw: CGFloat) {
        let anger = clamp01(p.angerIntensity.value)
        guard anger > 0.25 else { return }
        let a = min(1, (anger - 0.25) / 0.35)
        let pulse = 1.75 + sin(p.time * 14) * 0.12
        ctx.saveGState()
        ctx.translateBy(x: 615 + yaw * 20, y: 230)
        ctx.scaleBy(x: pulse / k, y: pulse / k)
        ctx.setStrokeColor(NSColor(calibratedRed: 1, green: 0.16, blue: 0.24, alpha: a).cgColor)
        ctx.setLineWidth(2.2)
        ctx.setLineCap(.round)
        let d: CGFloat = 2.6, r: CGFloat = 6.8
        for (sx, sy): (CGFloat, CGFloat) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] {
            ctx.move(to: CGPoint(x: sx * r, y: sy * d))
            ctx.addQuadCurve(to: CGPoint(x: sx * d, y: sy * r), control: CGPoint(x: sx * d, y: sy * d))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: Floating paws (derived design)

    static func drawPaws(in ctx: CGContext, physics p: CatPhysics) {
        let head = headCenter(p, showPaws: true)
        let lie = smooth(p.lieIntensity.value)
        let paws: [(CGPoint, CGPoint, CGFloat)] = [
            (p.leftPaw.point, CatPhysics.leftPawRest, -1),
            (p.rightPaw.point, CatPhysics.rightPawRest, 1),
        ]
        for (rawPos, rest, s) in paws {
            let resting = 1 - clamp01(hypot(rawPos.x - rest.x, rawPos.y - rest.y) / 12)
            // The physics rest spots sit above the keyboard, over the hidden chin; idle paws float over
            // the near (spacebar) row on either side of the face instead, so they never cover the face.
            let ix = head.x + s * 46
            let idle = CGPoint(x: ix, y: keyboardEdgeY(at: ix) + 14)
            let pos = CGPoint(x: rawPos.x + (idle.x - rawPos.x) * resting,
                              y: rawPos.y + (idle.y - rawPos.y) * resting)
            var c = pos
            // Resting paws bob slightly out of phase with the head, so they read as floating.
            c.y -= (1.5 + sin(p.time * 2.1 + s * 0.9) * 1.3) * resting
            // Lying down: paws tuck in beside the cheeks, resting on the keyboard's far edge.
            let tx = head.x + s * 44
            let tuck = CGPoint(x: tx, y: keyboardEdgeY(at: tx) + 8)
            c = CGPoint(x: c.x + (tuck.x - c.x) * lie, y: c.y + (tuck.y - c.y) * lie)

            // Contact shadow on the keyboard/mouse.
            ctx.saveGState()
            ctx.setFillColor(ink.copy(alpha: 0.16 * (1 - lie)) ?? ink)
            ctx.fillEllipse(in: CGRect(x: pos.x - 8, y: pos.y - 1, width: 16, height: 5))
            ctx.restoreGState()

            ctx.saveGState()
            ctx.translateBy(x: c.x, y: c.y - 6.5)
            ctx.rotate(by: s * 0.16 + p.headTilt.value * 0.3)
            let paw = CGMutablePath()
            paw.move(to: CGPoint(x: -10.5, y: 2))
            paw.addCurve(to: CGPoint(x: 10.5, y: 2), control1: CGPoint(x: -10.5, y: -10.5), control2: CGPoint(x: 10.5, y: -10.5))
            paw.addCurve(to: CGPoint(x: -10.5, y: 2), control1: CGPoint(x: 9.5, y: 8.8), control2: CGPoint(x: -9.5, y: 8.8))
            paw.closeSubpath()
            ctx.addPath(paw)
            ctx.setStrokeColor(cream.copy(alpha: 0.95) ?? cream)
            ctx.setLineWidth(2.6)
            ctx.strokePath()
            ctx.addPath(paw)
            ctx.setFillColor(ink)
            ctx.fillPath()
            // Two toe separations on the front edge (「记笔记」 sticker paw language).
            ctx.move(to: CGPoint(x: -3.6, y: 7.0)); ctx.addLine(to: CGPoint(x: -3.1, y: 3.4))
            ctx.move(to: CGPoint(x: 3.6, y: 7.0)); ctx.addLine(to: CGPoint(x: 3.1, y: 3.4))
            ctx.setStrokeColor(cream.copy(alpha: 0.9) ?? cream)
            ctx.setLineWidth(1.2)
            ctx.setLineCap(.round)
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    /// Small pop rays on the 3rd (head bonk) and 4th simultaneous keys; Xiaohei has no foot or tail.
    static func drawEasterEggImpacts(in ctx: CGContext, physics p: CatPhysics) {
        let hits: [(CGPoint, CGFloat)] = [
            (p.hindFoot.point, clamp01(p.hindFootActive.value)),
            (p.tailTip.point, clamp01((p.tailTyping.value - 0.4) / 0.6)),
        ]
        for (pt, a) in hits where a > 0.05 {
            ctx.saveGState()
            ctx.translateBy(x: pt.x, y: pt.y - 4)
            let pulse = 1 + sin(p.time * 18) * 0.12
            ctx.setStrokeColor(NSColor(calibratedRed: 0.231, green: 0.510, blue: 0.965, alpha: 0.95 * a).cgColor)
            ctx.setLineWidth(2.0)
            ctx.setLineCap(.round)
            for i in 0..<3 {
                let ang = -CGFloat.pi / 2 + CGFloat(i - 1) * 0.75
                ctx.move(to: CGPoint(x: cos(ang) * 9 * pulse, y: sin(ang) * 9 * pulse))
                ctx.addLine(to: CGPoint(x: cos(ang) * 15 * pulse, y: sin(ang) * 15 * pulse))
            }
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    // MARK: - Minimal SVG path parser (absolute M/L/C/Z, as used by the V14 export)

    private static func transformed(_ path: CGPath, _ t: CGAffineTransform) -> CGPath {
        var t = t
        return path.copy(using: &t) ?? path
    }

    static func parse(_ d: String) -> CGPath {
        var tokens: [String] = []
        var cur = ""
        func flush() { if !cur.isEmpty { tokens.append(cur); cur = "" } }
        for ch in d {
            if ch.isLetter && ch != "e" && ch != "E" {
                flush(); tokens.append(String(ch))
            } else if ch == " " || ch == "," || ch == "\n" || ch == "\t" {
                flush()
            } else if ch == "-" && !cur.isEmpty && !cur.hasSuffix("e") && !cur.hasSuffix("E") {
                flush(); cur.append(ch)
            } else {
                cur.append(ch)
            }
        }
        flush()

        let path = CGMutablePath()
        var i = 0
        var cmd = "M"
        func num() -> CGFloat {
            defer { i += 1 }
            guard i < tokens.count, let v = Double(tokens[i]) else {
                preconditionFailure("Bad SVG path data near token \(i)")
            }
            return CGFloat(v)
        }
        func point() -> CGPoint { let x = num(); let y = num(); return CGPoint(x: x, y: y) }
        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter {
                cmd = tokens[i]; i += 1
                if cmd == "Z" || cmd == "z" { path.closeSubpath(); continue }
            }
            switch cmd {
            case "M": path.move(to: point()); cmd = "L"
            case "L": path.addLine(to: point())
            case "C":
                let c1 = point(), c2 = point(), end = point()
                path.addCurve(to: end, control1: c1, control2: c2)
            default: preconditionFailure("Unsupported SVG path command \(cmd)")
            }
        }
        return path
    }
}
