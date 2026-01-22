// This file is generated and will be overwritten automatically.

#import <Foundation/Foundation.h>

// NOLINTNEXTLINE(modernize-use-using)
typedef NS_ENUM(NSInteger, MBMTracingBackendType)
{
    /**
     * The `Noop` backend introduces no overhead and does not produce any trace marks.
     * The `Noop` backend is used by default, and the enumeration value can be used to
     * disable tracing if needed.
     */
    MBMTracingBackendTypeNoop,
    /**
     * Tracing backend specific to the operating system.
     * For example, Signpost for the iOS or Android Trace for the Android platform.
     */
    MBMTracingBackendTypePlatform,
    /** Tracing backend that prints Perfetto-compatible trace marks to the platform log subsystem. */
    MBMTracingBackendTypeLogger
} NS_SWIFT_NAME(TracingBackendType);

NSString* MBMTracingBackendTypeToString(MBMTracingBackendType tracing_backend_type);
