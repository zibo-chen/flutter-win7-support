// Copyright 2026 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license in LICENSE.
#ifndef FLUTTER_SHELL_PLATFORM_WINDOWS_WIN7_TOUCH_INPUT_H_
#define FLUTTER_SHELL_PLATFORM_WINDOWS_WIN7_TOUCH_INPUT_H_

#include <windows.h>

#include <functional>
#include <utility>
#include <vector>

namespace flutter {

// Injectable Win32 calls keep legacy routing and handle ownership testable
// without manufacturing an OS-owned HTOUCHINPUT.
struct Win7TouchApi {
  std::function<bool()> supports_pointer = []() {
    return ::GetProcAddress(::GetModuleHandleW(L"user32.dll"),
                            "GetPointerInfo") != nullptr;
  };
  std::function<BOOL(HWND, ULONG)> register_window = ::RegisterTouchWindow;
  std::function<BOOL(HWND)> unregister_window = ::UnregisterTouchWindow;
  std::function<BOOL(HTOUCHINPUT, UINT, PTOUCHINPUT, int)> read =
      ::GetTouchInputInfo;
  std::function<BOOL(HTOUCHINPUT)> close = ::CloseTouchInputHandle;
  std::function<BOOL(HWND, POINT*)> screen_to_client = ::ScreenToClient;
};

// WM_POINTER requires Windows 8. Windows 7 needs WM_TOUCH, while Windows'
// promoted mouse messages must be suppressed only when another path handles
// the contacts, otherwise even single-finger taps are lost.
class Win7TouchInput {
 public:
  enum class Action { kDown, kMove, kUp };
  struct Contact {
    Action action;
    DWORD id;
    double x;
    double y;
  };

  explicit Win7TouchInput(Win7TouchApi api = {}) : api_(std::move(api)) {}
  ~Win7TouchInput() { Reset(); }
  Win7TouchInput(const Win7TouchInput&) = delete;
  Win7TouchInput& operator=(const Win7TouchInput&) = delete;

  void Initialize(HWND window) {
    Reset();
    if (!window) {
      return;
    }
    window_ = window;
    supports_pointer_ = api_.supports_pointer();
    if (!supports_pointer_) {
      registered_ = api_.register_window(window_, 0) != FALSE;
    }
  }

  void Reset() {
    if (registered_) {
      api_.unregister_window(window_);
    }
    registered_ = false;
    window_ = nullptr;
    supports_pointer_ = true;
  }

  bool FiltersPromotedMouse() const { return supports_pointer_ || registered_; }

  bool Handle(WPARAM wparam,
              LPARAM lparam,
              const std::function<void(const Contact&)>& dispatch) {
    if (!registered_) {
      // The caller must let DefWindowProc own the unhandled touch handle.
      return false;
    }
    const auto handle = reinterpret_cast<HTOUCHINPUT>(lparam);
    struct HandleCloser {
      Win7TouchApi& api;
      HTOUCHINPUT handle;
      ~HandleCloser() { api.close(handle); }
    } closer{api_, handle};
    const UINT count = LOWORD(wparam);
    // A malformed message must not cause an unbounded allocation.
    if (count == 0 || count > 256) {
      return true;
    }
    std::vector<TOUCHINPUT> points(count);
    if (!api_.read(handle, count, points.data(), sizeof(TOUCHINPUT))) {
      return true;
    }
    POINT origin{0, 0};
    if (!api_.screen_to_client(window_, &origin)) {
      return true;
    }
    for (const auto& point : points) {
      const DWORD flags = point.dwFlags & (TOUCHEVENTF_DOWN | TOUCHEVENTF_MOVE |
                                           TOUCHEVENTF_UP);
      Action action;
      if (flags == TOUCHEVENTF_DOWN) {
        action = Action::kDown;
      } else if (flags == TOUCHEVENTF_MOVE) {
        action = Action::kMove;
      } else if (flags == TOUCHEVENTF_UP) {
        action = Action::kUp;
      } else {
        continue;
      }
      // WM_TOUCH uses signed screen coordinates in hundredths of a physical
      // pixel. Preserve fractional and negative coordinates.
      dispatch({action, point.dwID, point.x / 100.0 + origin.x,
                point.y / 100.0 + origin.y});
    }
    return true;
  }

 private:
  Win7TouchApi api_;
  HWND window_ = nullptr;
  bool supports_pointer_ = true;
  bool registered_ = false;
};

}  // namespace flutter

#endif  // FLUTTER_SHELL_PLATFORM_WINDOWS_WIN7_TOUCH_INPUT_H_
