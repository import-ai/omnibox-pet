import AppKit
import CoreGraphics

/// Draws Xiaohei, the head-only black cat of 小黑 OmniBox, in place of the KuroCat body.
///
/// Identity rules (omnibox-art AGENTS.md): Xiaohei is only a head with two ears and two round eyes.
/// No nose, mouth, muzzle, whiskers, body, neck, tail, eyebrows or pupil highlights are ever drawn.
/// Emotions use gaze, eye shape, tilt and external symbols only.
///
/// Desktop-pet adaptation (derived design, draft, requested by the project owner): Xiaohei peeks out
/// from behind the far edge of a small desk and reaches over it with two arms to type and use the mouse.
/// The arms contradict the base "no limbs" identity and exist only in this pet; they can be switched
/// off, leaving just the peeking head, which then nods toward the keys.
enum XiaoheiRenderer {
    static let ink = CGColor(srgbRed: 23.0 / 255.0, green: 23.0 / 255.0, blue: 23.0 / 255.0, alpha: 1)
    static let cream = CGColor(srgbRed: 254.0 / 255.0, green: 246.0 / 255.0, blue: 236.0 / 255.0, alpha: 1)

    /// SVG units -> logical canvas points. The 486-unit-wide head becomes ~146 pt on the 360x320 canvas.
    static let k: CGFloat = 0.30
    /// Head pivot in SVG space (horizontal centre, vertical centre of the head without ears).
    private static let svgPivot = CGPoint(x: 320, y: 413)
    private static let svgChinY: CGFloat = 594
    /// Canvas Y of the head pivot at rest: the eyes sit just above the desk edge, the chin hides behind it.
    private static let restHeadY: CGFloat = 188

    // MARK: - Desk

    /// Far edge of the desk; everything of the head below it is hidden by the desk top.
    static let edgeY: CGFloat = 220
    private static let deskTop = CGRect(x: 30, y: edgeY, width: 304, height: 84)
    private static let deskThickness: CGFloat = 8
    static let deskHitRect = CGRect(x: 30, y: edgeY, width: 304, height: 84 + 8)
    /// Lift of the dizzy stars above the head pivot.
    static let starLift: CGFloat = 92
    private static let deskTopColor = CGColor(srgbRed: 0.918, green: 0.875, blue: 0.804, alpha: 1)
    private static let deskFrontColor = CGColor(srgbRed: 0.788, green: 0.706, blue: 0.592, alpha: 1)
    private static let deskEdgeColor = CGColor(srgbRed: 0.969, green: 0.941, blue: 0.898, alpha: 1)

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
        return EyeGeometry(white: white, pupil: pupil,
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
        // Sink behind the desk when stalking, dozing or slumped; rise when the window is carried.
        var y = restHeadY + p.headOffsetY.value * 0.8 + p.headPitch.value * 3 + p.breathingOffset * 1.4
            + hunt * 5 + p.sleepiness * 6 + lie * 8 + dizzyFall * 14 - scruff * 24

        // 3-key easter egg: a quick head-bonk nod toward the third key.
        y += 8 * clamp01(p.hindFootActive.value)

        // Arms off: nod toward the key being typed.
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
        guard pt.y < edgeY else { return false }
        let c = headCenter(physics, showPaws: showPaws)
        // Ears + head span SVG y 148...594; the ellipse covers both with a small margin.
        let cy = c.y + (371 - svgPivot.y) * k
        let dx = (pt.x - c.x) / (252 * k)
        let dy = (pt.y - cy) / (228 * k)
        return dx * dx + dy * dy <= 1
    }

    // MARK: - Drawing

