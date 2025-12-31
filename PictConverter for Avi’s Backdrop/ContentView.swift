import SwiftUI
import UniformTypeIdentifiers
import AppKit
import CoreGraphics
import Security

// MARK: - Models

enum BackdropOrientation: String, CaseIterable, Identifiable {
    case vertical = "vertical"
    case horizontal = "horizontal"

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .vertical: return "Vertical"
        case .horizontal: return "Horizontal"
        }
    }

    var templateFileName: String {
        switch self {
        case .vertical: return "LONGNAME-V-LONGNAME"
        case .horizontal: return "LONGNAME-H-LONGNAME"
        }
    }

    var templateFileExtension: String { "pkg" }

    var titlePlaceholder: String {
        switch self {
        case .vertical: return "SHORTTITLE-V"
        case .horizontal: return "SHORTTITLE-H"
        }
    }

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

    var rowBytesPacked4bpp: Int { (width + 1) / 2 }
}

enum DitherMode: String, CaseIterable, Identifiable {
    case off = "off"
    case floyd = "floyd"

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .off: return "Off"
        case .floyd: return "Floyd–Steinberg"
        }
    }
}

enum OnOff: String, CaseIterable, Identifiable {
    case on = "on"
    case off = "off"
    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .on: return "On"
        case .off: return "Off"
        }
    }

    var boolValue: Bool { self == .on }
    static func fromBool(_ v: Bool) -> OnOff { v ? .on : .off }
}

struct TemplateCaps {
    let titleMaxChars: Int
    let installerMaxChars: Int
}

struct TemplateInfoItem: Identifiable {
    let id = UUID()
    let name: String
    let value: String
}

struct TemplateInfoReport {
    let title: String
    let items: [TemplateInfoItem]
}

enum StatusLevel {
    case ok
    case warning
    case error

    var iconName: String {
        switch self {
        case .ok: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }
}

// MARK: - View

struct ContentView: View {

    private let idPrefix = "A!:"
    private let displayNameMaxChars = 12

    @AppStorage("orientationRaw") private var orientationRawStored: String = BackdropOrientation.vertical.rawValue
    @AppStorage("displayName") private var displayNameStored: String = "Backdrop01H"
    @AppStorage("invertGrayscale") private var invertGrayscaleStored: Bool = true
    @AppStorage("swapNibbles") private var swapNibblesStored: Bool = false
    @AppStorage("ditherModeRaw") private var ditherModeRawStored: String = DitherMode.floyd.rawValue
    @AppStorage("advancedOpen") private var advancedOpenStored: Bool = true

    @State private var orientation: BackdropOrientation = .vertical
    @State private var caps: TemplateCaps? = nil

    @State private var statusText: String = "Ready."
    @State private var statusLevel: StatusLevel = .ok

    @State private var selectedImage: NSImage?
    @State private var selectedImageURL: URL?

    @State private var showTemplateSheet: Bool = false
    @State private var templateReport: TemplateInfoReport? = nil

