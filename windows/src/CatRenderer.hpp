#pragma once
#define NOMINMAX
#include <windows.h>
#include <objidl.h>
#include <gdiplus.h>
#include <cmath>
#include <cstring>
#include <vector>
#include <algorithm>
#include "CatPhysics.hpp"
#include "XiaoheiRenderer.hpp"

enum class CatHitZone {
    None,
    Head,
    Body
};

class CatRenderer {
public:
    static constexpr float RadToDeg = 57.2957795f;

    static CatHitZone hitTest(Pt p, const CatPhysics& physics) {
        const Pt head = XiaoheiRenderer::headCenter(physics);
        const float dx = (p.x - head.x) / 72.0f;
        const float dy = (p.y - head.y) / 68.0f;
        if (p.y <= XiaoheiRenderer::keyboardEdge(p.x) && dx * dx + dy * dy <= 1.0f) return CatHitZone::Head;
        if (p.x >= 103.0f && p.x <= 286.0f && p.y >= XiaoheiRenderer::keyboardEdge(p.x) && p.y <= 292.0f) {
            return CatHitZone::Body;
        }
        return CatHitZone::None;
    }

    /// Edit-mode hit test in unflipped 360x320 canvas coordinates:
    /// 0..3 = corner resize handles, 10 = flip button, 11 = done button, 12 = inside edit box, -1 = outside.
    static int hitTestEditOverlay(Pt p) {
        if (p.x >= 92.0f && p.x <= 178.0f && p.y >= 10.0f && p.y <= 38.0f) return 10;
        if (p.x >= 182.0f && p.x <= 268.0f && p.y >= 10.0f && p.y <= 38.0f) return 11;
        constexpr Pt corners[4] = { {10.0f, 10.0f}, {350.0f, 10.0f}, {10.0f, 310.0f}, {350.0f, 310.0f} };
        for (int i = 0; i < 4; ++i) {
            if (std::hypot(p.x - corners[i].x, p.y - corners[i].y) <= 18.0f) return i;
        }
        if (p.x >= 6.0f && p.x <= 354.0f && p.y >= 6.0f && p.y <= 314.0f) return 12;
        return -1;
    }

    static void draw(Gdiplus::Graphics& g, const CatPhysics& physics, const CatSettings& settings) {
        using namespace Gdiplus;
        g.SetSmoothingMode(SmoothingModeAntiAlias);
        g.SetPixelOffsetMode(PixelOffsetModeHighQuality);
        g.SetTextRenderingHint(TextRenderingHintAntiAliasGridFit);

        GraphicsState flipState = g.Save();
        if (settings.flipHorizontal) {
            g.TranslateTransform(CatPhysics::CanvasWidth, 0.0f);
            g.ScaleTransform(-1.0f, 1.0f);
        }

        XiaoheiRenderer::drawHead(g, physics);
        if (physics.isTabletActive) {
            drawTablet(g, physics, settings.keyboardTheme, settings.eyeTheme);
            if (physics.leftPawOnMouse) {
                drawHeldStylus(g, physics, settings.keyboardTheme, settings.eyeTheme);
            } else {
                drawParkedStylus(g, settings.keyboardTheme, settings.eyeTheme);
            }
        } else {
            drawMouse(g, physics, settings.keyboardTheme);
        }
        drawKeyboard(g, physics, settings.keyboardTheme, settings.eyeTheme, settings.showKeyLegends, settings.keyboardMarquee);
        XiaoheiRenderer::drawPaws(g, physics);

        // 9. Floating Keycap Badges (keyboard + mouse clicks)
        if (!physics.floatingKeycaps.empty()) {
            drawFloatingKeycaps(g, physics);
        }

        // 10. Subtle Petting Sparkles & Sleep Z
        drawSparkles(g, physics, settings.eyeTheme);

        g.Restore(flipState);

        if (settings.isEditMode) {
            drawEditOverlay(g, settings.isEnglish, settings.scale);
        }
    }

