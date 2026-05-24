#!/usr/bin/env swift
import CryptoKit
import Foundation

let teamID   = "89T7Q7LS36"
let keyID    = "ZK74ZM73LS"
let p8Path   = "/Users/blakenelson/Downloads/AuthKey_ZK74ZM73LS.p8"
let bundleID = "com.blakenelson.Firepower"
let sandbox  = true

let channelID = "+pSGy0vgEfEAAKqhstn/Jg=="

let now = Int(Date().timeIntervalSince1970)
let payload: [String: Any] = [
    "aps": [
        "timestamp": now,
        "event": "update",
        "content-state": [
            "homeScore": 2,
            "awayScore": 1,
            "homeXG": 1.84,
            "awayXG": 0.97,
            "gameState": "8:14 left, 2nd period",
            "lastEvent": "Goal - Mikko Rantanen (18)"
        ] as [String: Any],
        "stale-date": now + 900
    ] as [String: Any]
]

func base64url(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

func makeJWT(privateKey: P256.Signing.PrivateKey) throws -> String {
    let iat = Int(Date().timeIntervalSince1970)
    let hdr = base64url(Data(#"{"alg":"ES256","kid":"\#(keyID)"}"#.utf8))
    let clm = base64url(Data(#"{"iss":"\#(teamID)","iat":\#(iat)}"#.utf8))
    let sig = try privateKey.signature(for: Data("\(hdr).\(clm)".utf8))
    return "\(hdr).\(clm).\(base64url(sig.rawRepresentation))"
}

let pem        = try String(contentsOfFile: p8Path, encoding: .utf8)
let privateKey = try P256.Signing.PrivateKey(pemRepresentation: pem)
let jwt        = try makeJWT(privateKey: privateKey)

let host = sandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com"
let url = URL(string: "https://\(host)/4/broadcasts/apps/\(bundleID)")!

var req = URLRequest(url: url)
req.httpMethod = "POST"
req.setValue("bearer \(jwt)",    forHTTPHeaderField: "authorization")
req.setValue("liveactivity",     forHTTPHeaderField: "apns-push-type")
req.setValue("10",               forHTTPHeaderField: "apns-priority")
req.setValue(channelID,          forHTTPHeaderField: "apns-channel-id")
req.setValue("application/json", forHTTPHeaderField: "content-type")
req.setValue(String(now + 900),  forHTTPHeaderField: "apns-expiration")
req.httpBody = try JSONSerialization.data(withJSONObject: payload)

print("→ channel: \(channelID)")
print("  url:     \(url)")
print()

let sem = DispatchSemaphore(value: 0)
var statusCode = 0
var apnsID = ""
var body = ""

URLSession.shared.dataTask(with: req) { data, response, error in
    defer { sem.signal() }
    if let error { fputs("error: \(error)\n", stderr); return }
    if let http = response as? HTTPURLResponse {
        statusCode = http.statusCode
        apnsID = http.value(forHTTPHeaderField: "apns-id") ?? ""
    }
    if let data, !data.isEmpty {
        body = String(data: data, encoding: .utf8) ?? ""
    }
}.resume()
sem.wait()

print("← HTTP \(statusCode)")
if !apnsID.isEmpty { print("  apns-id: \(apnsID)") }
if !body.isEmpty   { print("  body:    \(body)") }
print()

if statusCode == 200 {
    print("✓ message sent to channel")
} else {
    print("✗ rejected (HTTP \(statusCode))")
    exit(1)
}
