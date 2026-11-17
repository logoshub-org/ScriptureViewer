// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// What the parsers build their output in: text and lists that grow in place. In Swift they are a string and an array and nothing
// more. In the Kotlin that Skip makes of the core, a string cannot grow in place (`+=` copies all of it) and an array held as a
// stored property is copied whole at each `append`, which made a chapter's parse ten times slower (see the speed rules in
// Transpile/README.md); there they are a `StringBuilder` and a Java list. Classes, so that holding one never copies it.

/// Text that grows at its end, measured in UTF-16 code units (the model's offsets).
public final class TextBuffer {
    #if SKIP
    private let builder: java.lang.StringBuilder = java.lang.StringBuilder()
    #else
    private var string = ""
    private var units = 0
    #endif

    public init() {}

    /// Its length in UTF-16 code units.
    public var length: Int {
        #if SKIP
        return builder.length
        #else
        return units
        #endif
    }

    public var isEmpty: Bool { length == 0 }

    public func append(_ s: String) {
        #if SKIP
        let builder = self.builder.append(s)    // kept, so this stays a statement in Kotlin (append returns the builder)
        #else
        string += s
        units += s.utf16.count
        #endif
    }

    /// The UTF-16 code unit at `offset`, or nil outside the text.
    public func unit(at offset: Int) -> Int? {
        guard offset >= 0, offset < length else { return nil }
        #if SKIP
        return builder.get(offset).code
        #else
        let u = string.utf16
        return Int(u[u.index(u.startIndex, offsetBy: offset)])
        #endif
    }

    /// The last UTF-16 code unit, or nil when empty.
    public var lastUnit: Int? { unit(at: length - 1) }

    /// Whether the text ends with `suffix`.
    public func hasSuffix(_ suffix: String) -> Bool {
        let units = CodePoints.utf16(suffix)
        let count = length
        guard units.count <= count else { return false }
        var k = 0
        while k < units.count {
            if unit(at: count - units.count + k) != units[k] { return false }
            k += 1
        }
        return true
    }

    /// The text between two UTF-16 offsets (clamped to the text).
    public func substring(from start: Int, to end: Int) -> String {
        let from = max(0, min(start, length))
        let to = max(from, min(end, length))
        #if SKIP
        return builder.substring(from, to)
        #else
        let u = string.utf16
        let a = u.index(u.startIndex, offsetBy: from)
        let b = u.index(a, offsetBy: to - from)
        return String(u[a..<b]) ?? String(decoding: Array(u[a..<b]), as: UTF16.self)
        #endif
    }

    /// Removes ASCII code units (spaces, line ends) from the end while `drop` says so; returns how many went. `drop` is asked only
    /// about units below 0x80, so it never splits a character.
    @discardableResult
    public func dropTrailingASCII(where drop: (Int) -> Bool) -> Int {
        var removed = 0
        while let last = lastUnit, last < 0x80, drop(last) {
            #if SKIP
            builder.setLength(builder.length - 1)
            #else
            string.unicodeScalars.removeLast()
            units -= 1
            #endif
            removed += 1
        }
        return removed
    }

    /// All of it.
    public var text: String {
        #if SKIP
        return builder.toString()
        #else
        return string
        #endif
    }
}

/// A list that grows in place: an array in Swift, a Java list in Kotlin.
public final class GrowingList<Element> {
    #if SKIP
    private let items: java.util.ArrayList<Element> = java.util.ArrayList<Element>()
    #else
    private var items: [Element] = []
    #endif

    public init() {}

    public var count: Int {
        #if SKIP
        return items.size
        #else
        return items.count
        #endif
    }

    public var isEmpty: Bool { count == 0 }

    public func append(_ element: Element) {
        #if SKIP
        items.add(items.size, element)      // the form that returns nothing, so this stays a statement in Kotlin
        #else
        items.append(element)
        #endif
    }

    public subscript(index: Int) -> Element {
        get {
            #if SKIP
            return items.get(index)
            #else
            return items[index]
            #endif
        }
        set {
            #if SKIP
            let replaced = items.set(index, newValue)
            #else
            items[index] = newValue
            #endif
        }
    }

    public func insert(_ element: Element, at index: Int) {
        #if SKIP
        items.add(index, element)
        #else
        items.insert(element, at: index)
        #endif
    }

    public func remove(at index: Int) {
        #if SKIP
        let removed = items.removeAt(index)
        #else
        items.remove(at: index)
        #endif
    }

    /// Everything gathered, in order.
    public func elements() -> [Element] {
        #if SKIP
        return Array<Element>(items, nocopy: true)
        #else
        return items
        #endif
    }
}