    static void drawEditOverlay(Gdiplus::Graphics& g, bool isEnglish, float scale) {
        using namespace Gdiplus;
        GraphicsPath boxPath;
        addRoundedRect(boxPath, 10.0f, 10.0f, 340.0f, 300.0f, 12.0f);
        SolidBrush tint(Color(18, 41, 143, 250));
        g.FillPath(&tint, &boxPath);

        Pen dashPen(Color(235, 51, 158, 255), 1.8f);
        REAL dashes[2] = { 4.0f, 2.5f };
        dashPen.SetDashPattern(dashes, 2);
        g.DrawPath(&dashPen, &boxPath);

        constexpr Pt corners[4] = { {10.0f, 10.0f}, {350.0f, 10.0f}, {10.0f, 310.0f}, {350.0f, 310.0f} };
        SolidBrush whiteBrush(Color(255, 255, 255, 255));
        Pen handlePen(Color(255, 36, 133, 245), 2.0f);
        for (const auto& c : corners) {
            g.FillEllipse(&whiteBrush, c.x - 6.5f, c.y - 6.5f, 13.0f, 13.0f);
            g.DrawEllipse(&handlePen, c.x - 6.5f, c.y - 6.5f, 13.0f, 13.0f);
        }

        FontFamily ff(L"Segoe UI");
        Font btnFont(&ff, 10.0f, FontStyleBold, UnitPixel);
        StringFormat sf;
        sf.SetAlignment(StringAlignmentCenter);
        sf.SetLineAlignment(StringAlignmentCenter);

        auto drawBtn = [&](float x, float y, float w, float h, const wchar_t* txt, bool primary) {
            GraphicsPath bp;
            addRoundedRect(bp, x, y, w, h, 11.0f);
            SolidBrush fill(primary ? Color(242, 41, 138, 245) : Color(224, 36, 38, 48));
            Pen rim(Color(72, 255, 255, 255), 0.9f);
            g.FillPath(&fill, &bp);
            g.DrawPath(&rim, &bp);
            g.DrawString(txt, -1, &btnFont, RectF(x, y, w, h), &sf, &whiteBrush);
        };

        drawBtn(94.0f, 12.0f, 82.0f, 24.0f, isEnglish ? L"\u21C4 Flip" : L"\u21C4 \u7FFB\u8F6C", false);
        drawBtn(184.0f, 12.0f, 82.0f, 24.0f, isEnglish ? L"\u2713 Done" : L"\u2713 \u5B8C\u6210", true);

        wchar_t buf[16] = {};
        swprintf_s(buf, L"%.0f%%", scale * 100.0f);
        GraphicsPath sp;
        addRoundedRect(sp, 158.0f, 290.0f, 44.0f, 16.0f, 6.0f);
        SolidBrush spBg(Color(210, 30, 33, 41));
        Font spFont(&ff, 9.5f, FontStyleBold, UnitPixel);
        g.FillPath(&spBg, &sp);
        g.DrawString(buf, -1, &spFont, RectF(158.0f, 290.0f, 44.0f, 16.0f), &sf, &whiteBrush);
    }

private:
    static Gdiplus::Color catBlack(BYTE a = 255)      { return Gdiplus::Color(a, 22, 22, 24); }
    static constexpr float BlackOutlineW = 1.6f;
    static Gdiplus::Color blackOutline(BYTE a = 240)  { return Gdiplus::Color(a, 255, 255, 255); }
    static Gdiplus::Color rgb(unsigned int hex, BYTE a = 255) { return Gdiplus::Color(a, (hex >> 16) & 255, (hex >> 8) & 255, hex & 255); }

    static Gdiplus::Color eyePrimary(EyeColorTheme t, BYTE a = 255) {
        switch (t) {
            case EyeColorTheme::NeonChartreuse: return Gdiplus::Color(a, 201, 242, 64);
            case EyeColorTheme::SiameseBlue:    return Gdiplus::Color(a, 176, 218, 242);
            case EyeColorTheme::WarmAmber:      return Gdiplus::Color(a, 250, 194, 56);
            case EyeColorTheme::IceCyan:        return Gdiplus::Color(a, 115, 235, 245);
            case EyeColorTheme::ReferenceHazel: return Gdiplus::Color(a, 218, 178, 87);
            case EyeColorTheme::OliveGold:      return Gdiplus::Color(a, 191, 179, 102);
            case EyeColorTheme::SoftAmber: return Gdiplus::Color(a, 217, 173, 85);
        }
        return Gdiplus::Color(a, 201, 242, 64);
    }

    static Gdiplus::Color blendColor(Gdiplus::Color a, Gdiplus::Color b, float t) {
        t = std::clamp(t, 0.0f, 1.0f);
        auto lerp = [t](BYTE x, BYTE y) -> BYTE { return (BYTE)std::clamp((int)(x + (y - x) * t + 0.5f), 0, 255); };
        return Gdiplus::Color(lerp(a.GetA(), b.GetA()), lerp(a.GetR(), b.GetR()), lerp(a.GetG(), b.GetG()), lerp(a.GetB(), b.GetB()));
    }

    // Hue wheel helper for the keyboard marquee (one full hue cycle per sweep).
    static Gdiplus::Color hsvColor(float h, float s, float v, BYTE a = 255) {
        h = h - std::floor(h);
        float c = v * s;
        float x = c * (1.0f - std::fabs(std::fmod(h * 6.0f, 2.0f) - 1.0f));
        float m = v - c;
        float r = 0.0f, g = 0.0f, b = 0.0f;
        switch ((int)(h * 6.0f) % 6) {
            case 0: r = c; g = x; break;
            case 1: r = x; g = c; break;
            case 2: g = c; b = x; break;
            case 3: g = x; b = c; break;
            case 4: r = x; b = c; break;
            default: r = c; b = x; break;
        }
        return Gdiplus::Color(a, (BYTE)((r + m) * 255.0f), (BYTE)((g + m) * 255.0f), (BYTE)((b + m) * 255.0f));
    }

    static void addRoundedRect(Gdiplus::GraphicsPath& p, float x, float y, float w, float h, float r) {
        float d = std::min(r * 2.0f, std::min(w, h));
        if (d <= 0.5f) {
            p.AddRectangle(Gdiplus::RectF(x, y, w, h));
            return;
        }
        p.AddArc(x, y, d, d, 180.0f, 90.0f);
        p.AddArc(x + w - d, y, d, d, 270.0f, 90.0f);
        p.AddArc(x + w - d, y + h - d, d, d, 0.0f, 90.0f);
        p.AddArc(x, y + h - d, d, d, 90.0f, 90.0f);
        p.CloseFigure();
    }

    static void addQuadPoly(Gdiplus::GraphicsPath& p, Pt tl, Pt tr, Pt br, Pt bl) {
        Gdiplus::PointF pts[4] = { {tl.x, tl.y}, {tr.x, tr.y}, {br.x, br.y}, {bl.x, bl.y} };
        p.AddPolygon(pts, 4);
    }

    static void addQuadBezier(Gdiplus::GraphicsPath& p, Pt p0, Pt ctrl, Pt p2) {
        // Convert quadratic Bezier (p0, ctrl, p2) -> exact cubic Bezier for GDI+
        Gdiplus::PointF c1(p0.x + (2.0f / 3.0f) * (ctrl.x - p0.x), p0.y + (2.0f / 3.0f) * (ctrl.y - p0.y));
        Gdiplus::PointF c2(p2.x + (2.0f / 3.0f) * (ctrl.x - p2.x), p2.y + (2.0f / 3.0f) * (ctrl.y - p2.y));
        p.AddBezier(Gdiplus::PointF(p0.x, p0.y), c1, c2, Gdiplus::PointF(p2.x, p2.y));
    }