    /// Head only; the desk drawn afterwards covers everything below `edgeY`.
    static func drawHead(in ctx: CGContext, physics p: CatPhysics, showPaws: Bool) {
        let center = headCenter(p, showPaws: showPaws)

        ctx.saveGState()
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

    /// Small desk top with a visible front face; its far edge is where Xiaohei peeks out.
    static func drawDesk(in ctx: CGContext) {
        ctx.saveGState()
        let r: CGFloat = 14
        // Soft contact shadow under the desk.
        ctx.setFillColor(ink.copy(alpha: 0.10) ?? ink)
        ctx.fillEllipse(in: CGRect(x: deskTop.minX + 10, y: deskTop.maxY + deskThickness - 3,
                                   width: deskTop.width - 20, height: 9))
        let front = deskTop.offsetBy(dx: 0, dy: deskThickness)
        ctx.addPath(CGPath(roundedRect: front, cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.setFillColor(deskFrontColor)
        ctx.fillPath()
        ctx.addPath(CGPath(roundedRect: deskTop, cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.setFillColor(deskTopColor)
        ctx.fillPath()
        // Highlight along the far edge so the head reads as hidden behind it.
        ctx.move(to: CGPoint(x: deskTop.minX + r, y: edgeY + 1))
        ctx.addLine(to: CGPoint(x: deskTop.maxX - r, y: edgeY + 1))
        ctx.setStrokeColor(deskEdgeColor)
        ctx.setLineWidth(2)
        ctx.strokePath()
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

            if dizzy > 0.25 {
                drawSpiral(in: ctx, eye: e, phase: p.dizzyPhase, alpha: clamp01((dizzy - 0.25) / 0.2))
            } else if scruff > 0.35 {
                drawSqueeze(in: ctx, eye: e)
            } else if p.isHappyClosedEyes {
                drawClosedLine(in: ctx, eye: e, happy: true)
            } else if closure > 0.86 {
                drawClosedLine(in: ctx, eye: e, happy: false)
            } else {
                drawOpenEye(in: ctx, eye: e, physics: p, lid: max(closure, anger * 0.42), anger: anger, hunt: hunt)
            }
            ctx.restoreGState()
        }
    }

    private static func drawOpenEye(in ctx: CGContext, eye e: EyeGeometry, physics p: CatPhysics,
                                    lid: CGFloat, anger: CGFloat, hunt: CGFloat) {
        let r = e.radius, c = e.center
        if lid > 0.01 {
            // Flat upper lid (「思考中」 sticker); anger slants it down toward the inner corners.
            let base = c.y - r + lid * 2 * r
            let inner = base + anger * 0.30 * r
            let outer = base - anger * 0.12 * r
            let innerX = c.x - e.side * 1.6 * r, outerX = c.x + e.side * 1.6 * r
            let clip = CGMutablePath()
            clip.move(to: CGPoint(x: innerX, y: inner))
            clip.addLine(to: CGPoint(x: outerX, y: outer))
            clip.addLine(to: CGPoint(x: outerX, y: c.y + 2 * r))
            clip.addLine(to: CGPoint(x: innerX, y: c.y + 2 * r))
            clip.closeSubpath()
            ctx.addPath(clip)
            ctx.clip()
        }
        ctx.setFillColor(cream)
        ctx.addPath(e.white)
        ctx.fillPath()

        ctx.addPath(e.white)
        ctx.clip()
        let ps = max(0.8, min(1.3, p.pupilScale.value)) * (1 + hunt * 0.30)
        let travel = max(0, (r - e.pupilRadius * ps) * 0.85)
        var g = p.eyeGaze.point
        let gl = hypot(g.x, g.y)
        if gl > 1 { g = CGPoint(x: g.x / gl, y: g.y / gl) }
        var t = CGAffineTransform(translationX: e.pupilCenter.x + g.x * travel, y: e.pupilCenter.y + g.y * travel * 0.9)
        t = t.scaledBy(x: ps, y: ps)
        t = t.translatedBy(x: -e.pupilCenter.x, y: -e.pupilCenter.y)
        ctx.setFillColor(ink)
        if let pupil = e.pupil.copy(using: &t) { ctx.addPath(pupil) }
        ctx.fillPath()
    }

    private static func strokeCream(_ ctx: CGContext, width: CGFloat) {
        ctx.setStrokeColor(cream)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }

    /// Closed eyes: `^` when happily petted, a gentle `︶` when blinking or sleeping.
    private static func drawClosedLine(in ctx: CGContext, eye e: EyeGeometry, happy: Bool) {
        let r = e.radius, c = e.center
        if happy {
            ctx.move(to: CGPoint(x: c.x - 0.62 * r, y: c.y + 0.22 * r))
            ctx.addQuadCurve(to: CGPoint(x: c.x + 0.62 * r, y: c.y + 0.22 * r), control: CGPoint(x: c.x, y: c.y - 0.55 * r))
        } else {
            ctx.move(to: CGPoint(x: c.x - 0.62 * r, y: c.y))
            ctx.addQuadCurve(to: CGPoint(x: c.x + 0.62 * r, y: c.y), control: CGPoint(x: c.x, y: c.y + 0.42 * r))
        }
        strokeCream(ctx, width: 14)
    }

    /// `> <` squeezed eyes (「加油」/「赞」 stickers) while being carried around.
    private static func drawSqueeze(in ctx: CGContext, eye e: EyeGeometry) {
        let r = e.radius, c = e.center
        let s = -e.side // left eye ">" points right, right eye "<" points left
        ctx.move(to: CGPoint(x: c.x - s * 0.45 * r, y: c.y - 0.42 * r))
        ctx.addLine(to: CGPoint(x: c.x + s * 0.42 * r, y: c.y))
        ctx.addLine(to: CGPoint(x: c.x - s * 0.45 * r, y: c.y + 0.42 * r))
        strokeCream(ctx, width: 14)
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
        ctx.setStrokeColor(cream.copy(alpha: alpha) ?? cream)
        ctx.setLineWidth(11)
        ctx.setLineCap(.round)
        ctx.strokePath()
    }

    /// External anger symbol (💢) floating beside the head; Xiaohei itself gains no new features.
    private static func drawAngerMark(in ctx: CGContext, physics p: CatPhysics, yaw: CGFloat) {
        let anger = clamp01(p.angerIntensity.value)
        guard anger > 0.25 else { return }
        let a = min(1, (anger - 0.25) / 0.35)
        let pulse = 1 + sin(p.time * 14) * 0.10
        ctx.saveGState()
        ctx.translateBy(x: 560 + yaw * 20, y: 250)
        ctx.scaleBy(x: pulse / k, y: pulse / k)
        ctx.setStrokeColor(NSColor(calibratedRed: 0.96, green: 0.22, blue: 0.28, alpha: 0.95 * a).cgColor)
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

    // MARK: Arms over the desk edge (derived design)

    static func drawArms(in ctx: CGContext, physics p: CatPhysics) {
        let head = headCenter(p, showPaws: true)
        let lie = smooth(p.lieIntensity.value)
        // Physics assigns keys by QWERTY hand, but the keyboard faces Xiaohei (mirrored for the viewer).
        // Pair shoulders with paws by on-screen position so the arms never cross.
        let a = p.leftPaw.point, b = p.rightPaw.point
        let (viewerLeft, viewerRight) = a.x <= b.x ? (a, b) : (b, a)
        let arms: [(CGPoint, CGFloat)] = [(viewerLeft, -1), (viewerRight, 1)]
        for (rawPos, s) in arms {
            // Idle paws rest a little forward on the desk so the forearms show draped over the edge.
            let rest = s < 0 ? CatPhysics.leftPawRest : CatPhysics.rightPawRest
            let restness = 1 - clamp01(hypot(rawPos.x - rest.x, rawPos.y - rest.y) / 14)
            let idleSpot = CGPoint(x: head.x + s * 40, y: edgeY + 19)
            let pos = CGPoint(x: rawPos.x + (idleSpot.x - rawPos.x) * restness,
                              y: rawPos.y + (idleSpot.y - rawPos.y) * restness)
            // Lying down: forearms fold together just past the edge, like napping on a desk.
            let fold = CGPoint(x: head.x + s * 18, y: edgeY + 15)
            var end = CGPoint(x: pos.x + (fold.x - pos.x) * lie, y: pos.y + (fold.y - pos.y) * lie)
            end.y = max(end.y, edgeY + 10)
            // Shoulders sit behind the desk; the arm starts above the edge and is cut flat there, so it
            // reads as reaching up from below and over the lip.
            let root = CGPoint(x: head.x + s * 54, y: edgeY - 12)
            let dx = end.x - root.x, dy = end.y - root.y
            let len = max(1, hypot(dx, dy))
            let dir = CGPoint(x: dx / len, y: dy / len)
            let tip = CGPoint(x: end.x - dir.x * 5, y: end.y - dir.y * 5)
            // Elbow bulges outward and lies on the desk, giving a relaxed draped curve.
            let ctrl = CGPoint(x: (root.x + tip.x) * 0.5 + s * min(10, len * 0.12),
                               y: (root.y + tip.y) * 0.5 + 2)
            let arm = CGMutablePath()
            arm.move(to: root)
            arm.addQuadCurve(to: tip, control: ctrl)

            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: edgeY - 2, width: CatPhysics.canvasSize.width, height: CatPhysics.canvasSize.height))
            // Contact shadow of the forearm and paw on the desk.
            ctx.setFillColor(ink.copy(alpha: 0.14 * (1 - lie * 0.5)) ?? ink)
            ctx.fillEllipse(in: CGRect(x: end.x - 9, y: end.y - 1, width: 18, height: 5.5))
            ctx.addPath(arm)
            ctx.setLineCap(.butt)
            ctx.setStrokeColor(cream.copy(alpha: 0.95) ?? cream)
            ctx.setLineWidth(16)
            ctx.strokePath()
            ctx.addPath(arm)
            ctx.setStrokeColor(ink)
            ctx.setLineWidth(12.5)
            ctx.strokePath()
            ctx.restoreGState()

            drawPaw(in: ctx, at: end, direction: dir, physics: p)
        }
    }

    private static func drawPaw(in ctx: CGContext, at end: CGPoint, direction dir: CGPoint, physics p: CatPhysics) {
        ctx.saveGState()
        ctx.translateBy(x: end.x - dir.x * 4, y: end.y - dir.y * 4)
        // Local +y (toes) points along the reach direction.
        ctx.rotate(by: atan2(dir.y, dir.x) - .pi / 2)
        let paw = CGMutablePath()
        paw.move(to: CGPoint(x: -10, y: -2))
        paw.addCurve(to: CGPoint(x: 10, y: -2), control1: CGPoint(x: -10, y: -11), control2: CGPoint(x: 10, y: -11))
        paw.addCurve(to: CGPoint(x: -10, y: -2), control1: CGPoint(x: 10.5, y: 10), control2: CGPoint(x: -10.5, y: 10))
        paw.closeSubpath()
        ctx.addPath(paw)
        ctx.setStrokeColor(cream.copy(alpha: 0.95) ?? cream)
        ctx.setLineWidth(2.6)
        ctx.strokePath()
        ctx.addPath(paw)
        ctx.setFillColor(ink)
        ctx.fillPath()
        // Two toe separations on the front edge (「记笔记」 sticker paw language).
        ctx.move(to: CGPoint(x: -3.6, y: 6.6)); ctx.addLine(to: CGPoint(x: -3.0, y: 2.8))
        ctx.move(to: CGPoint(x: 3.6, y: 6.6)); ctx.addLine(to: CGPoint(x: 3.0, y: 2.8))
        ctx.setStrokeColor(cream.copy(alpha: 0.9) ?? cream)
        ctx.setLineWidth(1.2)
        ctx.setLineCap(.round)
        ctx.strokePath()
        ctx.restoreGState()
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
