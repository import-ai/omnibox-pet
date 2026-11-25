#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0601
#endif
#ifndef WINVER
#define WINVER 0x0601
#endif
#define NOMINMAX
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <shellapi.h>
#include <winhttp.h>
#include <array>
#include <memory>
#include <regex>
#include <thread>
#include "AppVersion.hpp"
// MSVC's GDI+ headers call unqualified min()/max() inside inline helpers; NOMINMAX
// removes the macros, so the std overloads must be visible before <gdiplus.h>.
#include <algorithm>
using std::min;
using std::max;
#include <objidl.h>
#include <gdiplus.h>
#include <wtsapi32.h>
#include <string>
#include <vector>
#include <cmath>
#include <cwchar>
#include "KeyMap.hpp"
#include "InputEngine.hpp"
#include "CatPhysics.hpp"
#include "CatRenderer.hpp"
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "gdiplus.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "wtsapi32.lib")

namespace {

constexpr const wchar_t* RELEASES_URL = L"https://github.com/import-ai/omnibox-pet/releases/latest";
constexpr const wchar_t* VERSION_PROP = L"OmniBoxPetVersion"; // set on the tray owner window so newer builds can take over older ones
constexpr const wchar_t* TRAY_OWNER_CLASS = L"XiaoheiPetTrayOwnerClass";
constexpr const wchar_t* OVERLAY_CLASS = L"XiaoheiPetOverlayWindowClass";
constexpr double FRAME_INTERVAL = 1.0 / 60.0;
constexpr UINT WM_TRAYICON = WM_APP + 1;
constexpr UINT WM_WAKE_EXISTING = WM_APP + 2;
constexpr UINT WM_UPDATE_CHECK_DONE = WM_APP + 3;
constexpr UINT WM_REQUEST_QUIT = WM_APP + 5; // posted by a newer / elevated instance that is taking over
constexpr UINT_PTR TIMER_RENDER = 1;
constexpr int HOTKEY_CLICKTHROUGH_ID = 101;
UINT g_msgTaskbarCreated = 0;

enum MenuCmd : UINT {
    CMD_TOGGLE_VISIBLE = 1001,
    CMD_TOGGLE_CLICKTHROUGH,
    CMD_TOGGLE_TOPMOST,
    CMD_TOGGLE_AUTOHIDE_FS,
    CMD_TOGGLE_AUTOSTART,
    CMD_TOGGLE_BADGES,
    CMD_TOGGLE_PAWS,
    CMD_TOGGLE_MOUSE_BADGES,
    CMD_TOGGLE_KEY_LEGENDS,
    CMD_TOGGLE_FOOT,
    CMD_TOGGLE_TAIL,
    CMD_TOGGLE_MARQUEE,
    CMD_TOGGLE_PET,
    CMD_OBS_OFF,
    CMD_OBS_TRANSPARENT,
    CMD_OBS_GREENSCREEN,
    CMD_TOGGLE_OBS_HIDE,
    CMD_TOGGLE_EDIT,
    CMD_LANG_ZH,
    CMD_LANG_EN,
    CMD_KB_MILK,
    CMD_KB_HACKER,
    CMD_KB_RETRO,
    CMD_SCALE_65,
    CMD_SCALE_85,
    CMD_SCALE_100,
    CMD_SCALE_125,
    CMD_SCALE_150,
    CMD_DEMO_BURST,
    CMD_RESET_POS,
    CMD_RELAUNCH_ADMIN,
    CMD_TOGGLE_RUN_AS_ADMIN,
    CMD_SKINS,
    CMD_CHECK_UPDATES,
    CMD_QUIT,
    CMD_TABLET_AUTO,
    CMD_TABLET_ON,
    CMD_TABLET_OFF,
};

struct AppState {
    HWND hwnd = nullptr;
    HWND menuOwnerHwnd = nullptr; // Non-NOACTIVATE helper window so TrackPopupMenu from tray NEVER fails!
    HICON trayIcon = nullptr;
    NOTIFYICONDATAW nid = {};

    CatSettings settings;
    InputEngine input;
    CatPhysics physics;

    bool updateCheckInProgress = false;
    bool updateCheckRequested = false;
    bool isVisible = true;
    bool hiddenByFullscreen = false;
    bool isDragging = false;
    int activeResizeCorner = -1; // -1 = none, 0=TL, 1=TR, 2=BL, 3=BR
    POINT resizeAnchorScreenPt = {};
    bool rButtonDown = false;
    bool pendingMenuAfterAlt = false;
    POINT pendingMenuPt = {};
    POINT dragStartCursor = {};
    POINT dragStartWinOrigin = {};
    bool hasLastHover = false;
    Pt lastHoverCanvas = {};

    // Reusable 32-bit premultiplied DIB backing buffer
    HDC memDC = nullptr;
    HBITMAP dibBmp = nullptr;
    HBITMAP oldBmp = nullptr;
    void* dibBits = nullptr;
    int bufW = 0;
    int bufH = 0;

    double lastTickTime = 0.0;
    bool demoActive = false;
    double demoStartTime = 0.0;
    int demoStepIdx = 0;


    // Robustness against games, Win+L, sleep and display changes
    double nextFrameTime = 0.0;
    double lastRenderTime = 0.0;
    double nextHousekeepingTime = 0.0;
    double pendingTopmostTime = 0.0;
    int ulwFailures = 0;
    bool isElevated = false;
    bool foregroundBlocksKeys = false;   // foreground app runs as admin -> Windows (UIPI) hides its keys from us
    double lastBlockedForegroundTime = 0.0;
    double blockedForegroundSince = 0.0;
    bool warnedElevatedForeground = false;
    HWINEVENTHOOK foregroundHook = nullptr;
    bool sessionNotifyRegistered = false;

    void destroyBuffer() {
        if (memDC && oldBmp) SelectObject(memDC, oldBmp);
        if (dibBmp) DeleteObject(dibBmp);
        if (memDC) DeleteDC(memDC);
        memDC = nullptr; dibBmp = nullptr; oldBmp = nullptr; dibBits = nullptr;
        bufW = 0; bufH = 0;
    }

    void ensureBuffer(int w, int h) {
        if (w == bufW && h == bufH && memDC && dibBits) return;
        destroyBuffer();

        HDC screenDC = GetDC(nullptr);
        memDC = CreateCompatibleDC(screenDC);
        ReleaseDC(nullptr, screenDC);

        BITMAPINFO bmi = {};
        bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        bmi.bmiHeader.biWidth = w;
        bmi.bmiHeader.biHeight = -h; // top-down 32bpp DIB
        bmi.bmiHeader.biPlanes = 1;
        bmi.bmiHeader.biBitCount = 32;
        bmi.bmiHeader.biCompression = BI_RGB;

        dibBmp = CreateDIBSection(memDC, &bmi, DIB_RGB_COLORS, &dibBits, nullptr, 0);
        if (dibBmp) {
            oldBmp = (HBITMAP)SelectObject(memDC, dibBmp);
            bufW = w;
            bufH = h;
        }
    }
};

AppState* g_app = nullptr;

HICON createCatTrayIcon();

// MARK: - Windows Auto-Start (HKCU\Software\Microsoft\Windows\CurrentVersion\Run)

std::wstring getCurrentExeQuotedPath() {
    wchar_t buf[MAX_PATH * 2] = {};
    DWORD len = GetModuleFileNameW(nullptr, buf, (DWORD)(sizeof(buf) / sizeof(buf[0]) - 1));
    if (len == 0) return L"";
    return L"\"" + std::wstring(buf, len) + L"\"";
}

bool isAutoStartEnabled() {
    HKEY hKey = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0, KEY_READ, &hKey) != ERROR_SUCCESS) {
        return false;
    }
    DWORD type = 0, size = 0;
    bool exists = (RegQueryValueExW(hKey, L"XiaoheiPet", nullptr, &type, nullptr, &size) == ERROR_SUCCESS && size > 0);
    RegCloseKey(hKey);
    return exists;
}

bool setAutoStartEnabled(bool enable) {
    HKEY hKey = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0, nullptr, 0, KEY_WRITE, nullptr, &hKey, nullptr) != ERROR_SUCCESS) {
        return false;
    }
    bool ok = false;
    if (enable) {
        std::wstring cmd = getCurrentExeQuotedPath();
        if (!cmd.empty()) {
            ok = (RegSetValueExW(hKey, L"XiaoheiPet", 0, REG_SZ, (const BYTE*)cmd.c_str(), (DWORD)((cmd.size() + 1) * sizeof(wchar_t))) == ERROR_SUCCESS);
        }
    } else {
        LSTATUS st = RegDeleteValueW(hKey, L"XiaoheiPet");
        ok = (st == ERROR_SUCCESS || st == ERROR_FILE_NOT_FOUND);
    }
    RegCloseKey(hKey);
    return ok;
}

void showTrayBalloon(AppState& app, const wchar_t* title, const wchar_t* body) {
    NOTIFYICONDATAW b = app.nid;
    b.uFlags = NIF_INFO;
    b.dwInfoFlags = NIIF_INFO | NIIF_NOSOUND;
    wcsncpy_s(b.szInfoTitle, title, _TRUNCATE);
    wcsncpy_s(b.szInfo, body, _TRUNCATE);
    Shell_NotifyIconW(NIM_MODIFY, &b);
}

// MARK: - Elevation (UIPI) helpers
//
// Many games (and launchers such as WeGame / anti-cheat clients) run as administrator. Windows'
// User Interface Privilege Isolation then refuses to deliver that window's keystrokes to normal
// programs — Raw Input, GetAsyncKeyState and low-level hooks all go silent — while mouse movement
// is still visible. That is exactly the "cat only sees the mouse in games" report. The only fix
// is for XiaoheiPet to run at the same level, so we detect it and offer an admin relaunch.

bool isCurrentProcessElevated() {
    HANDLE tok = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok)) return false;
    TOKEN_ELEVATION te = {};
    DWORD sz = 0;
    bool elevated = GetTokenInformation(tok, TokenElevation, &te, sizeof(te), &sz) && te.TokenIsElevated != 0;
    CloseHandle(tok);
    return elevated;
}

