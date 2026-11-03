import Foundation

/// A fractional-index key (driver.md §2 `displayOrder`).
///
/// Keys are base-62 strings whose value is a fraction in `[0, 1)`:
/// ```
/// value(s) = Σ code(s[i]) / 62^(i+1)
/// ```
/// The key property is `midpoint(a, b)`: a new key strictly between two existing
/// keys, so reordering an item is a single in-place update (no reindex of its
/// siblings) and syncs as one row change.
///
/// **Alphabet is byte-ordered** (`0-9`, then `A-Z`, then `a-z`). This is deliberate:
/// SQLite orders `TEXT` by byte value, so `ORDER BY displayOrder` with the default
/// BINARY collation agrees with `isLessThan` / `midpoint` — no custom collation.
public struct FractionalIndex: Sendable, Hashable {
    /// Base-62 alphabet in ascending byte order.
    public static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

    /// Number of base-62 fractional digits of precision.
    /// A safety margin: each `midpoint` roughly halves the gap, so this allows
    /// hundreds of reorders of the same slot before exhaustion.
    public static let precision = 32

    private static let codeTable: [Character: Int] = {
        var t: [Character: Int] = [:]
        for (i, c) in alphabet.enumerated() { t[c] = i }
        return t
    }()

    /// The code (0–61) of a character, or 0 for an unknown character.
    public static func code(_ c: Character) -> Int {
        codeTable[c] ?? 0
    }

    /// The character for a code (0–61). Out-of-range codes clamp to `0`.
    public static func char(_ code: Int) -> Character {
        guard code >= 0, code < alphabet.count else { return "0" }
        return alphabet[code]
    }

    /// The code of each character in `s`.
    public static func codes(_ s: String) -> [Int] {
        s.map { codeTable[$0] ?? 0 }
    }

    /// True if key `a` sorts before key `b` (by fractional value).
    ///
    /// This is the same order the database produces with `ORDER BY displayOrder`
    /// (byte order), because the alphabet is byte-ordered.
    public static func isLessThan(_ a: String, _ b: String) -> Bool {
        let ca = codes(a), cb = codes(b)
        let n = max(ca.count, cb.count)
        for i in 0..<n {
            let x = i < ca.count ? ca[i] : 0
            let y = i < cb.count ? cb[i] : 0
            if x != y { return x < y }
        }
        // Equal up to the shorter length; the shorter (a prefix) sorts first.
        return ca.count < cb.count
    }

    // MARK: - midpoint

    /// A new key strictly between `a` and `b` (in fractional-value order).
    ///
    /// `nil` means "no bound": `nil` for `a` is the bottom (value 0) and `nil` for
    /// `b` is the top (value 1). Use this to insert before the first or after the
    /// last item in a list.
    ///
    /// - Precondition: `a` sorts before `b` (or is `nil`). If they are equal or
    ///   out of order, the result is best-effort and may not be strictly between.
    public static func midpoint(_ a: String?, _ b: String?) -> String {
        let A = toFixed(a)
        let B = b.map(toFixed) ?? topBoundary
        let mid = half(add(A, B))
        return fromDigits(mid)
    }

    /// The smallest key (value 0) — convenient for "the first item".
    public static let bottom = "0"

    // MARK: - fixed-width base-62 arithmetic

    /// Working width: one integer digit + `precision` fractional digits.
    private static var workWidth: Int { precision + 1 }

    /// The value 1.0 as a fixed-width digit array (the top boundary).
    private static let topBoundary: [Int] = {
        var d = [Int](repeating: 0, count: workWidth)
        d[0] = 1 // 1.0 = "1" in the integer digit, zero fractional digits.
        return d
    }()

    /// Parse a key into a fixed-width digit array.
    ///
    /// `d[0]` is the integer part (always 0 for values < 1); `d[1...]` are the
    /// `precision` fractional digits, left-aligned (the key's first char is the most
    /// significant fractional digit). `nil` → value 0.
    private static func toFixed(_ s: String?) -> [Int] {
        let c = (s.map(codes) ?? []).prefix(precision)
        var d = [Int](repeating: 0, count: workWidth)
        for (i, code) in c.enumerated() {
            d[1 + i] = code
        }
        return d
    }

    /// Convert a fixed-width digit array back to a key string.
    ///
    /// Drops the (always-zero) integer digit, then strips trailing zero fractional
    /// digits, keeping at least one character.
    private static func fromDigits(_ d: [Int]) -> String {
        var chars: [Character] = d[1...].map(char)
        while chars.count > 1, chars.last == "0" {
            chars.removeLast()
        }
        return String(chars)
    }

    /// Base-62 addition of two fixed-width digit arrays (most-significant first).
    private static func add(_ a: [Int], _ b: [Int]) -> [Int] {
        var result = [Int](repeating: 0, count: workWidth)
        var carry = 0
        for i in stride(from: workWidth - 1, through: 0, by: -1) {
            let sum = a[i] + b[i] + carry
            result[i] = sum % 62
            carry = sum / 62
        }
        return result
    }

    /// Base-62 halving of a fixed-width digit array (long division by 2).
    private static func half(_ a: [Int]) -> [Int] {
        var result = [Int](repeating: 0, count: a.count)
        var remainder = 0
        for i in 0..<a.count {
            let cur = remainder * 62 + a[i]
            result[i] = cur / 2
            remainder = cur % 2
        }
        return result
    }
}