    static Pt projectHead3D(float x, float y, float z, float yawRad, float pitchRad) {
        float cy = std::cos(yawRad), sy = std::sin(yawRad);
        float x1 = x * cy + z * sy;
        float z1 = -x * sy + z * cy;
        float cp = std::cos(pitchRad), sp = std::sin(pitchRad);
        float y2 = y * cp + z1 * sp;
        return { x1, y2 };
    }

    static Pt quadPoint(Pt p0, Pt p1, Pt p2, float t) {
        float mt = 1.0f - t;
        return { mt * mt * p0.x + 2.0f * mt * t * p1.x + t * t * p2.x,
                 mt * mt * p0.y + 2.0f * mt * t * p1.y + t * t * p2.y };
    }

    static Pt quadTangent(Pt p0, Pt p1, Pt p2, float t) {
        float mt = 1.0f - t;
        return { 2.0f * mt * (p1.x - p0.x) + 2.0f * t * (p2.x - p1.x),
                 2.0f * mt * (p1.y - p0.y) + 2.0f * t * (p2.y - p1.y) };
    }

    // MARK: - Mini White Mouse (180° facing the cat)

    static void drawMouse(Gdiplus::Graphics& g, const CatPhysics& physics, KeyboardTheme theme) {
        using namespace Gdiplus;
        Pt center = { CatPhysics::MouseBaseCenter.x + physics.mouseOffset.point().x,
                      CatPhysics::MouseBaseCenter.y + physics.mouseOffset.point().y };
        float pressShift = std::max(physics.mousePressLeft.value, physics.mousePressRight.value) * 1.6f;

        GraphicsState st = g.Save();
        g.TranslateTransform(center.x, center.y + pressShift);
        g.RotateTransform(0.22f * RadToDeg);

        SolidBrush shadowBrush(Color(60, 0, 0, 0));
        g.FillEllipse(&shadowBrush, -13.5f, -9.5f, 27.0f, 31.0f);

        Color bodyCol, borderCol, wheelCol;
        if (theme == KeyboardTheme::MidnightHacker) {
            bodyCol = Color(255, 51, 54, 61); borderCol = Color(255, 20, 20, 26); wheelCol = Color(255, 199, 242, 64);
        } else if (theme == KeyboardTheme::RetroCream) {
            bodyCol = Color(255, 227, 222, 209); borderCol = Color(255, 51, 48, 46); wheelCol = Color(255, 224, 107, 61);
        } else {
            bodyCol = Color(255, 244, 242, 236); borderCol = Color(255, 36, 36, 41); wheelCol = Color(255, 245, 176, 41);
        }

        SolidBrush bodyBrush(bodyCol);
        g.FillEllipse(&bodyBrush, -13.5f, -16.5f, 27.0f, 33.0f);

        if (physics.mousePressLeft.value > 0.05f || physics.mousePressRight.value > 0.05f) {
            GraphicsPath clipPath;
            clipPath.AddEllipse(-13.5f, -16.5f, 27.0f, 33.0f);
            GraphicsState cs = g.Save();
            g.SetClip(&clipPath);
            if (physics.mousePressLeft.value > 0.05f) {
                SolidBrush hb(Color((BYTE)(96 * physics.mousePressLeft.value), 201, 242, 64));
                g.FillRectangle(&hb, 0.0f, 0.0f, 14.0f, 17.0f);
            }
            if (physics.mousePressRight.value > 0.05f) {
                SolidBrush hb(Color((BYTE)(96 * physics.mousePressRight.value), 201, 242, 64));
                g.FillRectangle(&hb, -14.0f, 0.0f, 14.0f, 17.0f);
            }
            g.Restore(cs);
        }

        // Front button split seam pointing away from cat (bottom)
        Pen seamPen(Color(82, borderCol.GetR(), borderCol.GetG(), borderCol.GetB()), 1.05f);
        g.DrawLine(&seamPen, 0.0f, 16.0f, 0.0f, 1.5f);

        // Amber scroll wheel on front (bottom) half
        GraphicsPath wheelPath;
        addRoundedRect(wheelPath, -1.9f, 2.5f, 3.8f, 8.5f, 1.9f);
        SolidBrush wheelBrush(wheelCol);
        g.FillPath(&wheelBrush, &wheelPath);

        Pen borderPen(borderCol, 1.7f);
        g.DrawEllipse(&borderPen, -13.5f, -16.5f, 27.0f, 33.0f);
        g.Restore(st);
    }

    // MARK: - Mini 2.5D Graphics Tablet & Stylus

