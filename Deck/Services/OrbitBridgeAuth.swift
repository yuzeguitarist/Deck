//
//  OrbitBridgeAuth.swift
//  Deck
//
//  Simple shared-token auth for the Orbit CLI bridge
//

import Foundation

enum OrbitBridgeAuth {
    static let tokenHeader = "x-orbit-token"
    private static let sharedToken = "orbit-bridge-v1-3c2b9f1a7e0d4a6c8b5e9d2f1a6c7b8e"

    static func authorize(headers: [String: String]) -> Bool {
        guard let provided = headers[tokenHeader]?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return provided == sharedToken
    }
}
