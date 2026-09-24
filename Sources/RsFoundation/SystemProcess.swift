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

                let buffer = UnsafeMutableRawPointer.allocate(
                    byteCount: Int(size), alignment: MemoryLayout<DWORD>.alignment)
                defer { buffer.deallocate() }
                guard
                    GetExtendedTcpTable(
                        buffer, &size, false, ULONG(family), TCP_TABLE_OWNER_PID_ALL, 0) == 0
                else {
                    continue
                }

                // The table header is a single dwNumEntries DWORD, immediately
                // followed by the MIB_TCP(6)ROW_OWNER_PID entries.
                let listening = DWORD(MIB_TCP_STATE_LISTEN.rawValue)
                let rows = buffer.advanced(by: MemoryLayout<DWORD>.size)
                let rowCount = Int(buffer.assumingMemoryBound(to: DWORD.self).pointee)
                if family == AF_INET {
                    let table = rows.assumingMemoryBound(to: MIB_TCPROW_OWNER_PID.self)
                    for i in 0..<rowCount {
                        let row = table[i]
                        if row.dwState == listening,
                            UInt16(bigEndian: UInt16(truncatingIfNeeded: row.dwLocalPort)) == port,
                            row.dwOwningPid != 0
                        {
                            return row.dwOwningPid
                        }
                    }
                } else {
                    let table = rows.assumingMemoryBound(to: MIB_TCP6ROW_OWNER_PID.self)
                    for i in 0..<rowCount {
                        let row = table[i]
                        if row.dwState == listening,
                            UInt16(bigEndian: UInt16(truncatingIfNeeded: row.dwLocalPort)) == port,
                            row.dwOwningPid != 0
                        {
                            return row.dwOwningPid
                        }
                    }
                }
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
