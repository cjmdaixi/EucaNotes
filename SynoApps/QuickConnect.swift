import Foundation
import CryptoKit

enum QuickConnectError: LocalizedError, Equatable {
    case invalidID
    case notFound
    case noRoute
    case invalidResponse
    case service(String)

    var errorDescription: String? {
        switch self {
        case .invalidID: return "QuickConnect ID 应以字母开头，只包含字母、数字、连字符或下划线。"
        case .notFound: return "未找到这个 QuickConnect ID。请检查 ID，并确认 DSM 已启用 QuickConnect。"
        case .noRoute: return "已找到 NAS，但直连和中继均不可达。请检查 NAS 的 QuickConnect 与网络设置。"
        case .invalidResponse: return "QuickConnect 服务返回了无法识别的数据。"
        case .service(let message): return "无法连接 QuickConnect 服务：\(message)"
        }
    }
}

struct QuickConnectResolver: Sendable {
    private struct ServerInfo: Sendable {
        var json: JSONValue
        var serviceURL: String
        var request: [String: JSONValue]
    }

    func resolve(id rawID: String, useHTTPS: Bool) async throws -> String {
        let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id.range(of: "^[A-Za-z][A-Za-z0-9_-]{0,63}$", options: .regularExpression) != nil else {
            throw QuickConnectError.invalidID
        }
        let info = try await lookupServerInfo(id: id, useHTTPS: useHTTPS)
        guard let serverID = info.json["server"]?["serverID"]?.stringValue else {
            throw QuickConnectError.invalidResponse
        }
        let ezid = md5(serverID)
        let candidates = directCandidates(info.json, id: id, useHTTPS: useHTTPS)
        if let host = await firstReachable(candidates, ezid: ezid) { return host }

        var tunnelRequest = info.request
        tunnelRequest["command"] = .string("request_tunnel")
        let tunnel = try await post(serviceURL: info.serviceURL, fields: tunnelRequest)
        guard tunnel["errno"]?.intValue == 0,
              let region = tunnel["env"]?["relay_region"]?.stringValue else {
            throw QuickConnectError.noRoute
        }
        let suffix = region.range(of: "^cn[0-9]+$", options: .regularExpression) == nil ? "to" : "cn"
        let relay = "https://\(id).\(region).quickconnect.\(suffix)/direct"
        guard await isReachable(relay, ezid: ezid) else { throw QuickConnectError.noRoute }
        return relay
    }

    private func lookupServerInfo(id: String, useHTTPS: Bool) async throws -> ServerInfo {
        var lastError: Error?
        for region in siteRegions {
            do {
                let siteList = try await post(
                    serviceURL: "https://global.quickconnect.\(region)/Serv.php",
                    fields: ["version": .number(1), "command": .string("get_site_list")]
                )
                let sites = siteList["sites"]?.arrayValue.compactMap(\.stringValue) ?? []
                guard !sites.isEmpty else { throw QuickConnectError.invalidResponse }
                let request: [String: JSONValue] = [
                    "version": .number(1),
                    "command": .string("get_server_info"),
                    "id": .string(useHTTPS ? "dsm_portal_https" : "dsm_portal"),
                    "serverID": .string(id)
                ]
                let serverInfo = try await withThrowingTaskGroup(of: ServerInfo?.self) { group -> ServerInfo? in
                    for site in sites {
                        group.addTask {
                            let serviceURL = "https://\(site)/Serv.php"
                            do {
                                let response = try await self.post(serviceURL: serviceURL, fields: request)
                                guard await response["errno"]?.intValue == 0 else { return nil }
                                return ServerInfo(json: response, serviceURL: serviceURL, request: request)
                            } catch { return nil }
                        }
                    }
                    for try await result in group {
                        if let result {
                            group.cancelAll()
                            return result
                        }
                    }
                    return nil
                }
                guard let serverInfo else { throw QuickConnectError.notFound }
                return serverInfo
            } catch {
                lastError = error
                // Region fallback is only for the site-list request. Once a region
                // has answered the server lookup, preserve its authoritative result.
                if let error = lastError as? QuickConnectError, error == .notFound { throw error }
            }
        }
        if let quickConnectError = lastError as? QuickConnectError { throw quickConnectError }
        throw QuickConnectError.service(lastError?.localizedDescription ?? "请稍后重试")
    }

    private var siteRegions: [String] {
        let zone = TimeZone.current.identifier
        return ["Asia/Shanghai", "Asia/Urumqi"].contains(zone) ? ["cn", "to"] : ["to"]
    }

    private func directCandidates(_ info: JSONValue, id: String, useHTTPS: Bool) -> [String] {
        guard let server = info["server"], let service = info["service"] else { return [] }
        let scheme = useHTTPS ? "https" : "http"
        let port = service["port"]?.intValue ?? (useHTTPS ? 5001 : 5000)
        let extPortValue = service["ext_port"]?.intValue ?? 0
        let externalPort = extPortValue == 0 ? port : extPortValue
        var result: [String] = []
        for interface in server["interface"]?.arrayValue ?? [] {
            if let ip = interface["ip"]?.stringValue, !ip.isEmpty {
                result.append("\(scheme)://\(urlHost(ip)):\(port)")
            }
        }
        if let ip = server["external"]?["ip"]?.stringValue, !ip.isEmpty {
            result.append("\(scheme)://\(urlHost(ip)):\(externalPort)")
        }
        for key in ["fqdn", "ddns"] {
            if let host = server[key]?.stringValue, !host.isEmpty, host != "NULL" {
                result.append("\(scheme)://\(urlHost(host)):\(externalPort)")
            }
        }
        var seen: Set<String> = []
        return result.filter { seen.insert($0).inserted }
    }

    private func firstReachable(_ hosts: [String], ezid: String) async -> String? {
        guard !hosts.isEmpty else { return nil }
        return await withTaskGroup(of: String?.self) { group in
            for host in hosts {
                group.addTask { await self.isReachable(host, ezid: ezid) ? host : nil }
            }
            for await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }

    private func isReachable(_ baseURL: String, ezid: String) async -> Bool {
        guard let url = URL(string: baseURL + "/webman/pingpong.cgi") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONDecoder().decode(JSONValue.self, from: data),
              json["ezid"]?.stringValue?.lowercased() == ezid else { return false }
        return true
    }

    private func post(serviceURL: String, fields: [String: JSONValue]) async throws -> JSONValue {
        guard let url = URL(string: serviceURL) else { throw QuickConnectError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("SynoApps/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(JSONValue.object(fields))
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw QuickConnectError.service("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch let error as QuickConnectError { throw error }
        catch is DecodingError { throw QuickConnectError.invalidResponse }
        catch { throw QuickConnectError.service(error.localizedDescription) }
    }

    private func urlHost(_ host: String) -> String {
        host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
    }

    private func md5(_ value: String) -> String {
        Insecure.MD5.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
