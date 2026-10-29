#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
void SOHNearbySync_Start(void);
void SOHNearbySync_Stop(void);
void SOHNearbySync_Pair(const char* code);
void SOHNearbySync_Sync(void);
void SOHNearbySync_Send(void);
void SOHNearbySync_GetStatus(char* buffer, size_t size);
void SOHNearbySync_GetIncoming(char* buffer, size_t size);
int SOHNearbySync_GetSlot(int slot, char* buffer, size_t size);
void SOHNearbySync_ChooseSlot(int slot, int incoming);
// Called only by SaveManager after its save worker has stopped.
void SOHNearbySync_PrepareSaves(void);
void SOHNearbySync_ApplyIncoming(void);
void SOHNearbySync_KeepLocal(void);
#if !defined(__TVOS__)
void SOHNearbySync_ChooseFolder(void);
void SOHNearbySync_SyncFolder(void);
void SOHNearbySync_ImportMods(void);
void SOHNearbySync_ActivateMods(void);
void SOHNearbySync_AutoFolderSync(int includeMods);
int SOHNearbySync_AutomaticFolderEnabled(void);
void SOHNearbySync_SetAutomaticFolder(int enabled);
#endif
#ifdef __cplusplus
}
#endif
