// DDC transport adapted from MonitorControl's Arm64DDC.swift and IntelDDC.swift.
// Copyright MonitorControl contributors, including @JoniVR, @theOneyouseek,
// @waydabber and @reitermarkus. See ThirdParty/MonitorControl-LICENSE.txt.
#include "MonitorHardware.h"
#include <IOKit/graphics/IOGraphicsLib.h>
#include <IOKit/i2c/IOI2CInterface.h>
#include <dlfcn.h>
#include <pthread.h>
#include <unistd.h>

typedef CFTypeRef (*CreateAV)(CFAllocatorRef, io_service_t);
typedef IOReturn (*AVTransfer)(CFTypeRef, uint32_t, uint32_t, void *, uint32_t);
typedef CFDictionaryRef (*CopyInfo)(CGDirectDisplayID);
typedef void (*FramebufferForDisplay)(CGDirectDisplayID, io_service_t *);
static CreateAV createAV;
static AVTransfer readAV, writeAV;
static CopyInfo copyInfo;
static FramebufferForDisplay framebufferForDisplay;
static pthread_once_t symbolsOnce = PTHREAD_ONCE_INIT;

static void loadSymbols(void) {
    // Resolve private functions defensively; unsupported OS versions must not prevent launch.
    void *io = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
    void *core = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY | RTLD_LOCAL);
    void *sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL);
    if (io) {
        createAV = (CreateAV)dlsym(io, "IOAVServiceCreateWithService");
        readAV = (AVTransfer)dlsym(io, "IOAVServiceReadI2C");
        writeAV = (AVTransfer)dlsym(io, "IOAVServiceWriteI2C");
    }
    if (core) copyInfo = (CopyInfo)dlsym(core, "CoreDisplay_DisplayCreateInfoDictionary");
    if (sky) framebufferForDisplay = (FramebufferForDisplay)dlsym(sky, "CGSServiceForDisplayNumber");
    // Framework handles live for the process lifetime because their function pointers do.
}

CFDictionaryRef BTMonitorCopyInfo(CGDirectDisplayID display) {
    pthread_once(&symbolsOnce, loadSymbols);
    return copyInfo ? copyInfo(display) : NULL;
}

CFTypeRef BTMonitorCreateAVService(io_service_t service) {
    pthread_once(&symbolsOnce, loadSymbols);
    return createAV && readAV && writeAV ? createAV(kCFAllocatorDefault, service) : NULL;
}

static uint8_t checksum(uint8_t initial, const uint8_t *bytes, size_t length) {
    for (size_t i = 0; i < length; ++i) initial ^= bytes[i];
    return initial;
}

bool BTMonitorParseReply(const uint8_t *b, size_t length, uint8_t code, uint16_t *current, uint16_t *maximum) {
    if (!b || length != 11 || b[0] != 0x6e || b[1] != 0x88 || b[2] != 0x02 || b[3] != 0 || b[4] != code)
        return false;
    if (checksum(0x50, b, 10) != b[10]) return false;
    uint16_t max = ((uint16_t)b[6] << 8) | b[7];
    uint16_t value = ((uint16_t)b[8] << 8) | b[9];
    if (max == 0 || value > max) return false;
    *current = value;
    *maximum = max;
    return true;
}

bool BTMonitorAVRead(CFTypeRef service, uint8_t code, uint16_t *current, uint16_t *maximum) {
    pthread_once(&symbolsOnce, loadSymbols);
    if (!service || !readAV || !writeAV) return false;
    uint8_t packet[] = {0x82, 0x01, code, 0};
    // IOAVService's read request uses the MonitorControl checksum convention.
    packet[3] = checksum(0x6e, packet, 3);
    for (int attempt = 0; attempt < 3; ++attempt) {
        bool sent = false;
        for (int cycle = 0; cycle < 2; ++cycle) {
            usleep(10000);
            sent = writeAV(service, 0x37, 0x51, packet, sizeof(packet)) == KERN_SUCCESS;
        }
        usleep(50000);
        uint8_t reply[11] = {0};
        if (sent && readAV(service, 0x37, 0, reply, sizeof(reply)) == KERN_SUCCESS &&
            BTMonitorParseReply(reply, sizeof(reply), code, current, maximum)) return true;
    }
    return false;
}

bool BTMonitorAVWrite(CFTypeRef service, uint8_t code, uint16_t value) {
    pthread_once(&symbolsOnce, loadSymbols);
    if (!service || !writeAV) return false;
    uint8_t packet[] = {0x84, 0x03, code, value >> 8, value & 0xff, 0};
    packet[5] = checksum(0x6e ^ 0x51, packet, 5);
    bool success = false;
    for (int cycle = 0; cycle < 2; ++cycle) {
        usleep(10000);
        success |= writeAV(service, 0x37, 0x51, packet, sizeof(packet)) == KERN_SUCCESS;
    }
    return success;
}

static uint32_t dictionaryNumber(CFDictionaryRef dictionary, CFStringRef key) {
    CFTypeRef value = CFDictionaryGetValue(dictionary, key);
    int64_t number = 0;
    if (value && CFGetTypeID(value) == CFNumberGetTypeID()) CFNumberGetValue(value, kCFNumberSInt64Type, &number);
    return (uint32_t)number;
}

