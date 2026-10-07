import Foundation

var count = 0
func expect(_ input: String, _ expected: String?) {
    count += 1
    let result = route(URL(string: input)!)
    switch (result, expected) {
    case (.zoom(let actual), .some(let expected)):
        precondition(actual.absoluteString == expected, "Wrong conversion in test \(count)")
    case (.safari(let actual), .none):
        precondition(actual.absoluteString == input, "Changed fallback in test \(count)")
    default:
        fatalError("Wrong destination in test \(count)")
    }
}
expect("https://zoom.us/j/123456789", "zoommtg://zoom.us/join?action=join&confno=123456789")
expect("https://us02web.zoom.us/j/12345678901?pwd=A%2BB%2FC%3D", "zoommtg://us02web.zoom.us/join?action=join&confno=12345678901&pwd=A%2BB%2FC%3D")
expect("https://company.zoom.us/j/1234567890/?pwd=A+B==&omn=123#success", "zoommtg://company.zoom.us/join?action=join&confno=1234567890&pwd=A+B==&omn=123")
expect("https://ZOOM.US/j/123456789", "zoommtg://zoom.us/join?action=join&confno=123456789")
expect("http://zoom.us/j/123456789", "zoommtg://zoom.us/join?action=join&confno=123456789")
expect("https://example.com/path?q=abc#fragment", nil)
expect("https://zoom.us/profile", nil)
expect("https://zoom.us/my/name", nil)
expect("https://zoom.us/w/123456789?tk=token", nil)
expect("https://zoom.us/s/123456789?zak=token", nil)
expect("https://zoom.us/j/123456789?wp=registration", nil)
expect("https://zoom.us/j/123456789?pwd=one&pwd=two", nil)
expect("https://zoom.us/j/123456789?confno=999999999", nil)
expect("https://zoom.us/j/123456789?action=start", nil)
expect("https://zoom.us/j/12345678", nil)
expect("https://zoom.us/j/123456789012", nil)
expect("https://zoom.us/j/123456789/extra", nil)
expect("https://zoom.us/j/%31%32%33%34%35%36%37%38%39", nil)
expect("https://zoom.us.evil.example/j/123456789", nil)
expect("https://fakezoom.us/j/123456789", nil)
expect("https://zoom.us@evil.example/j/123456789", nil)
expect("https://someone@zoom.us/j/123456789", nil)
expect("https://zoom.us:1234/j/123456789", nil)
expect("https://zoom.us/j/123456789?%70wd=encodedkey", nil)
expect("https://zoom.us/j/123456789?pwd", nil)
print("Passed \(count) routing tests; no applications or meetings were opened.")
