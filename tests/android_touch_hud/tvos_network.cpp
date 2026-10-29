#include "../../soh/ios/TVOSNetworkInterface.h"
#include <cassert>
int main() {
    using TVOSNetwork::InterfaceScore;
    assert(InterfaceScore("en0",0xC0A80102)>InterfaceScore("bridge0",0xC0A80103));
    assert(InterfaceScore("en1",0x0A000002)>InterfaceScore("other0",0xC0A80103));
    assert(InterfaceScore("utun0",0x0A200001)<0);
    assert(InterfaceScore("awdl0",0xC0A80103)<0);
    assert(InterfaceScore("en0",0xA9FE0101)<0);
    assert(InterfaceScore("en0",0x7F000001)<0);
    assert(InterfaceScore("en0",0xE0000001)<0);
    assert(InterfaceScore(nullptr,0xC0A80103)<0);
    assert(InterfaceScore("en0",0xAC100001)>0);
}