    static void drawTablet(Gdiplus::Graphics& g, const CatPhysics& physics, KeyboardTheme theme, EyeColorTheme eyeTheme) {
        using namespace Gdiplus;
        Pt tl = CatPhysics::tabletQuadPoint(0.0f, 0.0f);
        Pt tr = CatPhysics::tabletQuadPoint(1.0f, 0.0f);
        Pt bl = CatPhysics::tabletQuadPoint(0.0f, 1.0f);
        Pt br = CatPhysics::tabletQuadPoint(1.0f, 1.0f);
        constexpr float depth = 3.6f;

        Color baseCol, bodyCol, padCol, keyCol, accentCol;
        if (theme == KeyboardTheme::MidnightHacker) {
            baseCol = Color(255, 13, 13, 18); bodyCol = Color(255, 28, 31, 38);
            padCol = Color(255, 41, 43, 54); keyCol = Color(255, 61, 64, 77); accentCol = Color(255, 199, 242, 64);
        } else if (theme == KeyboardTheme::RetroCream) {
            baseCol = Color(255, 56, 54, 48); bodyCol = Color(255, 84, 79, 71);
            padCol = Color(255, 107, 99, 89); keyCol = Color(255, 138, 128, 115); accentCol = Color(255, 224, 107, 61);
        } else {
            baseCol = Color(255, 26, 26, 31); bodyCol = Color(255, 43, 46, 54);
            padCol = Color(255, 59, 61, 71); keyCol = Color(255, 77, 82, 94); accentCol = Color(255, 245, 176, 41);
        }

        // Drop shadow
        {
            GraphicsPath sp;
            addQuadPoly(sp, {tl.x, tl.y + depth + 2.0f}, {tr.x, tr.y + depth + 2.0f},
                            {br.x, br.y + depth + 2.6f}, {bl.x, bl.y + depth + 2.6f});
            SolidBrush sb(Color(56, 0, 0, 0));
            Pen spen(Color(56, 0, 0, 0), 3.0f); spen.SetLineJoin(LineJoinRound);
            g.FillPath(&sb, &sp); g.DrawPath(&spen, &sp);
        }
        // Lower 3D slab
        {
            GraphicsPath lp;
            addQuadPoly(lp, {tl.x, tl.y + depth}, {tr.x, tr.y + depth}, {br.x, br.y + depth}, {bl.x, bl.y + depth});
            SolidBrush bb(baseCol);
            Pen bp(baseCol, 2.5f); bp.SetLineJoin(LineJoinRound);
            g.FillPath(&bb, &lp); g.DrawPath(&bp, &lp);
        }
        // Top body
        GraphicsPath topPath;
        addQuadPoly(topPath, tl, tr, br, bl);
        {
            SolidBrush tb(bodyCol);
            Pen tp(bodyCol, 2.0f); tp.SetLineJoin(LineJoinRound);
            g.FillPath(&tb, &topPath); g.DrawPath(&tp, &topPath);
            Pen rim(Color(36, 255, 255, 255), 0.9f); rim.SetLineJoin(LineJoinRound);
            g.DrawPath(&rim, &topPath);
        }
        // Recessed active drawing pad
        Pt pTL = CatPhysics::tabletQuadPoint(0.21f, 0.11f);
        Pt pTR = CatPhysics::tabletQuadPoint(0.94f, 0.11f);
        Pt pBR = CatPhysics::tabletQuadPoint(0.94f, 0.89f);
        Pt pBL = CatPhysics::tabletQuadPoint(0.21f, 0.89f);
        GraphicsPath padPath;
        addQuadPoly(padPath, pTL, pTR, pBR, pBL);
        {
            SolidBrush pb(padCol);
            g.FillPath(&pb, &padPath);
        }
        // Corner L-brackets
        {
            Pen cp(Color(88, 255, 255, 255), 0.95f);
            cp.SetStartCap(LineCapRound); cp.SetEndCap(LineCapRound);
            const float corners[4][4] = {
                {0.24f, 0.15f,  0.07f,  0.11f},
                {0.91f, 0.15f, -0.07f,  0.11f},
                {0.24f, 0.85f,  0.07f, -0.11f},
                {0.91f, 0.85f, -0.07f, -0.11f}
            };
            for (const auto& c : corners) {
                Pt pt = CatPhysics::tabletQuadPoint(c[0], c[1]);
                Pt ph = CatPhysics::tabletQuadPoint(c[0] + c[2], c[1]);
                Pt pv = CatPhysics::tabletQuadPoint(c[0], c[1] + c[3]);
                g.DrawLine(&cp, ph.x, ph.y, pt.x, pt.y);
                g.DrawLine(&cp, pt.x, pt.y, pv.x, pv.y);
            }
        }
        // Status LED + 4 ExpressKeys
        Color eyeCol = eyePrimary(eyeTheme);
        Color ledCol = physics.tabletPenPress.value > 0.15f ? eyeCol : accentCol;
        Pt ledPt = CatPhysics::tabletQuadPoint(0.105f, 0.14f);
        {
            SolidBrush glow(Color(95, ledCol.GetR(), ledCol.GetG(), ledCol.GetB()));
            g.FillEllipse(&glow, ledPt.x - 3.6f, ledPt.y - 3.6f, 7.2f, 7.2f);
            SolidBrush lb(ledCol);
            g.FillEllipse(&lb, ledPt.x - 1.35f, ledPt.y - 1.35f, 2.7f, 2.7f);
        }
        {
            SolidBrush kb(keyCol);
            for (float kv : { 0.28f, 0.44f, 0.60f, 0.76f }) {
                GraphicsPath kp;
                addQuadPoly(kp,
                    CatPhysics::tabletQuadPoint(0.06f, kv - 0.05f),
                    CatPhysics::tabletQuadPoint(0.15f, kv - 0.05f),
                    CatPhysics::tabletQuadPoint(0.15f, kv + 0.05f),
                    CatPhysics::tabletQuadPoint(0.06f, kv + 0.05f));
                g.FillPath(&kb, &kp);
            }
        }
        // Live fading ink trail
        if (physics.tabletTrail.size() >= 2) {
            GraphicsState cs = g.Save();
            g.SetClip(&padPath, CombineModeIntersect);
            for (size_t i = 1; i < physics.tabletTrail.size(); ++i) {
                const auto& a = physics.tabletTrail[i - 1];
                const auto& b = physics.tabletTrail[i];
                if (std::hypot(b.point.x - a.point.x, b.point.y - a.point.y) > 22.0f) continue;
                float life = std::max(0.0f, 1.0f - b.age / 0.72f);
                if (life <= 0.01f) continue;
                Pen ink(Color((BYTE)(life * 224.0f), eyeCol.GetR(), eyeCol.GetG(), eyeCol.GetB()), 1.2f + life * 1.4f);
                ink.SetStartCap(LineCapRound); ink.SetEndCap(LineCapRound);
                g.DrawLine(&ink, a.point.x, a.point.y, b.point.x, b.point.y);
            }
            g.Restore(cs);
        }
        // Nib contact glow
        if (physics.leftPawOnMouse && physics.tabletPenPress.value > 0.08f) {
            Pt nib = physics.tabletNib.point();
            float r = 7.0f + physics.tabletPenPress.value * 3.5f;
            GraphicsPath gp;
            gp.AddEllipse(nib.x - r, nib.y - r, r * 2.0f, r * 2.0f);
            PathGradientBrush pgb(&gp);
            pgb.SetCenterColor(Color((BYTE)(115 * physics.tabletPenPress.value), eyeCol.GetR(), eyeCol.GetG(), eyeCol.GetB()));
            Color surr[1] = { Color(0, eyeCol.GetR(), eyeCol.GetG(), eyeCol.GetB()) };
            INT cnt = 1; pgb.SetSurroundColors(surr, &cnt);
            g.FillPath(&pgb, &gp);
        }
    }

