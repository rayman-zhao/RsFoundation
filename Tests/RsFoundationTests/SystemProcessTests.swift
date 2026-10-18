import Foundation
import RsFoundation
import Testing

#if os(Windows)
    import WinSDK

    private struct SocketError: Error {}

    /// Binds a wildcard TCP listener of `family` on a random port.
    ///
    /// The caller owns the socket and must `closesocket` it — the LISTEN row
    /// disappears from the TCP table as soon as the socket is closed.
    private func listenOn(family: INT32) throws -> (socket: SOCKET, port: UInt16) {
        let s = socket(family, Int32(SOCK_STREAM), Int32(IPPROTO_TCP.rawValue))
        guard s != INVALID_SOCKET else { throw SocketError() }

        if family == AF_INET {
            var addr = sockaddr_in()
            addr.sin_family = ADDRESS_FAMILY(AF_INET)
            try withUnsafeMutablePointer(to: &addr) {
                try $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    if bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) != 0 {
                        throw SocketError()
                    }
                    if listen(s, SOMAXCONN) != 0 { throw SocketError() }
                    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
                    if getsockname(s, $0, &len) != 0 { throw SocketError() }
                }
            }
            return (s, UInt16(bigEndian: addr.sin_port))
        } else {
            var addr = sockaddr_in6()
            addr.sin6_family = ADDRESS_FAMILY(AF_INET6)
            try withUnsafeMutablePointer(to: &addr) {
                try $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    if bind(s, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) != 0 {
                        throw SocketError()
                    }
                    if listen(s, SOMAXCONN) != 0 { throw SocketError() }
                    var len = socklen_t(MemoryLayout<sockaddr_in6>.size)
                    if getsockname(s, $0, &len) != 0 { throw SocketError() }
                }
            }
            return (s, UInt16(bigEndian: addr.sin6_port))
        }
    }

    @Test
    func systemProcess() throws {
        var wsaData = WSADATA()
        try #require(WSAStartup(WORD(0x0202), &wsaData) == 0)
        defer { _ = WSACleanup() }

        // A listener we own must resolve to this process, via the same data
        // source as `netstat -ano`. The v4/v6 listeners exercise both row types.
        let currentPID = GetCurrentProcessId()

        let v4 = try listenOn(family: AF_INET)
        defer { closesocket(v4.socket) }
        #expect(SystemProcess.pidListening(on: v4.port) == currentPID)

        let v6 = try listenOn(family: AF_INET6)
        defer { closesocket(v6.socket) }
        #expect(SystemProcess.pidListening(on: v6.port) == currentPID)
    }
#endif
