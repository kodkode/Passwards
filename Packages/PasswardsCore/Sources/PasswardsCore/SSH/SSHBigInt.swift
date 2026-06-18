import Foundation

/// Minimal big-endian unsigned big-integer ops, just enough to derive the RSA
/// CRT exponents (dP = d mod (p−1), dQ = d mod (q−1)) when importing an OpenSSH
/// RSA key into a `SecKey`, which requires the full PKCS#1 form.
///
/// Bit-by-bit reduction — deliberately simple so it's easy to read; the RSA
/// sign-then-verify round-trip test is the real correctness check.
enum SSHBigInt {
    /// big-endian `a` minus 1 (a must be > 0).
    static func decrement(_ a: [UInt8]) -> [UInt8] {
        var bytes = a
        var i = bytes.count - 1
        while i >= 0 {
            if bytes[i] > 0 { bytes[i] -= 1; break }
            bytes[i] = 0xFF
            i -= 1
        }
        return normalized(bytes)
    }

    /// big-endian `a` mod `m`.
    static func mod(_ a: [UInt8], _ m: [UInt8]) -> [UInt8] {
        let modulus = normalized(m)
        precondition(!isZero(modulus), "mod by zero")
        var r: [UInt8] = [0]
        for byte in a {
            for bit in stride(from: 7, through: 0, by: -1) {
                shiftLeftOne(&r)
                if (byte >> UInt8(bit)) & 1 == 1 { r[r.count - 1] |= 1 }
                if compare(r, modulus) >= 0 { r = subtract(r, modulus) }
            }
        }
        return normalized(r)
    }

    // MARK: helpers

    static func normalized(_ a: [UInt8]) -> [UInt8] {
        var bytes = a
        while bytes.count > 1 && bytes.first == 0 { bytes.removeFirst() }
        return bytes.isEmpty ? [0] : bytes
    }

    static func isZero(_ a: [UInt8]) -> Bool { a.allSatisfy { $0 == 0 } }

    static func shiftLeftOne(_ a: inout [UInt8]) {
        var carry: UInt8 = 0
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            let next = a[i] >> 7
            a[i] = (a[i] << 1) | carry
            carry = next
        }
        if carry == 1 { a.insert(1, at: 0) }
    }

    static func compare(_ a: [UInt8], _ b: [UInt8]) -> Int {
        let x = normalized(a), y = normalized(b)
        if x.count != y.count { return x.count < y.count ? -1 : 1 }
        for i in 0..<x.count where x[i] != y[i] { return x[i] < y[i] ? -1 : 1 }
        return 0
    }

    /// a − b, requires a >= b. big-endian.
    static func subtract(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
        var result = a
        var borrow = 0
        var ai = result.count - 1
        var bi = b.count - 1
        while ai >= 0 {
            let bv = bi >= 0 ? Int(b[bi]) : 0
            var diff = Int(result[ai]) - bv - borrow
            if diff < 0 { diff += 256; borrow = 1 } else { borrow = 0 }
            result[ai] = UInt8(diff)
            ai -= 1; bi -= 1
        }
        return normalized(result)
    }
}
