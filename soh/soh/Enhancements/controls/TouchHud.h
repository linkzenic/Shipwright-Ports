#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
int TouchHud_IsActive(void);
int TouchHud_ItemHidden(int slot);
int TouchHud_ItemRect(int slot, int16_t* x, int16_t* y, int16_t* size);
void TouchHud_MarkContent(int slot);
int TouchHud_MapPressed(void);
int TouchHud_NaviUtilityIcon(void);
int TouchHud_NaviPressed(void);
uint32_t TouchHud_Buttons(void);
void TouchHud_Stick(int8_t* x, int8_t* y);
#ifdef __cplusplus
}
#endif
