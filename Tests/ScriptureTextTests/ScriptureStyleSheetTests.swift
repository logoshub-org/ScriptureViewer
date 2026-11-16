// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import ScriptureText

// The presentation-rules layer (plan D41), tested on hand-built text so it
// needs no parser: this is the part both platforms share.

struct ScriptureStyleSheetTests {

    @Test func theClassicSheetDefinesEveryRole() {
        for role in ParagraphRole.allCases {
            #expect(ScriptureStyleSheet.classic.blocks[role] != nil, "\(role)")
        }
    }

    @Test func poetryIsIndentedByLevel() {
        let sheet = ScriptureStyleSheet.classic
        let levels = [ParagraphRole.q1, .q2, .q3, .q4].map { sheet.block(for: $0).firstLineIndent }
        #expect(levels == levels.sorted() && Set(levels).count == 4)
        #expect(sheet.block(for: .q1).firstLineIndent < sheet.block(for: .q2).firstLineIndent)
        #expect(sheet.block(for: .qr).alignment == .trailing)
        #expect(sheet.block(for: .mt).alignment == .center)
        #expect(sheet.block(for: .s1).bold)
    }

    @Test func aMissingRoleFallsBackToPlainParagraphRules() {
        var sheet = ScriptureStyleSheet.classic
        sheet.blocks[.ip] = nil
        #expect(sheet.block(for: .ip) == ScriptureStyleSheet.Block())
    }

    @Test func aHostCanOverrideASingleRole() {
        var sheet = ScriptureStyleSheet.classic
        sheet.blocks[.q1] = .init(firstLineIndent: 2, wrapIndent: 2)
        #expect(sheet.block(for: .q1).wrapIndent == 2)
        #expect(sheet.block(for: .q2) == ScriptureStyleSheet.classic.block(for: .q2))
    }

    // MARK: Codable

    @Test func theSheetRoundTripsThroughJSONWithRolesKeyedByUSFMName() throws {
        let data = try JSONEncoder().encode(ScriptureStyleSheet.classic)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"q1\"") && json.contains("\"s1\""))
        #expect(try JSONDecoder().decode(ScriptureStyleSheet.self, from: data) == .classic)
    }

    @Test func unknownRoleNamesInASheetAreIgnored() throws {
        var object = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(ScriptureStyleSheet.classic)) as? [String: Any])
        var blocks = try #require(object["blocks"] as? [String: Any])
        blocks["zz-future-role"] = blocks["q1"]
        object["blocks"] = blocks
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(ScriptureStyleSheet.self, from: data) == .classic)
    }

    // MARK: Resolution

    private func chapter(_ blocks: [(ParagraphRole, Int, Int)], length: Int = 100) -> ScriptureText {
        ScriptureText(text: String(repeating: "x", count: length),
                      spans: blocks.map { .init(start: $0.1, length: $0.2, attribute: .block($0.0)) })
    }

    @Test func resolvedBlocksCarryTheirRulesInOrder() {
        let m = chapter([(.s1, 0, 10), (.q1, 11, 20), (.qr, 32, 5)])
        let resolved = ScriptureStyleSheet.classic.resolveBlocks(in: m)
        #expect(resolved.map(\.role) == [.s1, .q1, .qr])
        #expect(resolved.map(\.start) == [0, 11, 32])
        #expect(resolved[1].style == ScriptureStyleSheet.classic.block(for: .q1))
    }

    @Test func consecutiveHeadingsOfTheSameRoleHaveNoGapBetweenThem() {
        // ethnosdev/scripture: "don't add vertical space between consecutive same title headings".
        let m = chapter([(.s1, 0, 10), (.s1, 11, 10), (.s2, 22, 5), (.s1, 28, 5)])
        let blocks = ScriptureStyleSheet.classic.resolveBlocks(in: m)
        let s1 = ScriptureStyleSheet.classic.block(for: .s1)
        #expect(blocks.map(\.spaceBefore) == [s1.spaceBefore, 0, 0, 0])
        // The two s1 touch; where the role changes there is one gap, carried below the first.
        #expect(blocks.map(\.spaceAfter) == [0, s1.spaceAfter, s1.spaceAfter, s1.spaceAfter])
    }

    @Test func betweenDifferentBlocksTheGapIsTheLargerOfTheTwoNotTheirSum() {
        var sheet = ScriptureStyleSheet.classic
        sheet.blocks[.s1] = .init(spaceBefore: 0.4, spaceAfter: 0.9)
        sheet.blocks[.q1] = .init(spaceBefore: 0.5)
        let blocks = sheet.resolveBlocks(in: chapter([(.s1, 0, 5), (.q1, 6, 5)]))
        #expect(blocks[0].spaceAfter == 0.9)
        #expect(blocks[1].spaceBefore == 0)
    }

    @Test func everyHeadingRoleIsLeftAlignedAndBoldLikeTheLegacyWebView() {
        for role in [ParagraphRole.cl, .ms, .mr, .s1, .r, .d, .qa] {   // only the book title (mt) is centred
            let block = ScriptureStyleSheet.classic.block(for: role)
            #expect(block.alignment == .leading, "\(role)")
            #expect(block.bold || block.italic, "\(role)")
        }
        #expect(ScriptureStyleSheet.classic.block(for: .mr).bold)
        #expect(ScriptureStyleSheet.classic.block(for: .r).bold)
    }

    @Test func aSheetSavedWithoutSpaceAfterOrDivineNameScaleStillLoads() throws {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(ScriptureStyleSheet.classic)) as? [String: Any])
        object.removeValue(forKey: "divineNameScale")
        var blocks = try #require(object["blocks"] as? [String: [String: Any]])
        for key in blocks.keys { blocks[key]?.removeValue(forKey: "spaceAfter") }
        object["blocks"] = blocks
        let sheet = try JSONDecoder().decode(ScriptureStyleSheet.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(sheet.divineNameScale == 0.85)
        #expect(sheet.block(for: .s1).spaceAfter == 0)
    }

    @Test func aGapOfTextBetweenSameRoleBlocksKeepsTheSpace() {
        let m = chapter([(.s1, 0, 10), (.s1, 40, 10)])      // prose lies between
        let space = ScriptureStyleSheet.classic.resolveBlocks(in: m).map(\.spaceBefore)
        #expect(space[1] == ScriptureStyleSheet.classic.block(for: .s1).spaceBefore)
    }

    @Test func nonBlockSpansAreIgnored() {
        let m = ScriptureText(text: "abc", spans: [.init(start: 0, length: 3, attribute: .italic)])
        #expect(ScriptureStyleSheet.classic.resolveBlocks(in: m).isEmpty)
    }
}

extension ScriptureStyleSheetTests {
    @Test func aWrappedLineOfPoetryOrAListIsFlushWithItsFirstLine() {
        for role in [ParagraphRole.q1, .q2, .q3, .q4, .li1, .li2] {
            let block = ScriptureStyleSheet.classic.block(for: role)
            #expect(block.wrapIndent == block.firstLineIndent, "\(role)")
        }
    }
}
