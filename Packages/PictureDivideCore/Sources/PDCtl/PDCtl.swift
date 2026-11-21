import Foundation
import ImageIO
import PictureDivideCore

/// 本机命令行工具：在 Mac 上直接跑检测（无需 iPhone、无需签名）。
///
/// 用法：
///   swift run pdctl detect <图片路径> [--model <模型目录>] [--policy standard|strict|allowTopless]
///   swift run pdctl scan <目录> [--model <模型目录>] [--policy ...] [--quality fast|balanced|accurate]
@main
struct PDCtl {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            printUsage()
            return
        }
        args.removeFirst()

        var positional: [String] = []
        var options: [String: String] = [:]
        var flags: Set<String> = []
        while !args.isEmpty {
            let arg = args.removeFirst()
            if arg.hasPrefix("--") {
                let key = String(arg.dropFirst(2))
                if key == "help" { flags.insert("help"); continue }
                if let value = args.first, !value.hasPrefix("--") {
                    options[key] = value
                    args.removeFirst()
                } else {
                    flags.insert(key)
                }
            } else {
                positional.append(arg)
            }
        }

        if flags.contains("help") || positional.isEmpty {
            printUsage()
            return
        }

        let policy = ScanPolicy(rawValue: options["policy"] ?? "standard") ?? .standard
        let quality = ModeratorDetector.Quality(rawValue: options["quality"] ?? "accurate") ?? .accurate

        let detector: ModeratorDetector
        do {
            if let path = options["model"] {
                detector = try ModeratorDetector(modelURL: URL(fileURLWithPath: path), quality: quality)
            } else {
                detector = try ModeratorDetector.loadFromDisk(quality: quality)
            }
        } catch {
            FileHandle.standardError.write(Data("加载模型失败：\(error.localizedDescription)\n".utf8))
            exit(2)
        }

        switch command {
        case "detect":
            guard positional.count >= 1 else { printUsage(); return }
            await runDetect(detector: detector, path: positional[0], policy: policy)
        case "scan":
            guard positional.count >= 1 else { printUsage(); return }
            await runScan(detector: detector, directory: URL(fileURLWithPath: positional[0]), policy: policy)
        default:
            printUsage()
        }
    }

    private static func runDetect(detector: ModeratorDetector, path: String, policy: ScanPolicy) async {
        let url = URL(fileURLWithPath: path)
        guard let image = loadImage(url) else {
            print("无法读取图片：\(path)")
            return
        }
        do {
            let result = try await detector.detect(image: image, policy: policy)
            print(resultLine(url.lastPathComponent, result))
        } catch {
            print("检测失败：\(error.localizedDescription)")
        }
    }

    private static func runScan(detector: ModeratorDetector, directory: URL, policy: ScanPolicy) async {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: directory,
                                         includingPropertiesForKeys: [.isRegularFileKey],
                                         options: [.skipsHiddenFiles]) else { return }
        var total = 0, flagged = 0
        let urls: [URL] = walker.compactMap { $0 as? URL }
        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard ["jpg", "jpeg", "png", "heic", "heif", "webp", "tiff", "bmp"].contains(ext) else { continue }
            guard let image = loadImage(url) else { continue }
            total += 1
            do {
                let result = try await detector.detect(image: image, policy: policy)
                if result.isSensitive {
                    flagged += 1
                    print(resultLine(url.lastPathComponent, result))
                }
            } catch {
                print("检测失败 \(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        print("\n共扫描 \(total) 张，命中 \(flagged) 张（策略：\(policy.displayName)）")
    }

    private static func resultLine(_ name: String, _ result: DetectionResult) -> String {
        let parts = result.regions.detectedParts.isEmpty ? "-" : result.regions.detectedParts.joined(separator: "/")
        return String(format: "%@  score=%.3f  sensitive=%@  部位=%@  [%.2f/%.2f/%.2f/%.2f/%.2f]",
                      name, result.score, result.isSensitive ? "是" : "否", parts,
                      result.regions.nipples, result.regions.genitals, result.regions.buttocks,
                      result.regions.nude, result.regions.sexAct)
    }

    private static func loadImage(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private static func printUsage() {
        print("""
        pdctl —— picture-divide 本机检测工具

        用法：
          pdctl detect <图片路径> [--model <模型目录>] [--policy standard|strict|allowTopless]
          pdctl scan <目录>     [--model <模型目录>] [--policy ...] [--quality fast|balanced|accurate]

        模型查找顺序：--model → 环境变量 PD_MODEL_PATH → ./Resources/Moderator.mlmodelc
        """)
    }
}