    static void drawStylusBody(Gdiplus::Graphics& g, float len, KeyboardTheme theme, EyeColorTheme eyeTheme, float pressed) {
        using namespace Gdiplus;
        Color barrelCol, gripCol, ringCol;
        if (theme == KeyboardTheme::MidnightHacker) {
            barrelCol = Color(255, 33, 36, 43); gripCol = Color(255, 56, 61, 74); ringCol = Color(255, 199, 242, 64);
        } else if (theme == KeyboardTheme::RetroCream) {
            barrelCol = Color(255, 71, 66, 61); gripCol = Color(255, 107, 99, 89); ringCol = Color(255, 224, 107, 61);
        } else {
            barrelCol = Color(255, 46, 48, 59); gripCol = Color(255, 71, 77, 89); ringCol = Color(255, 245, 176, 41);
        }
        GraphicsPath penPath;
        penPath.AddLine(0.0f, 0.0f, 7.5f, -2.4f);
        penPath.AddLine(7.5f, -2.4f, len - 3.0f, -2.6f);
        addQuadBezier(penPath, { len - 3.0f, -2.6f }, { len, -2.4f }, { len, 0.0f });
        addQuadBezier(penPath, { len, 0.0f }, { len, 2.4f }, { len - 3.0f, 2.6f });
        penPath.AddLine(len - 3.0f, 2.6f, 7.5f, 2.4f);
        penPath.CloseFigure();

        Pen halo(Color(204, 245, 245, 245), 1.6f);
        halo.SetLineJoin(LineJoinRound);
        g.DrawPath(&halo, &penPath);
        SolidBrush bb(barrelCol);
        g.FillPath(&bb, &penPath);

        GraphicsState cs = g.Save();
        g.SetClip(&penPath, CombineModeIntersect);
        SolidBrush gb(gripCol);
        g.FillRectangle(&gb, 7.5f, -3.0f, 11.5f, 6.0f);
        SolidBrush rb(ringCol);
        g.FillRectangle(&rb, 19.0f, -3.0f, 2.4f, 6.0f);
        Color nibCol = pressed > 0.15f ? eyePrimary(eyeTheme) : Color(255, 240, 240, 240);
        SolidBrush nb(nibCol);
        g.FillRectangle(&nb, -0.5f, -1.5f, 3.4f, 3.0f);
        SolidBrush sh(Color(60, 255, 255, 255));
        g.FillRectangle(&sh, 8.0f, -1.9f, std::max(1.0f, len - 12.0f), 1.1f);
        g.Restore(cs);

        GraphicsPath btn;
        addRoundedRect(btn, 11.0f, -3.1f, 6.0f, 1.4f, 0.7f);
        SolidBrush btnB(Color(230, 199, 199, 199));
        g.FillPath(&btnB, &btn);
    }

    static void drawParkedStylus(Gdiplus::Graphics& g, KeyboardTheme theme, EyeColorTheme eyeTheme) {
        using namespace Gdiplus;
        Pt nib = CatPhysics::tabletQuadPoint(0.88f, -0.02f);
        Pt tail = CatPhysics::tabletQuadPoint(0.18f, -0.02f);
        float ang = std::atan2(tail.y - nib.y, tail.x - nib.x) * RadToDeg;
        float len = std::hypot(tail.x - nib.x, tail.y - nib.y);

        GraphicsState st = g.Save();
        g.TranslateTransform(nib.x, nib.y + 2.2f);
        g.RotateTransform(ang);
        SolidBrush sb(Color(56, 0, 0, 0));
        g.FillRectangle(&sb, 2.0f, -2.0f, len - 4.0f, 4.5f);
        g.Restore(st);

        st = g.Save();
        g.TranslateTransform(nib.x, nib.y);
        g.RotateTransform(ang);
        drawStylusBody(g, len, theme, eyeTheme, 0.0f);
        g.Restore(st);
    }

    static void drawHeldStylus(Gdiplus::Graphics& g, const CatPhysics& physics, KeyboardTheme theme, EyeColorTheme eyeTheme) {
        using namespace Gdiplus;
        Pt lPos = physics.leftPaw.point();
        float press = std::clamp(physics.tabletPenPress.value, 0.0f, 1.0f);
        Pt nib = { lPos.x - 5.5f, lPos.y + 7.0f + press * 1.4f };
        float angleDeg = (-2.18f + physics.tabletPenTilt.value) * RadToDeg;

        GraphicsState st = g.Save();
        g.TranslateTransform(nib.x, nib.y);
        g.RotateTransform(angleDeg);
        drawStylusBody(g, 35.0f, theme, eyeTheme, press);
        g.Restore(st);
    }

