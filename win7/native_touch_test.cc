// Copyright 2026 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license in LICENSE.
#include "flutter/shell/platform/windows/win7_touch_input.h"

#include <algorithm>
#include <cassert>
#include <cmath>
#include <iostream>
#include <memory>
#include <vector>

namespace {
using flutter::Win7TouchApi;
using flutter::Win7TouchInput;

struct Fixture {
  bool modern = false;
  bool register_ok = true;
  bool read_ok = true;
  bool coordinates_ok = true;
  int registered = 0;
  int unregistered = 0;
  int reads = 0;
  int closed = 0;
  HWND window = reinterpret_cast<HWND>(0x1234);
  HTOUCHINPUT handle = reinterpret_cast<HTOUCHINPUT>(0x5678);
  std::vector<TOUCHINPUT> points;
  std::vector<Win7TouchInput::Contact> events;
  std::unique_ptr<Win7TouchInput> input;

  Fixture() {
    Win7TouchApi api;
    api.supports_pointer = [this]() { return modern; };
    api.register_window = [this](HWND hwnd, ULONG flags) -> BOOL {
      assert(hwnd == window && flags == 0);
      ++registered;
      return register_ok;
    };
    api.unregister_window = [this](HWND hwnd) -> BOOL {
      assert(hwnd == window);
      ++unregistered;
      return TRUE;
    };
    api.read = [this](HTOUCHINPUT h, UINT count, PTOUCHINPUT data,
                      int size) -> BOOL {
      assert(h == handle && count == points.size());
      assert(size == sizeof(TOUCHINPUT));
      ++reads;
      if (!read_ok)
        return FALSE;
      std::copy(points.begin(), points.end(), data);
      return TRUE;
    };
    api.close = [this](HTOUCHINPUT h) -> BOOL {
      assert(h == handle);
      ++closed;
      return TRUE;
    };
    api.screen_to_client = [this](HWND hwnd, POINT *origin) -> BOOL {
      assert(hwnd == window && origin->x == 0 && origin->y == 0);
      origin->x = -100;
      origin->y = -200;
      return coordinates_ok;
    };
    input = std::make_unique<Win7TouchInput>(std::move(api));
  }

  bool Dispatch(UINT count) {
    return input->Handle(count, reinterpret_cast<LPARAM>(handle),
                         [this](const Win7TouchInput::Contact &event) {
                           events.push_back(event);
                         });
  }
};

TOUCHINPUT Point(DWORD id, DWORD flags, LONG x = 10550, LONG y = 21025) {
  TOUCHINPUT point{};
  point.dwID = id;
  point.dwFlags = flags;
  point.x = x;
  point.y = y;
  return point;
}
} // namespace

int main() {
  {
    Fixture f;
    f.modern = true;
    f.input->Initialize(f.window);
    assert(f.registered == 0);
    assert(f.input->FiltersPromotedMouse());
    assert(!f.Dispatch(1));
    assert(f.reads == 0 && f.closed == 0);
  }
  {
    Fixture f;
    f.input->Initialize(f.window);
    assert(f.registered == 1 && f.input->FiltersPromotedMouse());
    f.points = {Point(7, TOUCHEVENTF_DOWN | TOUCHEVENTF_PRIMARY),
                Point(8, TOUCHEVENTF_DOWN, -2050, 19800)};
    assert(f.Dispatch(2));
    assert(f.events.size() == 2 && f.closed == 1);
    assert(f.events[0].id == 7 && f.events[1].id == 8);
    assert(f.events[0].action == Win7TouchInput::Action::kDown);
    assert(std::abs(f.events[0].x - 5.5) < 0.001);
    assert(std::abs(f.events[0].y - 10.25) < 0.001);
    assert(std::abs(f.events[1].x + 120.5) < 0.001);
    f.points = {Point(7, TOUCHEVENTF_MOVE), Point(8, TOUCHEVENTF_UP)};
    assert(f.Dispatch(2));
    assert(f.events[2].action == Win7TouchInput::Action::kMove);
    assert(f.events[3].action == Win7TouchInput::Action::kUp);
    assert(f.closed == 2);
    f.input->Reset();
    f.input->Reset();
    assert(f.unregistered == 1);
  }
  {
    Fixture f;
    f.register_ok = false;
    f.input->Initialize(f.window);
    assert(!f.input->FiltersPromotedMouse());
    assert(!f.Dispatch(1));
    assert(f.closed == 0);
  }
  {
    Fixture f;
    f.input->Initialize(f.window);
    f.read_ok = false;
    f.points = {Point(1, TOUCHEVENTF_DOWN)};
    assert(f.Dispatch(1));
    assert(f.closed == 1 && f.events.empty());
    f.read_ok = true;
    f.coordinates_ok = false;
    assert(f.Dispatch(1));
    assert(f.closed == 2 && f.events.empty());
  }
  {
    Fixture f;
    f.input->Initialize(f.window);
    assert(f.Dispatch(0));
    assert(f.Dispatch(65535));
    assert(f.reads == 0 && f.closed == 2);
    f.points = {Point(1, 0), Point(2, TOUCHEVENTF_DOWN | TOUCHEVENTF_UP)};
    assert(f.Dispatch(2));
    assert(f.events.empty() && f.closed == 3);
    f.input->Initialize(nullptr);
    assert(f.unregistered == 1);
    assert(!f.Dispatch(1));
  }
  std::cout
      << "Win7 touch routing, lifecycle, coordinates and ownership passed\n";
}
