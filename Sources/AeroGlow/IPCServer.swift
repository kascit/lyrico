import Foundation

public protocol IPCServerDelegate: AnyObject {
    func ipcServer(_ server: IPCServer, didReceiveCommand command: String) -> String
}

public final class IPCServer {
    public static let socketPath = "/tmp/aeroglow.sock"
    public weak var delegate: IPCServerDelegate?
    
    private var serverSource: DispatchSourceRead?
    private var serverSocket: Int32 = -1
    
    public init() {}
    
    deinit {
        stop()
    }
    
    public func start() -> Bool {
        unlink(IPCServer.socketPath)
        
        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else { return false }
        
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        
        let pathBytes = IPCServer.socketPath.utf8CString
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(serverSocket)
            return false
        }
        
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr)
            _ = pathBytes.withUnsafeBufferPointer { buf in
                memcpy(raw, buf.baseAddress!, buf.count)
            }
        }
        
        var rawAddr = sockaddr()
        memcpy(&rawAddr, &addr, MemoryLayout<sockaddr_un>.size)
        
        guard bind(serverSocket, &rawAddr, socklen_t(MemoryLayout<sockaddr_un>.size)) >= 0 else {
            close(serverSocket)
            return false
        }
        
        guard listen(serverSocket, 5) >= 0 else {
            close(serverSocket)
            return false
        }
        
        let source = DispatchSource.makeReadSource(fileDescriptor: serverSocket, queue: .main)
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            var clientAddr = sockaddr()
            var clientLen: socklen_t = socklen_t(MemoryLayout<sockaddr>.size)
            let clientSocket = accept(self.serverSocket, &clientAddr, &clientLen)
            guard clientSocket >= 0 else { return }
            
            var buffer = [UInt8](repeating: 0, count: 512)
            let bytesRead = read(clientSocket, &buffer, buffer.count - 1)
            if bytesRead > 0 {
                let command = String(decoding: buffer[0..<bytesRead], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                let response = (self.delegate?.ipcServer(self, didReceiveCommand: command) ?? "ok") + "\n"
                _ = response.utf8CString.withUnsafeBufferPointer { buf in
                    write(clientSocket, buf.baseAddress!, buf.count - 1)
                }
            }
            close(clientSocket)
        }
        
        source.resume()
        self.serverSource = source
        return true
    }
    
    public func stop() {
        serverSource?.cancel()
        serverSource = nil
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
        unlink(IPCServer.socketPath)
    }
    
    public static func sendCommand(_ command: String) -> String? {
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { return nil }
        defer { close(sock) }
        
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = IPCServer.socketPath.utf8CString
        
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr)
            _ = pathBytes.withUnsafeBufferPointer { buf in
                memcpy(raw, buf.baseAddress!, buf.count)
            }
        }
        
        var rawAddr = sockaddr()
        memcpy(&rawAddr, &addr, MemoryLayout<sockaddr_un>.size)
        
        guard connect(sock, &rawAddr, socklen_t(MemoryLayout<sockaddr_un>.size)) >= 0 else {
            return nil
        }
        
        let msg = command + "\n"
        _ = msg.utf8CString.withUnsafeBufferPointer { buf in
            write(sock, buf.baseAddress!, buf.count - 1)
        }
        
        var buffer = [UInt8](repeating: 0, count: 1024)
        let readBytes = read(sock, &buffer, buffer.count - 1)
        if readBytes > 0 {
            return String(decoding: buffer[0..<readBytes], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "ok"
    }
}
