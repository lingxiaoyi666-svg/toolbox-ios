//
//  AppStoreLink.swift
//  iridium
//
//  复制 App Store 链接 → 直接砸壳
//  依赖：AppListProto / SPIndicator / UIKit
//

import AppListProto
import SPIndicator
import UIKit

// MARK: - 查询结果

struct AppStoreLookupResult {
    let trackId: Int
    let bundleId: String
    let trackName: String
    let version: String
    let artworkUrl: URL?
}

enum AppStoreLinkError: LocalizedError {
    case badLink
    case lookupEmpty(Int)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .badLink:
            return "链接里找不到 /id 数字"
        case .lookupEmpty(let id):
            return "iTunes 查不到 id \(id)，该区可能已下架"
        case .network(let message):
            return "网络错误：\(message)"
        }
    }
}

// MARK: - 链接解析 + iTunes 查询

final class AppStoreLink {
    static let shared = AppStoreLink()
    private init() {}

    /// apps.apple.com/cn/app/xxx/id123456789、itms-apps://…/id123、纯数字、?id=123 都能认
    func trackId(from text: String) -> Int? {
        let patterns = [
            #"/id(\d{5,})"#,
            #"[?&]id=(\d{5,})"#,
            #"^\s*(\d{6,})\s*$"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let sub = Range(match.range(at: 1), in: text),
                  let value = Int(text[sub])
            else { continue }
            return value
        }
        return nil
    }

    /// 中国区查不到自动回退美国区
    func lookup(
        trackId: Int,
        country: String = "cn",
        completion: @escaping (Result<AppStoreLookupResult, Error>) -> Void
    ) {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "id", value: "\(trackId)"),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "entity", value: "software"),
        ]
        guard let url = components.url else {
            DispatchQueue.main.async { completion(.failure(AppStoreLinkError.badLink)) }
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            func fail(_ error: Error) {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
            guard let self = self else { return }
            if let error = error {
                return fail(AppStoreLinkError.network(error.localizedDescription))
            }
            guard let data = data,
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let results = root["results"] as? [[String: Any]]
            else {
                return fail(AppStoreLinkError.network("响应不是合法 JSON"))
            }
            guard let first = results.first,
                  let bundleId = first["bundleId"] as? String
            else {
                if country != "us" {
                    self.lookup(trackId: trackId, country: "us", completion: completion)
                } else {
                    fail(AppStoreLinkError.lookupEmpty(trackId))
                }
                return
            }
            let result = AppStoreLookupResult(
                trackId: trackId,
                bundleId: bundleId,
                trackName: first["trackName"] as? String ?? bundleId,
                version: first["version"] as? String ?? "?",
                artworkUrl: (first["artworkUrl512"] as? String).flatMap(URL.init(string:))
            )
            DispatchQueue.main.async { completion(.success(result)) }
        }
        .resume()
    }

    func openInAppStore(trackId: Int) {
        let candidates = [
            "itms-apps://itunes.apple.com/app/id\(trackId)",
            "https://apps.apple.com/app/id\(trackId)",
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                return
            }
        }
    }
}

// MARK: - 一次只处理一个链接

/// 点刷新、或者换了一条新链接之后，上一次的状态必须能清干净，
/// 否则会一直弹上一次复制过的那个 App。
enum AppStoreLinkSession {
    /// 上一次解析过的链接原文：同一条链接不再自动解析，避免反复打扰
    static var lastHandledLink: String?
    /// 上一次解析出的 App 名字，只用来做提示文案
    static var lastHandledName: String?

    static func markHandled(link: String, name: String) {
        lastHandledLink = link
        lastHandledName = name
    }

    /// 用户说「不砸这个了」：保留去重用的链接，只清掉名字，
    /// 这样剪贴板里还是老链接时不会又被自动解析一遍。
    static func skipCurrent() {
        lastHandledName = nil
    }

    static func reset() {
        lastHandledLink = nil
        lastHandledName = nil
    }

    static func isSameAsLast(_ text: String) -> Bool {
        guard let last = lastHandledLink else { return false }
        return last == text
    }
}

// MARK: - AppListViewController 入口

