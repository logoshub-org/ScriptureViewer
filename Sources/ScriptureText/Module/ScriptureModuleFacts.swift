// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// What a host tells the package about the module a text came from (plan D50).
// The package reads no conf files and opens no modules: the host, which owns
// the module, fills this in once and uses it to pick a parser and its options.

import Foundation

/// The markup a module's entries are written in (the conf `SourceType`).
public enum ScriptureSourceType: String, Sendable, Codable, CaseIterable {
    case osis, thml, gbf, tei
    /// No `SourceType` in the conf: plain text.
    case plain

    /// From the conf value, which SWORD compares case-insensitively.
    public static func from(conf value: String?) -> ScriptureSourceType {
        let v = trimmedSpaces(value ?? "").lowercased()
        for candidate in Self.allCases where candidate != .plain && candidate.rawValue == v { return candidate }
        return .plain
    }
}

public struct ScriptureModuleFacts: Equatable, Sendable {
    public var name: String
    public var sourceType: ScriptureSourceType
    public var versification: String
    public var rightToLeft: Bool
    /// SWORD's `OSISqToTick`: supply quotation marks for `<q>` without a marker.
    /// On unless the conf says false.
    public var osisQToTick: Bool
    /// The module lists the matching filter in its conf (UTF8GreekAccents and so on).
    public var declaresGreekAccents: Bool
    public var declaresHebrewPoints: Bool
    public var declaresCantillation: Bool

    public init(name: String, sourceType: ScriptureSourceType = .osis, versification: String = "KJV",
                rightToLeft: Bool = false, osisQToTick: Bool = true,
                declaresGreekAccents: Bool = false, declaresHebrewPoints: Bool = false,
                declaresCantillation: Bool = false) {
        self.name = name
        self.sourceType = sourceType
        self.versification = versification
        self.rightToLeft = rightToLeft
        self.osisQToTick = osisQToTick
        self.declaresGreekAccents = declaresGreekAccents
        self.declaresHebrewPoints = declaresHebrewPoints
        self.declaresCantillation = declaresCantillation
    }

    /// The identity of a chapter of this module.
    public func identity(book: String, chapter: Int?) -> PassageIdentity {
        PassageIdentity(work: name, versification: versification, book: book, chapter: chapter)
    }

    /// The transforms to apply for the user's preferences (D47). `true` means the
    /// preference is on (keep the characters). A transform is applied only when the
    /// preference is off **and** the module declares the filter, as SWORD does.
    public func textTransforms(greekAccents: Bool, hebrewPoints: Bool, hebrewCantillation: Bool) -> TextTransforms {
        TextTransforms(greekAccents: greekAccents || !declaresGreekAccents,
                       hebrewPoints: hebrewPoints || !declaresHebrewPoints,
                       hebrewCantillation: hebrewCantillation || !declaresCantillation)
    }
}
