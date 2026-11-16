// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// The middle layer of the three-layer rendering split (plan D41):
//
//   content transforms   what characters are in the text   parser Options
//   presentation rules   how each role looks, in neutral    THIS FILE
//                        units (em, multiples, roles)
//   platform realisation which font, colour and paragraph   UIKit / Compose
//                        APIs implement the rules           adapters
//
// The test for where a setting belongs: if it changes characters or offsets it
// is a parser option; if it changes only appearance it is a rule here. Rules
// are plain Codable data with no fonts, no colours and no platform types, so
// iOS and Android read the same sheet, a host can override single roles, and
// the *resolution* of a chapter against a sheet is ordinary portable code that
// is tested here rather than once per platform.

import Foundation

public struct ScriptureStyleSheet: Equatable, Sendable, Codable {

    public enum Alignment: String, Sendable, Codable {
        case leading, center, trailing
    }

    /// A colour by purpose; the platform theme decides the actual colour (and
    /// its night-mode variant).
    public enum ColorRole: String, Sendable, Codable {
        case text, marker, redLetter, link
    }

    /// How one paragraph role looks. Lengths are in em (multiples of the body
    /// size), so one sheet serves every font size.
    public struct Block: Equatable, Sendable, Codable {
        public var sizeScale: Double
        public var bold: Bool
        public var italic: Bool
        public var alignment: Alignment
        /// Indent of the first line from the leading edge.
        public var firstLineIndent: Double
        /// Indent of wrapped lines from the leading edge.
        public var wrapIndent: Double
        /// Space above the paragraph, dropped when it directly follows a
        /// paragraph of the same role (consecutive headings).
        public var spaceBefore: Double
        /// Space below the paragraph. Between two blocks the gap is the larger of the
        /// first's space below and the second's space above, not their sum.
        public var spaceAfter: Double

        public init(sizeScale: Double = 1, bold: Bool = false, italic: Bool = false,
                    alignment: Alignment = .leading, firstLineIndent: Double = 0,
                    wrapIndent: Double = 0, spaceBefore: Double = 0, spaceAfter: Double = 0) {
            self.sizeScale = sizeScale
            self.bold = bold
            self.italic = italic
            self.alignment = alignment
            self.firstLineIndent = firstLineIndent
            self.wrapIndent = wrapIndent
            self.spaceBefore = spaceBefore
            self.spaceAfter = spaceAfter
        }

        private enum CodingKeys: String, CodingKey {
            case sizeScale, bold, italic, alignment, firstLineIndent, wrapIndent, spaceBefore, spaceAfter
        }