io_service_t BTMonitorCopyFramebuffer(CGDirectDisplayID display) {
    if (CGDisplayIsBuiltin(display)) return IO_OBJECT_NULL;
    pthread_once(&symbolsOnce, loadSymbols);
    io_service_t framebuffer = IO_OBJECT_NULL;
    if (framebufferForDisplay) framebufferForDisplay(display, &framebuffer);
    if (framebuffer) return framebuffer;

    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOFramebuffer"), &iterator) != KERN_SUCCESS)
        return IO_OBJECT_NULL;
    // If identity is ambiguous, do not risk changing a different monitor.
    unsigned matches = 0;
    io_service_t service;
    while ((service = IOIteratorNext(iterator))) {
        CFDictionaryRef info = IODisplayCreateInfoDictionary(service, kIODisplayOnlyPreferredName);
        IOItemCount count = 0;
        if (info && dictionaryNumber(info, CFSTR(kDisplayVendorID)) == CGDisplayVendorNumber(display) &&
            dictionaryNumber(info, CFSTR(kDisplayProductID)) == CGDisplayModelNumber(display) &&
            dictionaryNumber(info, CFSTR(kDisplaySerialNumber)) == CGDisplaySerialNumber(display) &&
            IOFBGetI2CInterfaceCount(service, &count) == KERN_SUCCESS && count > 0) {
            ++matches;
            if (!framebuffer) { framebuffer = service; IOObjectRetain(service); }
        }
        if (info) CFRelease(info);
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    if (matches != 1 && framebuffer) { IOObjectRelease(framebuffer); framebuffer = IO_OBJECT_NULL; }
    return framebuffer;
}

static bool intelTransfer(io_service_t framebuffer, uint8_t *send, uint32_t count, uint8_t *reply) {
    IOItemCount busCount = 0;
    if (IOFBGetI2CInterfaceCount(framebuffer, &busCount) != KERN_SUCCESS) return false;
    for (IOOptionBits bus = 0; bus < busCount; ++bus) {
        io_service_t interface = IO_OBJECT_NULL;
        if (IOFBCopyI2CInterfaceForBus(framebuffer, bus, &interface) != KERN_SUCCESS) continue;
        IOOptionBits replyType = kIOI2CSimpleTransactionType;
        CFTypeRef supported = IORegistryEntryCreateCFProperty(interface, CFSTR(kIOI2CTransactionTypesKey), kCFAllocatorDefault, 0);
        int64_t types = 0;
        if (supported && CFGetTypeID(supported) == CFNumberGetTypeID()) CFNumberGetValue(supported, kCFNumberSInt64Type, &types);
        if (supported) CFRelease(supported);
        if (types & (1 << kIOI2CDDCciReplyTransactionType)) replyType = kIOI2CDDCciReplyTransactionType;
        IOI2CConnectRef connection = NULL;
        IOReturn opened = IOI2CInterfaceOpen(interface, 0, &connection);
        IOObjectRelease(interface);
        if (opened != KERN_SUCCESS) continue;
        IOI2CRequest request = {0};
        request.sendAddress = 0x6e;
        request.sendTransactionType = kIOI2CSimpleTransactionType;
        request.sendBuffer = (vm_address_t)send;
        request.sendBytes = count;
        request.minReplyDelay = 50000000; // 50 ms, in nanoseconds.
        request.replyAddress = 0x6f;
        request.replySubAddress = 0x51;
        request.replyTransactionType = reply ? replyType : kIOI2CNoTransactionType;
        request.replyBuffer = (vm_address_t)reply;
        request.replyBytes = reply ? 11 : 0;
        IOReturn result = IOI2CSendRequest(connection, 0, &request);
        IOI2CInterfaceClose(connection, 0);
        if (result == KERN_SUCCESS && request.result == KERN_SUCCESS) return true;
    }
    return false;
}

bool BTMonitorIntelRead(io_service_t framebuffer, uint8_t code, uint16_t *current, uint16_t *maximum) {
    uint8_t packet[] = {0x51, 0x82, 0x01, code, 0};
    packet[4] = checksum(0x6e, packet, 4);
    for (int attempt = 0; attempt < 3; ++attempt) {
        uint8_t reply[11] = {0};
        usleep(10000);
        if (intelTransfer(framebuffer, packet, sizeof(packet), reply) &&
            BTMonitorParseReply(reply, sizeof(reply), code, current, maximum)) return true;
    }
    return false;
}

bool BTMonitorIntelWrite(io_service_t framebuffer, uint8_t code, uint16_t value) {
    uint8_t packet[] = {0x51, 0x84, 0x03, code, value >> 8, value & 0xff, 0};
    packet[6] = checksum(0x6e, packet, 6);
    bool success = false;
    for (int cycle = 0; cycle < 2; ++cycle) {
        usleep(10000);
        success |= intelTransfer(framebuffer, packet, sizeof(packet), NULL);
    }
    return success;
}
