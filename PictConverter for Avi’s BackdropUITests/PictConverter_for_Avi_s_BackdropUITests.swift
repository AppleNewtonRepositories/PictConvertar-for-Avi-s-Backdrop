import SwiftUI
import UniformTypeIdentifiers
import AppKit
import CoreGraphics

enum BackdropOrientation: String, CaseIterable, Identifiable {
    case vertical = "V (320x365)"
    case horizontal = "H (435x250)"

    var id: String { rawValue }

    var templateFileName: String {
        switch self {
        case .vertical: return "Test-V"
        case .horizontal: return "Test-H"
        }
    }

    var templateFileExtension: String { "pkg" }

    var width: Int {
        switch self {
        case .vertical: return 320
        case .horizontal: return 435
        }
    }

    var height: Int {
        switch self {
        case .vertical: return 365
        case .horizontal: return 250
        }
    }

    var rowBytesPacked4bpp: Int {
        return (width + 1) / 2
    }
}

struct ContentView: View {
    @State private var orientation: BackdropOrientation = .vertical
    @State private var packageName: String = "Backdrop01"
    @State private var versionString: String = "1.0"
    @State private var status: String = "Ready."

    @State private var selectedImage: NSImage?
    @State private var selectedImageURL: URL?

    // Fixes for your current symptoms
    @State private var invertGrayscale: Bool = true
    @State private var swapNibbles: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PictConverter for Avi’s Backdrop")
                .font(.title2)

            Picker("Orientation", selection: $orientation) {
                ForEach(BackdropOrientation.allCases) { o in
                    Text(o.rawValue).tag(o)
                }
            }
            .pickerStyle(.radioGroup)

            HStack(spacing: 10) {
                Button("Import Image") { importImage() }

                if let url = selectedImageURL {
                    Text(url.lastPathComponent)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("No image selected.")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Package name")
                    .frame(width: 120, alignment: .leading)
                TextField("Name shown on Newton", text: $packageName)
            }

            HStack {
                Text("Version")
                    .frame(width: 120, alignment: .leading)
                TextField("Example: 1.0", text: $versionString)
                    .frame(width: 120)
            }

            Divider()

            Toggle("Invert grayscale (fix negative)", isOn: $invertGrayscale)
            Toggle("Swap nibbles (if pixels look wrong)", isOn: $swapNibbles)

            HStack(spacing: 10) {
                Button("Generate PKG") { generatePkg() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedImage == nil)

                Button("Show template info") { showTemplateInfo() }
            }

            if let img = selectedImage {
                Divider()
                Text("Preview (auto center-crop to target size)")
                    .foregroundStyle(.secondary)

                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 220)
                    .cornerRadius(8)
            }

            Text(status)
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(18)
        .frame(minWidth: 760, minHeight: 620)
    }

    private func importImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        let resp = panel.runModal()
        guard resp == .OK, let url = panel.url else {
            status = "Import cancelled."
            return
        }

        guard let img = NSImage(contentsOf: url) else {
            status = "Could not read image."
            return
        }

        selectedImageURL = url
        selectedImage = img
        status = "Image loaded."
    }

    private func showTemplateInfo() {
        guard let url = Bundle.main.url(forResource: orientation.templateFileName,
                                        withExtension: orientation.templateFileExtension) else {
            status = "Template not found in app bundle. Add Test-V.pkg and Test-H.pkg to the target."
            return
        }
        do {
            let data = try Data(contentsOf: url)

            if let info = NewtonBackdropBitmapPatcher.debugFindStreamInfo(pkg: data, rows: orientation.height) {
                let avg = Double(info.totalPayloadBytes) / Double(orientation.height)
                status = "Template: \(orientation.templateFileName).pkg, size \(data.count) bytes. StreamStart \(info.streamStart). TotalPayload \(info.totalPayloadBytes). AvgPerRow \(String(format: "%.1f", avg))."
            } else {
                status = "Template: \(orientation.templateFileName).pkg, size \(data.count) bytes. Bitmap stream not found."
            }
        } catch {
            status = "Failed to read template: \(error.localizedDescription)"
        }
    }

    private func generatePkg() {
        guard let img = selectedImage else {
            status = "Select an image first."
            return
        }

        guard let templateURL = Bundle.main.url(forResource: orientation.templateFileName,
                                                withExtension: orientation.templateFileExtension) else {
            status = "Template not found. Add Test-V.pkg and Test-H.pkg to the target."
            return
        }

        do {
            var pkgData = try Data(contentsOf: templateURL)

            // Patch names (robust, covers multiple Newton Press variants)
            pkgData = try NewtonPkgPatcher.patchNamesRobust(
                in: pkgData,
                orientation: orientation,
                newName: packageName
            )

            // Convert image into packed 4bpp grayscale pixels
            let packed = try NewtonImageEncoder.renderAndPack4bpp(
                nsImage: img,
                targetWidth: orientation.width,
                targetHeight: orientation.height,
                invert: invertGrayscale,
                swapNibbles: swapNibbles
            )

            // Patch bitmap stream in-place using template row allocations
            pkgData = try NewtonBackdropBitmapPatcher.patchBitmapInPlace(
                in: pkgData,
                orientation: orientation,
                packed4bpp: packed
            )

            let saveURL = try SavePanel.pickSaveLocation(defaultFileName: safeFileName(packageName) + ".pkg")
            try pkgData.write(to: saveURL, options: .atomic)

            status = "Saved: \(saveURL.lastPathComponent). Install it on Newton."
        } catch {
            status = "Error: \(error.localizedDescription)"
        }
    }

    private func safeFileName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = s.components(separatedBy: bad).joined(separator: "_")
        return cleaned.isEmpty ? "Backdrop" : cleaned
    }
}



