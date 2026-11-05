import Foundation

struct OpenBotLossyArray<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: any Decoder) throws {
        var values = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !values.isAtEnd {
            let elementDecoder = try values.superDecoder()
            if let element = try? Element(from: elementDecoder) { elements.append(element) }
        }
        self.elements = elements
    }
}
