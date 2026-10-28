#pragma once
#include <cctype>

namespace UIWidgets {
inline bool ComboLabelVisible(const char* label) {
    if (label == nullptr) return false;
    for (; *label != '\0'; ++label) {
        if (!std::isspace(static_cast<unsigned char>(*label))) return true;
    }
    return false;
}
}
