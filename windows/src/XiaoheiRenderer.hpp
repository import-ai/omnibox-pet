#pragma once

#include "CatPhysics.hpp"
#include "XiaoheiArt.hpp"
#include <gdiplus.h>
#include <cstdlib>

namespace XiaoheiRenderer {
using namespace Gdiplus;

inline const Color ink(255, 23, 23, 23);
inline const Color cream(255, 254, 246, 236);
inline constexpr float HeadScale = 0.30f;
inline constexpr float HeadPivotX = 320.0f;
inline constexpr float HeadPivotY = 413.0f;
inline constexpr float HeadChinY = 594.0f;
inline constexpr float RadToDeg = 57.2957795f;

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

struct EyeArt {
    GraphicsPath white;
    GraphicsPath pupil;
};

inline float keyboardEdge(float x) {
    const Pt left = KeyboardLayout::screenQuadPoint(-0.012f, -0.04f);
    const Pt right = KeyboardLayout::screenQuadPoint(1.012f, -0.04f);
    return left.y + (right.y - left.y) * (x - left.x) / (right.x - left.x);
}

inline float clampUnit(float value) {
    return std::clamp(value, 0.0f, 1.0f);
}

inline float smoothUnit(float value) {
    const float t = clampUnit(value);
    return t * t * (3.0f - 2.0f * t);
}

inline Pt headCenter(const CatPhysics& p, bool showPaws = true) {
    const float x = CatPhysics::SeatAnchor.x + p.bodyShiftX.value + p.bodyTilt.value * 30.0f + p.headYaw.value * 4.0f;
    float y = 208.0f + p.headOffsetY.value * 0.8f + p.headPitch.value * 3.0f + std::sin(p.time * 2.1f) * (1.6f * 1.4f)
        + clampUnit(p.huntIntensity.value) * 5.0f + p.sleepiness * 6.0f + smoothUnit(p.lieIntensity.value) * 8.0f
        + smoothUnit((p.dizzyIntensity.value - 0.5f) / 0.5f) * 14.0f
        - clampUnit(p.scruffDrag.value) * 24.0f + clampUnit(p.hindFootActive.value) * 8.0f;
    if (!showPaws) {
        float keyDistance = p.rightPaw.y.value - CatPhysics::RightPawRest.y;
        if (!p.leftPawOnMouse) keyDistance = std::max(keyDistance, p.leftPaw.y.value - CatPhysics::LeftPawRest.y);
        y += std::clamp(keyDistance * 0.25f, 0.0f, 8.0f);
    }
    return {x, y};
}

inline float headRotation(const CatPhysics& p, Pt center) {
    const float dizzy = clampUnit(p.dizzyIntensity.value);
    const float fall = smoothUnit((dizzy - 0.5f) / 0.5f);
    const float wobble = clampUnit((dizzy - 0.12f) / 0.38f) * (1.0f - fall);
    const float bonkDirection = p.hindFoot.x.value >= center.x ? 1.0f : -1.0f;
    return p.headTilt.value + p.bodyTilt.value * 0.5f - smoothUnit(p.lieIntensity.value) * 0.12f
        + p.scruffSwing.value * 0.6f + clampUnit(p.hindFootActive.value) * 0.12f * bonkDirection
        + std::sin(p.time * 9.5f) * 0.16f * wobble - fall * 0.30f;
}

inline void poseEar(GraphicsPath& ear, const char* path, float side, float yaw, float pitch, const CatPhysics& p) {
    addSvgPath(ear, path);
    const float rootX = HeadPivotX + side * 150.0f;
    constexpr float rootY = 268.0f;
    const float fold = std::clamp(p.earFold.value, -0.3f, 1.0f);
    Matrix pose;
    pose.Translate(rootX + yaw * 30.0f, rootY - pitch * 10.0f);
    pose.Rotate((side * fold * 0.32f + p.earTwitch.value * 0.05f) * RadToDeg);
    pose.Scale(1.0f - 0.22f * std::max(0.0f, side * yaw) + 0.06f * std::max(0.0f, -side * yaw),
               1.0f - 0.10f * std::max(0.0f, fold));
    pose.Translate(-rootX, -rootY);
    ear.Transform(&pose);
}

inline void drawEye(Graphics& g, const EyeArt& eye, const CatPhysics& p, float side, float yaw, float pitch) {
    RectF whiteBounds, pupilBounds;
    eye.white.GetBounds(&whiteBounds);
    eye.pupil.GetBounds(&pupilBounds);
    const float x = whiteBounds.X + whiteBounds.Width * 0.5f;
    const float y = whiteBounds.Y + whiteBounds.Height * 0.5f;
    const float radius = (whiteBounds.Width + whiteBounds.Height) * 0.25f;
    const float hunt = clampUnit(p.huntIntensity.value);

    // Use the same spherical projection as macOS so the far eye foreshortens as the face turns.
    constexpr float rx = 250.0f, ry = 230.0f;
    const float neutralYaw = std::asin(std::clamp((x - HeadPivotX) / rx, -0.95f, 0.95f));
    const float neutralPitch = std::asin(std::clamp((y - HeadPivotY) / ry, -0.95f, 0.95f));
    const float longitude = neutralYaw + yaw * 0.32f;
    const float latitude = neutralPitch + pitch * (pitch > 0.0f ? 0.12f : 0.26f);
    const float wide = 1.0f + hunt * 0.07f;
    const GraphicsState state = g.Save();
    g.TranslateTransform(HeadPivotX + rx * std::sin(longitude) + yaw * 8.0f, HeadPivotY + ry * std::sin(latitude));
    g.ScaleTransform(std::clamp(std::cos(longitude) / std::cos(neutralYaw), 0.35f, 1.15f) * wide,
                     std::clamp(std::cos(latitude) / std::cos(neutralPitch), 0.6f, 1.1f) * wide);
    g.TranslateTransform(-x, -y);

    SolidBrush white(cream), dark(ink);
    g.FillPath(&white, &eye.white);
    g.SetClip(&eye.white, CombineModeIntersect);
    const float closure = p.effectiveEyeClosure();
    const bool happy = p.isHappyClosedEyes();
    if (closure > 0.86f || happy) {
        Pen closed(ink, 18.0f);
        closed.SetStartCap(LineCapRound);
        closed.SetEndCap(LineCapRound);
        const float halfWidth = radius * (happy ? 0.62f : 0.52f);
        const float lineY = y + radius * (happy ? 0.22f : 0.48f);
        const float bend = radius * (happy ? -0.77f : 0.32f) * (2.0f / 3.0f);
        g.DrawBezier(&closed, PointF(x - halfWidth, lineY), PointF(x - halfWidth / 3.0f, lineY + bend),
                     PointF(x + halfWidth / 3.0f, lineY + bend), PointF(x + halfWidth, lineY));
    } else {
        const float pupilScale = std::clamp(p.pupilScale.value, 0.8f, 1.3f) * (1.0f + hunt * 0.30f);
        const float pupilRadius = (pupilBounds.Width + pupilBounds.Height) * 0.25f;
        const Pt gaze = p.eyeGaze.point();
        const float travel = std::max(0.0f, (radius - pupilRadius * pupilScale) * 0.85f)
            / std::max(1.0f, std::hypot(gaze.x, gaze.y));
        const float px = pupilBounds.X + pupilBounds.Width * 0.5f;
        const float py = pupilBounds.Y + pupilBounds.Height * 0.5f;
        const GraphicsState pupilState = g.Save();
        g.TranslateTransform(px + gaze.x * travel, py + gaze.y * travel * 0.9f);
        g.ScaleTransform(pupilScale, pupilScale);
        g.TranslateTransform(-px, -py);
        g.FillPath(&dark, &eye.pupil);
        g.Restore(pupilState);
    }
    const float anger = clampUnit((p.angerIntensity.value - 0.15f) / 0.6f);
    const float lid = std::max(closure, anger * 0.42f);
    if (!happy && lid > 0.01f) {
        const float edge = whiteBounds.Y + std::min(lid, 0.64f) * whiteBounds.Height;
        const float left = whiteBounds.X, right = whiteBounds.GetRight();
        const float inner = edge + anger * 0.20f * radius, outer = edge - anger * 0.08f * radius;
        const PointF lidPath[] = {
            {left, whiteBounds.Y - 1.0f}, {right, whiteBounds.Y - 1.0f},
            {right, side > 0.0f ? outer : inner}, {left, side > 0.0f ? inner : outer}
        };
        g.FillPolygon(&dark, lidPath, 4);
    }
    g.Restore(state);
}

inline void drawAngerMark(Graphics& g, const CatPhysics& p, float yaw) {
    const float intensity = clampUnit((p.angerIntensity.value - 0.25f) / 0.35f);
    if (intensity <= 0.0f) return;

    const GraphicsState state = g.Save();
    const float pulse = (1.75f + std::sin(p.time * 14.0f) * 0.12f) / HeadScale;
    g.TranslateTransform(615.0f + yaw * 20.0f, 230.0f);
    g.ScaleTransform(pulse, pulse);

    Pen mark(Color(static_cast<BYTE>(intensity * 255.0f), 255, 41, 61), 2.2f);
    mark.SetStartCap(LineCapRound);
    mark.SetEndCap(LineCapRound);
    constexpr float inner = 2.6f, outer = 6.8f;
    constexpr float control = inner + (outer - inner) / 3.0f;
    constexpr Pt sides[] = {{-1, -1}, {1, -1}, {-1, 1}, {1, 1}};
    for (const Pt side : sides) {
        g.DrawBezier(&mark, PointF(side.x * outer, side.y * inner), PointF(side.x * control, side.y * inner),
                     PointF(side.x * inner, side.y * control), PointF(side.x * inner, side.y * outer));
    }
    g.Restore(state);
}

inline void drawHead(Graphics& g, const CatPhysics& p, bool showPaws) {
    const GraphicsState state = g.Save();
    constexpr float width = CatPhysics::CanvasWidth;
    const PointF points[] = {{0, 0}, {width, 0}, {width, keyboardEdge(width)}, {0, keyboardEdge(0)}};
    GraphicsPath visibleHead;
    visibleHead.AddPolygon(points, 4);
    g.SetClip(&visibleHead, CombineModeIntersect);
    const Pt center = headCenter(p, showPaws);
    const float squash = 1.0f - p.bodySquash.value;
    g.TranslateTransform(center.x, center.y);
    g.RotateTransform(headRotation(p, center) * RadToDeg);
    g.TranslateTransform(0.0f, (HeadChinY - HeadPivotY) * HeadScale);
    g.ScaleTransform(HeadScale * (1.0f + squash * 0.25f), HeadScale * (1.0f - squash * 0.45f));
    g.TranslateTransform(-HeadPivotX, -HeadChinY);

    const float yaw = std::clamp(p.headYaw.value, -1.0f, 1.0f);
    const float pitch = std::clamp(p.headPitch.value, -1.0f, 1.0f);
    GraphicsPath leftEar, rightEar, head;
    poseEar(leftEar, XiaoheiArt::earLeft, -1.0f, yaw, pitch, p);
    poseEar(rightEar, XiaoheiArt::earRight, 1.0f, yaw, pitch, p);
    addSvgPath(head, XiaoheiArt::head);
    Matrix headShift(1.0f, 0.0f, 0.0f, 1.0f, yaw * 8.0f, 0.0f);
    head.Transform(&headShift);

    Pen rim(Color(235, 254, 246, 236), 15.0f);
    rim.SetLineJoin(LineJoinRound);
    SolidBrush dark(ink);
    for (auto* part : {&leftEar, &rightEar, &head}) g.DrawPath(&rim, part);
    for (auto* part : {&leftEar, &rightEar, &head}) g.FillPath(&dark, part);

    EyeArt left, right;
    addSvgPath(right.white, XiaoheiArt::eyeWhite);
    addSvgPath(right.pupil, XiaoheiArt::pupil);
    const auto& t = XiaoheiArt::eyeTransform;
    Matrix eyeTransform(t[0], t[1], t[2], t[3], t[4], t[5]);
    right.white.Transform(&eyeTransform);
    right.pupil.Transform(&eyeTransform);
    left.white.AddPath(&right.white, FALSE);
    left.pupil.AddPath(&right.pupil, FALSE);
    Matrix mirror(-1.0f, 0.0f, 0.0f, 1.0f, 2.0f * HeadPivotX, 0.0f);
    left.white.Transform(&mirror);
    left.pupil.Transform(&mirror);
    drawEye(g, left, p, -1.0f, yaw, pitch);
    drawEye(g, right, p, 1.0f, yaw, pitch);
    drawAngerMark(g, p, yaw);
    g.Restore(state);
}

inline void drawPaws(Graphics& g, const CatPhysics& p) {
    const Pt head = headCenter(p);
    const float lie = smoothUnit(p.lieIntensity.value);
    const Pt paws[] = {p.leftPaw.point(), p.rightPaw.point()};
    const Pt rest[] = {CatPhysics::LeftPawRest, CatPhysics::RightPawRest};

    GraphicsPath paw;
    paw.AddBezier(PointF(-10.5f, 2.0f), PointF(-10.5f, -10.5f), PointF(10.5f, -10.5f), PointF(10.5f, 2.0f));
    paw.AddBezier(PointF(10.5f, 2.0f), PointF(9.5f, 8.8f), PointF(-9.5f, 8.8f), PointF(-10.5f, 2.0f));
    paw.CloseFigure();
    SolidBrush fill(ink);
    SolidBrush shadow(Color(static_cast<BYTE>(255.0f * 0.16f * (1.0f - lie)), 23, 23, 23));
    Pen outline(Color(242, 254, 246, 236), 2.6f);
    Pen toes(Color(230, 254, 246, 236), 1.2f);
    toes.SetStartCap(LineCapRound);
    toes.SetEndCap(LineCapRound);

    for (int i = 0; i < 2; ++i) {
        const float side = i == 0 ? -1.0f : 1.0f;
        const float resting = 1.0f - clampUnit(std::hypot(paws[i].x - rest[i].x, paws[i].y - rest[i].y) / 12.0f);
        const float idleX = head.x + side * 46.0f;
        const float x = paws[i].x + (idleX - paws[i].x) * resting;
        const float y = paws[i].y + (keyboardEdge(idleX) + 14.0f - paws[i].y) * resting;
        const float liftedY = y - (1.5f + std::sin(p.time * 2.1f + side * 0.9f) * 1.3f) * resting;
        const float tuckX = head.x + side * 44.0f;
        const float tuckY = keyboardEdge(tuckX) + 8.0f;
        g.FillEllipse(&shadow, x - 8.0f, y - 1.0f, 16.0f, 5.0f);

        const GraphicsState state = g.Save();
        g.TranslateTransform(x + (tuckX - x) * lie, liftedY + (tuckY - liftedY) * lie - 6.5f);
        g.RotateTransform((side * 0.16f + p.headTilt.value * 0.3f) * RadToDeg);
        g.DrawPath(&outline, &paw);
        g.FillPath(&fill, &paw);
        g.DrawLine(&toes, -3.6f, 7.0f, -3.1f, 3.4f);
        g.DrawLine(&toes, 3.6f, 7.0f, 3.1f, 3.4f);
        g.Restore(state);
    }
}
}
