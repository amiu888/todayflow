import Crypto
import Foundation

/// Signed-in admin browser sessions, kept in memory: a server restart signs
/// everyone out, which is fine for a page used now and then.
public actor AdminSessions {
    struct Session {
        var csrf: String
        var expires: Date
    }

    let lifetime: TimeInterval
    private var sessions: [String: Session] = [:]

    public init(lifetime: TimeInterval = 12 * 60 * 60) {
        self.lifetime = lifetime
    }

    /// A new session id (for the cookie) and its form token.
    func create(now: Date) -> (id: String, csrf: String) {
        sessions = sessions.filter { $0.value.expires > now }
        let id = Store.randomHex(bytes: 32)
        let csrf = Store.randomHex(bytes: 32)
        sessions[id] = Session(csrf: csrf, expires: now.addingTimeInterval(lifetime))
        return (id, csrf)
    }

    /// The form token of a live session, or nil.
    func csrf(for id: String, now: Date) -> String? {
        guard let session = sessions[id], session.expires > now else {
            sessions[id] = nil
            return nil
        }
        return session.csrf
    }

    func end(_ id: String) {
        sessions[id] = nil
    }
}

enum AdminSecurity {
    /// Compares two secrets in time that does not depend on where they differ.
    static func equal(_ a: String, _ b: String) -> Bool {
        let left = Array(SHA256.hash(data: Data(a.utf8)))
        let right = Array(SHA256.hash(data: Data(b.utf8)))
        var difference: UInt8 = 0
        for index in left.indices { difference |= left[index] ^ right[index] }
        return difference == 0
    }

    /// Escapes text for HTML element content and attribute values.
    static func html(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }
}
