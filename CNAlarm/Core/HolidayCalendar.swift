import Foundation

struct HolidayPeriod: Hashable, Codable {
    var name: String
    var startKey: String
    var endKey: String
    var compDayKeys: [String]
    var memo: String
}

struct HolidayCalendar: Hashable, Codable {
    var name: String
    var generated: String
    var restDays: [String: String]
    var compWorkdays: [String: String]
    var periods: [HolidayPeriod]

    static let empty = HolidayCalendar(name: "未加载", generated: "", restDays: [:], compWorkdays: [:], periods: [])

    func isHolidayRestDay(_ key: String) -> Bool {
        restDays[key] != nil
    }

    func isCompensatedWorkday(_ key: String) -> Bool {
        compWorkdays[key] != nil
    }

    func holidayName(for key: String) -> String? {
        restDays[key] ?? compWorkdays[key]
    }

    func mergedWithFallback(_ fallback: HolidayCalendar) -> HolidayCalendar {
        var mergedRestDays = fallback.restDays
        mergedRestDays.merge(restDays) { _, current in current }

        var mergedCompWorkdays = fallback.compWorkdays
        mergedCompWorkdays.merge(compWorkdays) { _, current in current }

        var seenPeriods: Set<String> = []
        let mergedPeriods = (fallback.periods + periods).filter { period in
            seenPeriods.insert("\(period.name)-\(period.startKey)").inserted
        }

        return HolidayCalendar(
            name: name.isEmpty ? fallback.name : name,
            generated: generated.isEmpty ? fallback.generated : generated,
            restDays: mergedRestDays,
            compWorkdays: mergedCompWorkdays,
            periods: mergedPeriods.sorted { $0.startKey < $1.startKey }
        )
    }

    static func decodeStored(_ rawJSON: String) -> HolidayCalendar {
        let data = Data(rawJSON.utf8)
        if let decoded = try? JSONDecoder().decode(HolidayCalendar.self, from: data) {
            return decoded.mergedWithFallback(.fixture2026)
        }
        if let parsed = try? HolidayCalendarParser().parse(data: data) {
            return parsed.mergedWithFallback(.fixture2026)
        }
        return .fixture2026
    }
}

enum HolidayCalendarParseError: Error {
    case invalidDateRange(String)
}

struct HolidayCalendarParser {
    private struct APIFile: Decodable {
        let Name: String
        let Generated: String
        let Years: [String: [APIPeriod]]
    }

    private struct APIPeriod: Decodable {
        let Name: String
        let StartDate: String
        let EndDate: String
        let CompDays: [String]
        let Memo: String?
    }

    func parse(data: Data, calendar: Calendar = .chinaAlarm) throws -> HolidayCalendar {
        let decoded = try JSONDecoder().decode(APIFile.self, from: data)
        var restDays: [String: String] = [:]
        var compWorkdays: [String: String] = [:]
        var periods: [HolidayPeriod] = []

        for yearPeriods in decoded.Years.values {
            for period in yearPeriods {
                guard
                    let start = calendar.date(from: period.StartDate),
                    let end = calendar.date(from: period.EndDate)
                else {
                    throw HolidayCalendarParseError.invalidDateRange(period.Name)
                }
                let dayCount = max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
                for offset in 0...dayCount {
                    if let date = calendar.date(byAdding: .day, value: offset, to: start) {
                        restDays[calendar.startOfDayKey(for: date)] = period.Name
                    }
                }
                for compDay in period.CompDays {
                    compWorkdays[compDay] = period.Name
                }
                periods.append(
                    HolidayPeriod(
                        name: period.Name,
                        startKey: period.StartDate,
                        endKey: period.EndDate,
                        compDayKeys: period.CompDays,
                        memo: period.Memo ?? ""
                    )
                )
            }
        }

        return HolidayCalendar(
            name: decoded.Name,
            generated: decoded.Generated,
            restDays: restDays,
            compWorkdays: compWorkdays,
            periods: periods.sorted { $0.startKey < $1.startKey }
        )
    }
}

struct HolidayCalendarSource {
    static let defaultURL = URL(string: "https://www.shuyz.com/githubfiles/china-holiday-calender/master/holidayAPI.json")!

    var url: URL = defaultURL
    var session: URLSession = .shared

    func fetch() async throws -> HolidayCalendar {
        let (data, _) = try await session.data(from: url)
        return try HolidayCalendarParser().parse(data: data)
    }
}

extension HolidayCalendar {
    static var fixture2026: HolidayCalendar {
        let json = """
        {
          "Name": "Fixture",
          "Generated": "20260509T000000Z",
          "Years": {
            "2026": [
              {
                "Name": "元旦",
                "StartDate": "2026-01-01",
                "EndDate": "2026-01-03",
                "Duration": 3,
                "CompDays": ["2026-01-04"],
                "Memo": "元旦调休"
              },
              {
                "Name": "春节",
                "StartDate": "2026-02-15",
                "EndDate": "2026-02-23",
                "Duration": 9,
                "CompDays": ["2026-02-14", "2026-02-28"],
                "Memo": "春节调休"
              },
              {
                "Name": "清明节",
                "StartDate": "2026-04-04",
                "EndDate": "2026-04-06",
                "Duration": 3,
                "CompDays": [],
                "Memo": "清明节"
              },
              {
                "Name": "劳动节",
                "StartDate": "2026-05-01",
                "EndDate": "2026-05-05",
                "Duration": 5,
                "CompDays": ["2026-05-09"],
                "Memo": "劳动节调休"
              },
              {
                "Name": "端午节",
                "StartDate": "2026-06-19",
                "EndDate": "2026-06-21",
                "Duration": 3,
                "CompDays": [],
                "Memo": "端午节"
              },
              {
                "Name": "中秋节",
                "StartDate": "2026-09-25",
                "EndDate": "2026-09-27",
                "Duration": 3,
                "CompDays": [],
                "Memo": "中秋节"
              },
              {
                "Name": "国庆节",
                "StartDate": "2026-10-01",
                "EndDate": "2026-10-07",
                "Duration": 7,
                "CompDays": ["2026-09-20", "2026-10-10"],
                "Memo": "国庆调休"
              }
            ]
          }
        }
        """
        return (try? HolidayCalendarParser().parse(data: Data(json.utf8))) ?? .empty
    }
}
