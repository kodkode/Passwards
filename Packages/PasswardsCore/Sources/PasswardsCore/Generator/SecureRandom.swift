import Foundation
import Security

enum SecureRandom {
    /// Uniform integer in 0..<upperBound via rejection sampling.
    static func int(below upperBound: Int) -> Int {
        precondition(upperBound > 0 && upperBound <= Int(UInt32.max))
        let bound = UInt32(upperBound)
        let limit = UInt32.max - (UInt32.max % bound)
        while true {
            var value: UInt32 = 0
            let status = withUnsafeMutableBytes(of: &value) {
                SecRandomCopyBytes(kSecRandomDefault, 4, $0.baseAddress!)
            }
            guard status == errSecSuccess else { continue }
            if value < limit { return Int(value % bound) }
        }
    }

    static func element<C: RandomAccessCollection>(of collection: C) -> C.Element where C.Index == Int {
        collection[collection.startIndex + int(below: collection.count)]
    }

    /// Fisher–Yates shuffle with the CSPRNG.
    static func shuffle<T>(_ array: inout [T]) {
        guard array.count > 1 else { return }
        for i in stride(from: array.count - 1, to: 0, by: -1) {
            array.swapAt(i, int(below: i + 1))
        }
    }
}
