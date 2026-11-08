import AppKit
import Darwin

/// Retrouve l'app (Terminal, iTerm, VS Code, Claude…) dans laquelle tourne un processus,
/// en remontant ses processus parents.
enum ProcessOwner {
    static func app(of pid: pid_t) -> NSRunningApplication? {
        var current = pid
        // Une dizaine de niveaux suffit (shell, login, terminal…).
        for _ in 0..<12 {
            guard current > 1 else { return nil }
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular {
                return app
            }
            guard let parent = parent(of: current), parent != current else { return nil }
            current = parent
        }
        return nil
    }

    /// Ramène au premier plan l'app où tourne ce processus.
    @discardableResult
    static func activateApp(of pid: pid_t) -> Bool {
        guard let app = app(of: pid) else { return false }
        return app.activate()
    }

    /// Terminal du processus (`/dev/ttys003`), ou `nil` s'il n'en a pas (app Claude…).
    static func ttyPath(of pid: pid_t) -> String? {
        guard let device = info(of: pid)?.kp_eproc.e_tdev, device != -1,
            let name = devname(device, S_IFCHR)
        else { return nil }
        return "/dev/" + String(cString: name)
    }

    private static func parent(of pid: pid_t) -> pid_t? {
        info(of: pid)?.kp_eproc.e_ppid
    }

    private static func info(of pid: pid_t) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }
}
