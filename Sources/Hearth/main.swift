import AppKit
import SwiftUI
import HearthCore

/// Draws the app icon in code, so the build needs no design assets: `Hearth --make-icon <dir.iconset>`.
@MainActor
enum IconMaker {
    struct IconView: View {
        let s: CGFloat
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.99, green: 0.62, blue: 0.25), Color(red: 0.86, green: 0.30, blue: 0.16)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: s * 0.82, height: s * 0.82)
                    .shadow(color: .black.opacity(0.25), radius: s * 0.02, y: s * 0.012)
                Image(systemName: "house.fill").font(.system(size: s * 0.42, weight: .bold)).foregroundStyle(.white)
                Image(systemName: "heart.fill").font(.system(size: s * 0.15, weight: .bold))
                    .foregroundStyle(Color(red: 0.86, green: 0.30, blue: 0.16)).offset(y: s * 0.055)
            }
            .frame(width: s, height: s)
        }
    }

    static func run(dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let sizes: [(String, CGFloat)] = [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                                          ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256),
                                          ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)]
        for (name, px) in sizes {
            let r = ImageRenderer(content: IconView(s: px))
            r.scale = 1
            guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: URL(fileURLWithPath: dir + "/" + name + ".png"))
        }
    }
}

let args = CommandLine.arguments

if let i = args.firstIndex(of: "--make-icon"), args.count > i + 1 {
    MainActor.assumeIsolated { IconMaker.run(dir: args[i + 1]) }
    exit(0)
}
if let i = args.firstIndex(of: "--render") {
    let dir = args.count > i + 1 ? args[i + 1] : "."
    MainActor.assumeIsolated { RenderScenes.run(outDir: dir) }
    print("rendered to \(dir)")
    exit(0)
}
if args.contains("--selftest") {
    let dir = NSTemporaryDirectory() + "/hearth-selftest-\(UUID().uuidString)"
    let code = MainActor.assumeIsolated { RenderScenes.selftest(outDir: dir) }
    try? FileManager.default.removeItem(atPath: dir)
    exit(code)
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { HearthApp(windowed: args.contains("--windowed")) }
app.delegate = delegate
app.run()