        /// `spaceAfter` is newer than the other rules: a sheet saved without it still loads.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            sizeScale = try c.decode(Double.self, forKey: .sizeScale)
            bold = try c.decode(Bool.self, forKey: .bold)
            italic = try c.decode(Bool.self, forKey: .italic)
            alignment = try c.decode(Alignment.self, forKey: .alignment)
            firstLineIndent = try c.decode(Double.self, forKey: .firstLineIndent)
            wrapIndent = try c.decode(Double.self, forKey: .wrapIndent)
            spaceBefore = try c.decode(Double.self, forKey: .spaceBefore)
            spaceAfter = try c.decodeIfPresent(Double.self, forKey: .spaceAfter) ?? 0.0
        }
    }

    /// A raised, smaller run: verse numbers, Strong's and morphology markers,
    /// footnote markers.
    public struct Superscript: Equatable, Sendable, Codable {
        public var sizeScale: Double
        /// Baseline raise, in em.
        public var raise: Double
        public var italic: Bool
        public var color: ColorRole

        public init(sizeScale: Double, raise: Double, italic: Bool, color: ColorRole) {
            self.sizeScale = sizeScale
            self.raise = raise
            self.italic = italic
            self.color = color
        }
    }

    /// Per-role rules. A role missing here uses a plain `Block()`.
    public var blocks: [ParagraphRole: Block]
    /// Line height as a multiple of the font size.
    public var lineHeight: Double
    public var verseNumber: Superscript
    /// Strong's and morphology marker runs.
    public var lexicalMarker: Superscript
    public var footnoteMarker: Superscript
    /// Size of `small` text, as a multiple of the body size.
    public var smallScale: Double
    /// The divine name is set as a full-size first letter followed by smaller capitals
    /// (LORD); this is the size of the smaller letters, as a multiple of the body size.
    public var divineNameScale: Double

    public init(blocks: [ParagraphRole: Block], lineHeight: Double, verseNumber: Superscript,
                lexicalMarker: Superscript, footnoteMarker: Superscript, smallScale: Double,
                divineNameScale: Double = 0.85) {
        self.divineNameScale = divineNameScale
        self.blocks = blocks
        self.lineHeight = lineHeight
        self.verseNumber = verseNumber
        self.lexicalMarker = lexicalMarker
        self.footnoteMarker = footnoteMarker
        self.smallScale = smallScale
    }

    public func block(for role: ParagraphRole) -> Block {
        blocks[role] ?? Block()
    }

    // MARK: Presets

    /// PocketSword's look: the legacy CSS contract (superscript verse numbers
    /// at 70%, gray italic Strong's, bold headings at 1.1 / 1.05 / 1.0 em)
    /// plus role rules informed by ethnosdev/scripture's USFM defaults
    /// (plan §11): poetry is indented by its level and wraps flush with its
    /// first line (a hanging indent made long lines look misplaced),
    /// headings are set apart, Selah is a trailing-aligned aside.
    public static let classic: ScriptureStyleSheet = {
        let heading = 0.6
        // The web view sets headings in paragraphs with a margin above and below.
        func titled(_ block: Block) -> Block {
            var b = block
            b.spaceBefore = heading
            b.spaceAfter = heading
            return b
        }
        let blocks: [ParagraphRole: Block] = [
            .mt: titled(Block(sizeScale: 1.1, bold: true, alignment: .center, spaceBefore: heading)),
            .cl: titled(Block(sizeScale: 1.05, bold: true, spaceBefore: heading)),
            .ms: titled(Block(sizeScale: 1.05, bold: true, spaceBefore: heading)),
            // The legacy web view sets every heading bold and left-aligned, scope and parallel lines included.
            .mr: Block(bold: true),
            .s1: titled(Block(bold: true, spaceBefore: heading)),
            .s2: titled(Block(italic: true, spaceBefore: heading)),
            .r: Block(bold: true),
            // A psalm's superscription: bold like every heading in the legacy web view.
            .d: titled(Block(bold: true, spaceBefore: heading)),
            .qa: titled(Block(bold: true, spaceBefore: heading)),   // legacy: left, like every heading
            .sp: titled(Block(italic: true, spaceBefore: heading)),
            .q1: Block(firstLineIndent: 1, wrapIndent: 1),
            .q2: Block(firstLineIndent: 2, wrapIndent: 2),
            .q3: Block(firstLineIndent: 3, wrapIndent: 3),
            .q4: Block(firstLineIndent: 4, wrapIndent: 4),
            .qr: Block(italic: true, alignment: .trailing),
            .li1: Block(firstLineIndent: 1, wrapIndent: 1),
            .li2: Block(firstLineIndent: 2, wrapIndent: 2),
            .ip: Block(),
            .io: Block(firstLineIndent: 1, wrapIndent: 1),
        ]
        return ScriptureStyleSheet(
            blocks: blocks,
            lineHeight: 1.4,
            verseNumber: Superscript(sizeScale: 0.7, raise: 0.33, italic: false, color: .text),
            // The legacy CSS sets `a.strongs` to 70% inside `<small>` (about 83%), so the numbers
            // measure about 58% of the body size on screen.
            lexicalMarker: Superscript(sizeScale: 0.58, raise: 0.33, italic: true, color: .marker),
            footnoteMarker: Superscript(sizeScale: 0.7, raise: 0.33, italic: false, color: .marker),
            smallScale: 0.9)
    }()

    // MARK: Codable (roles are keyed by their USFM names)

    private enum CodingKeys: String, CodingKey {
        case blocks, lineHeight, verseNumber, lexicalMarker, footnoteMarker, smallScale, divineNameScale
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode([String: Block].self, forKey: .blocks)
        // Unknown role names are ignored, so a newer sheet still loads in an older reader.
        var decoded: [ParagraphRole: Block] = [:]
        for (key, value) in raw {
            if let role = ParagraphRole(rawValue: key) { decoded[role] = value }
        }
        blocks = decoded
        lineHeight = try c.decode(Double.self, forKey: .lineHeight)
        verseNumber = try c.decode(Superscript.self, forKey: .verseNumber)
        lexicalMarker = try c.decode(Superscript.self, forKey: .lexicalMarker)
        footnoteMarker = try c.decode(Superscript.self, forKey: .footnoteMarker)
        smallScale = try c.decode(Double.self, forKey: .smallScale)
        divineNameScale = try c.decodeIfPresent(Double.self, forKey: .divineNameScale) ?? 0.85
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Dictionary(uniqueKeysWithValues: blocks.map { ($0.key.rawValue, $0.value) }), forKey: .blocks)
        try c.encode(lineHeight, forKey: .lineHeight)
        try c.encode(verseNumber, forKey: .verseNumber)
        try c.encode(lexicalMarker, forKey: .lexicalMarker)
        try c.encode(footnoteMarker, forKey: .footnoteMarker)
        try c.encode(smallScale, forKey: .smallScale)
        try c.encode(divineNameScale, forKey: .divineNameScale)
    }
}

