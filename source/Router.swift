import Foundation

enum Route {
    case zoom(URL)
    case safari(URL)
}

// Only simple meeting invitations are rewritten. Web flows such as SSO,
// registration, webinars and personal aliases keep their original URL.
func route(_ original: URL) -> Route {
    guard let parts = URLComponents(url: original, resolvingAgainstBaseURL: false),
          let scheme = parts.scheme?.lowercased(),
          ["https", "http"].contains(scheme),
          let host = parts.host?.lowercased(),
          host == "zoom.us" || host.hasSuffix(".zoom.us"),
          parts.user == nil, parts.password == nil, parts.port == nil,
          parts.percentEncodedPath.range(of: #"^/j/[0-9]{9,11}/?$"#,
                                        options: .regularExpression) != nil else {
        return .safari(original)
    }

    let fields = (parts.percentEncodedQuery ?? "").split(separator: "&", omittingEmptySubsequences: false)
    var seen = Set<String>()
    var preserved: [String] = []
    for field in fields where !field.isEmpty {
        let pair = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        let name = String(pair[0])
        // Preserve the encoded password exactly, including +, %2B and =.
        // omn is carried through unchanged; unknown parameters use the web flow.
        guard ["pwd", "omn"].contains(name), pair.count == 2,
              seen.insert(name).inserted else { return .safari(original) }
        preserved.append(String(field))
    }

    let meeting = parts.path.split(separator: "/")[1]
    var target = URLComponents()
    target.scheme = "zoommtg"
    target.host = host
    target.path = "/join"
    target.percentEncodedQuery = (["action=join", "confno=\(meeting)"] + preserved).joined(separator: "&")
    guard let url = target.url else { return .safari(original) }
    return .zoom(url)
}
