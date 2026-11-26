#pragma once
#include <windows.h>
#include <algorithm>
#include <array>
#include <string>
#include <vector>

namespace DisplayPlacement {

struct Monitor {
    std::wstring id;
    RECT bounds;
    RECT work;
    bool primary;
    bool builtIn = false;
};

inline constexpr wchar_t registryKey[] = L"Software\\XiaoheiPet\\DisplayPositions";
inline constexpr wchar_t preferredValue[] = L"PreferredDisplay";
inline constexpr DWORD units = 10000;
using Position = std::array<DWORD, 2>;

inline std::vector<Monitor> connectedMonitors() {
    std::vector<Monitor> monitors;
    std::vector<std::wstring> deviceNames;
    struct Enumeration {
        std::vector<Monitor>& monitors;
        std::vector<std::wstring>& deviceNames;
    } result{monitors, deviceNames};
    EnumDisplayMonitors(nullptr, nullptr, [](HMONITOR handle, HDC, LPRECT, LPARAM data) -> BOOL {
        auto& result = *reinterpret_cast<Enumeration*>(data);
        MONITORINFOEXW info{};
        info.cbSize = sizeof(info);
        if (GetMonitorInfoW(handle, reinterpret_cast<MONITORINFO*>(&info))) {
            result.monitors.push_back({{}, info.rcMonitor, info.rcWork, (info.dwFlags & MONITORINFOF_PRIMARY) != 0});
            result.deviceNames.emplace_back(info.szDevice);
        }
        return TRUE;
    }, reinterpret_cast<LPARAM>(&result));

    std::vector<DISPLAYCONFIG_PATH_INFO> paths;
    std::vector<DISPLAYCONFIG_MODE_INFO> modes;
    LONG status = ERROR_INSUFFICIENT_BUFFER;
    for (int attempt = 0; attempt < 3 && status == ERROR_INSUFFICIENT_BUFFER; ++attempt) {
        UINT32 pathCount = 0, modeCount = 0;
        if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &pathCount, &modeCount) != ERROR_SUCCESS) return monitors;
        paths.resize(pathCount);
        modes.resize(modeCount);
        status = QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &pathCount, paths.data(), &modeCount, modes.data(), nullptr);
        if (status == ERROR_SUCCESS) paths.resize(pathCount);
    }
    if (status != ERROR_SUCCESS) return monitors;
    for (const auto& path : paths) {
        DISPLAYCONFIG_SOURCE_DEVICE_NAME source{};
        source.header = {DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME, sizeof(source), path.sourceInfo.adapterId, path.sourceInfo.id};
        if (DisplayConfigGetDeviceInfo(&source.header) != ERROR_SUCCESS) continue;
        auto match = std::find(deviceNames.begin(), deviceNames.end(), source.viewGdiDeviceName);
        if (match == deviceNames.end()) continue;

        DISPLAYCONFIG_TARGET_DEVICE_NAME target{};
        target.header = {DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME, sizeof(target), path.targetInfo.adapterId, path.targetInfo.id};
        if (DisplayConfigGetDeviceInfo(&target.header) != ERROR_SUCCESS) continue;
        auto& monitor = monitors[static_cast<size_t>(match - deviceNames.begin())];
        const auto technology = path.targetInfo.outputTechnology;
        const bool builtIn = technology == DISPLAYCONFIG_OUTPUT_TECHNOLOGY_INTERNAL
            || technology == DISPLAYCONFIG_OUTPUT_TECHNOLOGY_LVDS
            || technology == DISPLAYCONFIG_OUTPUT_TECHNOLOGY_DISPLAYPORT_EMBEDDED
            || technology == DISPLAYCONFIG_OUTPUT_TECHNOLOGY_UDI_EMBEDDED;
        if (monitor.id.empty() || builtIn) monitor.id = target.monitorDevicePath;
        monitor.builtIn = monitor.builtIn || builtIn;
    }
    return monitors;
}

inline const Monitor* fallbackMonitor(const std::vector<Monitor>& monitors) {
    const Monitor* primary = monitors.empty() ? nullptr : &monitors.front();
    for (const auto& monitor : monitors) {
        if (monitor.builtIn) return &monitor;
        if (monitor.primary) primary = &monitor;
    }
    return primary;
}