bool isProcessElevatedOrProtected(DWORD pid) {
    HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!h) return GetLastError() == ERROR_ACCESS_DENIED; // protected / anti-cheat processes
    bool elevated = false;
    HANDLE tok = nullptr;
    if (OpenProcessToken(h, TOKEN_QUERY, &tok)) {
        TOKEN_ELEVATION te = {};
        DWORD sz = 0;
        if (GetTokenInformation(tok, TokenElevation, &te, sizeof(te), &sz)) elevated = te.TokenIsElevated != 0;
        CloseHandle(tok);
    } else {
        elevated = (GetLastError() == ERROR_ACCESS_DENIED);
    }
    CloseHandle(h);
    return elevated;
}

bool commandLineHasFlag(const wchar_t* flag) {
    int argc = 0;
    LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!argv) return false;
    bool found = false;
    for (int i = 1; i < argc; ++i) {
        if (_wcsicmp(argv[i], flag) == 0) { found = true; break; }
    }
    LocalFree(argv);
    return found;
}

/// Starts a new elevated copy of this exe (UAC prompt). Returns false if the user declined.
bool relaunchSelfElevated(const wchar_t* params) {
    wchar_t exe[MAX_PATH * 2] = {};
    if (GetModuleFileNameW(nullptr, exe, (DWORD)(sizeof(exe) / sizeof(exe[0]) - 1)) == 0) return false;
    SHELLEXECUTEINFOW sei = {};
    sei.cbSize = sizeof(sei);
    sei.fMask = SEE_MASK_NOASYNC;
    sei.lpVerb = L"runas";
    sei.lpFile = exe;
    sei.lpParameters = params;
    sei.nShow = SW_SHOWNORMAL;
    return ShellExecuteExW(&sei) != FALSE;
}

/// True when the foreground window covers its whole monitor (WPS PPT slideshow, fullscreen video, games).
bool isForegroundFullscreen(HWND selfHwnd) {
    HWND fg = GetForegroundWindow();
    if (!fg || fg == selfHwnd || fg == GetDesktopWindow() || fg == GetShellWindow()) return false;
    wchar_t cls[64] = {};
    GetClassNameW(fg, cls, 63);
    if (wcscmp(cls, L"WorkerW") == 0 || wcscmp(cls, L"Progman") == 0 ||
        wcscmp(cls, L"Shell_TrayWnd") == 0 || wcscmp(cls, L"Shell_SecondaryTrayWnd") == 0) return false;
    RECT wr = {};
    if (!GetWindowRect(fg, &wr)) return false;
    MONITORINFO mi = {};
    mi.cbSize = sizeof(mi);
    if (!GetMonitorInfoW(MonitorFromWindow(fg, MONITOR_DEFAULTTONEAREST), &mi)) return false;
    return wr.left <= mi.rcMonitor.left + 2 && wr.top <= mi.rcMonitor.top + 2 &&
           wr.right >= mi.rcMonitor.right - 2 && wr.bottom >= mi.rcMonitor.bottom - 2;
}

bool hasVisibleWindowAbove(HWND hwnd) {
    if (!hwnd) return false;
    HWND prev = GetWindow(hwnd, GW_HWNDPREV);
    int steps = 0;
    while (prev && steps++ < 16) {
        if (IsWindowVisible(prev)) {
            RECT r = {};
            if (GetWindowRect(prev, &r) && (r.right - r.left) > 4 && (r.bottom - r.top) > 4) {
                return true;
            }
        }
        prev = GetWindow(prev, GW_HWNDPREV);
    }
    return false;
}

int versionToNumber(const std::wstring& v) {
    int parts[3] = { 0, 0, 0 };
    int idx = 0;
    for (wchar_t c : v) {
        if (c >= L'0' && c <= L'9') parts[idx] = parts[idx] * 10 + (c - L'0');
        else if (c == L'.') { if (++idx >= 3) break; }
    }
    return parts[0] * 10000 + parts[1] * 100 + parts[2];
}

enum class UpdateResult { Failed, NoRelease, Current, Available };

std::array<int, 3> versionParts(const std::string& version) {
    std::array<int, 3> parts{};
    size_t start = version.front() == 'v' ? 1 : 0;
    for (int& part : parts) {
        const size_t dot = version.find('.', start);
        part = std::stoi(version.substr(start, dot - start));
        start = dot + 1;
    }
    return parts;
}

UpdateResult checkLatestRelease() {
    using Handle = std::unique_ptr<void, decltype(&WinHttpCloseHandle)>;
    Handle session(WinHttpOpen(L"OmniBox Pet", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                              WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0), WinHttpCloseHandle);
    if (!session || !WinHttpSetTimeouts(session.get(), 5000, 5000, 5000, 5000)) return UpdateResult::Failed;
    Handle connection(WinHttpConnect(session.get(), L"api.github.com", INTERNET_DEFAULT_HTTPS_PORT, 0),
                      WinHttpCloseHandle);
    if (!connection) return UpdateResult::Failed;
    Handle request(WinHttpOpenRequest(connection.get(), L"GET", L"/repos/import-ai/omnibox-pet/releases/latest",
                                      nullptr, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE),
                   WinHttpCloseHandle);
    if (!request ||
        !WinHttpSendRequest(request.get(), L"Accept: application/vnd.github+json\r\n", DWORD(-1),
                            WINHTTP_NO_REQUEST_DATA, 0, 0, 0) ||
        !WinHttpReceiveResponse(request.get(), nullptr)) return UpdateResult::Failed;

    DWORD status = 0;
    DWORD size = sizeof(status);
    if (!WinHttpQueryHeaders(request.get(), WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                            WINHTTP_HEADER_NAME_BY_INDEX, &status, &size, WINHTTP_NO_HEADER_INDEX)) {
        return UpdateResult::Failed;
    }
    if (status == 404) return UpdateResult::NoRelease;
    if (status != 200) return UpdateResult::Failed;

    std::string body;
    char buffer[4096];
    while (body.size() < 1024 * 1024) {
        DWORD bytes = 0;
        if (!WinHttpReadData(request.get(), buffer, sizeof(buffer), &bytes)) return UpdateResult::Failed;
        if (bytes == 0) break;
        body.append(buffer, bytes);
    }
    static const std::regex tagPattern(R"tag("tag_name"\s*:\s*"(v?[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4})")tag");
    std::smatch tag;
    if (!std::regex_search(body, tag, tagPattern)) return UpdateResult::Failed;
    return versionParts(tag[1].str()) > versionParts(APP_VERSION_TEXT) ? UpdateResult::Available : UpdateResult::Current;
}

void startUpdateCheck(AppState& app, bool manual) {
    app.updateCheckRequested = app.updateCheckRequested || manual;
    if (app.updateCheckInProgress) return;
    app.updateCheckInProgress = true;
    const HWND window = app.hwnd;
    std::thread([window] {
        PostMessageW(window, WM_UPDATE_CHECK_DONE, 0, static_cast<LPARAM>(checkLatestRelease()));
    }).detach();
}

void showUpdateResult(AppState& app, UpdateResult result) {
    const bool manual = app.updateCheckRequested;
    app.updateCheckRequested = false;
    app.updateCheckInProgress = false;
    const bool english = app.settings.isEnglish;
    const wchar_t* title = english ? L"OmniBox Pet" : L"桌宠小黑";
    if (result == UpdateResult::Available) {
        const wchar_t* message = english ? L"A new version is available. Open the release page to download it?"
                                         : L"有新版本。要打开发布页下载吗？";
        if (MessageBoxW(app.hwnd, message, title, MB_YESNO | MB_ICONINFORMATION) == IDYES) {
            ShellExecuteW(app.hwnd, L"open", RELEASES_URL, nullptr, nullptr, SW_SHOWNORMAL);
        }
    } else if (manual) {
        const wchar_t* message = english ? L"Couldn’t check for updates." : L"暂时无法检查更新。";
        if (result == UpdateResult::Current) message = english ? L"You’re up to date." : L"当前已是最新版本。";
        if (result == UpdateResult::NoRelease) message = english ? L"No stable release yet." : L"暂无正式版本。";
        MessageBoxW(app.hwnd, message, title, MB_OK | MB_ICONINFORMATION);
    }
}

void enableBestDpiAwareness() {
    // 1. Windows 10 1703+: Per-Monitor V2 DPI Awareness (dynamically loaded so Win7/8 won't fail to launch)
    if (HMODULE hUser32 = GetModuleHandleW(L"user32.dll")) {
        using SetDpiCtxFn = BOOL(WINAPI*)(HANDLE);
        auto fn = reinterpret_cast<SetDpiCtxFn>(GetProcAddress(hUser32, "SetProcessDpiAwarenessContext"));
        if (fn && fn(reinterpret_cast<HANDLE>(static_cast<INT_PTR>(-4)))) {
            return;
        }
    }
    // 2. Windows 8.1+: Per-Monitor DPI Awareness via shcore.dll
    if (HMODULE hShcore = LoadLibraryW(L"shcore.dll")) {
        using SetDpiAwareFn = HRESULT(WINAPI*)(int);
        auto fn = reinterpret_cast<SetDpiAwareFn>(GetProcAddress(hShcore, "SetProcessDpiAwareness"));
        bool ok = (fn && SUCCEEDED(fn(2)));
        FreeLibrary(hShcore);
        if (ok) return;
    }
    // 3. Windows Vista / 7: System DPI Awareness
    if (HMODULE hUser32 = GetModuleHandleW(L"user32.dll")) {
        using SetSysDpiFn = BOOL(WINAPI*)();
        auto fn = reinterpret_cast<SetSysDpiFn>(GetProcAddress(hUser32, "SetProcessDPIAware"));
        if (fn) fn();
    }
}

