#pragma once

#ifdef __cplusplus
extern "C" {
#endif

int SOHiOS_TouchControlsAvailable(void);
void SOHiOS_SetTouchControlsEnabled(int enabled);
void SOHiOS_SetFaceButtonLayout(int layout);
void SOHiOS_SetTouchControlsMenuVisible(int visible);
int SOHiOS_ConsumeMenuToggleRequest(void);
void SOHiOS_RequestMenuToggle(void);
void SOHiOS_RefreshOverlay(void);
void SOHiOS_SetCameraStick(float x, float y);
void SOHiOS_SetTouchStickOptions(int leftFloating, int rightFloating, int transparent);
int SOHiOS_IntegratedTouchStyle(void);
void SOHiOS_ConfigureIntegratedTouch(int style, float scale, float opacity, int leftFloating, int rightFloating,
                                   int transparent);
void SOHiOS_ApplyIntegratedTouch(void* window, int enabled, int menuVisible);
void SOHiOS_EditIntegratedTouch(void);

#ifdef __cplusplus
}
#endif
