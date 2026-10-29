#pragma once
#include <cstdint>
#include <cstring>
#include <initializer_list>

namespace TVOSNetwork {
// Address is in host byte order. Negative scores are never advertised.
inline int InterfaceScore(const char* name, uint32_t address) {
    if (!name || !*name || (address >> 24) == 127 || (address >> 16) == 0xA9FE ||
        (address >> 24) == 0 || (address >> 28) >= 14) return -1;
    for (auto prefix : {"utun", "ipsec", "ppp", "pdp_ip", "awdl", "llw"}) {
        if (std::strncmp(name, prefix, std::strlen(prefix)) == 0) return -1;
    }
    int score = std::strcmp(name, "en0") == 0 ? 100 : std::strcmp(name, "en1") == 0 ? 90 :
                std::strncmp(name, "bridge", 6) == 0 ? 70 : 30;
    const bool privateAddress = (address >> 24) == 10 || (address >> 16) == 0xC0A8 ||
                               (address & 0xFFF00000U) == 0xAC100000U;
    return score + (privateAddress ? 20 : 0);
}
}