    // MARK: - Mini 65% Mechanical Keyboard (180° facing the cat)

    static std::wstring keycapLegend(PhysicalKey k) {
        switch (k) {
            case PhysicalKey::Escape: return L"ESC";
            case PhysicalKey::Tab: return L"\u21E5";
            case PhysicalKey::CapsLock: return L"\u21EA";
            case PhysicalKey::LeftShift:
            case PhysicalKey::RightShift: return L"\u21E7";
            case PhysicalKey::LeftControl:
            case PhysicalKey::RightControl: return L"Ctrl";
            case PhysicalKey::LeftOption:
            case PhysicalKey::RightOption: return L"Alt";
            case PhysicalKey::LeftCommand:
            case PhysicalKey::RightCommand: return L"Win";
            case PhysicalKey::Backspace: return L"\u232B";
            case PhysicalKey::Enter: return L"\u21B5";
            case PhysicalKey::Space: return L"";
            default: return keyBadgeLabel(k);
        }
    }

    static void drawKeyboard(Gdiplus::Graphics& g, const CatPhysics& physics, KeyboardTheme theme, EyeColorTheme eyeTheme, bool showLegends, bool marquee) {
        using namespace Gdiplus;
        Pt tl = KeyboardLayout::screenQuadPoint(-0.012f, -0.04f);
        Pt tr = KeyboardLayout::screenQuadPoint(1.012f, -0.04f);
        Pt bl = KeyboardLayout::screenQuadPoint(-0.016f, 1.04f);
        Pt br = KeyboardLayout::screenQuadPoint(1.016f, 1.04f);
        constexpr float depth = 4.5f;

        // Shadow
        {
            GraphicsPath sp;
            addQuadPoly(sp, {tl.x, tl.y + depth + 2}, {tr.x, tr.y + depth + 2},
                            {br.x, br.y + depth + 3}, {bl.x, bl.y + depth + 3});
            SolidBrush sb(Color(56, 0, 0, 0));
            g.FillPath(&sb, &sp);
        }

        Color baseCol, deckCol, keyCol, borderCol, accentCol;
        if (theme == KeyboardTheme::MidnightHacker) {
            baseCol = Color(255, 15, 15, 20); deckCol = Color(255, 26, 28, 33);
            keyCol = Color(255, 54, 56, 64); borderCol = Color(242, 28, 28, 33); accentCol = Color(255, 196, 240, 64);
        } else if (theme == KeyboardTheme::RetroCream) {
            baseCol = Color(255, 64, 61, 56); deckCol = Color(255, 97, 92, 84);
            keyCol = Color(255, 230, 224, 209); borderCol = Color(216, 173, 166, 153); accentCol = Color(255, 224, 107, 61);
        } else {
            baseCol = Color(255, 26, 26, 31); deckCol = Color(255, 36, 36, 41);
            keyCol = Color(255, 247, 246, 240); borderCol = Color(190, 199, 196, 189); accentCol = Color(255, 247, 179, 41);
        }

        {
            GraphicsPath lp;
            addQuadPoly(lp, {tl.x, tl.y + depth}, {tr.x, tr.y + depth}, {br.x, br.y + depth}, {bl.x, bl.y + depth});
            SolidBrush bb(baseCol);
            Pen bp(baseCol, 2.5f); bp.SetLineJoin(LineJoinRound);
            g.FillPath(&bb, &lp);
            g.DrawPath(&bp, &lp);
        }
        GraphicsPath deckPath;
        addQuadPoly(deckPath, tl, tr, br, bl);
        {
            SolidBrush db(deckCol);
            Pen dp(deckCol, 2.0f); dp.SetLineJoin(LineJoinRound);
            g.FillPath(&db, &deckPath);
            g.DrawPath(&dp, &deckPath);
        }

        // MARK: - Marquee backlight
        // A comet of light sweeps diagonally under the keycaps: bright head, long fading tail.
        Color glowCol = eyePrimary(eyeTheme, 215);
        float mqHead = physics.marqueePhase - std::floor(physics.marqueePhase);
        // One full hue cycle per sweep, so the deck reads as RGB backlight rather than paint.
        Color mqCol = hsvColor(mqHead + 0.52f, 0.55f, 1.0f);
        auto mqWave = [mqHead, marquee](float t) {
            if (!marquee) return 0.0f;
            float d = mqHead - t;
            if (d < 0.0f) d += 1.0f;
            return std::exp(-d / 0.125f);
        };
        float bandDx = br.x - tl.x, bandDy = br.y - tl.y;
        float bandLen2 = bandDx * bandDx + bandDy * bandDy;
        if (marquee) {
            GraphicsState mqState = g.Save();
            g.SetClip(&deckPath);
            const int kN = 24;
            Color mqColors[kN];
            REAL mqPos[kN];
            for (int i = 0; i < kN; ++i) {
                float t = (float)i / (float)(kN - 1);
                mqPos[i] = t;
                mqColors[i] = Color((BYTE)std::clamp(mqWave(t) * 200.0f, 0.0f, 255.0f),
                                    mqCol.GetR(), mqCol.GetG(), mqCol.GetB());
            }
            LinearGradientBrush band(PointF(tl.x, tl.y), PointF(br.x, br.y), Color(0, 0, 0, 0), Color(0, 0, 0, 0));
            band.SetInterpolationColors(mqColors, mqPos, kN);
            g.FillPath(&band, &deckPath);

            // White-hot lamp at the head of the comet, clipped to the deck.
            Pt head = { tl.x + bandDx * mqHead, tl.y + bandDy * mqHead };
            float hr = 44.0f;
            GraphicsPath hp;
            hp.AddEllipse(head.x - hr, head.y - hr, hr * 2.0f, hr * 2.0f);
            PathGradientBrush hb(&hp);
            hb.SetCenterPoint(PointF(head.x, head.y));
            hb.SetCenterColor(Color(150, 240, 252, 255));
            Color hSurr[1] = { Color(0, mqCol.GetR(), mqCol.GetG(), mqCol.GetB()) };
            INT hCnt = 1;
            hb.SetSurroundColors(hSurr, &hCnt);
            g.FillPath(&hb, &hp);
            g.Restore(mqState);
        }

        constexpr float padU = 0.0028f;
        constexpr float padV = 0.014f;
        Pen keyBorderPen(borderCol, 0.65f);
        FontFamily kbFF(L"Segoe UI");
        StringFormat kbSF;
        kbSF.SetAlignment(StringAlignmentCenter);
        kbSF.SetLineAlignment(StringAlignmentCenter);

        for (const auto& cap : KeyboardLayout::keycaps()) {
            float glow = 0.0f;
            auto it = physics.keyGlow.find(cap.key);
            if (it != physics.keyGlow.end()) glow = it->second;

            // 180° rotated to face the cat
            float su0 = (1.0f - (cap.xUnits + cap.widthUnits)) + padU;
            float su1 = (1.0f - cap.xUnits) - padU;
            float sv0 = (1.0f - (cap.row + 1) / 5.0f) + padV;
            float sv1 = (1.0f - cap.row / 5.0f) - padV;

            float dy = glow * 1.9f;
            Pt kTL = KeyboardLayout::screenQuadPoint(su0, sv0); kTL.y += dy;
            Pt kTR = KeyboardLayout::screenQuadPoint(su1, sv0); kTR.y += dy;
            Pt kBR = KeyboardLayout::screenQuadPoint(su1, sv1); kBR.y += dy;
            Pt kBL = KeyboardLayout::screenQuadPoint(su0, sv1); kBL.y += dy;

            // Where this keycap sits along the marquee axis, and how bright the comet makes it.
            float kcx = (kTL.x + kTR.x + kBR.x + kBL.x) * 0.25f;
            float kcy = (kTL.y + kTR.y + kBR.y + kBL.y) * 0.25f;
            float kt = std::clamp(((kcx - tl.x) * bandDx + (kcy - tl.y) * bandDy) / bandLen2, 0.0f, 1.0f);
            float mq = mqWave(kt);

            GraphicsPath kp;
            addQuadPoly(kp, kTL, kTR, kBR, kBL);
            Color fill = cap.isAmberAccent ? accentCol : keyCol;
            if (mq > 0.015f) {
                // Head of the comet reads hot (near white), the trailing keys stay saturated.
                Color lit = blendColor(mqCol, Color(255, 255, 255, 255), mq * mq * 0.5f);
                fill = blendColor(fill, lit, std::clamp(mq * 0.88f, 0.0f, 0.9f));
            }
            if (glow > 0.02f) fill = blendColor(fill, glowCol, glow * 0.55f);

            SolidBrush kb(fill);
            g.FillPath(&kb, &kp);
            if (mq > 0.10f) {
                Pen litPen(Color((BYTE)std::clamp(mq * 215.0f, 0.0f, 215.0f),
                                 mqCol.GetR(), mqCol.GetG(), mqCol.GetB()), 1.0f);
                g.DrawPath(&litPen, &kp);
            } else {
                g.DrawPath(&keyBorderPen, &kp);
            }

            // Under-key bloom where the beam is hottest, so the light spills between caps.
            if (mq > 0.45f) {
                float bloom = (mq - 0.45f) / 0.55f;
                float br2 = 15.0f;
                GraphicsPath bp;
                bp.AddEllipse(kcx - br2, kcy - br2 * 0.7f, br2 * 2.0f, br2 * 1.4f);
                PathGradientBrush pb(&bp);
                pb.SetCenterPoint(PointF(kcx, kcy));
                pb.SetCenterColor(Color((BYTE)std::clamp(bloom * 135.0f, 0.0f, 135.0f),
                                        mqCol.GetR(), mqCol.GetG(), mqCol.GetB()));
                Color bSurr[1] = { Color(0, mqCol.GetR(), mqCol.GetG(), mqCol.GetB()) };
                INT bCnt = 1;
                pb.SetSurroundColors(bSurr, &bCnt);
                g.FillPath(&pb, &bp);
            }

            if (showLegends) {
                bool isSpace = (cap.key == PhysicalKey::Space);
                std::wstring legend = isSpace ? std::wstring(L"space") : keycapLegend(cap.key);
                if (!legend.empty()) {
                    float cx = (kTL.x + kTR.x + kBR.x + kBL.x) * 0.25f;
                    float cy = (kTL.y + kTR.y + kBR.y + kBL.y) * 0.25f;
                    if (isSpace) {
                        // The spacebar sits right under the cat: its legs hide the middle, and an
                        // unlabeled visible end looked like an odd blank patch beside the cat.
                        // Label the end that stays visible instead.
                        Pt sp = KeyboardLayout::screenQuadPoint(su0 + (su1 - su0) * 0.82f, (sv0 + sv1) * 0.5f);
                        cx = sp.x;
                        cy = sp.y + dy;
                    }
                    Color txtCol = (cap.isAmberAccent || theme != KeyboardTheme::MidnightHacker)
                        ? Color(198, 36, 36, 41)
                        : Color(210, 224, 230, 235);
                    SolidBrush tb(txtCol);
                    float fSz = legend.size() <= 1 ? 5.2f : 3.9f;
                    Font kf(&kbFF, fSz, FontStyleBold, UnitPixel);
                    GraphicsState ks = g.Save();
                    g.TranslateTransform(cx, cy);
                    // The keyboard is laid out 180° to face the cat, so the legends must be too
                    // (upside-down to the viewer, upright from the cat's seat). +3° follows the deck slope.
                    g.RotateTransform(180.0f + 3.0f);
                    g.DrawString(legend.c_str(), -1, &kf, RectF(-14.0f, -7.0f, 28.0f, 14.0f), &kbSF, &tb);
                    g.Restore(ks);
                }
            }
        }

        // Radiant backlit glow halos over pressed keys
        for (const auto& kv : physics.keyGlow) {
            if (kv.second <= 0.05f) continue;
            Pt c = KeyboardLayout::canvasPointForKey(kv.first);
            float r = 17.0f + kv.second * 6.0f;
            GraphicsPath gp;
            gp.AddEllipse(c.x - r, c.y - r, r * 2.0f, r * 2.0f);
            PathGradientBrush pgb(&gp);
            pgb.SetCenterColor(Color((BYTE)(92 * kv.second), glowCol.GetR(), glowCol.GetG(), glowCol.GetB()));
            Color surr[1] = { Color(0, glowCol.GetR(), glowCol.GetG(), glowCol.GetB()) };
            INT cnt = 1;
            pgb.SetSurroundColors(surr, &cnt);
            g.FillPath(&pgb, &gp);
        }
    }

