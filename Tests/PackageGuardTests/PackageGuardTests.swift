// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import XCTest

/// What keeps the package what it says it is. They read the package's own sources, so they run wherever the package is built.
final class PackageGuardTests: XCTestCase {

	/// The package folder: this file is Tests/PackageGuardTests/PackageGuardTests.swift.
	private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

	private func swiftFiles(in folder: String) throws -> [URL] {
		let directory = root.appendingPathComponent(folder)
		let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil), folder)
		return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
	}

	/// What a host needs is `public`; the rest is `package` or internal. This keeps the viewer's surface from growing unnoticed. If a
	/// change needs more of it, raise the number here on purpose, in the same commit.
	/// (88 with the old UIKit container, 75 once it went, 56 once the book navigator and the app hooks left, 57 with `frameOfVerse`,
	/// 63 with the Android branch of `ScriptureViewer` and the macOS placeholder: each a struct, an initialiser and a body, the same view
	/// under `#if SKIP` and on macOS.)
	func testTheViewersPublicSurfaceHasNotGrown() throws {
		var count = 0
		for file in try swiftFiles(in: "Sources/ScriptureViewer") {
			for line in try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false) {
				let trimmed = line.trimmingCharacters(in: .whitespaces)
				guard !trimmed.hasPrefix("//") else { continue }
				if trimmed.range(of: #"^(@[A-Za-z_]+(\([^)]*\))?\s+)*(nonisolated\(unsafe\)\s+)?public "#, options: .regularExpression) != nil { count += 1 }
			}
		}
		XCTAssertLessThanOrEqual(count, 63)
	}

	/// Every source file is MPL-2.0, except the data embedded under its own licence (MIT, which the MPL accepts), and uses no engine, no
	/// defaults and no notification: those belong to the host. The compiler already stops the package importing an app; this catches the
	/// names that would sneak in through a string.
	func testEverySourceIsMPLAndTouchesNoHostThings() throws {
		let names = ["UserDefaults", "NotificationCenter", "SwordRawChapterReader", "SwordLibrary", "PSModuleController", "NSUserDefaults"]
		let otherLicences = ["StandardVersifications.swift": "// SPDX-License-Identifier: MIT"]
		var checked = 0
		for file in try swiftFiles(in: "Sources") {
			let source = try String(contentsOf: file, encoding: .utf8)
			let header = otherLicences[file.lastPathComponent] ?? "// SPDX-License-Identifier: MPL-2.0"
			XCTAssertTrue(source.hasPrefix(header), "\(file.lastPathComponent) lacks the \(header.dropFirst(28)) header")
			let code = source.split(separator: "\n", omittingEmptySubsequences: false)
				.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
			for name in names { XCTAssertFalse(code.contains(name), "\(file.lastPathComponent) uses \(name)") }
			checked += 1
		}
		XCTAssertGreaterThan(checked, 15)
	}
}
