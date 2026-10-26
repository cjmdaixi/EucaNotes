import Foundation

// Synology's WebAPI returns loosely typed values (numbers may be strings).
// JSONValue keeps the transport layer tolerant across DSM/Note Station versions.
enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    var arrayValue: [JSONValue] {
        if case .array(let value) = self { return value }
        return []
    }

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return value.rounded() == value ? String(Int(value)) : String(value)
        default: return nil
        }
    }

    var intValue: Int {
        switch self {
        case .number(let value): return Int(value)
        case .string(let value): return Int(value) ?? 0
        default: return 0
        }
    }

    var boolValue: Bool {
        switch self {
        case .bool(let value): return value
        case .number(let value): return value != 0
        case .string(let value): return value == "true" || value == "1"
        default: return false
        }
    }
}

struct Notebook: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var itemCount: Int

    init(id: String, title: String, itemCount: Int = 0) {
        self.id = id
        self.title = title
        self.itemCount = itemCount
    }

    init(json: JSONValue) {
        id = json["object_id"]?.stringValue ?? UUID().uuidString
        title = json["title"]?.stringValue ?? "未命名笔记本"
        itemCount = json["item_count"]?.intValue ?? 0
    }
}

struct NoteTag: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    init(json: JSONValue) {
        id = json["tag_id"]?.stringValue ?? json["object_id"]?.stringValue ?? UUID().uuidString
        title = json["title"]?.stringValue ?? "未命名标签"
    }
}

struct Note: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var content: String
    var brief: String
    var parentID: String
    var tags: [String]
    var createdAt: Date
    var modifiedAt: Date
    var version: String
    var isInTrash: Bool
    var isArchived: Bool
    var isEncrypted: Bool
    var hasLoadedContent: Bool
    var isPinned: Bool

    init(id: String = UUID().uuidString, title: String, content: String = "", brief: String = "", parentID: String = "", tags: [String] = [], createdAt: Date = .now, modifiedAt: Date = .now, version: String = "", isInTrash: Bool = false, isArchived: Bool = false, isEncrypted: Bool = false, hasLoadedContent: Bool = true, isPinned: Bool = false) {
        self.id = id
        self.title = title
        self.content = content
        self.brief = brief
        self.parentID = parentID
        self.tags = tags
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.version = version
        self.isInTrash = isInTrash
        self.isArchived = isArchived
        self.isEncrypted = isEncrypted
        self.hasLoadedContent = hasLoadedContent
        self.isPinned = isPinned
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, content, brief, parentID, tags, createdAt, modifiedAt, version
        case isInTrash, isArchived, isEncrypted, hasLoadedContent, isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        brief = try container.decode(String.self, forKey: .brief)
        parentID = try container.decode(String.self, forKey: .parentID)
        tags = try container.decode([String].self, forKey: .tags)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        if let stringVersion = try? container.decode(String.self, forKey: .version) {
            version = stringVersion
        } else {
            version = String((try? container.decode(Int.self, forKey: .version)) ?? 0)
        }
        isInTrash = try container.decode(Bool.self, forKey: .isInTrash)
        isArchived = try container.decode(Bool.self, forKey: .isArchived)
        isEncrypted = try container.decode(Bool.self, forKey: .isEncrypted)
        hasLoadedContent = try container.decode(Bool.self, forKey: .hasLoadedContent)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    init(json: JSONValue) {
        id = json["object_id"]?.stringValue ?? UUID().uuidString
        title = json["title"]?.stringValue ?? "无标题"
        content = json["content"]?.stringValue ?? ""
        brief = json["brief"]?.stringValue ?? ""
        parentID = json["parent_id"]?.stringValue ?? ""
        tags = json["tag"]?.arrayValue.compactMap { tag in
            tag["title"]?.stringValue ?? tag.stringValue
        } ?? []
        createdAt = Date(timeIntervalSince1970: TimeInterval(json["ctime"]?.intValue ?? 0))
        modifiedAt = Date(timeIntervalSince1970: TimeInterval(json["mtime"]?.intValue ?? 0))
        version = json["ver"]?.stringValue ?? json["version"]?.stringValue ?? ""
        isInTrash = json["recycle"]?.boolValue ?? false
        isArchived = json["archive"]?.boolValue ?? false
        isEncrypted = json["encrypt"]?.boolValue ?? false
        hasLoadedContent = json["content"] != nil
        isPinned = false
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "无标题" : trimmed
    }

    var preview: String {
        let source = brief.isEmpty ? content : brief
        let withoutTags = source.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

enum LibraryFilter: Hashable, Codable {
    case all
    case notebook(String)
    case tag(String)
    case trash

    var title: String {
        switch self {
        case .all: return "全部笔记"
        case .notebook: return "笔记本"
        case .tag: return "标签"
        case .trash: return "废纸篓"
        }
    }
}

struct SynologySession: Codable, Sendable {
    var baseURL: String
    var sid: String
    var did: String?
    var account: String
    var isDemo: Bool = false
}

enum SyncState: Equatable {
    case idle
    case syncing
    case saved(Date)
    case failed(String)

    var title: String {
        switch self {
        case .idle: return "已同步"
        case .syncing: return "正在同步…"
        case .saved(let date): return "已保存 · " + date.formatted(date: .omitted, time: .shortened)
        case .failed: return "保存失败"
        }
    }
}

enum SynologyError: LocalizedError, Equatable {
    case invalidServer
    case invalidResponse
    case api(String, Int)
    case network(String)
    case noNotebook
    case encryptedNote

    var errorDescription: String? {
        switch self {
        case .invalidServer: return "请输入有效的服务器地址，例如 https://nas.example.com:5001"
        case .invalidResponse: return "服务器返回了无法识别的数据，请确认已安装 Note Station。"
        case .api(let api, let code):
            switch (api, code) {
            case ("SYNO.API.Auth", 400), ("SYNO.API.Auth", 401), ("SYNO.API.Auth", 402):
                return "账户或密码不正确，请重试。（\(code)）"
            case ("SYNO.API.Auth", 403): return "此账户需要输入二次验证码。"
            case ("SYNO.API.Auth", 404): return "二次验证码不正确，请重试。"
            case ("SYNO.API.Auth", 405): return "此账户没有登录权限。"
            case ("SYNO.API.Auth", 407): return "登录尝试次数过多，账户已被暂时锁定。"
            case ("SYNO.API.Auth", 408), ("SYNO.API.Auth", 409), ("SYNO.API.Auth", 410):
                return "密码已过期，请先在 DSM 中修改密码。"
            case ("SYNO.API.Auth", 411): return "账户已停用，请联系管理员。"
            case (_, 105), (_, 119): return "登录已过期，请重新登录。"
            default: return "请求失败：\(api)（错误码 \(code)）"
            }
        case .network(let message): return message
        case .noNotebook: return "没有可用的笔记本，请先在 Note Station 中创建笔记本。"
        case .encryptedNote: return "加密笔记暂不支持在此客户端中解密编辑。"
        }
    }
}
