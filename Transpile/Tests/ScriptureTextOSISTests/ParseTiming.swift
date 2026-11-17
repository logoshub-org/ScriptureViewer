// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Timing for the tests that check how parse time grows.
enum ParseTiming {
    /// How many times over the text is repeated for the longer run.
    static let factor = 8

    /// The most that `factor` times the text may take, as a multiple of once: linear growth gives about 8 (less in Kotlin, where the
    /// longer run gives the compiler more time), growth with the square up to 64. Eight times, not four, because at four a JVM did not
    /// tell the square from a line clearly enough: with the old copying bug put back, OSIS took 7 times as long at four times the text.
    static let limit = 16.0

    /// The median of seven timed runs, in seconds, after three that are not timed (the code is still being compiled then).
    static func median(_ work: () throws -> Void) throws -> Double {
        for _ in 0..<3 { try work() }
        var times: [Double] = []
        for _ in 0..<7 {
            let start = Date()
            try work()
            times.append(Date().timeIntervalSince(start))
        }
        times.sort()
        return max(times[3], 0.000001)
    }

    static func describe(_ seconds: Double) -> String { String(Int(seconds * 1000.0)) + " ms" }
}
