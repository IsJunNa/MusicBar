// 文件说明：读写补丁运行时配置文件

import Foundation

struct ConfigStore {
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func read(appURL: URL = URL(fileURLWithPath: defaultAppPath)) throws -> PatchConfig? {
        for candidateURL in [bundleConfigURL(appURL: appURL), configURL] where fileManager.fileExists(atPath: candidateURL.path) {
            let data = try Data(contentsOf: candidateURL)
            return try decoder.decode(PatchConfig.self, from: data)
        }

        return nil
    }

    // 应用补丁时把配置写进目标 App Bundle，sandbox 内运行时可以直接读取
    func write(_ config: PatchConfig, toApp appURL: URL? = nil) throws {
        let targetURL = appURL.map { bundleConfigURL(appURL: $0) } ?? configURL
        try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(config)
        try data.write(to: targetURL, options: .atomic)
    }

    func remove() throws {
        guard fileManager.fileExists(atPath: configURL.path) else {
            return
        }

        try fileManager.removeItem(at: configURL)
    }
}
