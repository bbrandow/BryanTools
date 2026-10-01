#pragma once
#include <CoreGraphics/CoreGraphics.h>
#include <IOKit/IOKitLib.h>
#include <stdbool.h>

CF_ASSUME_NONNULL_BEGIN
CFDictionaryRef _Nullable BTMonitorCopyInfo(CGDirectDisplayID display) CF_RETURNS_RETAINED;
CFTypeRef _Nullable BTMonitorCreateAVService(io_service_t service) CF_RETURNS_RETAINED;
bool BTMonitorAVRead(CFTypeRef service, uint8_t code, uint16_t *current, uint16_t *maximum);
bool BTMonitorAVWrite(CFTypeRef service, uint8_t code, uint16_t value);
io_service_t BTMonitorCopyFramebuffer(CGDirectDisplayID display);
bool BTMonitorIntelRead(io_service_t framebuffer, uint8_t code, uint16_t *current, uint16_t *maximum);
bool BTMonitorIntelWrite(io_service_t framebuffer, uint8_t code, uint16_t value);
// Also exposed to tests: reject malformed, unsupported and mismatched replies.
bool BTMonitorParseReply(const uint8_t *bytes, size_t length, uint8_t code, uint16_t *current, uint16_t *maximum);
CF_ASSUME_NONNULL_END
