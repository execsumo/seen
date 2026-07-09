import Foundation

public protocol ProcessRunning: Sendable {
    func run(_ executable: String, _ arguments: [String]) async throws -> Int32
}

/// Resolved once: the private libSystem SPI that lets a spawned child become
/// its *own* TCC "responsible process". Without it, any permission a child
/// triggers (network, Documents/Downloads, Apple Events to other apps…) is
/// attributed to the parent — so a menu-bar app that spawns `claude` gets
/// blamed for all of claude's prompts. `dlsym`'d rather than linked so a
/// missing symbol degrades to the old behavior instead of failing to launch.
private typealias DisclaimFn = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
private let disclaimResponsibility: DisclaimFn? = {
    // RTLD_DEFAULT
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                          "responsibility_spawnattrs_setdisclaim") else { return nil }
    return unsafeBitCast(sym, to: DisclaimFn.self)
}()

public struct DefaultProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ executable: String, _ arguments: [String]) async throws -> Int32 {
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }

        // Detach TCC responsibility so the child owns its own permission
        // prompts. No-op if the SPI is unavailable on this OS.
        _ = disclaimResponsibility?(&attr, 1)

        let argv = [executable] + arguments
        var cArgs: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
        cArgs.append(nil)
        defer { for p in cArgs where p != nil { free(p) } }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, executable, nil, &attr, cArgs, environ)
        guard rc == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(rc),
                          userInfo: [NSLocalizedDescriptionKey: "posix_spawn failed for \(executable) (errno \(rc))"])
        }

        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}

        // WIFEXITED / WEXITSTATUS
        if (status & 0x7f) == 0 {
            return (status >> 8) & 0xff
        }
        return status
    }
}