    private var packageNameCount: Int { min(displayNameStored.count, displayNameMaxChars) }
    private var packageNameProgress: Double {
        if displayNameMaxChars == 0 { return 0 }
        return Double(packageNameCount) / Double(displayNameMaxChars)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // CONTENT (top pinned)
            HStack(alignment: .top, spacing: 12) {

                // LEFT
                VStack(alignment: .leading, spacing: 0) {

                    GroupBox(label: sectionLabel("Picture source")) {
                        VStack(alignment: .leading, spacing: 8) {

                            Button("Upload image") { importImage() }
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text("Accepted file types: PNG, JPG/JPEG, TIFF. You can also drag and drop a file onto this window.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 8) {
                                Text("Selected:")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)

                                if let url = selectedImageURL {
                                    Text(url.lastPathComponent)
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                } else {
                                    Text("None")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                    }
                    .padding(.bottom, 23)

                    GroupBox(label: sectionLabel("Picture orientation")) {
                        VStack(alignment: .leading, spacing: 8) {

                            Picker("", selection: $orientation) {
                                ForEach(BackdropOrientation.allCases) { o in
                                    Text(o.displayLabel).tag(o)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.radioGroup)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 10) {
                                Text("Target size")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)

                                Text("\(orientation.width)x\(orientation.height)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)

                                Spacer()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                    }
                    .padding(.bottom, 23)

                    GroupBox(label: sectionLabel("Package name")) {
                        VStack(alignment: .leading, spacing: 8) {

                            HStack(alignment: .center, spacing: 10) {
                                TextField("Max 12 chars", text: Binding(
                                    get: { displayNameStored },
                                    set: { newValue in
                                        let trimmed = String(newValue.prefix(displayNameMaxChars))
                                        if trimmed != newValue {
                                            displayNameStored = trimmed
                                            setStatus(.warning, "Package name trimmed to 12 characters.")
                                        } else {
                                            displayNameStored = newValue
                                        }
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200, alignment: .leading)

                                VStack(alignment: .leading, spacing: 2) {
                                    ProgressView(value: packageNameProgress)
                                        .frame(width: 140)

                                    Text("\(packageNameCount)/12")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                    }
                    .padding(.bottom, 23)

                    GroupBox(label: sectionLabel("Advanced")) {
                        VStack(alignment: .leading, spacing: 6) {

                            DisclosureGroup(isExpanded: Binding(
                                get: { advancedOpenStored },
                                set: { advancedOpenStored = $0 }
                            )) {
                                VStack(alignment: .leading, spacing: 10) {

                                    HStack(spacing: 10) {
                                        Text("Invert grayscale")
                                            .font(.system(size: 12))
                                            .frame(width: 140, alignment: .leading)

                                        Picker("", selection: Binding(
                                            get: { OnOff.fromBool(invertGrayscaleStored) },
                                            set: { invertGrayscaleStored = $0.boolValue }
                                        )) {
                                            ForEach(OnOff.allCases) { m in
                                                Text(m.displayLabel).tag(m)
                                            }
                                        }
                                        .frame(width: 180, alignment: .leading)

                                        Spacer()
                                    }

                                    HStack(spacing: 10) {
                                        Text("Swap nibbles")
                                            .font(.system(size: 12))
                                            .frame(width: 140, alignment: .leading)

                                        Picker("", selection: Binding(
                                            get: { OnOff.fromBool(swapNibblesStored) },
                                            set: { swapNibblesStored = $0.boolValue }
                                        )) {
                                            ForEach(OnOff.allCases) { m in
                                                Text(m.displayLabel).tag(m)
                                            }
                                        }
                                        .frame(width: 180, alignment: .leading)

                                        Spacer()
                                    }

                                    HStack(spacing: 10) {
                                        Text("Dithering")
                                            .font(.system(size: 12))
                                            .frame(width: 140, alignment: .leading)

                                        Picker("", selection: Binding(
                                            get: { DitherMode(rawValue: ditherModeRawStored) ?? .floyd },
                                            set: { ditherModeRawStored = $0.rawValue }
                                        )) {
                                            ForEach(DitherMode.allCases) { m in
                                                Text(m.displayLabel).tag(m)
                                            }
                                        }
                                        .frame(width: 180, alignment: .leading)

                                        Spacer()
                                    }

                                    HStack {
                                        Spacer()
                                        Button("Some Dev stuff...") {
                                            buildAndShowTemplateInfo()
                                        }
                                        .font(.system(size: 12))
                                    }
                                }
                                .padding(.top, 6)
                            } label: {
                                Text("Advanced options")
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                    }

                    Spacer(minLength: 0)
                }
                .frame(width: 500, alignment: .leading)

                // RIGHT
                VStack(alignment: .leading, spacing: 0) {

                    GroupBox(label: sectionLabel("Preview")) {
                        VStack(alignment: .leading, spacing: 6) {

                            Text("Final crop (what gets converted)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)

                            if let img = selectedImage,
                               let cropped = makeCroppedPreview(nsImage: img,
                                                               targetWidth: orientation.width,
                                                               targetHeight: orientation.height) {

                                Image(nsImage: cropped)
                                    .resizable()
                                    .interpolation(.high)
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 304)
                                    .overlay(
                                        Rectangle()
                                            .stroke(Color.green, lineWidth: 1)
                                    )

                                Text("\(orientation.width)x\(orientation.height)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.top, 10)
                                    .padding(.bottom, 11)

                            } else {
                                VStack(spacing: 0) {
                                    Text("No preview.")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)

                                    Text("Upload or drag an image to see the final crop preview.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 345, alignment: .center)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                    }
                    .padding(.bottom, 23)

                    GroupBox(label: Text("Generate")) {
                        VStack(alignment: .center, spacing: 8) {

                            Button {
                                generatePkg()
                            } label: {
                                Text("Generate Package")
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(minWidth: 255, minHeight: 40, alignment: .center)
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(height: 52)
                            .disabled(selectedImage == nil)
                            .frame(alignment: .center)

                            Text("Press the button to generate package.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                    }

                    Spacer(minLength: 0)
                }
                .frame(width: 276, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            // ONLY this spacer pushes status bar to the bottom
            Spacer(minLength: 0)

            // STATUS BAR (bottom pinned)
            HStack(spacing: 8) {
                Image(systemName: statusLevel.iconName)
                    .imageScale(.medium)

                Text(statusText)
                    .font(.system(size: 12))
                    .lineLimit(1)

                Spacer()

                if selectedImage != nil {
                    Text("Image: OK")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Image: missing")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.thinMaterial)
            .cornerRadius(5)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .frame(width: 812) // 800 minus 12 minus 12
        }
        .frame(width: 800, height: 590)
        .onAppear {
            let restored = BackdropOrientation(rawValue: orientationRawStored) ?? .vertical
            orientation = restored
            advancedOpenStored = true
        }
        .onChange(of: orientation) { _, newValue in
            orientationRawStored = newValue.rawValue
            caps = nil
            setStatus(.ok, "Orientation changed.")
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .sheet(isPresented: $showTemplateSheet) {
            TemplateInfoSheet(report: templateReport, isPresented: $showTemplateSheet)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setStatus(_ level: StatusLevel, _ text: String) {
        statusLevel = level
        statusText = text
    }

    // MARK: - Drop + Import

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    loadImage(from: url)
                }
            }
            return true
        }
        return false
    }

    private func importImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        let resp = panel.runModal()
        guard resp == .OK, let url = panel.url else {
            setStatus(.warning, "Upload cancelled.")
            return
        }
        loadImage(from: url)
    }

    private func loadImage(from url: URL) {
        guard let img = NSImage(contentsOf: url) else {
            setStatus(.error, "Could not read image.")
            return
        }
        selectedImageURL = url
        selectedImage = img
        setStatus(.ok, "Image loaded.")
    }

    // MARK: - Template Info

    private func buildAndShowTemplateInfo() {
        do {
            let report = try makeTemplateInfoReport()
            templateReport = report
            showTemplateSheet = true
            setStatus(.ok, "Template info ready.")
        } catch {
            setStatus(.error, "Error: \(error.localizedDescription)")
        }
    }

    private func makeTemplateInfoReport() throws -> TemplateInfoReport {
        guard let templateURL = Bundle.main.url(forResource: orientation.templateFileName,
                                               withExtension: orientation.templateFileExtension) else {
            throw NSError(domain: "TemplateInfo", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Template not found in app bundle. Check Copy Bundle Resources."
            ])
        }

        let data = try Data(contentsOf: templateURL)

        guard let installerCap = NewtonPkgPatcher.installerNameCapacityChars(in: data) else {
            throw NSError(domain: "TemplateInfo", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Installer name area not detected in template."
            ])
        }

        guard let titleCap = NewtonPkgPatcher.titleFieldCapacityChars(in: data, placeholder: orientation.titlePlaceholder) else {
            throw NSError(domain: "TemplateInfo", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Title placeholder not found: \(orientation.titlePlaceholder)"
            ])
        }

        let c = TemplateCaps(titleMaxChars: titleCap, installerMaxChars: installerCap)
        caps = c

        let padded12 = paddedDisplayName12()
        let randomId = idPrefix + PCHexRandom.randomLowerHex12()

        let items: [TemplateInfoItem] = [
            .init(name: "Template file", value: "\(orientation.templateFileName).\(orientation.templateFileExtension)"),
            .init(name: "Orientation", value: orientation.displayLabel),
            .init(name: "Target bitmap size", value: "\(orientation.width)x\(orientation.height)"),
            .init(name: "Row bytes (packed 4bpp)", value: "\(orientation.rowBytesPacked4bpp)"),
            .init(name: "Title placeholder", value: orientation.titlePlaceholder),
            .init(name: "Detected Title capacity", value: "\(titleCap) chars"),
            .init(name: "Detected Installer-name capacity", value: "\(installerCap) chars"),
            .init(name: "Package name (typed)", value: displayNameStored),
            .init(name: "Package name (internal padded 12)", value: visibleSpaces(padded12)),
            .init(name: "Identifier example (random)", value: randomId),
            .init(name: "Installer-name header markers", value: "UTF-16BE \"drds\\0\" to ASCII \"bookBuilt with Newton Press\""),
            .init(name: "Advanced: Invert grayscale", value: invertGrayscaleStored ? "On" : "Off"),
            .init(name: "Advanced: Swap nibbles", value: swapNibblesStored ? "On" : "Off"),
            .init(name: "Advanced: Dithering", value: (DitherMode(rawValue: ditherModeRawStored) ?? .floyd).displayLabel),
            .init(name: "Template size", value: "\(data.count) bytes")
        ]

        return TemplateInfoReport(title: "Template info", items: items)
    }

    private func visibleSpaces(_ s: String) -> String {
        s.replacingOccurrences(of: " ", with: "␠")
    }

    // MARK: - Generate

    private func paddedDisplayName12() -> String {
        let base = String(displayNameStored.prefix(displayNameMaxChars))
        if base.count >= displayNameMaxChars { return base }
        return base + String(repeating: " ", count: displayNameMaxChars - base.count)
    }

    private func safeFileBaseName(from padded12: String) -> String {
        let trimmed = padded12.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Backdrop" }
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = trimmed.components(separatedBy: bad).joined(separator: "_")
        return cleaned.isEmpty ? "Backdrop" : cleaned
    }

    private func generatePkg() {
        guard let img = selectedImage else {
            setStatus(.warning, "Select an image first.")
            return
        }

        guard let templateURL = Bundle.main.url(forResource: orientation.templateFileName,
                                               withExtension: orientation.templateFileExtension) else {
            setStatus(.error, "Template not found. Add it to Copy Bundle Resources.")
            return
        }

        do {
            var pkgData = try Data(contentsOf: templateURL)

            let computedCaps: TemplateCaps
            if let c = caps {
                computedCaps = c
            } else {
                guard let installerCap = NewtonPkgPatcher.installerNameCapacityChars(in: pkgData),
                      let titleCap = NewtonPkgPatcher.titleFieldCapacityChars(in: pkgData, placeholder: orientation.titlePlaceholder) else {
                    throw NSError(domain: "TemplateCaps", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Could not detect template capacities. Use “Some Dev stuff...” once."
                    ])
                }
                computedCaps = TemplateCaps(titleMaxChars: titleCap, installerMaxChars: installerCap)
                caps = computedCaps
            }

            if computedCaps.titleMaxChars < 12 || computedCaps.installerMaxChars < 12 {
                throw NSError(domain: "TemplateCaps", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Template capacities are smaller than 12. Regenerate templates in Newton Press."
                ])
            }

            let display12 = paddedDisplayName12()
            let titleValue = String(display12.prefix(computedCaps.titleMaxChars))
            let installerValue = String(display12.prefix(computedCaps.installerMaxChars))

            let identifier = idPrefix + PCHexRandom.randomLowerHex12()

            _ = try NewtonPkgPatcher.patchAll(
                in: &pkgData,
                titlePlaceholder: orientation.titlePlaceholder,
                newTitle: titleValue,
                newInstallerName: installerValue,
                newIdentifier: identifier
            )

            let dither = DitherMode(rawValue: ditherModeRawStored) ?? .floyd

            let packed = try NewtonImageEncoder.renderAndPack4bpp(
                nsImage: img,
                targetWidth: orientation.width,
                targetHeight: orientation.height,
                invert: invertGrayscaleStored,
                swapNibbles: swapNibblesStored,
                dither: dither
            )

            pkgData = try NewtonBackdropBitmapPatcher.patchBitmapInPlace(
                in: pkgData,
                orientation: orientation,
                packed4bpp: packed
            )

            let defaultFileName = safeFileBaseName(from: display12) + ".pkg"
            let saveURL = try PCSavePanel.pickSaveLocation(defaultFileName: defaultFileName)
            try pkgData.write(to: saveURL, options: .atomic)

            setStatus(.ok, "Saved \(saveURL.lastPathComponent).")
        } catch {
            setStatus(.error, "Error: \(error.localizedDescription)")
        }
    }

    // MARK: - Preview crop rendering

    private func makeCroppedPreview(nsImage: NSImage, targetWidth: Int, targetHeight: Int) -> NSImage? {
        var proposedRect = CGRect(origin: .zero, size: nsImage.size)
        guard let cg = nsImage.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else { return nil }

        let w = targetWidth
        let h = targetHeight

        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

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

        guard let outCG = ctx.makeImage() else { return nil }
        return NSImage(cgImage: outCG, size: NSSize(width: w, height: h))
    }
}

// MARK: - Template info popup

struct TemplateInfoSheet: View {
    let report: TemplateInfoReport?
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(report?.title ?? "Template info")
                .font(.system(size: 14, weight: .semibold))

            if let items = report?.items {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(items) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Text(item.name + ":")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 240, alignment: .leading)

                                Text(item.value)
                                    .font(.system(size: 11))
                                    .textSelection(.enabled)

                                Spacer()
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            } else {
                Text("No data.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Close") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .frame(width: 640, height: 440)
    }
}

// MARK: - PKG patching (names)

enum NewtonPkgPatcher {

    struct PatchCounts {
        let title: Int
        let installer: Int
        let identifier: Int
    }

    static func installerNameCapacityChars(in data: Data) -> Int? {
        let marker = Data("bookBuilt with Newton Press".utf8)
        guard let markerOff = data.firstRange(of: marker)?.lowerBound else { return nil }

        let drds = utf16beZ("drds")
        guard let drdsOff = data.firstRange(of: drds)?.lowerBound else { return nil }

        let nameStart = drdsOff + drds.count
        if nameStart >= markerOff { return nil }

        let capacityBytes = markerOff - nameStart
        if capacityBytes < 2 { return nil }

        let capacityCharsIncludingTerm = capacityBytes / 2
        let maxChars = max(0, capacityCharsIncludingTerm - 1)
        return maxChars
    }

    static func titleFieldCapacityChars(in data: Data, placeholder: String) -> Int? {
        let pat = utf16be(placeholder)
        guard let start = data.firstRange(of: pat)?.lowerBound else { return nil }

        var i = start
        var term: Int? = nil
        while i + 1 < data.count {
            if data[i] == 0x00 && data[i + 1] == 0x00 {
                term = i
                break
            }
            i += 2
        }
        guard let termOff = term else { return nil }

        var end = termOff + 2
        while end < data.count && data[end] == 0xBA { end += 1 }

        let capacityBytes = end - start
        if capacityBytes < 2 { return nil }

        let capacityCharsIncludingTerm = capacityBytes / 2
        let maxChars = max(0, capacityCharsIncludingTerm - 1)
        return maxChars
    }

    static func patchAll(in data: inout Data,
                         titlePlaceholder: String,
                         newTitle: String,
                         newInstallerName: String,
                         newIdentifier: String) throws -> PatchCounts {

        let titleCount = replaceTitleUtf16BEZWithBAPadding(
            in: &data,
            placeholder: titlePlaceholder,
            newValue: newTitle
        )

        let installerCount = replaceInstallerNameInHeaderNoEarlyZeros(
            in: &data,
            newInstallerName: newInstallerName
        )

        let idCount = replaceIdentifierByPrefixFixed15Utf16BE(
            in: &data,
            newIdentifier: newIdentifier
        )

        if titleCount == 0 {
            throw NSError(domain: "NewtonPkgPatcher", code: 200, userInfo: [
                NSLocalizedDescriptionKey: "Title placeholder not found. Ensure template contains \(titlePlaceholder)."
            ])
        }
        if installerCount == 0 {
            throw NSError(domain: "NewtonPkgPatcher", code: 202, userInfo: [
                NSLocalizedDescriptionKey: "Installer name area not found in template."
            ])
        }
        if idCount == 0 {
            throw NSError(domain: "NewtonPkgPatcher", code: 203, userInfo: [
                NSLocalizedDescriptionKey: "Identifier field not found. Ensure template contains A!:ABCDEFGHIJKL."
            ])
        }

        return PatchCounts(title: titleCount, installer: installerCount, identifier: idCount)
    }

    private static func utf16be(_ s: String) -> Data {
        var out = Data()
        out.reserveCapacity(s.utf16.count * 2)
        for u in s.utf16 {
            out.append(UInt8((u >> 8) & 0xFF))
            out.append(UInt8(u & 0xFF))
        }
        return out
    }

    private static func utf16beZ(_ s: String) -> Data {
        var out = utf16be(s)
        out.append(0x00)
        out.append(0x00)
        return out
    }

    private static func findAllOccurrences(hay: Data, pat: Data) -> [Int] {
        if pat.isEmpty || hay.count < pat.count { return [] }
        var res: [Int] = []
        var start = 0
        while start <= hay.count - pat.count {
            if let r = hay.range(of: pat, options: [], in: start..<hay.count) {
                res.append(r.lowerBound)
                start = r.lowerBound + 1
            } else {
                break
            }
        }
        return res
    }

    @discardableResult
    private static func replaceTitleUtf16BEZWithBAPadding(in data: inout Data,
                                                         placeholder: String,
                                                         newValue: String) -> Int {
        let pat = utf16be(placeholder)
        let hits = findAllOccurrences(hay: data, pat: pat)
        if hits.isEmpty { return 0 }

        var patched = 0
        for start in hits {
            var term: Int? = nil
            var i = start
            while i + 1 < data.count {
                if data[i] == 0x00 && data[i + 1] == 0x00 {
                    term = i
                    break
                }
                i += 2
            }
            guard let termOff = term else { continue }

            var end = termOff + 2
            while end < data.count && data[end] == 0xBA { end += 1 }

            let capacity = end - start
            if capacity <= 0 { continue }

            var rep = utf16beZ(newValue)
            if rep.count > capacity {
                rep = rep.prefix(capacity)
                rep[capacity - 2] = 0x00
                rep[capacity - 1] = 0x00
            } else if rep.count < capacity {
                rep.append(Data(repeating: 0xBA, count: capacity - rep.count))
            }

            data.replaceSubrange(start..<(start + capacity), with: rep)
            patched += 1
        }

        return patched
    }

    @discardableResult
    private static func replaceInstallerNameInHeaderNoEarlyZeros(in data: inout Data,
                                                                 newInstallerName: String) -> Int {
        let marker = Data("bookBuilt with Newton Press".utf8)
        guard let markerOff = data.firstRange(of: marker)?.lowerBound else { return 0 }

        let drds = utf16beZ("drds")
        guard let drdsOff = data.firstRange(of: drds)?.lowerBound else { return 0 }

        let nameStart = drdsOff + drds.count
        if nameStart >= markerOff { return 0 }

        let capacityBytes = markerOff - nameStart
        if capacityBytes < 2 { return 0 }

        let capacityChars = capacityBytes / 2
        if capacityChars < 2 { return 0 }

        let maxChars = capacityChars - 1
        var value = String(newInstallerName.prefix(maxChars))
        if value.count < maxChars {
            value += String(repeating: " ", count: maxChars - value.count)
        }

        var rep = utf16be(value)
        rep.append(0x00)
        rep.append(0x00)

        if rep.count != capacityBytes {
            if rep.count > capacityBytes {
                rep = rep.prefix(capacityBytes)
                rep[capacityBytes - 2] = 0x00
                rep[capacityBytes - 1] = 0x00
            } else {
                rep.append(Data(repeating: 0x00, count: capacityBytes - rep.count))
            }
        }

        data.replaceSubrange(nameStart..<(nameStart + capacityBytes), with: rep)
        return 1
    }

    @discardableResult
    private static func replaceIdentifierByPrefixFixed15Utf16BE(in data: inout Data,
                                                                newIdentifier: String) -> Int {
        let prefix = utf16be("A!:")
        let hits = findAllOccurrences(hay: data, pat: prefix)
        if hits.isEmpty { return 0 }

        let fixed = 15 * 2 + 2
        var rep = utf16beZ(newIdentifier)

        if rep.count > fixed {
            rep = rep.prefix(fixed)
            rep[fixed - 2] = 0x00
            rep[fixed - 1] = 0x00
        } else if rep.count < fixed {
            rep.append(Data(repeating: 0xBA, count: fixed - rep.count))
        }

        var patched = 0
        for start in hits {
            if start + fixed <= data.count {
                data.replaceSubrange(start..<(start + fixed), with: rep)
                patched += 1
            }
        }
        return patched
    }
}

// MARK: - Image conversion

enum NewtonImageEncoder {

    static func renderAndPack4bpp(nsImage: NSImage,
                                 targetWidth: Int,
                                 targetHeight: Int,
                                 invert: Bool,
                                 swapNibbles: Bool,
                                 dither: DitherMode) throws -> Data {
        var proposedRect = CGRect(origin: .zero, size: nsImage.size)
        guard let cg = nsImage.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            throw NSError(domain: "NewtonImageEncoder", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not convert image to CGImage."
            ])
        }

        let w = targetWidth
        let h = targetHeight

        var gray = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(
            data: &gray,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw NSError(domain: "NewtonImageEncoder", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Could not create grayscale context."
            ])
        }

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

        var buf = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) { buf[i] = Float(gray[i]) }

        var q4 = [UInt8](repeating: 0, count: w * h)

        func clamp255(_ v: Float) -> Float {
            if v < 0 { return 0 }
            if v > 255 { return 255 }
            return v
        }

        if dither == .floyd {
            for y in 0..<h {
                for x in 0..<w {
                    let idx = y * w + x
                    let old = clamp255(buf[idx])
                    var new4 = UInt8((Int(old) * 15 + 127) / 255)
                    let new = Float(new4) * 255.0 / 15.0
                    let err = old - new

                    buf[idx] = new

                    if x + 1 < w { buf[idx + 1] += err * (7.0 / 16.0) }
                    if y + 1 < h {
                        if x > 0 { buf[idx + w - 1] += err * (3.0 / 16.0) }
                        buf[idx + w] += err * (5.0 / 16.0)
                        if x + 1 < w { buf[idx + w + 1] += err * (1.0 / 16.0) }
                    }

                    if invert { new4 = 15 - new4 }
                    q4[idx] = new4
                }
            }
        } else {
            for i in 0..<(w * h) {
                var v = UInt8((Int(gray[i]) * 15 + 127) / 255)
                if invert { v = 15 - v }
                q4[i] = v
            }
        }

        let rowBytesPacked = (w + 1) / 2
        var packed = [UInt8](repeating: 0, count: rowBytesPacked * h)

        for yy in 0..<h {
            for xx in 0..<w {
                let g4 = q4[yy * w + xx]
                let outIndex = yy * rowBytesPacked + (xx / 2)

                if !swapNibbles {
                    if (xx % 2) == 0 {
                        packed[outIndex] = (g4 << 4) | (packed[outIndex] & 0x0F)
                    } else {
                        packed[outIndex] = (packed[outIndex] & 0xF0) | (g4 & 0x0F)
                    }
                } else {
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

// MARK: - Bitmap patching

enum NewtonBackdropBitmapPatcher {

    static func patchBitmapInPlace(in pkg: Data,
                                   orientation: BackdropOrientation,
                                   packed4bpp: Data) throws -> Data {
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
                    NSLocalizedDescriptionKey: "Image is too complex for this template. Row \(r + 1) needs \(compressed.count) bytes, template allows \(allocLen)."
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
                    if total > b.totalPayload { best = Candidate(start: start, totalPayload: total) }
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

// MARK: - PackBits

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

// MARK: - Save panel (renamed)

enum PCSavePanel {
    static func pickSaveLocation(defaultFileName: String) throws -> URL {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "pkg") ?? .data]
        panel.nameFieldStringValue = defaultFileName
        panel.canCreateDirectories = true

        let response = panel.runModal()
        if response == .OK, let url = panel.url { return url }
        throw NSError(domain: "SavePanel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Save cancelled."])
    }
}

// MARK: - Random hex (renamed)

enum PCHexRandom {
    static func randomLowerHex12() -> String {
        var bytes = [UInt8](repeating: 0, count: 6)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)

        if status != errSecSuccess {
            let t = UInt64(Date().timeIntervalSince1970 * 1_000_000)
            bytes = [
                UInt8((t >> 0) & 0xFF),
                UInt8((t >> 8) & 0xFF),
                UInt8((t >> 16) & 0xFF),
                UInt8((t >> 24) & 0xFF),
                UInt8((t >> 32) & 0xFF),
                UInt8((t >> 40) & 0xFF),
            ]
        }

        let hex = "0123456789abcdef"
        var out = ""
        out.reserveCapacity(12)
        for b in bytes {
            out.append(hex[hex.index(hex.startIndex, offsetBy: Int(b >> 4))])
            out.append(hex[hex.index(hex.startIndex, offsetBy: Int(b & 0x0F))])
        }
        return out
    }
}
