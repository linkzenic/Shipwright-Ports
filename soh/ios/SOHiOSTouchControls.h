#pragma once

#ifdef __cplusplus
extern "C" {
#endif

int SOHiOS_TouchControlsAvailable(void);
void SOHiOS_SetTouchControlsEnabled(int enabled);
void SOHiOS_SetFaceButtonLayout(int layout);
void SOHiOS_SetTouchControlsMenuVisible(int visible);
int SOHiOS_ConsumeMenuToggleRequest(void);

#ifdef __cplusplus
}
#endif