extension AppListViewController {
    /// 在 viewDidLoad 末尾调用一次
    func installAppStoreLinkEntry() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "link"),
            style: .plain,
            target: self,
            action: #selector(promptForAppStoreLink)
        )
    }

    @objc func promptForAppStoreLink() {
        let pasteboardText = (UIPasteboard.general.string ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 剪贴板里是链接、且不是上次刚处理过的那一条，才直接开砸。
        // 还是老链接就走输入框，免得用户以为点了没反应，或者被旧 App 反复打扰。
        if AppStoreLink.shared.trackId(from: pasteboardText) != nil,
           !AppStoreLinkSession.isSameAsLast(pasteboardText)
        {
            resolveAndDecrypt(text: pasteboardText)
            return
        }

        let alert = UIAlertController(
            title: "App Store 链接",
            message: promptMessage(),
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "https://apps.apple.com/cn/app/id123456789"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "砸壳", style: .default) { [weak self, weak alert] _ in
            let text = alert?.textFields?.first?.text ?? ""
            self?.resolveAndDecrypt(text: text)
        })
        presentOnTop(alert)
    }

    private func promptMessage() -> String {
        if let name = AppStoreLinkSession.lastHandledName {
            return "上次处理的是「\(name)」。换一个 App 就粘贴新的链接，直接输入数字 ID 也行。"
        }
        return "粘贴 apps.apple.com/.../id123456789，直接输入数字 ID 也行"
    }

    /// 已经有一个 alert 在前台时再 present 会静默失败，先收掉旧的
    private func presentOnTop(_ controller: UIViewController) {
        if let presented = presentedViewController {
            presented.dismiss(animated: false) { [weak self] in
                self?.present(controller, animated: true)
            }
        } else {
            present(controller, animated: true)
        }
    }

    func resolveAndDecrypt(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trackId = AppStoreLink.shared.trackId(from: trimmed) else {
            SPIndicator.present(title: "解析失败", message: "没找到 /id 后面的数字", preset: .error)
            return
        }
        AppStoreLink.shared.lookup(trackId: trackId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                SPIndicator.present(title: "查询失败", message: error.localizedDescription, preset: .error)
            case .success(let meta):
                AppStoreLinkSession.markHandled(link: trimmed, name: meta.trackName)
                self.matchOrAskInstall(meta)
            }
        }
    }

    private func matchOrAskInstall(_ meta: AppStoreLookupResult) {
        if let app = installedApp(matching: meta.bundleId) {
            startDecrypt(app)
            return
        }
        // 列表可能是旧的，重扫一次再下结论
        DispatchQueue.global(qos: .userInitiated).async {
            let fresh = Agent.shared.generateAppList()
            DispatchQueue.main.async {
                self.origDataSource = fresh
                if let app = fresh.first(where: {
                    $0.bundleIdentifier.caseInsensitiveCompare(meta.bundleId) == .orderedSame
                }) {
                    self.startDecrypt(app)
                } else {
                    self.askToInstall(meta, listEmpty: fresh.isEmpty)
                }
            }
        }
    }

    private func installedApp(matching bundleId: String) -> AppListElement? {
        origDataSource.first {
            $0.bundleIdentifier.caseInsensitiveCompare(bundleId) == .orderedSame
        }
    }

    private func startDecrypt(_ app: AppListElement) {
        SPIndicator.present(title: "开始砸壳", message: app.localizedName, preset: .done)
        dispatchDecrypt(app: app)
    }

    private func askToInstall(_ meta: AppStoreLookupResult, listEmpty: Bool = false) {
        // 列表整个是空的 = 辅助程序没拿到 root，扫不到任何 App。
        // 这时候说「你没装」是假的，得把真正的原因讲清楚。
        if listEmpty {
            let alert = UIAlertController(
                title: "读不到应用列表",
                message: """
                辅助程序没拿到 root 权限，扫不出 /var/containers/Bundle/Application 里的 App。
                列表空的时候，装没装都会显示「没装」。

                确认用 TrollStore 或带 platform-application 的签名工具安装；装完从后台划掉再重开本 App。
                """,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "知道了", style: .cancel))
            presentOnTop(alert)
            return
        }

        let alert = UIAlertController(
            title: meta.trackName,
            message: """
            \(meta.bundleId) · \(meta.version)

            设备上没装这个 App，没有东西可砸。去 App Store 装好，回来重新复制一次链接就行 —— 不会自动开始，也不会反复弹同一个 App。
            """,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "去 App Store", style: .default) { _ in
            AppStoreLink.shared.openInAppStore(trackId: meta.trackId)
        })
        alert.addAction(UIAlertAction(title: "不砸了", style: .cancel) { _ in
            // 保留去重记录：剪贴板里还是这条链接的话，下次点链接按钮走输入框
            AppStoreLinkSession.skipCurrent()
        })
        presentOnTop(alert)
    }
}