void registerTrayIcon(AppState& app) {
    if (!app.trayIcon) app.trayIcon = createCatTrayIcon();
    app.nid = {};
    app.nid.cbSize = sizeof(app.nid);
    app.nid.hWnd = app.menuOwnerHwnd ? app.menuOwnerHwnd : app.hwnd;
    app.nid.uID = 1;
    app.nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    app.nid.uCallbackMessage = WM_TRAYICON;
    app.nid.hIcon = app.trayIcon;
    wcscpy_s(app.nid.szTip, L"桌宠小黑 (OmniBox Pet)");
    Shell_NotifyIconW(NIM_ADD, &app.nid);
}

HICON createCatTrayIcon() {
    using namespace Gdiplus;
    constexpr int sz = 32;
    Bitmap bmp(sz, sz, PixelFormat32bppPARGB);
    Graphics g(&bmp);
    g.SetSmoothingMode(SmoothingModeAntiAlias);
    g.Clear(Color(0, 0, 0, 0));

    g.TranslateTransform(16.0f, 16.0f);
    g.ScaleTransform(0.051f, 0.051f);
    g.TranslateTransform(-320.0f, -375.0f);
    XiaoheiRenderer::drawFace(g, CatPhysics{}, 10.0f);

    HICON hIcon = nullptr;
    bmp.GetHICON(&hIcon);
    return hIcon;
}

void computeDefaultOrigin(int w, int h, int& outX, int& outY) {
    RECT work = {};
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
    outX = work.right - w - 24;
    outY = work.bottom - h - 12;
}

void applyWindowScaleAndPosition(AppState& app, bool anchorBottomCenter, bool persist = true) {
    int newW = (int)std::round(CatPhysics::CanvasWidth * app.settings.scale);
    int newH = (int)std::round(CatPhysics::CanvasHeight * app.settings.scale);

    int x = app.settings.posX;
    int y = app.settings.posY;
    if (anchorBottomCenter && app.hwnd) {
        RECT r = {};
        GetWindowRect(app.hwnd, &r);
        int oldMidX = (r.left + r.right) / 2;
        int oldBotY = r.bottom;
        x = oldMidX - newW / 2;
        y = oldBotY - newH;
    } else if (x == -99999 || y == -99999) {
        computeDefaultOrigin(newW, newH, x, y);
    }

    // Clamp onto virtual desktop so saved off-monitor coords never get lost
    int vx = GetSystemMetrics(SM_XVIRTUALSCREEN);
    int vy = GetSystemMetrics(SM_YVIRTUALSCREEN);
    int vw = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    int vh = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    if (x + newW < vx + 40 || x > vx + vw - 40 || y + newH < vy + 40 || y > vy + vh - 40) {
        computeDefaultOrigin(newW, newH, x, y);
    }

    HWND insertAfter = app.settings.alwaysOnTop ? HWND_TOPMOST : HWND_NOTOPMOST;
    SetWindowPos(app.hwnd, insertAfter, x, y, newW, newH, SWP_NOACTIVATE);
    if (persist) {
        app.settings.posX = x;
        app.settings.posY = y;
        app.settings.saveToRegistry();
    }
}

/// Puts the cat back on top of other topmost windows (borderless/fullscreen games that make
/// themselves topmost after launching used to bury the cat, which looked like it "vanished").
void assertTopmost(AppState& app) {
    if (!app.hwnd || !app.isVisible || app.hiddenByFullscreen || !app.settings.alwaysOnTop) return;
    if (app.settings.obsCaptureMode > 0 && app.settings.obsHideDesktop) return;
    SetWindowPos(app.hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_NOSENDCHANGING);
}

/// Full self-repair after Win+L unlock, sleep/resume, display-mode changes (games switching
/// resolution) or a rendering stall: clears stuck keys, re-registers Raw Input, rebuilds the
/// layered-window buffer, restarts the frame timer and re-places the window on a visible monitor
/// WITHOUT overwriting the user's saved position.
void applyOBSMode(AppState& app);

void recoverAfterSystemEvent(AppState& app) {
    if (!app.hwnd) return;
    double now = nowSeconds();
    app.input.resetAllState();
    app.input.registerRawInput(app.hwnd);
    app.input.installKeyboardHook();
    if (app.settings.obsCaptureMode > 0 && app.settings.obsHideDesktop) {
        applyOBSMode(app);
    }
    app.input.lastMouseMoveTime = now; // wake the cat up so it visibly greets the user again
    app.destroyBuffer();
    app.ulwFailures = 0;
    app.isDragging = false;
    app.lastTickTime = now;
    app.nextFrameTime = 0.0;
    app.lastRenderTime = now;
    KillTimer(app.hwnd, TIMER_RENDER);
    SetTimer(app.hwnd, TIMER_RENDER, 16, nullptr);
    if (app.isVisible && !app.hiddenByFullscreen) ShowWindow(app.hwnd, SW_SHOWNOACTIVATE);
    applyWindowScaleAndPosition(app, false, false);
    app.pendingTopmostTime = now + 1.5; // some games re-assert topmost shortly after a mode switch
}

/// Twice per second: watchdog, fullscreen auto-hide, topmost re-assert, and UIPI detection.
void housekeeping(AppState& app) {
    double now = nowSeconds();
    if (now < app.nextHousekeepingTime) return;
    app.nextHousekeepingTime = now + 0.5;
    if (!app.hwnd) return;

    bool fullscreenFg = isForegroundFullscreen(app.hwnd);
    bool obsBg = (app.settings.obsCaptureMode > 0 && app.settings.obsHideDesktop);

    // Fullscreen auto-hide (PPT slideshow, fullscreen video, games)
    if (app.isVisible && app.settings.autoHideFullscreen && !obsBg) {
        if (fullscreenFg) {
            if (!app.hiddenByFullscreen) {
                app.hiddenByFullscreen = true;
                ShowWindow(app.hwnd, SW_HIDE);
            }
        } else if (app.hiddenByFullscreen) {
            app.hiddenByFullscreen = false;
            ShowWindow(app.hwnd, SW_SHOWNOACTIVATE);
            app.lastTickTime = now;
            app.lastRenderTime = now;
            assertTopmost(app);
        }
    } else if (app.hiddenByFullscreen) {
        app.hiddenByFullscreen = false;
        if (app.isVisible) {
            ShowWindow(app.hwnd, SW_SHOWNOACTIVATE);
            app.lastTickTime = now;
            app.lastRenderTime = now;
            assertTopmost(app);
        }
    }

    const bool effectivelyVisible = app.isVisible && !app.hiddenByFullscreen;

    // Rendering stalled for >2s while visible (e.g. the layered window lost its surface): self-heal.
    if (effectivelyVisible && app.lastRenderTime > 0.0 && now - app.lastRenderTime > 2.0) {
        recoverAfterSystemEvent(app);
        return;
    }
    if (effectivelyVisible && !IsWindowVisible(app.hwnd)) ShowWindow(app.hwnd, SW_SHOWNOACTIVATE);

    if (effectivelyVisible && !obsBg && app.settings.alwaysOnTop) {
        if (app.pendingTopmostTime > 0.0 && now >= app.pendingTopmostTime) {
            app.pendingTopmostTime = 0.0;
            assertTopmost(app);
        } else if (fullscreenFg || hasVisibleWindowAbove(app.hwnd)) {
            assertTopmost(app);
        }
    }

    // Some fullscreen/DirectInput games reset or starve Raw Input when taking focus;
    // periodically re-register RIDEV_INPUTSINK while a fullscreen app is active and no raw keys arrive.
    if (fullscreenFg && app.input.secondsSinceRawKeyboard(now) > 3.0) {
        app.input.registerRawInput(app.hwnd);
        if (!app.input.kbHook_) app.input.installKeyboardHook();
    }

    // Detect admin-level apps (WPS Office/PPT, games, admin terminals) whose keystrokes Windows withholds (UIPI).
    app.foregroundBlocksKeys = false;
    if (!app.isElevated) {
        HWND fg = GetForegroundWindow();
        DWORD pid = 0;
        if (fg) GetWindowThreadProcessId(fg, &pid);
        if (pid && pid != GetCurrentProcessId() && isProcessElevatedOrProtected(pid)) {
            app.foregroundBlocksKeys = true;
            app.lastBlockedForegroundTime = now;
            if (app.blockedForegroundSince <= 0.0) app.blockedForegroundSince = now;
            if (!app.warnedElevatedForeground && (fullscreenFg || (now - app.blockedForegroundSince >= 1.0))) {
                app.warnedElevatedForeground = true;
                showTrayBalloon(app,
                    L"XiaoheiPet 听不到当前窗口的键盘",
                    L"当前软件（如 WPS / 游戏）以管理员权限运行，Windows 会拦截它的键盘输入。右键小猫或托盘图标 →「以管理员身份重新启动」即可恢复。");
            }
        } else {
            app.blockedForegroundSince = 0.0;
        }
    }
}

void quitApp(AppState& app) {
    app.input.uninstallKeyboardHook();
    // Destroying the overlay runs the normal WM_DESTROY cleanup (tray icon, hotkey...) and quits.
    if (app.hwnd && IsWindow(app.hwnd)) DestroyWindow(app.hwnd);
    else PostQuitMessage(0);
}

void setClickThrough(HWND hwnd, bool transparent) {
    LONG_PTR ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    bool isTrans = (ex & WS_EX_TRANSPARENT) != 0;
    if (isTrans != transparent) {
        if (transparent) ex |= WS_EX_TRANSPARENT;
        else ex &= ~WS_EX_TRANSPARENT;
        SetWindowLongPtrW(hwnd, GWL_EXSTYLE, ex);
    }
}