    static void drawFloatingKeycaps(Gdiplus::Graphics& g, const CatPhysics& physics) {
        using namespace Gdiplus;
        FontFamily ff(L"Segoe UI");
        StringFormat sf;
        sf.SetAlignment(StringAlignmentCenter);
        sf.SetLineAlignment(StringAlignmentCenter);

        for (const auto& b : physics.floatingKeycaps) {
            float prog = b.age / b.lifetime;
            float scale = 1.0f;
            if (b.age < 0.09f) {
                scale = 0.72f + 0.38f * std::sin((b.age / 0.09f) * 3.14159f * 0.65f);
            } else if (b.age < 0.18f) {
                scale = 1.10f - 0.10f * ((b.age - 0.09f) / 0.09f);
            }

            float alphaF = prog < 0.62f ? 1.0f : std::max(0.0f, 1.0f - (prog - 0.62f) / 0.38f);
            BYTE a = (BYTE)(alphaF * 255.0f);
            if (a < 4) continue;

            size_t len = b.label.size();
            bool hasWide = !b.label.empty() && b.label[0] > 0x7F;
            float w = (len <= 1) ? 23.0f : (len == 2 ? (hasWide ? 34.0f : 30.0f) : 38.0f);
            float h = 22.0f;

            GraphicsState st = g.Save();
            g.TranslateTransform(b.position.x, b.position.y);
            g.RotateTransform(b.rotation * RadToDeg);
            g.ScaleTransform(scale, scale);

            GraphicsPath basePath;
            addRoundedRect(basePath, -w * 0.5f, -h * 0.5f + 2.5f, w, h, 5.5f);
            SolidBrush baseBrush(Color((BYTE)(alphaF * 242), 38, 38, 43));
            g.FillPath(&baseBrush, &basePath);

            GraphicsPath facePath;
            addRoundedRect(facePath, -w * 0.5f, -h * 0.5f, w, h, 5.2f);
            SolidBrush faceBrush(Color(a, 249, 248, 243));
            Pen facePen(Color(a, 41, 41, 46), 1.45f);
            g.FillPath(&faceBrush, &facePath);
            g.DrawPath(&facePen, &facePath);

            Font font(&ff, len <= 1 ? 11.0f : 9.2f, FontStyleBold, UnitPixel);
            SolidBrush txtBrush(Color(a, 31, 31, 36));
            g.DrawString(b.label.c_str(), -1, &font, RectF(-w * 0.5f, -h * 0.5f, w, h), &sf, &txtBrush);

            g.Restore(st);
        }
    }

