// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// One problem `jit doctor --format json` reports: a profile whose vault
/// reference is missing or unreadable, with the CLI's own fix advice.
public struct DoctorProblem: Codable, Sendable, Equatable {
    public var kind: String
    public var profile: String
    public var variable: String?
    public var path: String?
    public var action: String?
}

public struct DoctorReport: Codable, Sendable, Equatable {
    public var ok: Bool
    public var problems: [DoctorProblem]

    public init(ok: Bool, problems: [DoctorProblem]) {
        self.ok = ok
        self.problems = problems
    }

    /// Profile name to a one-line reason it cannot be granted.
    public var brokenProfiles: [String: String] {
        var out: [String: String] = [:]
        for problem in problems where out[problem.profile] == nil {
            out[problem.profile] = problem.variable.map { "\(problem.kind): \($0)" } ?? problem.kind
        }
        return out
    }
}
