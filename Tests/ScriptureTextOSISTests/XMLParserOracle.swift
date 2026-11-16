// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import ScriptureText
@testable import ScriptureTextOSIS
import ScriptureTextMarkup

// A test-only oracle (plan D32): Foundation's XMLParser reads the same input as
// OSISTokenizer and the two event streams must agree. XMLParser is never part
// of the shipped package — it is only used here, as an independent check that
// the hand-written tokenizer is not making things up.
//
// The streams are compared in a *canonical* form, because the two parsers
// legitimately report some things differently:
//  • XMLParser cannot tell `<x/>` from `<x></x>` (both are start + end), so a
//    self-closing start is expanded to start + end on the tokenizer side;
//  • XMLParser delivers text in arbitrary chunks, so adjacent text events are
//    merged on both sides;
//  • XML normalises CR and CRLF line endings to LF; the tokenizer is applied
//    the same normalisation here.
// Known, accepted divergence: input that is not well-formed XML (XMLParser
// stops; the tokenizer degrades to text) and entities other than the five
// predefined ones (XMLParser errors; the tokenizer passes them through).

typealias OracleEvent = RecordingSink.Event

/// Collects XMLParser events, unwrapping the synthetic root element.
private final class OracleDelegate: NSObject, XMLParserDelegate {
    var events: [OracleEvent] = []
    private var depth = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if depth > 0 { events.append(.start(elementName, attributeDict, selfClosing: false)) }
        depth += 1
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        depth -= 1
        if depth > 0 { events.append(.end(elementName)) }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if depth > 0 { events.append(.text(string)) }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if depth > 0 { events.append(.text(String(decoding: CDATABlock, as: UTF8.self))) }
    }
}

enum XMLParserOracle {

    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    /// XMLParser's view of `fragment` (wrapped in a root element), canonicalised.
    static func events(of fragment: String) throws -> [OracleEvent] {
        let xml = "<oracleRoot>" + fragment + "</oracleRoot>"
        let parser = XMLParser(data: Data(xml.utf8))
        let delegate = OracleDelegate()
        parser.delegate = delegate
        guard parser.parse() else {
            let line = parser.lineNumber, column = parser.columnNumber
            throw Failure(description: "XMLParser rejected the input at \(line):\(column): \(parser.parserError?.localizedDescription ?? "unknown")")
        }
        return canonical(delegate.events)
    }

    /// OSISTokenizer's view of `fragment`, canonicalised.
    static func tokenizerEvents(of fragment: String) -> [OracleEvent] {
        var sink = RecordingSink()
        MarkupTokenizer.tokenize(fragment, into: &sink)
        return canonical(sink.events)
    }

    /// Both streams reduced to the same shape (see the file comment).
    static func canonical(_ events: [OracleEvent]) -> [OracleEvent] {
        var out: [OracleEvent] = []
        func appendText(_ raw: String) {
            let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            guard !text.isEmpty else { return }
            if case .text(let previous)? = out.last {
                out[out.count - 1] = .text(previous + text)
            } else {
                out.append(.text(text))
            }
        }
        for event in events {
            switch event {
            case .text(let t):
                appendText(t)
            case .start(let name, let attributes, let selfClosing):
                out.append(.start(name, attributes, selfClosing: false))
                if selfClosing { out.append(.end(name)) }
            case .end:
                out.append(event)
            }
        }
        return out
    }

    /// The first point where two canonical streams differ, with context, or nil.
    static func firstDifference(_ a: [OracleEvent], _ b: [OracleEvent]) -> String? {
        let n = min(a.count, b.count)
        for i in 0..<n where a[i] != b[i] {
            return "event \(i): tokenizer \(describe(a[safe: i])) vs XMLParser \(describe(b[safe: i]))"
        }
        if a.count != b.count {
            return "stream length: tokenizer \(a.count) vs XMLParser \(b.count); next \(describe(a[safe: n])) / \(describe(b[safe: n]))"
        }
        return nil
    }

    private static func describe(_ event: OracleEvent?) -> String {
        guard let event else { return "∅" }
        let s = "\(event)"
        return s.count > 120 ? String(s.prefix(120)) + "…" : s
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
