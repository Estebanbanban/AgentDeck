import Foundation

/// Minimal blocking OpenRouter chat call, shared by Titler and BootBriefing.
/// gpt-oss-120b is a reasoning model: reasoning tokens count against max_tokens
/// (effort=low keeps them small) and the payload sometimes lands in `reasoning`
/// with an empty `content` — take whichever is non-empty.
enum OpenRouter {
    static let model = "openai/gpt-oss-120b"

    static let apiKey: String? = {
        guard let line = try? String(contentsOfFile: NSHomeDirectory() + "/.config/agentdeck/env",
                                     encoding: .utf8) else { return nil }
        let key = line.split(separator: "=", maxSplits: 1).last.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (key?.isEmpty == false) ? key : nil
    }()

    /// Blocking; call off-main.
    static func chat(system: String, user: String, maxTokens: Int) -> String? {
        guard let key = apiKey else { return nil }
        let body: [String: Any] = ["model": model, "max_tokens": maxTokens, "temperature": 0.2,
                                   "reasoning": ["effort": "low"],
                                   "messages": [["role": "system", "content": system],
                                                ["role": "user", "content": user]]]
        var req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let sem = DispatchSemaphore(value: 0)
        var out: String?
        URLSession.shared.dataTask(with: req) { data, _, _ in
            defer { sem.signal() }
            guard let data,
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let msg = (root["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
            else { return }
            let content = (msg["content"] as? String) ?? ""
            out = content.isEmpty ? msg["reasoning"] as? String : content
        }.resume()
        sem.wait()
        return out
    }
}
