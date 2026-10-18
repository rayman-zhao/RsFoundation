import Foundation

#if os(Windows)
    import WinSDK
    public typealias PID = UInt32
#else
    public typealias PID = Int32
#endif

/// Locates and terminates system processes the runner did not spawn itself,
/// e.g. a service process kept alive by a previous app session.
public enum SystemProcess {
    /// Returns the PID of the local process listening on the given port
    /// (IPv4 and IPv6; same data source as `netstat -ano`).
    public static func pidListening(on port: UInt16) -> PID? {
        #if os(Windows)
            for family in [AF_INET, AF_INET6] {
                var size: ULONG = 0
                _ = GetExtendedTcpTable(
                    nil, &size, false, ULONG(family), TCP_TABLE_OWNER_PID_ALL, 0)
                guard size >= MemoryLayout<MIB_TCPTABLE_OWNER_PID>.size else { continue }

                // The table header is a single dwNumEntries DWORD, immediately
                // followed by the MIB_TCP(6)ROW_OWNER_PID entries.
                let found = withUnsafeTemporaryAllocation(
                    byteCount: Int(size), alignment: MemoryLayout<DWORD>.alignment
                ) { buffer -> PID? in
                    guard
                        GetExtendedTcpTable(
                            buffer.baseAddress, &size, false, ULONG(family),
                            TCP_TABLE_OWNER_PID_ALL, 0) == 0
                    else { return nil }

                    let raw = UnsafeRawBufferPointer(buffer)
                    let rowCount = Int(raw.load(as: DWORD.self))
                    let header = MemoryLayout<DWORD>.size

                    if family == AF_INET {
                        let stride = MemoryLayout<MIB_TCPROW_OWNER_PID>.stride
                        for i in 0..<rowCount {
                            let row = raw.load(
                                fromByteOffset: header + i * stride, as: MIB_TCPROW_OWNER_PID.self)
                            if let pid = row.listeningPID(on: port) { return pid }
                        }
                    } else {
                        let stride = MemoryLayout<MIB_TCP6ROW_OWNER_PID>.stride
                        for i in 0..<rowCount {
                            let row = raw.load(
                                fromByteOffset: header + i * stride, as: MIB_TCP6ROW_OWNER_PID.self)
                            if let pid = row.listeningPID(on: port) { return pid }
                        }
                    }
                    return nil
                }
                if let found { return found }
            }
        #endif
        return nil
    }

    /// Terminates the process only when its executable name matches, so an
    /// unrelated process squatting on the expected port is never killed.
    ///
    /// - Parameters:
    ///   - pid: The PID of the process to terminate.
    ///   - name: The required executable file name without extension, e.g. "javaw"
    ///     (compared case-insensitively).
    /// - Returns: Whether the process was terminated.
    @discardableResult
    public static func terminate(_ pid: PID, ifExecutableNamed name: String) -> Bool {
        #if os(Windows)
            guard
                let process = OpenProcess(
                    DWORD(PROCESS_QUERY_LIMITED_INFORMATION) | DWORD(PROCESS_TERMINATE), false, pid)
            else { return false }
            defer { CloseHandle(process) }

            var path = [WCHAR](repeating: 0, count: 1024)
            var length = DWORD(path.count)
            guard QueryFullProcessImageNameW(process, 0, &path, &length) else { return false }
            let exePath = String(utf16: path)
            guard
                URL(filePath: exePath).deletingPathExtension().lastPathComponent
                    .caseInsensitiveCompare(name) == .orderedSame
            else {
                return false
            }
            return TerminateProcess(process, 1)
        #else
            return false
        #endif
    }
}

#if os(Windows)
    extension MIB_TCPROW_OWNER_PID {
        /// The owning PID when this row is the listener on `port`, otherwise nil.
        fileprivate func listeningPID(on port: UInt16) -> DWORD? {
            guard
                dwState == DWORD(MIB_TCP_STATE_LISTEN.rawValue),
                UInt16(bigEndian: UInt16(truncatingIfNeeded: dwLocalPort)) == port,
                dwOwningPid != 0
            else { return nil }
            return dwOwningPid
        }
    }

    extension MIB_TCP6ROW_OWNER_PID {
        /// The owning PID when this row is the listener on `port`, otherwise nil.
        fileprivate func listeningPID(on port: UInt16) -> DWORD? {
            guard
                dwState == DWORD(MIB_TCP_STATE_LISTEN.rawValue),
                UInt16(bigEndian: UInt16(truncatingIfNeeded: dwLocalPort)) == port,
                dwOwningPid != 0
            else { return nil }
            return dwOwningPid
        }
    }
#endif
