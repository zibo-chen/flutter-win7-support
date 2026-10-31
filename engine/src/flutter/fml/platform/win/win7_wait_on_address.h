// Copyright 2026 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_FML_PLATFORM_WIN_WIN7_WAIT_ON_ADDRESS_H_
#define FLUTTER_FML_PLATFORM_WIN_WIN7_WAIT_ON_ADDRESS_H_

#include <windows.h>

namespace fml::win7 {

BOOL WINAPI WaitOnAddressFallback(volatile VOID* address,
                                  PVOID expected,
                                  SIZE_T size,
                                  DWORD timeout);
void WINAPI WakeByAddressFallback(PVOID address);

}  // namespace fml::win7

#endif  // FLUTTER_FML_PLATFORM_WIN_WIN7_WAIT_ON_ADDRESS_H_
