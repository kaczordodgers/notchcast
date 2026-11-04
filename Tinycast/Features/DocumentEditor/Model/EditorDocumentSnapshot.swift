import Foundation

struct EditorDocumentSnapshot: Sendable {
    let bytes: Data
    let source: String
    let encoding: String.Encoding
    let byteOrderMark: Data

    init(bytes: Data) throws {
        let formats: [(Data, String.Encoding)] = [
            (Data([0xEF, 0xBB, 0xBF]), .utf8),
            (Data([0xFF, 0xFE]), .utf16LittleEndian),
            (Data([0xFE, 0xFF]), .utf16BigEndian)
        ]
        let format = formats.first { bytes.starts(with: $0.0) }
        let mark = format?.0 ?? Data()
        let payload = bytes.dropFirst(mark.count)
        let encoding = format?.1 ?? (Self.decode(Data(payload), using: .utf8) != nil ? .utf8 : .windowsCP1250)
        guard let source = Self.decode(Data(payload), using: encoding),
            let roundTrip = source.data(using: encoding, allowLossyConversion: false),
            roundTrip == payload
        else { throw EditorFailure.invalidEncoding }
        self.bytes = bytes
        self.source = source
        self.encoding = encoding
        byteOrderMark = mark
    }

    func encoded(_ source: String) throws -> Data {
        if source.utf8.elementsEqual(self.source.utf8) { return bytes }
        guard let payload = source.data(using: encoding, allowLossyConversion: false),
            let decoded = Self.decode(payload, using: encoding),
            decoded.utf8.elementsEqual(source.utf8)
        else { throw EditorFailure.invalidEncoding }
        return byteOrderMark + payload
    }

    private static func decode(_ bytes: Data, using encoding: String.Encoding) -> String? {
        encoding == .utf8 ? String(validating: bytes, as: UTF8.self) : String(bytes: bytes, encoding: encoding)
    }
}