    // MARK: - Petting Sparkles & Sleep Z

    static void drawSparkles(Gdiplus::Graphics& g, const CatPhysics& physics, EyeColorTheme eyeTheme) {
        using namespace Gdiplus;
        Color baseCol = eyePrimary(eyeTheme);
        FontFamily ff(L"Segoe UI");

        for (const auto& sp : physics.sparkles) {
            float p = std::min(1.0f, sp.age / sp.lifetime);
            BYTE a = (BYTE)(std::sin(p * 3.14159f) * 215.0f);
            if (a < 4) continue;

            Color c(a, baseCol.GetR(), baseCol.GetG(), baseCol.GetB());
            if (sp.isSleepZ) {
                Font f(&ff, 11.0f + p * 3.0f, FontStyleBold, UnitPixel);
                SolidBrush sb(c);
                g.DrawString(L"z", -1, &f, PointF(sp.position.x, sp.position.y), &sb);
            } else {
                float r = 3.5f + p * 1.5f;
                GraphicsState st = g.Save();
                g.TranslateTransform(sp.position.x, sp.position.y);
                GraphicsPath star;
                addQuadBezier(star, {0, -r}, {0.8f, -0.8f}, {r, 0});
                addQuadBezier(star, {r, 0}, {0.8f, 0.8f}, {0, r});
                addQuadBezier(star, {0, r}, {-0.8f, 0.8f}, {-r, 0});
                addQuadBezier(star, {-r, 0}, {-0.8f, -0.8f}, {0, -r});
                star.CloseFigure();
                SolidBrush sb(c);
                g.FillPath(&sb, &star);
                g.Restore(st);
            }
        }
    }
};
