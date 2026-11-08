import Foundation
import Security

struct RunningAppIdentity {
    enum Signing: Equatable { case certificate, adHoc, unknown }

    let bundleURL: URL
    let identifier: String
    let signing: Signing
    let team: String?

    static func current() -> Self {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: 0)
        guard SecCodeCopySelf(flags, &code) == errSecSuccess, let code,
            SecCodeCopyStaticCode(code, flags, &staticCode) == errSecSuccess, let staticCode,
            SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
            let info = information as? [String: Any] else {
            return Self(bundleURL: Bundle.main.bundleURL, identifier: Bundle.main.bundleIdentifier ?? "Unknown",
                signing: .unknown, team: nil)
        }
        let signatureFlags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value
        let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate]
        return Self(bundleURL: Bundle.main.bundleURL,
            identifier: info[kSecCodeInfoIdentifier as String] as? String ?? "Unknown",
            signing: classify(flags: signatureFlags, certificateCount: certificates?.count ?? 0),
            team: info[kSecCodeInfoTeamIdentifier as String] as? String)
    }

    static func classify(flags: UInt32?, certificateCount: Int) -> Signing {
        guard let flags else { return .unknown }
        if flags & SecCodeSignatureFlags.adhoc.rawValue != 0 { return .adHoc }
        return certificateCount > 0 ? .certificate : .unknown
    }

    var signingDescription: String {
        switch signing {
        case .certificate: "Certificate-signed\(team.map { " (team \($0))" } ?? "")"
        case .adHoc: "Locally built, ad-hoc signature"
        case .unknown: "Signing identity could not be verified"
        }
    }
}

struct SettingsAccessVerification {
    enum State: Equatable { case waiting, checking, blocked, otherFailure, empty, readable }

    static func state(requestedAt: Date?, review: AppSettingsReview?, busy: Bool) -> State {
        guard let requestedAt else { return .waiting }
        if busy { return .checking }
        guard let review, review.checkedAt >= requestedAt else { return .waiting }
        if let error = review.error {
            return AppSettingsReadFailure(message: error).isAccessDenied ? .blocked : .otherFailure
        }
        if review.noPreferences != nil { return .empty }
        // A partial capture can still omit an unreadable source. Do not call that resolved.
        if review.response?.skipped.contains(where: {
            $0.kind != "manual" && AppSettingsReadFailure(message: $0.reason).isAccessDenied
        }) == true { return .blocked }
        return review.response == nil ? .waiting : .readable
    }
}