enum NewtonPkgPatcher {

    static func patchNamesRobust(in data: Data, orientation: BackdropOrientation, newName: String) throws -> Data {
        var out = data

        let baseCandidates: [String]
        let aCandidates: [String]

        switch orientation {
        case .vertical:
            baseCandidates = [
                "Test-V", "Test V", "TEST-V", "TEST V",
                "Scale-V", "Scale V"
            ]
            aCandidates = [
                "A!:Test-V", "A!: Test-V", "A!:Test V", "A!: Test V",
                "A!:Scale-V", "A!: Scale-V", "A!:Scale V", "A!: Scale V"
            ]
        case .horizontal:
            baseCandidates = [
                "Test-H", "Test H", "TEST-H", "TEST H",
                "Scale-H", "Scale H"
            ]
            aCandidates = [
                "A!:Test-H", "A!: Test-H", "A!:Test H", "A!: Test H",
                "A!:Scale-H", "A!: Scale-H", "A!:Scale H", "A!: Scale H"
            ]
        }

        // Replace ALL occurrences of any candidate we can find.
        // If none found, throw an error so you know the template differs.
        var replacedAny = false

        for old in baseCandidates {
            let count = replaceAllUtf16BEZStringExact(in: &out, oldValue: old, newValue: newName)
            if count > 0 { replacedAny = true }
        }

        for old in aCandidates {
            let count = replaceAllUtf16BEZStringExact(in: &out, oldValue: old, newValue: "A!:" + newName)
            if count > 0 { replacedAny = true }
        }

        if !replacedAny {
            throw NSError(domain: "NewtonPkgPatcher", code: 20, userInfo: [
                NSLocalizedDescriptionKey: "Could not find template name strings to patch. Template differs from expected Newton Press output."
            ])
        }

        return out
    }

    @discardableResult
    private static func replaceAllUtf16BEZStringExact(in data: inout Data, oldValue: String, newValue: String) -> Int {
        let oldBytes = encodeUtf16BEZ(oldValue)
        if oldBytes.isEmpty { return 0 }

        var count = 0
        var searchStart = 0

        while searchStart <= max(0, data.count - oldBytes.count) {
            guard let r = findFirstOccurrence(data: data, pattern: oldBytes, start: searchStart) else {
                break
            }

            var replacement = encodeUtf16BEZ(newValue)

            // Keep file size stable for this field
            if replacement.count < r.count {
                replacement.append(Data(repeating: 0x00, count: r.count - replacement.count))
            } else if replacement.count > r.count {
                replacement = replacement.prefix(r.count)
            }

            data.replaceSubrange(r, with: replacement)
            count += 1
            searchStart = r.upperBound
        }

        return count
    }

    private static func encodeUtf16BEZ(_ s: String) -> Data {
        var d = Data()
        for u in s.utf16 {
            d.append(UInt8((u >> 8) & 0xFF))
            d.append(UInt8(u & 0xFF))
        }
        d.append(0x00)
        d.append(0x00)
        return d
    }