void applyOBSMode(AppState& app) {
    if (!app.hwnd) return;
    LONG_PTR ex = GetWindowLongPtrW(app.hwnd, GWL_EXSTYLE);
    bool wantToolWindow = (app.settings.obsCaptureMode == 0);
    bool isToolWindow = (ex & WS_EX_TOOLWINDOW) != 0;
    if (wantToolWindow != isToolWindow) {
        if (wantToolWindow) ex |= WS_EX_TOOLWINDOW;
        else ex &= ~WS_EX_TOOLWINDOW;
        bool wasVis = app.isVisible && !app.hiddenByFullscreen;
        if (wasVis) ShowWindow(app.hwnd, SW_HIDE);
        SetWindowLongPtrW(app.hwnd, GWL_EXSTYLE, ex);
        SetWindowPos(app.hwnd, nullptr, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
        if (wasVis) ShowWindow(app.hwnd, SW_SHOWNOACTIVATE);
    }
    bool hideDesk = (app.settings.obsCaptureMode > 0 && app.settings.obsHideDesktop);
    if (hideDesk) {
        // Move off-monitor & remove topmost so desktop stays clean while OBS WGC captures live frames!
        int offX = GetSystemMetrics(SM_XVIRTUALSCREEN) + GetSystemMetrics(SM_CXVIRTUALSCREEN) + 120;
        int offY = GetSystemMetrics(SM_YVIRTUALSCREEN) + 40;
        SetWindowPos(app.hwnd, HWND_BOTTOM, offX, offY, 0, 0, SWP_NOSIZE | SWP_NOACTIVATE);
    } else {
        applyWindowScaleAndPosition(app, false);
    }
}

void showContextMenu(AppState& app, POINT screenPt) {
    HMENU menu = CreatePopupMenu();
    bool en = app.settings.isEnglish;
    auto tr = [&](const wchar_t* zh, const wchar_t* eng) -> const wchar_t* { return en ? eng : zh; };

    // Status & live stats header
    std::wstring statusStr = app.input.isRawInputRegistered
        ? tr(L"\u25CF \u786C\u4EF6\u7EA7\u5168\u72B6\u6001\u76D1\u542C\u4E2D (Raw Input \u6E38\u620F/\u6253\u5B57)",
             L"\u25CF Hardware Input Active (Raw Input)")
        : tr(L"\u26A0 Raw Input \u672A\u542F\u52A8", L"\u26A0 Raw Input Inactive");
    AppendMenuW(menu, MF_STRING | MF_GRAYED, 0, statusStr.c_str());
    if (!app.isElevated && app.lastBlockedForegroundTime > 0.0 && nowSeconds() - app.lastBlockedForegroundTime < 600.0) {
        AppendMenuW(menu, MF_STRING | MF_GRAYED, 0,
            tr(L"\u26A0 \u521A\u624D\u7684\u5E94\u7528\uFF08\u5982 WPS / \u6E38\u620F\uFF09\u4EE5\u7BA1\u7406\u5458\u6743\u9650\u8FD0\u884C\uFF0C\u952E\u76D8\u88AB Windows \u62E6\u622A\u4E86",
               L"\u26A0 Foreground admin app (e.g. WPS / game) blocked keyboard input"));
    }

    std::wstring stats = en
        ? (L"Today " + std::to_wstring(app.input.totalKeystrokesToday)
            + L"  \u00B7  KPM " + std::to_wstring(app.input.currentKPM())
            + L"  \u00B7  Pets " + std::to_wstring(app.physics.totalPetSessions))
        : (L"\u4ECA\u65E5\u51FB\u952E " + std::to_wstring(app.input.totalKeystrokesToday)
            + L"  \u00B7  KPM " + std::to_wstring(app.input.currentKPM())
            + L"  \u00B7  \u6478\u732B " + std::to_wstring(app.physics.totalPetSessions) + L" \u6B21");
    AppendMenuW(menu, MF_STRING | MF_GRAYED, 0, stats.c_str());
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);

    AppendMenuW(menu, MF_STRING, CMD_TOGGLE_VISIBLE, app.isVisible ? tr(L"\u9690\u85CF\u684C\u5BA0", L"Hide Pet") : tr(L"\u663E\u793A\u684C\u5BA0", L"Show Pet"));
    AppendMenuW(menu, MF_STRING | (app.settings.fullClickThrough ? MF_CHECKED : 0), CMD_TOGGLE_CLICKTHROUGH,
        tr(L"\u5B8C\u5168\u9F20\u6807\u7A7F\u900F (Ctrl+Alt+Shift+P / \u6309\u4F4FAlt\u53EF\u53F3\u952E)",
           L"Full Click-Through (Ctrl+Alt+Shift+P / Hold Alt)"));
    AppendMenuW(menu, MF_STRING | (app.settings.alwaysOnTop ? MF_CHECKED : 0), CMD_TOGGLE_TOPMOST, tr(L"\u7A97\u53E3\u7F6E\u9876\u663E\u793A", L"Always On Top"));
    AppendMenuW(menu, MF_STRING | (app.settings.autoHideFullscreen ? MF_CHECKED : 0), CMD_TOGGLE_AUTOHIDE_FS,
        tr(L"\u5168\u5C4F\u5E94\u7528\u65F6\u81EA\u52A8\u9690\u85CF\uFF08PPT / \u89C6\u9891 / \u6E38\u620F\uFF09",
           L"Auto-Hide in Fullscreen Apps (PPT / Video / Games)"));
    AppendMenuW(menu, MF_STRING | (isAutoStartEnabled() ? MF_CHECKED : 0), CMD_TOGGLE_AUTOSTART, tr(L"\u5F00\u673A\u81EA\u52A8\u542F\u52A8", L"Launch at Startup"));
    if (app.isElevated) {
        AppendMenuW(menu, MF_STRING | MF_GRAYED, 0,
            tr(L"\u2713 \u5DF2\u4EE5\u7BA1\u7406\u5458\u8EAB\u4EFD\u8FD0\u884C\uFF08WPS / \u7BA1\u7406\u5458\u6743\u9650\u6E38\u620F\u7684\u952E\u76D8\u90FD\u80FD\u76D1\u542C\uFF09",
               L"\u2713 Running as Administrator (captures keys in WPS / admin games)"));
    } else {
        AppendMenuW(menu, MF_STRING, CMD_RELAUNCH_ADMIN,
            tr(L"\u4EE5\u7BA1\u7406\u5458\u8EAB\u4EFD\u91CD\u65B0\u542F\u52A8\uFF08WPS / \u6E38\u620F\u91CC\u952E\u76D8\u6CA1\u53CD\u5E94\u65F6\u70B9\u8FD9\u91CC\uFF09",
               L"Restart as Administrator (fix no keyboard input in WPS / games)"));
    }
    AppendMenuW(menu, MF_STRING | (app.settings.runAsAdmin ? MF_CHECKED : 0), CMD_TOGGLE_RUN_AS_ADMIN, tr(L"\u6BCF\u6B21\u542F\u52A8\u90FD\u4EE5\u7BA1\u7406\u5458\u8EAB\u4EFD\u8FD0\u884C", L"Always Run as Administrator"));
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);

    AppendMenuW(menu, MF_STRING | (app.settings.showKeyBadges ? MF_CHECKED : 0), CMD_TOGGLE_BADGES, tr(L"\u663E\u793A\u6309\u952E\u6C14\u6CE1 ([S] [W] [\u21E7])", L"Show Key & Click Badges"));
    AppendMenuW(menu, MF_STRING | (app.settings.showKeyLegends ? MF_CHECKED : 0), CMD_TOGGLE_KEY_LEGENDS, tr(L"\u663E\u793A\u952E\u76D8\u5B57\u7B26", L"Show Keycap Legends"));
    AppendMenuW(menu, MF_STRING | (app.settings.keyboardMarquee ? MF_CHECKED : 0), CMD_TOGGLE_MARQUEE, tr(L"\u952E\u76D8\u8DD1\u9A6C\u706F\u6D41\u5149", L"Keyboard RGB Marquee"));

    AppendMenuW(menu, MF_STRING | (app.settings.showPaws ? MF_CHECKED : 0), CMD_TOGGLE_PAWS,
        tr(L"显示悬浮小爪", L"Show Floating Paws"));

    // OBS Live Capture Mode submenu
    HMENU obsMenu = CreatePopupMenu();
    AppendMenuW(obsMenu, MF_STRING | (app.settings.obsCaptureMode == 0 ? MF_CHECKED : 0), CMD_OBS_OFF, tr(L"\u5173\u95ED\uFF08\u6B63\u5E38\u684C\u9762\u60AC\u6D6E\uFF09", L"Off (Normal Overlay)"));
    AppendMenuW(obsMenu, MF_STRING | (app.settings.obsCaptureMode == 1 ? MF_CHECKED : 0), CMD_OBS_TRANSPARENT, tr(L"OBS \u900F\u660E\u7A97\u53E3\u6355\u83B7", L"OBS Transparent Window Capture"));
    AppendMenuW(obsMenu, MF_STRING | (app.settings.obsCaptureMode == 2 ? MF_CHECKED : 0), CMD_OBS_GREENSCREEN, tr(L"OBS \u7EFF\u5E55\u6A21\u5F0F (#00FF00)", L"OBS Green Screen (#00FF00)"));
    AppendMenuW(obsMenu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(obsMenu, MF_STRING | (app.settings.obsHideDesktop ? MF_CHECKED : 0) | (app.settings.obsCaptureMode == 0 ? MF_GRAYED : 0),
        CMD_TOGGLE_OBS_HIDE, tr(L"\u540E\u53F0\u6355\u83B7\uFF08\u9690\u85CF\u684C\u9762\u5C0F\u732B\uFF0COBS\u4ECD\u6B63\u5E38\u6355\u83B7\uFF09", L"Background Capture (Hide on Desktop)"));
    AppendMenuW(menu, MF_POPUP, (UINT_PTR)obsMenu, tr(L"\U0001F4FA \u76F4\u64AD\u6355\u83B7\u6A21\u5F0F (OBS)", L"\U0001F4FA OBS Live Capture Mode"));
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);

    // Interactive resize & flip mode (replaces static scale submenu; also triggered by double-clicking cat)
    AppendMenuW(menu, MF_STRING | (app.settings.isEditMode ? MF_CHECKED : 0), CMD_TOGGLE_EDIT,
        app.settings.isEditMode
            ? tr(L"\u2713 \u5B8C\u6210\u8C03\u6574\u5927\u5C0F\u4E0E\u65B9\u5411", L"\u2713 Finish Resize & Flip")
            : tr(L"\u8C03\u6574\u5927\u5C0F\u4E0E\u65B9\u5411 (\u53CC\u51FB\u5C0F\u732B)", L"Resize & Flip (Double-Click Cat)"));

    // Keyboard Theme submenu
    HMENU kbMenu = CreatePopupMenu();
    AppendMenuW(kbMenu, MF_STRING | (app.settings.keyboardTheme == KeyboardTheme::ClassicMilk ? MF_CHECKED : 0), CMD_KB_MILK, tr(L"\u7ECF\u5178\u5976\u767D\u6696\u9EC4 (\u539F\u7248)", L"Classic Milk White"));
    AppendMenuW(kbMenu, MF_STRING | (app.settings.keyboardTheme == KeyboardTheme::MidnightHacker ? MF_CHECKED : 0), CMD_KB_HACKER, tr(L"\u6697\u591C\u6781\u5BA2\u9ED1", L"Midnight Hacker Black"));
    AppendMenuW(kbMenu, MF_STRING | (app.settings.keyboardTheme == KeyboardTheme::RetroCream ? MF_CHECKED : 0), CMD_KB_RETRO, tr(L"\u590D\u53E4\u5976\u6CB9\u7070", L"Retro Cream Gray"));
    AppendMenuW(menu, MF_POPUP, (UINT_PTR)kbMenu, tr(L"\u952E\u76D8\u914D\u8272", L"Keyboard Theme"));

    // Drawing Tablet & Stylus submenu
    HMENU tabMenu = CreatePopupMenu();
    AppendMenuW(tabMenu, MF_STRING | (app.settings.tabletMode == 0 ? MF_CHECKED : 0), CMD_TABLET_AUTO, tr(L"\u81EA\u52A8\u68C0\u6D4B\uFF08\u8FDE\u63A5\u6570\u4F4D\u677F\u65F6\u81EA\u52A8\u5207\u6362\uFF09", L"Auto-Detect (Switch When Connected)"));
    AppendMenuW(tabMenu, MF_STRING | (app.settings.tabletMode == 1 ? MF_CHECKED : 0), CMD_TABLET_ON,   tr(L"\u59CB\u7EC8\u663E\u793A\u6570\u4F4D\u677F\u4E0E\u89E6\u63A7\u7B14", L"Always Show Tablet & Stylus"));
    AppendMenuW(tabMenu, MF_STRING | (app.settings.tabletMode == 2 ? MF_CHECKED : 0), CMD_TABLET_OFF,  tr(L"\u59CB\u7EC8\u663E\u793A\u9F20\u6807", L"Always Show Mouse"));
    AppendMenuW(menu, MF_POPUP, (UINT_PTR)tabMenu, tr(L"\U0001F3A8 \u6570\u4F4D\u677F\u4E0E\u89E6\u63A7\u7B14", L"\U0001F3A8 Drawing Tablet & Stylus"));

    // Language submenu
    HMENU langMenu = CreatePopupMenu();
    AppendMenuW(langMenu, MF_STRING | (!app.settings.isEnglish ? MF_CHECKED : 0), CMD_LANG_ZH, L"\u7B80\u4F53\u4E2D\u6587");
    AppendMenuW(langMenu, MF_STRING | (app.settings.isEnglish ? MF_CHECKED : 0), CMD_LANG_EN, L"English");
    AppendMenuW(menu, MF_POPUP, (UINT_PTR)langMenu, L"\U0001F310 \u8BED\u8A00 / Language");

    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, CMD_SKINS, tr(L"皮肤", L"Skins"));
    AppendMenuW(menu, MF_STRING, CMD_CHECK_UPDATES, tr(L"检查更新…", L"Check for Updates…"));
    AppendMenuW(menu, MF_STRING, CMD_QUIT, tr(L"退出桌宠小黑", L"Quit OmniBox Pet"));

    HWND menuOwner = app.menuOwnerHwnd ? app.menuOwnerHwnd : app.hwnd;
    SetForegroundWindow(menuOwner);
    UINT cmd = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, screenPt.x, screenPt.y, 0, menuOwner, nullptr);
    PostMessageW(menuOwner, WM_NULL, 0, 0);
    DestroyMenu(menu);

    switch (cmd) {
        case CMD_TOGGLE_VISIBLE:
            app.isVisible = !app.isVisible;
            app.hiddenByFullscreen = false;
            ShowWindow(app.hwnd, app.isVisible ? SW_SHOWNOACTIVATE : SW_HIDE);
            break;
        case CMD_TOGGLE_CLICKTHROUGH:
            app.settings.fullClickThrough = !app.settings.fullClickThrough;
            app.settings.saveToRegistry();
            if (app.settings.fullClickThrough) {
                showTrayBalloon(app,
                    L"XiaoheiPet \u5DF2\u5F00\u542F\u5B8C\u5168\u9F20\u6807\u7A7F\u900F",
                    L"\u53D6\u6D88\u65B9\u5F0F\uFF1A\u6309 Ctrl+Alt+Shift+P\uFF0C\u6216\u6309\u4F4F Alt \u952E\u53F3\u952E\u5C0F\u732B\uFF0C\u6216\u70B9\u53F3\u4E0B\u89D2\u6258\u76D8\u5C0F\u732B\u56FE\u6807\uFF0C\u6216\u518D\u6B21\u53CC\u51FB XiaoheiPet.exe");
            }
            break;
        case CMD_TOGGLE_TOPMOST:
            app.settings.alwaysOnTop = !app.settings.alwaysOnTop;
            applyWindowScaleAndPosition(app, false);
            break;
        case CMD_TOGGLE_AUTOHIDE_FS:
            app.settings.autoHideFullscreen = !app.settings.autoHideFullscreen;
            app.settings.saveToRegistry();
            if (!app.settings.autoHideFullscreen && app.hiddenByFullscreen) {
                app.hiddenByFullscreen = false;
                if (app.isVisible) {
                    ShowWindow(app.hwnd, SW_SHOWNOACTIVATE);
                    assertTopmost(app);
                }
            }
            app.nextHousekeepingTime = 0.0;
            break;
        case CMD_TOGGLE_AUTOSTART:
            setAutoStartEnabled(!isAutoStartEnabled());
            break;
        case CMD_TOGGLE_PAWS:
            app.settings.showPaws = !app.settings.showPaws;
            app.settings.saveToRegistry();
            break;
        case CMD_TOGGLE_BADGES:
            app.settings.showKeyBadges = !app.settings.showKeyBadges;
            app.settings.saveToRegistry();
            break;
        case CMD_TOGGLE_MOUSE_BADGES:
            app.settings.showMouseBadges = !app.settings.showMouseBadges;
            app.settings.saveToRegistry();
            break;
        case CMD_TOGGLE_KEY_LEGENDS:
            app.settings.showKeyLegends = !app.settings.showKeyLegends;
            app.settings.saveToRegistry();
            break;
        case CMD_TOGGLE_FOOT:
            app.settings.footEasterEgg = !app.settings.footEasterEgg;
            app.settings.saveToRegistry();
            break;
        case CMD_TOGGLE_TAIL:
            app.settings.tailEasterEgg = !app.settings.tailEasterEgg;
            app.settings.saveToRegistry();
            break;
        case CMD_TOGGLE_MARQUEE:
            app.settings.keyboardMarquee = !app.settings.keyboardMarquee;
            app.settings.saveToRegistry();
            break;
        case CMD_TOGGLE_PET:
            app.settings.petInteraction = !app.settings.petInteraction;
            app.settings.saveToRegistry();
            break;
        case CMD_OBS_OFF:
            app.settings.obsCaptureMode = 0;
            app.settings.obsHideDesktop = false;
            app.settings.saveToRegistry();
            applyOBSMode(app);
            break;
        case CMD_OBS_TRANSPARENT:
            app.settings.obsCaptureMode = 1;
            app.settings.saveToRegistry();
            applyOBSMode(app);
            break;
        case CMD_OBS_GREENSCREEN:
            app.settings.obsCaptureMode = 2;
            app.settings.saveToRegistry();
            applyOBSMode(app);
            break;
        case CMD_TOGGLE_OBS_HIDE:
            app.settings.obsHideDesktop = !app.settings.obsHideDesktop;
            app.settings.saveToRegistry();
            applyOBSMode(app);
            break;
        case CMD_TOGGLE_EDIT:
            app.settings.isEditMode = !app.settings.isEditMode;
            break;
        case CMD_LANG_ZH:
            app.settings.isEnglish = false;
            app.settings.saveToRegistry();
            break;
        case CMD_LANG_EN:
            app.settings.isEnglish = true;
            app.settings.saveToRegistry();
            break;
        case CMD_TABLET_AUTO:
            app.settings.tabletMode = 0;
            app.settings.saveToRegistry();
            break;
        case CMD_TABLET_ON:
            app.settings.tabletMode = 1;
            app.settings.saveToRegistry();
            break;
        case CMD_TABLET_OFF:
            app.settings.tabletMode = 2;
            app.settings.saveToRegistry();
            break;
        case CMD_KB_MILK:   app.settings.keyboardTheme = KeyboardTheme::ClassicMilk; app.settings.saveToRegistry(); break;
        case CMD_KB_HACKER: app.settings.keyboardTheme = KeyboardTheme::MidnightHacker; app.settings.saveToRegistry(); break;
        case CMD_KB_RETRO:  app.settings.keyboardTheme = KeyboardTheme::RetroCream; app.settings.saveToRegistry(); break;
        case CMD_SCALE_65:  app.settings.scale = 0.65f; applyWindowScaleAndPosition(app, true); break;
        case CMD_SCALE_85:  app.settings.scale = 0.85f; applyWindowScaleAndPosition(app, true); break;
        case CMD_SCALE_100: app.settings.scale = 1.00f; applyWindowScaleAndPosition(app, true); break;
        case CMD_SCALE_125: app.settings.scale = 1.25f; applyWindowScaleAndPosition(app, true); break;
        case CMD_SCALE_150: app.settings.scale = 1.50f; applyWindowScaleAndPosition(app, true); break;
        case CMD_DEMO_BURST:
            app.demoActive = true;
            app.demoStartTime = nowSeconds();
            app.demoStepIdx = 0;
            break;
        case CMD_RESET_POS:
            app.settings.posX = -99999;
            app.settings.posY = -99999;
            applyWindowScaleAndPosition(app, false);
            break;
        case CMD_RELAUNCH_ADMIN:
            // The elevated copy starts with --takeover and waits for this one to exit.
            if (relaunchSelfElevated(L"--takeover --no-elevate")) quitApp(app);
            break;
        case CMD_TOGGLE_RUN_AS_ADMIN:
            app.settings.runAsAdmin = !app.settings.runAsAdmin;
            app.settings.saveToRegistry();
            if (app.settings.runAsAdmin && !app.isElevated && relaunchSelfElevated(L"--takeover --no-elevate")) {
                quitApp(app);
            }
            break;
        case CMD_SKINS:
            MessageBoxW(menuOwner, tr(L"小黑现在使用默认造型。衣服、帽子和首饰上线后，可以在这里换装。",
                                      L"Xiaohei’s default look is active. Clothes, hats, and accessories will appear here when available."),
                        tr(L"皮肤", L"Skins"), MB_OK | MB_ICONINFORMATION);
            break;
        case CMD_CHECK_UPDATES:
            startUpdateCheck(app, true);
            break;
        case CMD_QUIT:
            quitApp(app);
            break;
    }
}

