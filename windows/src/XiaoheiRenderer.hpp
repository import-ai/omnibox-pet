#pragma once

#include "CatPhysics.hpp"
#include "XiaoheiArt.hpp"
#include <gdiplus.h>
#include <cstdlib>

namespace XiaoheiRenderer {
using namespace Gdiplus;

inline const Color ink(255, 23, 23, 23);
inline const Color cream(255, 254, 246, 236);

// The shared artwork uses absolute M, L, C and Z path commands.
inline void addSvgPath(GraphicsPath& path, const char* data) {
    PointF current{};
    char command = 0;
    auto readNumber = [&]() {
        char* end = nullptr;
        const float value = std::strtof(data, &end);
        data = end;
        return value;
    };
    auto readPoint = [&]() {
        const float x = readNumber();
        return PointF(x, readNumber());
    };
    while (*data) {
        while (*data == ' ' || *data == ',') ++data;
        if (!*data) break;
        if (*data >= 'A' && *data <= 'Z') command = *data++;
        if (command == 'M') {
            path.StartFigure();
            current = readPoint();
            command = 'L';
        } else if (command == 'L') {
            const PointF end = readPoint();
            path.AddLine(current, end);
            current = end;
        } else if (command == 'C') {
            const PointF first = readPoint();
            const PointF second = readPoint();
            const PointF end = readPoint();
            path.AddBezier(current, first, second, end);
            current = end;
        } else if (command == 'Z') {
            path.CloseFigure();
            command = 0;
        } else {
            break;
        }
    }
}

struct Art {
    GraphicsPath silhouette{FillModeWinding};
    GraphicsPath eyeWhite;
    GraphicsPath pupil;

    Art() {
        addSvgPath(silhouette, XiaoheiArt::earLeft);
        addSvgPath(silhouette, XiaoheiArt::earRight);
        addSvgPath(silhouette, XiaoheiArt::head);
        addSvgPath(eyeWhite, XiaoheiArt::eyeWhite);
        addSvgPath(pupil, XiaoheiArt::pupil);
        Matrix eyeTransform(XiaoheiArt::eyeTransform[0], XiaoheiArt::eyeTransform[1],
                            XiaoheiArt::eyeTransform[2], XiaoheiArt::eyeTransform[3],
                            XiaoheiArt::eyeTransform[4], XiaoheiArt::eyeTransform[5]);
        eyeWhite.Transform(&eyeTransform);
        pupil.Transform(&eyeTransform);
    }
};

inline float keyboardEdge(float x) {
    const Pt left = KeyboardLayout::screenQuadPoint(0.0f, -0.04f);
    const Pt right = KeyboardLayout::screenQuadPoint(1.0f, -0.04f);
    return left.y + (right.y - left.y) * (x - left.x) / (right.x - left.x);
}

inline Pt headCenter(const CatPhysics& p) {
    return {
        CatPhysics::SeatAnchor.x + p.bodyShiftX.value + p.bodyTilt.value * 30.0f + p.headYaw.value * 4.0f,
        207.0f + p.headOffsetY.value * 0.8f + p.headPitch.value * 3.0f + p.sleepiness * 6.0f
            + p.lieIntensity.value * 8.0f + p.dizzyIntensity.value * 10.0f
            + p.hindFootActive.value * 8.0f - p.scruffDrag.value * 24.0f
    };
}

inline void drawFace(Graphics& g, const CatPhysics& p, float outlineWidth) {
    Art art;
    SolidBrush dark(ink), white(cream);
    if (outlineWidth > 0.0f) {
        Pen rim(cream, outlineWidth);
        rim.SetLineJoin(LineJoinRound);
        g.DrawPath(&rim, &art.silhouette);
    }
    g.FillPath(&dark, &art.silhouette);

    const Pt gaze = p.eyeGaze.point();
    for (const bool mirrored : {false, true}) {
        const GraphicsState eye = g.Save();
        if (mirrored) {
            g.TranslateTransform(640.0f, 0.0f);
            g.ScaleTransform(-1.0f, 1.0f);
        }
        g.FillPath(&white, &art.eyeWhite);
        g.SetClip(&art.eyeWhite, CombineModeIntersect);
        RectF bounds;
        art.pupil.GetBounds(&bounds);
        const float x = bounds.X + bounds.Width * 0.5f;
        const float y = bounds.Y + bounds.Height * 0.5f;
        if (p.effectiveEyeClosure() > 0.8f || p.isHappyClosedEyes()) {
            Pen closed(ink, 11.0f);
            closed.SetStartCap(LineCapRound);
            closed.SetEndCap(LineCapRound);
            const float bend = p.isHappyClosedEyes() ? -18.0f : 13.0f;
            g.DrawBezier(&closed, PointF(x-22,y), PointF(x-13,y+bend), PointF(x+13,y+bend), PointF(x+22,y));
        } else {
            const float scale = std::clamp(p.pupilScale.value, 0.8f, 1.35f);
            const float anger = p.angerIntensity.value;
            if (anger > 0.25f) {
                g.SetClip(RectF(x-64.0f, y-18.0f+anger*16.0f, 128.0f, 90.0f), CombineModeIntersect);
            }
            g.TranslateTransform(x + gaze.x * (mirrored ? -13.0f : 13.0f), y + gaze.y * 11.0f);
            g.ScaleTransform(scale, scale);
            g.TranslateTransform(-x, -y);
            g.FillPath(&dark, &art.pupil);
        }
        g.Restore(eye);
    }
}

inline void drawHead(Graphics& g, const CatPhysics& p) {
    const GraphicsState state = g.Save();
    const PointF points[] = {{0, 0}, {360, 0}, {360, keyboardEdge(360)}, {0, keyboardEdge(0)}};
    GraphicsPath visibleHead;
    visibleHead.AddPolygon(points, 4);
    g.SetClip(&visibleHead, CombineModeIntersect);
    const Pt head = headCenter(p);
    g.TranslateTransform(head.x, head.y);
    g.RotateTransform(p.headTilt.value * 57.29578f);
    g.ScaleTransform(0.30f * (1.0f - 0.10f * std::abs(p.headYaw.value)), 0.30f);
    g.TranslateTransform(-320.0f, -413.0f);
    drawFace(g, p, 8.0f);
    g.Restore(state);
}

inline void drawPaws(Graphics& g, const CatPhysics& p) {
    const Pt head = headCenter(p);
    const Pt paws[] = {p.leftPaw.point(), p.rightPaw.point()};
    const Pt rest[] = {CatPhysics::LeftPawRest, CatPhysics::RightPawRest};
    SolidBrush fill(ink);
    Pen outline(cream, 1.4f);
    for (int i = 0; i < 2; ++i) {
        const float side = i == 0 ? -1.0f : 1.0f;
        const float idle = 1.0f - std::clamp(std::hypot(paws[i].x-rest[i].x, paws[i].y-rest[i].y)/12.0f, 0.0f, 1.0f);
        const float idleX = head.x + side * 46.0f;
        const float x = paws[i].x + (idleX-paws[i].x)*idle;
        const float idleY = keyboardEdge(idleX) + 13.0f + std::sin(p.time*2.1f + side)*1.3f;
        const float y = paws[i].y + (idleY-paws[i].y)*idle;
        g.FillEllipse(&fill, x-9.0f, y-6.0f, 18.0f, 12.0f);
        g.DrawEllipse(&outline, x-9.0f, y-6.0f, 18.0f, 12.0f);
    }
}
}