    private static func findFirstOccurrence(data: Data, pattern: Data, start: Int) -> Range<Int>? {
        if pattern.isEmpty { return nil }
        if start < 0 || start >= data.count { return nil }
        if data.count < pattern.count { return nil }

        return data.withUnsafeBytes { rawBuf in
            let hay = rawBuf.bindMemory(to: UInt8.self)
            return pattern.withUnsafeBytes { patBuf in
                let pat = patBuf.bindMemory(to: UInt8.self)
                if hay.count < pat.count { return nil }

                let last = hay.count - pat.count
                if start > last { return nil }

                for i in start...last {
                    var match = true
                    for j in 0..<pat.count {
                        if hay[i + j] != pat[j] { match = false; break }
                    }
                    if match { return i..<(i + pat.count) }
                }
                return nil
            }
        }
    }
}

enum NewtonImageEncoder {

    static func renderAndPack4bpp(nsImage: NSImage,
                                 targetWidth: Int,
                                 targetHeight: Int,
                                 invert: Bool,
                                 swapNibbles: Bool) throws -> Data {
        var proposedRect = CGRect(origin: .zero, size: nsImage.size)
        guard let cg = nsImage.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            throw NSError(domain: "NewtonImageEncoder", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not convert image to CGImage."
            ])
        }

        let w = targetWidth
        let h = targetHeight

        var gray = [UInt8](repeating: 0, count: w * h)
        let bytesPerRow = w

        guard let ctx = CGContext(
            data: &gray,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw NSError(domain: "NewtonImageEncoder", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Could not create a grayscale drawing context."
            ])
        }

        // Auto center-crop with aspect fill
        let srcW = CGFloat(cg.width)
        let srcH = CGFloat(cg.height)
        let dstW = CGFloat(w)
        let dstH = CGFloat(h)

        let scale = max(dstW / srcW, dstH / srcH)
        let drawW = srcW * scale
        let drawH = srcH * scale
        let x = (dstW - drawW) / 2.0
        let y = (dstH - drawH) / 2.0

        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: x, y: y, width: drawW, height: drawH))

        // Pack to 4bpp
        let rowBytesPacked = (w + 1) / 2
        var packed = [UInt8](repeating: 0, count: rowBytesPacked * h)

        for yy in 0..<h {
            for xx in 0..<w {
                let g8 = gray[yy * w + xx]
                var g4 = UInt8((Int(g8) * 15 + 127) / 255) // 0..15

                if invert {
                    g4 = 15 - g4
                }

                let outIndex = yy * rowBytesPacked + (xx / 2)

                if !swapNibbles {
                    // default: left pixel in high nibble, right pixel in low nibble
                    if (xx % 2) == 0 {
                        packed[outIndex] = (g4 << 4) | (packed[outIndex] & 0x0F)
                    } else {
                        packed[outIndex] = (packed[outIndex] & 0xF0) | (g4 & 0x0F)
                    }
                } else {
                    // swapped: left pixel in low nibble, right pixel in high nibble
                    if (xx % 2) == 0 {
                        packed[outIndex] = (packed[outIndex] & 0xF0) | (g4 & 0x0F)
                    } else {
                        packed[outIndex] = (g4 << 4) | (packed[outIndex] & 0x0F)
                    }
                }
            }
        }

        return Data(packed)
    }
}

enum NewtonBackdropBitmapPatcher {

    struct StreamDebugInfo {
        let streamStart: Int
        let totalPayloadBytes: Int
    }

    static func debugFindStreamInfo(pkg: Data, rows: Int) -> StreamDebugInfo? {
        guard let candidate = findBestBitmapStreamStart(pkg: pkg, rowCount: rows) else { return nil }
        return StreamDebugInfo(streamStart: candidate.start, totalPayloadBytes: candidate.totalPayload)
    }

    static func patchBitmapInPlace(in pkg: Data, orientation: BackdropOrientation, packed4bpp: Data) throws -> Data {
        let rowBytes = orientation.rowBytesPacked4bpp
        let rows = orientation.height

        guard let best = findBestBitmapStreamStart(pkg: pkg, rowCount: rows) else {
            throw NSError(domain: "NewtonBackdropBitmapPatcher", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not locate bitmap stream in template."
            ])
        }

