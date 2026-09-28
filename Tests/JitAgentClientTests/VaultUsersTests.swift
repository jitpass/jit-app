// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class VaultUsersTests: XCTestCase {
    /// A profile in a project folder is what uses an MCP server's secrets:
    /// the listing names it and its folder, once however many secrets.
    func testAProfilesUsersAreItsSecretsUsersOnce() throws {
        let json = #"{"secrets":[{"path":"mcp-tickets/URL","version":1,"#
            + #""users":[{"profile":"mcp-tickets","project":"/Users/me/work/ops"}]},"#
            + #"{"path":"mcp-tickets/TOKEN","version":1,"users":[{"profile":"mcp-tickets","project":"/Users/me/work/ops"}]},"#
            + #"{"path":"scratch/ONE","version":1}]}"#
        let listing = try JSONDecoder().decode(VaultUsersListing.self, from: Data(json.utf8))
        XCTAssertEqual(
            listing.profiles(for: ["mcp-tickets/URL", "mcp-tickets/TOKEN"]),
            [VaultSecretUser(profile: "mcp-tickets", project: "/Users/me/work/ops")]
        )
        XCTAssertEqual(listing.profiles(for: ["scratch/ONE"]), [])
    }
}
