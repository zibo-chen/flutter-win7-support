// Copyright 2026 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "flutter/fml/platform/win/win7_wait_on_address.h"

#include <cstdint>
#include <cstring>

namespace {

// Windows allows spurious address-wait wakeups. Hash collisions may therefore
// share a condition variable, provided notifications wake the whole bucket.
// Both the value check and notification hold its lock to avoid lost wakeups.
struct WaitBucket {
  SRWLOCK lock = SRWLOCK_INIT;
  CONDITION_VARIABLE condition = CONDITION_VARIABLE_INIT;
};

WaitBucket& BucketFor(const volatile void* address) {
  static WaitBucket buckets[128];
  return buckets[(reinterpret_cast<uintptr_t>(address) >> 3) % 128];
}

using NativeWait = BOOL(WINAPI*)(volatile VOID*, PVOID, SIZE_T, DWORD);
using NativeWake = void(WINAPI*)(PVOID);

struct NativeFunctions {
  NativeWait wait;
  NativeWake wake_one;
  NativeWake wake_all;
};

const NativeFunctions& Native() {
  static const NativeFunctions functions = [] {
    HMODULE module = GetModuleHandleW(L"kernel32.dll");
    return NativeFunctions{
        reinterpret_cast<NativeWait>(GetProcAddress(module, "WaitOnAddress")),
        reinterpret_cast<NativeWake>(
            GetProcAddress(module, "WakeByAddressSingle")),
        reinterpret_cast<NativeWake>(
            GetProcAddress(module, "WakeByAddressAll"))};
  }();
  return functions;
}

bool HasNativeWait() {
  return Native().wait && Native().wake_one && Native().wake_all;
}

BOOL WINAPI WaitCompatible(volatile VOID* address,
                           PVOID expected,
                           SIZE_T size,
                           DWORD timeout) {
  return HasNativeWait() ? Native().wait(address, expected, size, timeout)
                         : fml::win7::WaitOnAddressFallback(address, expected,
                                                            size, timeout);
}

void WINAPI WakeOneCompatible(PVOID address) {
  if (HasNativeWait()) {
    Native().wake_one(address);
  } else {
    fml::win7::WakeByAddressFallback(address);
  }
}

void WINAPI WakeAllCompatible(PVOID address) {
  if (HasNativeWait()) {
    Native().wake_all(address);
  } else {
    fml::win7::WakeByAddressFallback(address);
  }
}

}  // namespace

namespace fml::win7 {

BOOL WINAPI WaitOnAddressFallback(volatile VOID* address,
                                  PVOID expected,
                                  SIZE_T size,
                                  DWORD timeout) {
  if (address == nullptr || expected == nullptr ||
      (size != 1 && size != 2 && size != 4 && size != 8)) {
    SetLastError(ERROR_INVALID_PARAMETER);
    return FALSE;
  }
  auto& bucket = BucketFor(address);
  AcquireSRWLockExclusive(&bucket.lock);
  BOOL result = TRUE;
  if (std::memcmp(const_cast<const void*>(address), expected, size) == 0) {
    result =
        SleepConditionVariableSRW(&bucket.condition, &bucket.lock, timeout, 0);
  }
  DWORD error = result ? ERROR_SUCCESS : GetLastError();
  ReleaseSRWLockExclusive(&bucket.lock);
  if (!result)
    SetLastError(error);
  return result;
}

void WINAPI WakeByAddressFallback(PVOID address) {
  auto& bucket = BucketFor(address);
  AcquireSRWLockExclusive(&bucket.lock);
  WakeAllConditionVariable(&bucket.condition);
  ReleaseSRWLockExclusive(&bucket.lock);
}

}  // namespace fml::win7

// Static MSVC library objects can reference the Win8 address-wait import
// pointers. Supply them in this source_set so linking cannot pull those
// entries from Synchronization.lib. Normal builds never compile this file.
extern "C" {
NativeWait __imp_WaitOnAddress = WaitCompatible;
NativeWake __imp_WakeByAddressSingle = WakeOneCompatible;
NativeWake __imp_WakeByAddressAll = WakeAllCompatible;
}
