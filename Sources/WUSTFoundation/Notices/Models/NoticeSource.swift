import Foundation

public enum NoticeSource: String, CaseIterable, Codable, Hashable, Sendable {
    case campus
    case academicAffairs
    case studentAffairs
    case research
    case graduateSchool

    public var name: String {
        switch self {
        case .campus: return "校园通知"
        case .academicAffairs: return "教务通知"
        case .studentAffairs: return "学工通知"
        case .research: return "科研通知"
        case .graduateSchool: return "研究生院通知"
        }
    }

    public var listURL: URL {
        switch self {
        case .campus: return URL(string: "https://www.wust.edu.cn/index/tzgg.htm")!
        case .academicAffairs: return URL(string: "https://jwc.wust.edu.cn/tzgg.htm")!
        case .studentAffairs: return URL(string: "https://xgc.wust.edu.cn/tzgg.htm")!
        case .research: return URL(string: "https://kjc.wust.edu.cn/tzgg.htm")!
        case .graduateSchool: return URL(string: "https://ysxy.wust.edu.cn/tzgg.htm")!
        }
    }
}