// MARK: - Resolution against a chapter

/// One paragraph of a parsed chapter with its rules applied: what a platform
/// adapter needs to build a paragraph style, with nothing left to decide.
public struct ResolvedBlock: Equatable, Sendable {
    public var start: Int
    public var length: Int
    public var role: ParagraphRole
    public var style: ScriptureStyleSheet.Block
    /// The space above, after the same-role rule: zero when this block directly
    /// follows a block of the same role.
    public var spaceBefore: Double
    /// The space below, after the same rules: zero when a block of the same role
    /// follows directly, and the space above the next block takes over when it is larger.
    public var spaceAfter: Double

    public init(start: Int, length: Int, role: ParagraphRole,
                style: ScriptureStyleSheet.Block, spaceBefore: Double, spaceAfter: Double = 0) {
        self.spaceAfter = spaceAfter
        self.start = start
        self.length = length
        self.role = role
        self.style = style
        self.spaceBefore = spaceBefore
    }
}

extension ScriptureStyleSheet {

    /// Every role paragraph of `scripture`, in order, with this sheet's rules.
    /// This is where "no gap between consecutive headings of the same role"
    /// lives, once, for every platform.
    public func resolveBlocks(in scripture: ScriptureText) -> [ResolvedBlock] {
        var result: [ResolvedBlock] = []
        var previousEnd = -1
        for span in scripture.spans {
            guard case .block(let role) = span.attribute else { continue }
            let style = block(for: role)
            var block = ResolvedBlock(start: span.start, length: span.length, role: role, style: style,
                                      spaceBefore: style.spaceBefore, spaceAfter: style.spaceAfter)
            // Directly following: only the paragraph's "\n" lies between the two.
            if let last = result.last, previousEnd + 1 == span.start {
                if last.role == role {
                    block.spaceBefore = 0
                    result[result.count - 1].spaceAfter = 0
                } else {
                    // One gap, the larger of the two, carried by the space below the first.
                    let gap = max(last.spaceAfter, block.spaceBefore)
                    result[result.count - 1].spaceAfter = gap
                    block.spaceBefore = 0
                }
            }
            result.append(block)
            previousEnd = span.start + span.length
        }
        return result
    }
}
