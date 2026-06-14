import Foundation

/// SSH binary wire format (RFC 4251 §5): byte / uint32 / length-prefixed string
/// / mpint. Used by the OpenSSH private-key container, public-key blobs, agent
/// protocol messages, and signature encodings.
struct SSHWireWriter {
    private(set) var data = Data()

    mutating func writeByte(_ value: UInt8) { data.append(value) }

    mutating func writeUInt32(_ value: UInt32) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    mutating func writeString(_ bytes: Data) {
        writeUInt32(UInt32(bytes.count))
        data.append(bytes)
    }

    mutating func writeString(_ string: String) {
        writeString(Data(string.utf8))
    }

    /// mpint: big-endian two's-complement integer; a leading 0x00 is prepended
    /// when the high bit is set so the value stays positive.
    mutating func writeMPInt(_ magnitude: Data) {
        let trimmed = Data(magnitude.drop { $0 == 0 })
        if trimmed.isEmpty { writeUInt32(0); return }
        if trimmed.first! & 0x80 != 0 {
            writeString(Data([0]) + trimmed)
        } else {
            writeString(trimmed)
        }
    }
}

enum SSHWireError: Error, Equatable {
    case truncated
    case unsupportedKeyType(String)
    case malformedKey
    case encryptedKeyUnsupported
}

struct SSHWireReader {
    private let data: Data
    private var offset: Int

    init(_ data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    var isAtEnd: Bool { offset >= data.endIndex }

    mutating func readByte() throws -> UInt8 {
        guard offset < data.endIndex else { throw SSHWireError.truncated }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readUInt32() throws -> UInt32 {
        guard offset + 4 <= data.endIndex else { throw SSHWireError.truncated }
        var value: UInt32 = 0
        for index in offset..<offset + 4 { value = (value << 8) | UInt32(data[index]) }
        offset += 4
        return value
    }

    mutating func readString() throws -> Data {
        let length = Int(try readUInt32())
        guard length >= 0, offset + length <= data.endIndex else { throw SSHWireError.truncated }
        defer { offset += length }
        return Data(data[offset..<offset + length])
    }

    mutating func readStringUTF8() throws -> String {
        String(decoding: try readString(), as: UTF8.self)
    }
}