inline const Monitor* monitorContaining(RECT frame, const std::vector<Monitor>& monitors) {
    const Monitor* selected = nullptr;
    long long largestOverlap = 0;
    for (const auto& monitor : monitors) {
        RECT intersection{};
        if (!IntersectRect(&intersection, &frame, &monitor.bounds)) continue;
        const auto area = static_cast<long long>(intersection.right - intersection.left)
            * (intersection.bottom - intersection.top);
        if (area <= largestOverlap) continue;
        largestOverlap = area;
        selected = &monitor;
    }
    return selected;
}

inline POINT originInWorkArea(RECT work, SIZE size, const Position* position = nullptr) {
    const LONG travelX = std::max(0L, work.right - work.left - size.cx);
    const LONG travelY = std::max(0L, work.bottom - work.top - size.cy);
    if (!position) {
        return {work.left + std::max(0L, travelX - 24), work.top + std::max(0L, travelY - 12)};
    }
    return {work.left + static_cast<LONG>(static_cast<long long>(travelX) * (*position)[0] / units),
            work.top + static_cast<LONG>(static_cast<long long>(travelY) * (*position)[1] / units)};
}

inline std::wstring preferredMonitor() {
    wchar_t id[128]{};
    DWORD bytes = sizeof(id);
    if (RegGetValueW(HKEY_CURRENT_USER, registryKey, preferredValue, RRF_RT_REG_SZ, nullptr, id, &bytes) != ERROR_SUCCESS) return {};
    return id;
}

inline void remember(RECT frame, const std::vector<Monitor>& monitors, bool preferred) {
    const auto* monitor = monitorContaining(frame, monitors);
    if (!monitor || monitor->id.empty()) return;
    auto fraction = [](LONG offset, LONG travel) -> DWORD {
        if (travel <= 0) return 0;
        return static_cast<DWORD>(static_cast<long long>(std::clamp(offset, 0L, travel)) * units / travel);
    };
    const RECT work = monitor->work;
    const Position position{fraction(frame.left - work.left, (work.right - work.left) - (frame.right - frame.left)),
                            fraction(frame.top - work.top, (work.bottom - work.top) - (frame.bottom - frame.top))};
    HKEY key = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, registryKey, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &key, nullptr)
        != ERROR_SUCCESS) return;
    if (RegSetValueExW(key, monitor->id.c_str(), 0, REG_BINARY, reinterpret_cast<const BYTE*>(position.data()), sizeof(position))
        == ERROR_SUCCESS && preferred) {
        RegSetValueExW(key, preferredValue, 0, REG_SZ, reinterpret_cast<const BYTE*>(monitor->id.c_str()),
                       static_cast<DWORD>((monitor->id.size() + 1) * sizeof(wchar_t)));
    }
    RegCloseKey(key);
}

inline POINT restore(SIZE size, POINT legacyOrigin, const std::vector<Monitor>& monitors) {
    const Monitor* monitor = fallbackMonitor(monitors);
    if (!monitor) {
        RECT work{};
        SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
        return originInWorkArea(work, size);
    }
    auto preferred = preferredMonitor();
    if (preferred.empty() && legacyOrigin.x != -99999 && legacyOrigin.y != -99999) {
        const RECT frame{legacyOrigin.x, legacyOrigin.y, legacyOrigin.x + size.cx, legacyOrigin.y + size.cy};
        remember(frame, monitors, true);
        preferred = preferredMonitor();
    }
    if (!preferred.empty()) {
        auto match = std::find_if(monitors.begin(), monitors.end(), [&](const Monitor& entry) { return entry.id == preferred; });
        if (match != monitors.end()) monitor = &*match;
    }
    Position saved{};
    DWORD bytes = sizeof(saved);
    if (!monitor->id.empty()
        && RegGetValueW(HKEY_CURRENT_USER, registryKey, monitor->id.c_str(), RRF_RT_REG_BINARY, nullptr, saved.data(), &bytes)
            == ERROR_SUCCESS
        && bytes == sizeof(saved) && saved[0] <= units && saved[1] <= units) {
        return originInWorkArea(monitor->work, size, &saved);
    }
    return originInWorkArea(monitor->work, size);
}

} // namespace DisplayPlacement