bool physicsLooksSane(const CatPhysics& p) {
    const float vals[] = {
        p.leftPaw.x.value, p.leftPaw.y.value, p.rightPaw.x.value, p.rightPaw.y.value,
        p.hindFoot.x.value, p.hindFoot.y.value, p.bodyShiftX.value, p.bodyTilt.value,
        p.bodySquash.value, p.headTilt.value, p.headYaw.value, p.headPitch.value,
        p.headOffsetY.value, p.eyeGaze.x.value, p.eyeGaze.y.value, p.pupilScale.value,
        p.huntIntensity.value, p.mouseOffset.x.value, p.mouseOffset.y.value, p.time
    };
    for (float v : vals) {
        if (!std::isfinite(v) || std::fabs(v) > 1.0e6f) return false;
    }
    return true;
}

void tickAndRender(AppState& app) {
    if (!app.isVisible || app.hiddenByFullscreen || !app.hwnd) return;

    double now = nowSeconds();
    app.lastRenderTime = now;
    float dt = (float)(now - app.lastTickTime);
    app.lastTickTime = now;
    if (dt <= 0.0f || dt > 0.2f) dt = 1.0f / 60.0f;

    // Optional menu demo typing burst
    if (app.demoActive) {
        static const PhysicalKey demoKeys[] = {
            PhysicalKey::W, PhysicalKey::A, PhysicalKey::S, PhysicalKey::D,
            PhysicalKey::F, PhysicalKey::J, PhysicalKey::O, PhysicalKey::E,
            PhysicalKey::Space, PhysicalKey::LeftShift
        };
        int targetIdx = (int)((now - app.demoStartTime) / 0.13);
        while (app.demoStepIdx <= targetIdx && app.demoStepIdx < 10) {
            app.physics.triggerKeyDown(demoKeys[app.demoStepIdx], app.settings);
            app.demoStepIdx++;
        }
        if (app.demoStepIdx >= 10) app.demoActive = false;
    }

    RECT wr = {};
    GetWindowRect(app.hwnd, &wr);
    int w = std::max(1, (int)(wr.right - wr.left));
    int h = std::max(1, (int)(wr.bottom - wr.top));

    app.physics.step(dt, wr, app.input, app.settings);
    if (!physicsLooksSane(app.physics)) {
        // A single non-finite value would otherwise make every later frame draw nothing (the cat
        // "vanishes" until restart). Rebuild the pose but keep the session statistics.
        int pets = app.physics.totalPetSessions;
        app.physics = CatPhysics();
        app.physics.totalPetSessions = pets;
    }

    // Smart Click-Through + Petting Detection
    if (!app.isDragging && app.activeResizeCorner < 0) {
        POINT cur = {};
        GetCursorPos(&cur);
        if (PtInRect(&wr, cur)) {
            Pt rawCp = {
                (float)(cur.x - wr.left) / (float)w * CatPhysics::CanvasWidth,
                (float)(cur.y - wr.top)  / (float)h * CatPhysics::CanvasHeight
            };
            if (app.settings.isEditMode) {
                int editHit = CatRenderer::hitTestEditOverlay(rawCp);
                setClickThrough(app.hwnd, editHit < 0);
                app.hasLastHover = false;
            } else {
                Pt cp = app.settings.flipHorizontal ? Pt{ CatPhysics::CanvasWidth - rawCp.x, rawCp.y } : rawCp;
                CatHitZone zone = CatRenderer::hitTest(cp, app.physics);
                if (zone == CatHitZone::Head) {
                    if (app.hasLastHover) {
                        float d = std::hypot(cp.x - app.lastHoverCanvas.x, cp.y - app.lastHoverCanvas.y);
                        if (d > 1.2f && d < 80.0f) {
                            app.physics.registerPetStroke(cp, d, true, app.settings);
                        }
                    }
                    app.lastHoverCanvas = cp;
                    app.hasLastHover = true;
                } else {
                    app.hasLastHover = false;
                }
                // Holding Alt temporarily unlocks click-through so user can ALWAYS right-click or drag the cat!
                bool altHeld = (GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
                bool clickThrough = (app.settings.fullClickThrough && !altHeld) || (zone == CatHitZone::None);
                setClickThrough(app.hwnd, clickThrough);
            }
        } else {
            app.hasLastHover = false;
            setClickThrough(app.hwnd, true);
        }
    }

    if (app.pendingMenuAfterAlt && (GetAsyncKeyState(VK_MENU) & 0x8000) == 0) {
        app.pendingMenuAfterAlt = false;
        POINT pt = app.pendingMenuPt;
        showContextMenu(app, pt);
    }

    // Render 32-bit Premultiplied ARGB frame directly into DIB and present via UpdateLayeredWindow
    app.ensureBuffer(w, h);
    if (!app.memDC || !app.dibBits) return;

    Gdiplus::Bitmap bmp(w, h, w * 4, PixelFormat32bppPARGB, static_cast<BYTE*>(app.dibBits));
    Gdiplus::Graphics g(&bmp);
    g.Clear(app.settings.obsCaptureMode == 2 ? Gdiplus::Color(255, 0, 255, 0) : Gdiplus::Color(0, 0, 0, 0));
    g.ScaleTransform((float)w / CatPhysics::CanvasWidth, (float)h / CatPhysics::CanvasHeight);
    CatRenderer::draw(g, app.physics, app.settings);

    POINT ptDst = { wr.left, wr.top };
    SIZE szWnd = { w, h };
    POINT ptSrc = { 0, 0 };
    BLENDFUNCTION blend = {};
    blend.BlendOp = AC_SRC_OVER;
    blend.SourceConstantAlpha = 255;
    blend.AlphaFormat = AC_SRC_ALPHA;

    HDC screenDC = GetDC(nullptr);
    BOOL presented = UpdateLayeredWindow(app.hwnd, screenDC, &ptDst, &szWnd, app.memDC, &ptSrc, 0, &blend, ULW_ALPHA);
    ReleaseDC(nullptr, screenDC);
    if (presented) {
        app.ulwFailures = 0;
    } else if (++app.ulwFailures > 30) {
        // Surface lost (typically after Win+L / display reconnect): rebuild the DIB next frame.
        app.ulwFailures = 0;
        app.destroyBuffer();
    }
}

/// Renders at most once per FRAME_INTERVAL; called from both the main loop and WM_TIMER (the latter
/// keeps the cat alive while a menu / message box runs its own modal loop).
void renderIfDue(AppState& app) {
    double now = nowSeconds();
    if (now < app.nextFrameTime) return;
    app.nextFrameTime = (now - app.nextFrameTime < FRAME_INTERVAL) ? app.nextFrameTime + FRAME_INTERVAL
                                                                    : now + FRAME_INTERVAL;
    tickAndRender(app);
}

LRESULT CALLBACK wndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    AppState* app = g_app;
    switch (msg) {
        case WM_INPUT:
            if (app) app->input.handleRawInput(lParam);
            return 0;

        case WM_TIMER:
            if (wParam == TIMER_RENDER && app) renderIfDue(*app);
            return 0;

        case WM_WTSSESSION_CHANGE:
            if (app && hwnd == app->hwnd) {
                switch (wParam) {
                    case WTS_SESSION_LOCK:
                    case WTS_CONSOLE_DISCONNECT:
                    case WTS_REMOTE_DISCONNECT:
                        // Win+L: the key-ups for Win and L go to the secure desktop, never to us.
                        app->input.resetAllState();
                        break;
                    case WTS_SESSION_UNLOCK:
                    case WTS_SESSION_LOGON:
                    case WTS_CONSOLE_CONNECT:
                    case WTS_REMOTE_CONNECT:
                        recoverAfterSystemEvent(*app);
                        break;
                    default:
                        break;
                }
            }
            return 0;

        case WM_POWERBROADCAST:
            if (app && hwnd == app->hwnd &&
                (wParam == PBT_APMRESUMEAUTOMATIC || wParam == PBT_APMRESUMESUSPEND)) {
                recoverAfterSystemEvent(*app);
            }
            return TRUE;

        case WM_DISPLAYCHANGE:
            // Fullscreen games often switch resolution; the cat could end up off-screen or with a
            // stale surface. Re-place it (without touching the saved position) and rebuild the buffer.
            if (app && hwnd == app->hwnd) recoverAfterSystemEvent(*app);
            return 0;

        case WM_REQUEST_QUIT:
            if (app) quitApp(*app);
            return 0;

        case WM_SETCURSOR:
            if (LOWORD(lParam) == HTCLIENT) {
                SetCursor(LoadCursorW(nullptr, IDC_HAND));
                return TRUE;
            }
            break;

        case WM_LBUTTONDBLCLK:
            if (app && hwnd == app->hwnd) {
                app->settings.isEditMode = !app->settings.isEditMode;
            }
            return 0;

        case WM_LBUTTONDOWN: {
            bool altHeld = (GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
            if (app && hwnd == app->hwnd && (app->settings.isEditMode || !app->settings.fullClickThrough || altHeld)) {
                RECT wr = {};
                GetWindowRect(hwnd, &wr);
                int w = std::max(1, (int)(wr.right - wr.left));
                int h = std::max(1, (int)(wr.bottom - wr.top));
                POINT cur = {};
                GetCursorPos(&cur);
                if (app->settings.isEditMode) {
                    Pt rawCp = {
                        (float)(cur.x - wr.left) / (float)w * CatPhysics::CanvasWidth,
                        (float)(cur.y - wr.top)  / (float)h * CatPhysics::CanvasHeight
                    };
                    int hit = CatRenderer::hitTestEditOverlay(rawCp);
                    if (hit == 10) {
                        app->settings.flipHorizontal = !app->settings.flipHorizontal;
                        app->settings.saveToRegistry();
                        return 0;
                    }
                    if (hit == 11) {
                        app->settings.isEditMode = false;
                        return 0;
                    }
                    if (hit >= 0 && hit <= 3) {
                        app->activeResizeCorner = hit;
                        // Windows screen Y is top-down: anchor opposite corner
                        if (hit == 0) app->resizeAnchorScreenPt = { wr.right, wr.bottom };
                        else if (hit == 1) app->resizeAnchorScreenPt = { wr.left, wr.bottom };
                        else if (hit == 2) app->resizeAnchorScreenPt = { wr.right, wr.top };
                        else app->resizeAnchorScreenPt = { wr.left, wr.top };
                        SetCapture(hwnd);
                        return 0;
                    }
                }
                app->isDragging = true;
                app->dragStartCursor = cur;
                app->dragStartWinOrigin = { wr.left, wr.top };
                app->physics.setDragging(true, 0.0f);
                SetCapture(hwnd);
            }
            return 0;
        }

        case WM_MOUSEMOVE:
            if (app && app->activeResizeCorner >= 0) {
                POINT cur = {};
                GetCursorPos(&cur);
                float dx = std::fabs((float)(cur.x - app->resizeAnchorScreenPt.x));
                float dy = std::fabs((float)(cur.y - app->resizeAnchorScreenPt.y));
                float newScale = std::clamp(std::max(dx / CatPhysics::CanvasWidth, dy / CatPhysics::CanvasHeight), 0.45f, 2.50f);
                int nw = (int)std::round(CatPhysics::CanvasWidth * newScale);
                int nh = (int)std::round(CatPhysics::CanvasHeight * newScale);
                int nx = (app->activeResizeCorner == 0 || app->activeResizeCorner == 2)
                    ? (app->resizeAnchorScreenPt.x - nw) : app->resizeAnchorScreenPt.x;
                int ny = (app->activeResizeCorner == 0 || app->activeResizeCorner == 1)
                    ? (app->resizeAnchorScreenPt.y - nh) : app->resizeAnchorScreenPt.y;
                app->settings.scale = newScale;
                SetWindowPos(hwnd, nullptr, nx, ny, nw, nh, SWP_NOZORDER | SWP_NOACTIVATE);
                return 0;
            }
            if (app && app->isDragging) {
                POINT cur = {};
                GetCursorPos(&cur);
                RECT wr = {};
                GetWindowRect(hwnd, &wr);
                int nx = app->dragStartWinOrigin.x + (cur.x - app->dragStartCursor.x);
                int ny = app->dragStartWinOrigin.y + (cur.y - app->dragStartCursor.y);
                float stepDx = (float)(nx - wr.left);
                app->physics.setDragging(true, app->settings.flipHorizontal ? -stepDx : stepDx);
                SetWindowPos(hwnd, nullptr, nx, ny, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
            }
            return 0;

        case WM_LBUTTONUP:
            if (app && app->activeResizeCorner >= 0) {
                app->activeResizeCorner = -1;
                ReleaseCapture();
                RECT wr = {};
                GetWindowRect(hwnd, &wr);
                app->settings.posX = wr.left;
                app->settings.posY = wr.top;
                app->settings.saveToRegistry();
                return 0;
            }
            if (app && app->isDragging) {
                app->isDragging = false;
                app->physics.setDragging(false);
                ReleaseCapture();
                RECT wr = {};
                GetWindowRect(hwnd, &wr);
                app->settings.posX = wr.left;
                app->settings.posY = wr.top;
                app->settings.saveToRegistry();
            }
            return 0;

        case WM_RBUTTONDOWN:
            if (app && hwnd == app->hwnd) {
                bool altHeld = (GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
                if (!app->settings.fullClickThrough || altHeld) {
                    app->rButtonDown = true;
                }
            }
            return 0;

        case WM_RBUTTONUP:
            if (app && hwnd == app->hwnd && app->rButtonDown) {
                app->rButtonDown = false;
                POINT pt = {};
                GetCursorPos(&pt);
                if ((GetAsyncKeyState(VK_MENU) & 0x8000) != 0) {
                    // Defer opening the popup menu until Alt is released; otherwise
                    // Windows' TrackPopupMenu modal loop cancels the menu on WM_SYSKEYUP(VK_MENU).
                    app->pendingMenuAfterAlt = true;
                    app->pendingMenuPt = pt;
                } else {
                    showContextMenu(*app, pt);
                }
            }
            return 0;

        case WM_CANCELMODE:
        case WM_CAPTURECHANGED:
            if (app && hwnd == app->hwnd) {
                app->rButtonDown = false;
            }
            return 0;

        case WM_TRAYICON:
            if (app && (lParam == WM_RBUTTONUP || lParam == WM_LBUTTONUP || lParam == WM_CONTEXTMENU)) {
                POINT pt = {};
                GetCursorPos(&pt);
                showContextMenu(*app, pt);
            }
            return 0;

        case WM_HOTKEY:
            if (app && wParam == HOTKEY_CLICKTHROUGH_ID) {
                app->settings.fullClickThrough = !app->settings.fullClickThrough;
                app->settings.saveToRegistry();
                if (app->settings.fullClickThrough) {
                    showTrayBalloon(*app,
                        L"XiaoheiPet \u5DF2\u5F00\u542F\u5B8C\u5168\u9F20\u6807\u7A7F\u900F",
                        L"\u518D\u6B21\u6309 Ctrl+Alt+Shift+P \u6216\u6309\u4F4F Alt \u53F3\u952E\u5C0F\u732B\u5373\u53EF\u53D6\u6D88");
                } else {
                    showTrayBalloon(*app,
                        L"XiaoheiPet \u5DF2\u53D6\u6D88\u5B8C\u5168\u9F20\u6807\u7A7F\u900F",
                        L"\u73B0\u5728\u53EF\u4EE5\u6B63\u5E38\u62D6\u52A8\u3001\u6478\u5934\u548C\u53F3\u952E\u6253\u5F00\u83DC\u5355\u4E86");
                }
            }
            return 0;

        case WM_UPDATE_CHECK_DONE:
            if (app && hwnd == app->hwnd) showUpdateResult(*app, static_cast<UpdateResult>(lParam));
            return 0;

        case WM_WAKE_EXISTING:
            if (app) {
                // Re-launching XiaoheiPet.exe unlocks click-through, restores visibility & opens settings menu!
                if (app->settings.fullClickThrough) {
                    app->settings.fullClickThrough = false;
                    app->settings.saveToRegistry();
                }
                if (!app->isVisible) {
                    app->isVisible = true;
                    ShowWindow(app->hwnd, SW_SHOWNOACTIVATE);
                }
                POINT pt = {};
                GetCursorPos(&pt);
                showContextMenu(*app, pt);
            }
            return 0;

        case WM_DESTROY:
            if (hwnd == (app ? app->hwnd : nullptr)) {
                KillTimer(hwnd, TIMER_RENDER);
                if (app) {
                    if (app->sessionNotifyRegistered) {
                        WTSUnRegisterSessionNotification(hwnd);
                        app->sessionNotifyRegistered = false;
                    }
                    if (app->foregroundHook) {
                        UnhookWinEvent(app->foregroundHook);
                        app->foregroundHook = nullptr;
                    }
                    if (app->menuOwnerHwnd) {
                        UnregisterHotKey(app->menuOwnerHwnd, HOTKEY_CLICKTHROUGH_ID);
                        RemovePropW(app->menuOwnerHwnd, VERSION_PROP);
                        DestroyWindow(app->menuOwnerHwnd);
                        app->menuOwnerHwnd = nullptr;
                    }
                    Shell_NotifyIconW(NIM_DELETE, &app->nid);
                    if (app->trayIcon) DestroyIcon(app->trayIcon);
                    app->destroyBuffer();
                }
                PostQuitMessage(0);
            }
            return 0;
    }
    if (g_msgTaskbarCreated != 0 && msg == g_msgTaskbarCreated && app && hwnd == app->menuOwnerHwnd) {
        registerTrayIcon(*app);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

void CALLBACK onForegroundChanged(HWINEVENTHOOK, DWORD, HWND, LONG, LONG, DWORD, DWORD) {
    // A game just came to the front: many make themselves topmost right after showing, so
    // re-assert our own topmost state shortly afterwards instead of staying buried ("vanished").
    if (g_app) g_app->pendingTopmostTime = nowSeconds() + 0.4;
}

/// Asks the already-running XiaoheiPet to exit and waits for it. Builds <= 1.3.2 do not know
/// WM_REQUEST_QUIT, but they shut down cleanly when their overlay window receives WM_CLOSE.
bool shutDownRunningInstance(HWND owner, DWORD timeoutMs) {
    DWORD pid = 0;
    if (owner) GetWindowThreadProcessId(owner, &pid);
    HANDLE hProc = pid ? OpenProcess(SYNCHRONIZE, FALSE, pid) : nullptr;
    if (owner) PostMessageW(owner, WM_REQUEST_QUIT, 0, 0);
    if (HWND overlay = FindWindowW(OVERLAY_CLASS, nullptr)) PostMessageW(overlay, WM_CLOSE, 0, 0);
    bool gone = false;
    if (hProc) {
        gone = (WaitForSingleObject(hProc, timeoutMs) == WAIT_OBJECT_0);
        CloseHandle(hProc);
    } else {
        for (DWORD waited = 0; waited <= timeoutMs; waited += 100) {
            if (!FindWindowW(TRAY_OWNER_CLASS, nullptr) && !FindWindowW(OVERLAY_CLASS, nullptr)) { gone = true; break; }
            Sleep(100);
        }
    }
    return gone;
}

} // namespace

int WINAPI wWinMain(HINSTANCE hInst, HINSTANCE, PWSTR, int) {
    // Enable best available DPI awareness (Per-Monitor V2 on Win10/11, Per-Monitor on Win8.1, System DPI on Win7)
    enableBestDpiAwareness();

    const int myVersion = versionToNumber(APP_VERSION);
    const bool forceTakeover = commandLineHasFlag(L"--takeover");   // admin relaunch
    const bool noElevate = commandLineHasFlag(L"--no-elevate");
    const wchar_t* kMutexName = L"Local\\XiaoheiPetDesktopPetSingleInstance";

    // Single-instance guard. Re-launching the SAME version wakes the existing cat (cancels full
    // click-through and pops the menu so users never get stuck). Launching a NEWER version (e.g. a
    // freshly downloaded exe while the old one still sits in the tray or autostarts from another
    // folder) now replaces the old process instead of silently waking it — previously the old
    // version kept running and kept reporting "new version available".
    HANDLE hMutex = CreateMutexW(nullptr, FALSE, kMutexName);
    DWORD mutexErr = GetLastError();
    bool alreadyRunning = (hMutex && mutexErr == ERROR_ALREADY_EXISTS) || (!hMutex && mutexErr == ERROR_ACCESS_DENIED);
    if (alreadyRunning) {
        HWND owner = FindWindowW(TRAY_OWNER_CLASS, nullptr);
        if (!owner && forceTakeover) {
            // The instance we replace is already shutting down; give it a moment to disappear.
            for (int i = 0; i < 50 && FindWindowW(OVERLAY_CLASS, nullptr); ++i) Sleep(100);
        } else if (!owner) {
            if (hMutex) CloseHandle(hMutex);
            return 0;
        }
        if (owner) {
            int runningVersion = (int)(INT_PTR)GetPropW(owner, VERSION_PROP);
            bool replace = forceTakeover || runningVersion < myVersion;
            if (!replace || !shutDownRunningInstance(owner, 6000)) {
                PostMessageW(owner, WM_WAKE_EXISTING, 0, 0);
                if (hMutex) CloseHandle(hMutex);
                return 0;
            }
        }
        if (!hMutex) hMutex = CreateMutexW(nullptr, FALSE, kMutexName);
    }

    AppState app;
    g_app = &app;
    app.settings.loadFromRegistry();
    app.isElevated = isCurrentProcessElevated();

    // "Always run as administrator": hand over to an elevated copy (one UAC prompt). If the user
    // declines, simply carry on non-elevated.
    if (app.settings.runAsAdmin && !app.isElevated && !noElevate) {
        if (hMutex) { CloseHandle(hMutex); hMutex = nullptr; }
        if (relaunchSelfElevated(L"--takeover --no-elevate")) {
            g_app = nullptr;
            return 0;
        }
        hMutex = CreateMutexW(nullptr, FALSE, kMutexName);
    }

    g_msgTaskbarCreated = RegisterWindowMessageW(L"TaskbarCreated");

    Gdiplus::GdiplusStartupInput gdipInput;
    ULONG_PTR gdipToken = 0;
    Gdiplus::GdiplusStartup(&gdipToken, &gdipInput, nullptr);

    // Refresh auto-start exe path if user enabled auto-start and moved XiaoheiPet.exe
    if (isAutoStartEnabled()) {
        setAutoStartEnabled(true);
    }

    app.input.onKeyDown = [&](PhysicalKey k) { app.physics.triggerKeyDown(k, app.settings); };
    app.input.onMouseClick = [&](int btn, bool down) { app.physics.triggerMouseClick(btn, down, app.settings); };

    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.style = CS_DBLCLKS;
    wc.lpfnWndProc = wndProc;
    wc.hInstance = hInst;
    wc.lpszClassName = OVERLAY_CLASS;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    RegisterClassExW(&wc);

    // Dedicated hidden tray/menu owner window (NO WS_EX_NOACTIVATE / WS_EX_TRANSPARENT)
    WNDCLASSEXW trayWc = {};
    trayWc.cbSize = sizeof(trayWc);
    trayWc.lpfnWndProc = wndProc;
    trayWc.hInstance = hInst;
    trayWc.lpszClassName = TRAY_OWNER_CLASS;
    RegisterClassExW(&trayWc);

    app.menuOwnerHwnd = CreateWindowExW(
        WS_EX_TOOLWINDOW,
        trayWc.lpszClassName,
        L"XiaoheiPetTray",
        WS_POPUP,
        0, 0, 0, 0,
        nullptr, nullptr, hInst, nullptr
    );
    if (app.menuOwnerHwnd) {
        SetPropW(app.menuOwnerHwnd, VERSION_PROP, (HANDLE)(INT_PTR)myVersion);
        // When elevated, UIPI would drop messages from the (non-elevated) taskbar and from a
        // re-launched XiaoheiPet. Explicitly allow the few messages we rely on.
        const UINT allowed[] = { WM_TRAYICON, WM_WAKE_EXISTING, WM_REQUEST_QUIT };
        for (UINT m : allowed) ChangeWindowMessageFilterEx(app.menuOwnerHwnd, m, MSGFLT_ALLOW, nullptr);
        if (g_msgTaskbarCreated) ChangeWindowMessageFilterEx(app.menuOwnerHwnd, g_msgTaskbarCreated, MSGFLT_ALLOW, nullptr);
    }

    int initW = (int)std::round(CatPhysics::CanvasWidth * app.settings.scale);
    int initH = (int)std::round(CatPhysics::CanvasHeight * app.settings.scale);
    int initX = 0, initY = 0;
    if (app.settings.posX != -99999 && app.settings.posY != -99999) {
        initX = app.settings.posX; initY = app.settings.posY;
    } else {
        computeDefaultOrigin(initW, initH, initX, initY);
    }

    DWORD exStyle = WS_EX_LAYERED | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT
                  | (app.settings.obsCaptureMode == 0 ? WS_EX_TOOLWINDOW : 0)
                  | (app.settings.alwaysOnTop ? WS_EX_TOPMOST : 0);

    app.hwnd = CreateWindowExW(
        exStyle,
        wc.lpszClassName,
        L"XiaoheiPet",
        WS_POPUP,
        initX, initY, initW, initH,
        nullptr, nullptr, hInst, nullptr
    );
    if (!app.hwnd) {
        if (app.menuOwnerHwnd) DestroyWindow(app.menuOwnerHwnd);
        Gdiplus::GdiplusShutdown(gdipToken);
        if (hMutex) CloseHandle(hMutex);
        return 1;
    }

    applyWindowScaleAndPosition(app, false);
    app.input.registerRawInput(app.hwnd);
    app.input.installKeyboardHook();
    if (app.settings.obsCaptureMode > 0 && app.settings.obsHideDesktop) {
        applyOBSMode(app);
    }
    registerTrayIcon(app);

    // Win+L / fast-user-switch notifications (see recoverAfterSystemEvent)
    app.sessionNotifyRegistered = WTSRegisterSessionNotification(app.hwnd, NOTIFY_FOR_THIS_SESSION) != FALSE;
    // Foreground changes (games launching) -> re-assert topmost
    app.foregroundHook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, nullptr,
                                         onForegroundChanged, 0, 0, WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);

    // Global shortcut Ctrl+Alt+Shift+P to toggle full click-through anytime!
    if (app.menuOwnerHwnd) {
        RegisterHotKey(app.menuOwnerHwnd, HOTKEY_CLICKTHROUGH_ID, MOD_CONTROL | MOD_ALT | MOD_SHIFT | MOD_NOREPEAT, 'P');
    }

    ShowWindow(app.hwnd, SW_SHOWNOACTIVATE);
    app.lastTickTime = nowSeconds();
    tickAndRender(app);
    if (!commandLineHasFlag(L"--no-update-check")) startUpdateCheck(app, false);
    app.nextFrameTime = nowSeconds() + FRAME_INTERVAL;
    SetTimer(app.hwnd, TIMER_RENDER, 16, nullptr);

    // Frame loop. WM_TIMER is only generated when the queue is empty, so a 1000-8000 Hz gaming mouse
    // (one WM_INPUT per report) could starve it and freeze the cat. Here frames are driven by time:
    // drain messages for at most ~10 ms, then render if a frame is due. WM_TIMER still calls
    // renderIfDue() so the cat keeps animating inside menus / message boxes (their own modal loops).
    MSG msg = {};
    int exitCode = 0;
    bool running = true;
    while (running) {
        double now = nowSeconds();
        double waitSec = (app.isVisible && !app.hiddenByFullscreen) ? (app.nextFrameTime - now) : 0.25;
        if (waitSec > 0.0) {
            MsgWaitForMultipleObjectsEx(0, nullptr, (DWORD)(waitSec * 1000.0), QS_ALLINPUT, MWMO_INPUTAVAILABLE);
        }
        double drainUntil = nowSeconds() + 0.010;
        while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) {
                running = false;
                exitCode = (int)msg.wParam;
                break;
            }
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
            if (nowSeconds() > drainUntil) break;
        }
        if (!running) break;
        renderIfDue(app);
        housekeeping(app);
    }

    g_app = nullptr;
    Gdiplus::GdiplusShutdown(gdipToken);
    if (hMutex) CloseHandle(hMutex);
    return exitCode;
}
