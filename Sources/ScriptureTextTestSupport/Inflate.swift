// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// A small zlib reader (RFC 1950 wrapping RFC 1951), so that the tests can read a SWORD module's compressed
// blocks on any platform Swift runs on, without a system library. It follows the structure of zlib's own
// `puff.c` reference decoder: correct and short, not fast. Test support only.

import Foundation

public enum Inflate {

    public struct Failure: Error, CustomStringConvertible {
        public let description: String
        init(_ description: String) { self.description = description }
    }

    /// Decompresses a zlib stream (a two byte header, deflate data, an Adler-32 checksum that is not checked).
    public static func zlib(_ data: Data) throws -> Data {
        guard data.count >= 2 else { throw Failure("zlib stream too short") }
        guard data[data.startIndex] & 0x0F == 8 else { throw Failure("not a deflate stream") }
        return try raw(data.dropFirst(2))
    }

    /// Decompresses raw deflate data.
    public static func raw<D: DataProtocol>(_ data: D) throws -> Data {
        var state = State(bytes: Array(data))
        try state.run()
        return Data(state.output)
    }

    // MARK: Decoder

    private struct Huffman {
        var counts = [Int](repeating: 0, count: 16)
        var symbols: [Int] = []

        init(lengths: [Int]) {
            symbols = [Int](repeating: 0, count: lengths.count)
            for length in lengths { counts[length] += 1 }
            var offsets = [Int](repeating: 0, count: 16)
            for i in 1..<15 { offsets[i + 1] = offsets[i] + counts[i] }
            for (symbol, length) in lengths.enumerated() where length != 0 {
                symbols[offsets[length]] = symbol
                offsets[length] += 1
            }
        }
    }

    private static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    private static let distanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

    private struct State {
        let bytes: [UInt8]
        var position = 0
        var bitBuffer = 0
        var bitCount = 0
        var output: [UInt8] = []

        init(bytes: [UInt8]) { self.bytes = bytes }

        mutating func bits(_ need: Int) throws -> Int {
            var value = bitBuffer
            while bitCount < need {
                guard position < bytes.count else { throw Failure("unexpected end of data") }
                value |= Int(bytes[position]) << bitCount
                position += 1
                bitCount += 8
            }
            bitBuffer = value >> need
            bitCount -= need
            return value & ((1 << need) - 1)
        }

        mutating func decode(_ h: Huffman) throws -> Int {
            var code = 0, first = 0, index = 0
            for length in 1...15 {
                code |= try bits(1)
                let count = h.counts[length]
                if code - count < first { return h.symbols[index + (code - first)] }
                index += count
                first += count
                first <<= 1
                code <<= 1
            }
            throw Failure("bad code")
        }

        mutating func run() throws {
            var last = false
            while !last {
                last = try bits(1) == 1
                switch try bits(2) {
                case 0: try stored()
                case 1: try codes(Self.fixedLiteral, Self.fixedDistance)
                case 2: try dynamic()
                default: throw Failure("bad block type")
                }
            }
        }

        mutating func stored() throws {
            bitBuffer = 0
            bitCount = 0
            guard position + 4 <= bytes.count else { throw Failure("truncated stored block") }
            let length = Int(bytes[position]) | Int(bytes[position + 1]) << 8
            let inverse = Int(bytes[position + 2]) | Int(bytes[position + 3]) << 8
            guard length == (~inverse & 0xFFFF) else { throw Failure("stored block length mismatch") }
            position += 4
            guard position + length <= bytes.count else { throw Failure("truncated stored block") }
            output.append(contentsOf: bytes[position..<(position + length)])
            position += length
        }

        static let fixedLiteral: Huffman = {
            var lengths = [Int](repeating: 8, count: 288)
            for i in 144..<256 { lengths[i] = 9 }
            for i in 256..<280 { lengths[i] = 7 }
            return Huffman(lengths: lengths)
        }()
        static let fixedDistance = Huffman(lengths: [Int](repeating: 5, count: 30))

        mutating func dynamic() throws {
            let literalCount = try bits(5) + 257
            let distanceCount = try bits(5) + 1
            let codeLengthCount = try bits(4) + 4
            guard literalCount <= 286, distanceCount <= 30 else { throw Failure("bad counts") }
            let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
            var lengths = [Int](repeating: 0, count: 19)
            for i in 0..<codeLengthCount { lengths[order[i]] = try bits(3) }
            let lengthCode = Huffman(lengths: lengths)
            var all: [Int] = []
            while all.count < literalCount + distanceCount {
                let symbol = try decode(lengthCode)
                if symbol < 16 {
                    all.append(symbol)
                } else {
                    var repeatValue = 0, repeatCount = 0
                    switch symbol {
                    case 16:
                        guard let previous = all.last else { throw Failure("repeat with no previous length") }
                        repeatValue = previous
                        repeatCount = 3 + (try bits(2))
                    case 17: repeatCount = 3 + (try bits(3))
                    default: repeatCount = 11 + (try bits(7))
                    }
                    guard all.count + repeatCount <= literalCount + distanceCount else { throw Failure("too many lengths") }
                    all.append(contentsOf: [Int](repeating: repeatValue, count: repeatCount))
                }
            }
            try codes(Huffman(lengths: Array(all[0..<literalCount])), Huffman(lengths: Array(all[literalCount...])))
        }

        mutating func codes(_ literal: Huffman, _ distance: Huffman) throws {
            while true {
                let symbol = try decode(literal)
                if symbol < 256 {
                    output.append(UInt8(symbol))
                } else if symbol == 256 {
                    return
                } else {
                    let s = symbol - 257
                    guard s < 29 else { throw Failure("bad length symbol") }
                    let length = Inflate.lengthBase[s] + (try bits(Inflate.lengthExtra[s]))
                    let d = try decode(distance)
                    guard d < 30 else { throw Failure("bad distance symbol") }
                    let back = Inflate.distanceBase[d] + (try bits(Inflate.distanceExtra[d]))
                    guard back <= output.count else { throw Failure("distance too far back") }
                    for _ in 0..<length { output.append(output[output.count - back]) }
                }
            }
        }
    }
}
