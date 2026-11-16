// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import ScriptureText
@testable import ScriptureTextOSIS

// Golden snapshots of the OSIS parser (plan test group 5). Re-record after an
// intended change, then read the diff:  RECORD_GOLDEN=1 swift test --filter OSISGolden

struct OSISGoldenTests {

    private func load(_ url: URL) throws -> GoldenFixture {
        try JSONDecoder().decode(GoldenFixture.self, from: Data(contentsOf: url))
    }

    @Test func everyFixtureRunMatchesItsGolden() throws {
        let urls = try GoldenFiles.fixtureURLs()
        #expect(urls.count >= 10, "fixtures went missing: \(urls.count)")
        var runs = 0
        for url in urls {
            let name = GoldenFiles.name(of: url)
            let fixture = try load(url)
            #expect(!fixture.runs.isEmpty, "\(name): no runs")
            for run in fixture.runs {
                runs += 1
                let model = fixture.parse(run)
                let dump = GoldenDump.render(model)
                let golden = GoldenFiles.goldenURL(fixture: name, run: run.name)
                if GoldenFiles.recording {
                    try dump.write(to: golden, atomically: true, encoding: .utf8)
                    continue
                }
                guard let expected = try? String(contentsOf: golden, encoding: .utf8) else {
                    Issue.record("\(name).\(run.name): no golden file (record with RECORD_GOLDEN=1)")
                    continue
                }
                if dump != expected {
                    Issue.record("\(name).\(run.name) differs from its golden: \(firstDifference(expected, dump))")
                }
            }
        }
        #expect(runs >= 15)
    }

    @Test func theDumpLosesNothing_theModelRoundTripsThroughJSON() throws {
        for url in try GoldenFiles.fixtureURLs() {
            let fixture = try load(url)
            for run in fixture.runs {
                let model = fixture.parse(run)
                let decoded = try JSONDecoder().decode(ScriptureText.self, from: JSONEncoder().encode(model))
                #expect(decoded == model, "\(GoldenFiles.name(of: url)).\(run.name)")
            }
        }
    }

    @Test func parsingIsDeterministicAndStructurallyConsistent() throws {
        for url in try GoldenFiles.fixtureURLs() {
            let fixture = try load(url)
            for run in fixture.runs {
                let a = fixture.parse(run)
                #expect(a == fixture.parse(run), "\(GoldenFiles.name(of: url)).\(run.name) is not deterministic")
                #expect(a.isConsistent, "\(GoldenFiles.name(of: url)).\(run.name) is inconsistent")
            }
        }
    }

    @Test func everyGoldenFileHasAFixtureRun() throws {
        // A stale golden (its fixture or run was removed) would otherwise rot silently.
        var expected = Set<String>()
        for url in try GoldenFiles.fixtureURLs() {
            let name = GoldenFiles.name(of: url)
            for run in try load(url).runs { expected.insert(GoldenFiles.goldenURL(fixture: name, run: run.name).lastPathComponent) }
        }
        let onDisk = try FileManager.default.contentsOfDirectory(atPath: GoldenFiles.directory.path)
            .filter { $0.hasSuffix(".golden.txt") }
        #expect(Set(onDisk).subtracting(expected).isEmpty, "orphan goldens: \(Set(onDisk).subtracting(expected).sorted())")
    }

    private func firstDifference(_ a: String, _ b: String) -> String {
        let x = a.split(separator: "\n", omittingEmptySubsequences: false)
        let y = b.split(separator: "\n", omittingEmptySubsequences: false)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? String(x[i]) : "<end>"
            let r = i < y.count ? String(y[i]) : "<end>"
            if l != r { return "line \(i + 1): golden «\(l)» vs now «\(r)»" }
        }
        return "no difference"
    }
}
