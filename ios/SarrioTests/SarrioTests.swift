import Testing
@testable import Sarrio

/// Tests de la app (los de lógica pura viven en Packages/SarrioKit y se ejecutan con `swift test`).
@Suite struct AppConfigTests {
    @Test func apiBaseURLHasScheme() {
        #expect(AppConfig.apiBaseURL.scheme?.hasPrefix("http") == true)
    }
}

@Suite struct ActivityDecodingTests {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }()

    @Test func decodesDetailWithTrackSegments() throws {
        let json = Data("""
        {"activity":{"id":"a1","userId":"u1","source":"file","sportType":"hiking","title":null,
          "startAt":1784000000000,"durationS":18000,"distanceM":14800,"elevGainM":1500,
          "bbox":null,"visibility":"friends","createdAt":1784000000000},
         "ascents":[{"id":"x","userId":"u1","activityId":"a1","summitedAt":1784010800000,"note":null,
           "visibility":"friends","peak":{"id":1001,"name":"Aneto","nameEs":null,"ele":3404,"lat":42.6311,"lon":0.6569}}],
         "track":[[[42.64,0.66,2400,0],[42.6312,0.657,null,10800]]]}
        """.utf8)
        let detail = try decoder.decode(ActivityDetail.self, from: json)
        #expect(detail.activity.displayTitle == "Senderismo")
        #expect(detail.ascents.first?.peak.displayName == "Aneto")
        let points = try #require(detail.segments.first)
        #expect(points.count == 2)
        #expect(points[1].elevation == nil)
        #expect(points[1].time == detail.activity.startAt.addingTimeInterval(10800))
    }
}

@Suite struct SharedInboxTests {
    @Test func stripsUniquePrefix() {
        #expect(SharedInbox.originalName(of: URL(fileURLWithPath: "/tmp/1a2b3c4d-Aneto.gpx")) == "Aneto")
        #expect(SharedInbox.originalName(of: URL(fileURLWithPath: "/tmp/Aneto.gpx")) == "Aneto")
    }
}
