// Copyright 2026 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "flutter/fml/platform/win/win7_wait_on_address.h"

#include <atomic>
#include <cassert>
#include <iostream>
#include <thread>
#include <vector>

int main() {
  using fml::win7::WaitOnAddressFallback;
  using fml::win7::WakeByAddressFallback;
  LONG value = 1;
  LONG expected = 0;
  assert(WaitOnAddressFallback(&value, &expected, sizeof(value), 0));
  expected = 1;
  assert(!WaitOnAddressFallback(&value, &expected, sizeof(value), 0));
  assert(GetLastError() == ERROR_TIMEOUT);
  assert(!WaitOnAddressFallback(&value, &expected, 3, 0));
  assert(GetLastError() == ERROR_INVALID_PARAMETER);
  value = 2;
  assert(WaitOnAddress(&value, &expected, sizeof(value), 0));
  for (SIZE_T size : {SIZE_T{1}, SIZE_T{2}, SIZE_T{4}, SIZE_T{8}}) {
    ULONGLONG actual = 1;
    ULONGLONG old = 0;
    assert(WaitOnAddressFallback(&actual, &old, size, 0));
  }
  std::atomic<LONG> shared{0};
  std::atomic<int> ready{0};
  std::vector<std::thread> threads;
  for (int i = 0; i < 8; i++) {
    threads.emplace_back([&] {
      ready.fetch_add(1);
      LONG old = 0;
      while (shared.load() == 0) {
        assert(WaitOnAddressFallback(&shared, &old, sizeof(old), 5000));
      }
    });
  }
  while (ready.load() != 8)
    Sleep(1);
  shared.store(1);
  WakeByAddressFallback(&shared);
  for (auto &thread : threads)
    thread.join();
  // Also exercise the static STL object that previously imported Win8 APIs.
  std::atomic<int> atomic_wait_value{0};
  std::thread atomic_waiter([&] { atomic_wait_value.wait(0); });
  atomic_wait_value.store(1);
  atomic_wait_value.notify_one();
  atomic_waiter.join();
  std::cout << "{\"passed\":true,\"waiters\":8,\"sizes\":[1,2,4,8]}\n";
  return 0;
}