        let rowLayouts = try parseRowLayout(pkg: pkg, streamStart: best.start, rows: rows)

        if packed4bpp.count != rowBytes * rows {
            throw NSError(domain: "NewtonBackdropBitmapPatcher", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Internal error: packed image size mismatch."
            ])
        }

        var out = pkg

        for r in 0..<rows {
            let rowPacked = packed4bpp[(r * rowBytes)..<((r + 1) * rowBytes)]
            let compressed = PackBits.compress(Data(rowPacked))

            let allocLen = rowLayouts[r].payloadLen
            if compressed.count > allocLen {
                throw NSError(domain: "NewtonBackdropBitmapPatcher", code: 3, userInfo: [
                    NSLocalizedDescriptionKey:
                        "Image is too complex for this template. Row \(r + 1) needs \(compressed.count) bytes, template allows \(allocLen)."
                ])
            }

            var padded = compressed
            if padded.count < allocLen {
                padded.append(Data(repeating: 0x80, count: allocLen - padded.count))
            }

            out.replaceSubrange(rowLayouts[r].payloadOffset..<(rowLayouts[r].payloadOffset + allocLen), with: padded)
        }

        return out
    }

    private struct Candidate {
        let start: Int
        let totalPayload: Int
    }

    private static func findBestBitmapStreamStart(pkg: Data, rowCount: Int) -> Candidate? {
        if rowCount <= 0 || pkg.count < 10 { return nil }

        var best: Candidate?
        let maxStart = max(0, pkg.count - 2)

        for start in 0..<maxStart {
            var i = start
            var ok = true
            var total = 0

            for _ in 0..<rowCount {
                if i >= pkg.count { ok = false; break }
                let L = Int(pkg[i])
                if L == 0 { ok = false; break }
                i += 1
                if i + L > pkg.count { ok = false; break }
                total += L
                i += L
            }

            if ok {
                if let b = best {
                    if total > b.totalPayload {
                        best = Candidate(start: start, totalPayload: total)
                    }
                } else {
                    best = Candidate(start: start, totalPayload: total)
                }
            }
        }

        return best
    }

    private struct RowLayout {
        let payloadOffset: Int
        let payloadLen: Int
    }

    private static func parseRowLayout(pkg: Data, streamStart: Int, rows: Int) throws -> [RowLayout] {
        var layouts: [RowLayout] = []
        layouts.reserveCapacity(rows)

        var i = streamStart
        for _ in 0..<rows {
            if i >= pkg.count {
                throw NSError(domain: "NewtonBackdropBitmapPatcher", code: 10, userInfo: [
                    NSLocalizedDescriptionKey: "Template stream parsing failed."
                ])
            }
            let L = Int(pkg[i])
            if L == 0 {
                throw NSError(domain: "NewtonBackdropBitmapPatcher", code: 11, userInfo: [
                    NSLocalizedDescriptionKey: "Template stream parsing failed. Found zero row length."
                ])
            }
            i += 1
            let payloadOff = i
            if i + L > pkg.count {
                throw NSError(domain: "NewtonBackdropBitmapPatcher", code: 12, userInfo: [
                    NSLocalizedDescriptionKey: "Template stream parsing failed."
                ])
            }
            layouts.append(RowLayout(payloadOffset: payloadOff, payloadLen: L))
            i += L
        }

        return layouts
    }
}

enum PackBits {
    static func compress(_ input: Data) -> Data {
        let bytes = [UInt8](input)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)

        var i = 0
        while i < bytes.count {
            let runStart = i
            var runLen = 1

            while runStart + runLen < bytes.count && bytes[runStart] == bytes[runStart + runLen] && runLen < 128 {
                runLen += 1
            }

            if runLen >= 3 {
                out.append(UInt8(257 - runLen))
                out.append(bytes[runStart])
                i += runLen
                continue
            }

            let litStart = i
            var litLen = 0

            while i < bytes.count && litLen < 128 {
                var tRunLen = 1
                while i + tRunLen < bytes.count && bytes[i] == bytes[i + tRunLen] && tRunLen < 128 {
                    tRunLen += 1
                }
                if tRunLen >= 3 { break }
                i += 1
                litLen += 1
            }

            out.append(UInt8(litLen - 1))
            out.append(contentsOf: bytes[litStart..<(litStart + litLen)])
        }

        return Data(out)
    }
}
