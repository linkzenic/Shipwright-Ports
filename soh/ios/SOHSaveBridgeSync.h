#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Pairs this installation with a Save Bridge discovered on the local network.
void SOHSaveBridgeSync_Pair(const char* code);

// Compares SOH save files with the paired Mac and transfers the newer copy.
void SOHSaveBridgeSync_SyncNow(void);

// Returns safely to file select after a downloaded save is ready to load.
void SOHSaveBridgeSync_ReloadDownloadedSaves(void);

// Copies the current user-facing state into buffer as UTF-8.
void SOHSaveBridgeSync_GetStatus(char* buffer, size_t bufferSize);

#ifdef __cplusplus
}
#endif
