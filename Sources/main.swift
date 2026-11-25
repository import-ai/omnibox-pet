import Foundation
import AppKit

// Headless Xiaohei state sheet for visual QA: --render-xiaohei-preview <out.png> [--dark]
if let idx = CommandLine.arguments.firstIndex(of: "--render-xiaohei-preview"),
   idx + 1 < CommandLine.arguments.count {
    renderXiaoheiPreview(to: CommandLine.arguments[idx + 1], dark: CommandLine.arguments.contains("--dark"))
    exit(0)
}

// MARK: - Xiaohei State Sheet (visual QA)

func renderXiaoheiPreview(to path: String, dark: Bool) {
    let settings = CatSettings.shared
    let prevPaws = settings.xiaoheiPaws
    let prevBadges = settings.showKeyBadges
    defer { settings.xiaoheiPaws = prevPaws; settings.showKeyBadges = prevBadges }
    settings.showKeyBadges = true

    func pawsAt(_ p: CatPhysics, _ l: CGPoint, _ r: CGPoint) {
        p.leftPaw.x.value = l.x; p.leftPaw.y.value = l.y
        p.rightPaw.x.value = r.x; p.rightPaw.y.value = r.y
    }
    let mousePt = CGPoint(x: CatPhysics.mouseBaseCenter.x + 2, y: CatPhysics.mouseBaseCenter.y - 3)
    let scenarios: [(String, Bool, (CatPhysics) -> Void)] = [
        ("1. 待机", true, { _ in }),
        ("2. 转头左上 + 握鼠标", true, { p in
            pawsAt(p, mousePt, CatPhysics.rightPawRest)
            p.headYaw.value = -0.88; p.headPitch.value = -0.62; p.headTilt.value = -0.11
            p.eyeGaze.x.value = -0.78; p.eyeGaze.y.value = -0.58
        }),
        ("3. 转头右下 + 打字", true, { p in
            for k: PhysicalKey in [.j, .o, .e] { p.triggerKeyDown(k) }
            for i in p.floatingKeycaps.indices { p.floatingKeycaps[i].age = 0.25 + CGFloat(i) * 0.1 }
            pawsAt(p, KeyboardLayout.canvasPoint(for: .o), KeyboardLayout.canvasPoint(for: .f))
            p.headYaw.value = 0.72; p.headPitch.value = 0.78; p.headTilt.value = 0.09
            p.eyeGaze.x.value = 0.65; p.eyeGaze.y.value = 0.72
        }),
        ("4. 捕猎大圆眼", true, { p in
            pawsAt(p, mousePt, CatPhysics.rightPawRest)
            p.huntIntensity.value = 1; p.bodySquash.value = 0.89; p.headOffsetY.value = 10.5
            p.headYaw.value = -0.55; p.headPitch.value = -0.25; p.headTilt.value = -0.09
            p.eyeGaze.x.value = -0.5; p.eyeGaze.y.value = -0.22
        }),
        ("5. 3 键：点头 + 第 3 键冲击线", true, { p in
            for k: PhysicalKey in [.w, .leftShift, .space] { p.triggerKeyDown(k) }
            for i in p.floatingKeycaps.indices { p.floatingKeycaps[i].age = 0.2 }
            pawsAt(p, KeyboardLayout.canvasPoint(for: .space), KeyboardLayout.canvasPoint(for: .w))
            let f = KeyboardLayout.canvasPoint(for: .leftShift)
            p.hindFoot.x.value = f.x; p.hindFoot.y.value = f.y; p.hindFootActive.value = 1
            p.headPitch.value = 0.55; p.eyeGaze.y.value = 0.6
        }),
        ("6. 摸头 ^ ^", true, { p in
            pawsAt(p, mousePt, CatPhysics.rightPawRest)
            p.headYaw.value = -0.25; p.headTilt.value = -0.08; p.earFold.value = 0.65
            for _ in 0..<10 { p.registerPetStroke(canvasPoint: CGPoint(x: 184, y: 130), delta: 16, isHead: true) }
        }),
        ("7. 打瞌睡", true, { p in
            p.setPreviewMoods(sleepiness: 1); p.earFold.value = 0.25; p.headOffsetY.value = 5
            p.sparkles.append(PurrSparkle(position: CGPoint(x: 236, y: 92), velocity: .zero, isSleepZ: true))
        }),
        ("8. 打字太快生气", true, { p in
            p.angerIntensity.value = 1
            pawsAt(p, KeyboardLayout.canvasPoint(for: .d), KeyboardLayout.canvasPoint(for: .k))
            p.eyeGaze.y.value = 0.5; p.headPitch.value = 0.4
        }),
        ("9. 晕头转向", true, { p in
            p.dizzyIntensity.value = 0.4; p.setPreviewMoods(dizzyPhase: 1.3)
        }),
        ("10. 被拎起来 > <", true, { p in
            p.scruffDrag.value = 1; p.scruffSwing.value = 0.12; p.earFold.value = 0.4
        }),
        ("11. 趴在键盘后睡", true, { p in
            p.lieIntensity.value = 1; p.setPreviewMoods(sleepiness: 1)
        }),
        ("12. 只露脑袋（关闭小爪）", false, { p in
            p.triggerKeyDown(.k); p.floatingKeycaps[0].age = 0.25
            pawsAt(p, CatPhysics.leftPawRest, KeyboardLayout.canvasPoint(for: .k))
            p.headPitch.value = 0.6; p.eyeGaze.x.value = 0.4; p.eyeGaze.y.value = 0.7
        }),
    ]

    let cellW = 360, cellH = 320, scale = 2, cols = 4
    let rows = (scenarios.count + cols - 1) / cols
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: cellW * cols * scale, height: cellH * rows * scale,
                              bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.translateBy(x: 0, y: CGFloat(cellH * rows * scale))
    ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
    let bg = dark
        ? [NSColor(calibratedWhite: 0.16, alpha: 1).cgColor, NSColor(calibratedWhite: 0.08, alpha: 1).cgColor]
        : [NSColor(calibratedRed: 0.86, green: 0.90, blue: 0.96, alpha: 1).cgColor,
           NSColor(calibratedRed: 0.70, green: 0.78, blue: 0.90, alpha: 1).cgColor]
    if let grad = CGGradient(colorsSpace: cs, colors: bg as CFArray, locations: [0, 1]) {
        ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: cellW * cols, y: cellH * rows), options: [])
    }
    for (index, (label, paws, configure)) in scenarios.enumerated() {
        settings.xiaoheiPaws = paws
        let physics = CatPhysics()
        configure(physics)
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(index % cols * cellW), y: CGFloat(index / cols * cellH))
        ctx.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.3).cgColor)
        ctx.stroke(CGRect(x: 0.5, y: 0.5, width: CGFloat(cellW) - 1, height: CGFloat(cellH) - 1))
        CatRenderer.draw(in: ctx, physics: physics, showPermissionPill: false)
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                                                     .foregroundColor: NSColor.white]
        let text = NSAttributedString(string: label, attributes: attrs)
        ctx.setFillColor(NSColor(calibratedWhite: 0.08, alpha: 0.72).cgColor)
        ctx.fill(CGRect(x: 8, y: 8, width: text.size().width + 12, height: 22))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        text.draw(at: CGPoint(x: 14, y: 11))
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()
    }
    guard let img = ctx.makeImage(),
          let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
