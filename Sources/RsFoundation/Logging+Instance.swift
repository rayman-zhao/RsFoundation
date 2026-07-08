import Foundation
import Logging

/// The global logger for application.
/// 
/// The logger will use different output levels on test, debug and release.
public let log: Logger = {
    var log = Logger(label:"swiftworks")
    
    if ProcessInfo.processInfo.processName == "xctest" {
        log.logLevel = .trace
    }
    else {
        #if DEBUG
        log.logLevel = .info
        #else
        log.logLevel = .warning
        #endif
    }
    
    return log
}()