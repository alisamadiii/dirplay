import AVFoundation
import UIKit

enum ArtworkEmbedError: LocalizedError {
    case invalidImage
    case unsupportedFormat(String)
    case unsupportedTag
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "That image couldn't be read."
        case .unsupportedFormat(let ext):
            return "Embedding covers is supported for MP3 and M4A files, not .\(ext)."
        case .unsupportedTag:
            return "This MP3 has an old or unusual tag format that can't be updated safely."
        case .exportFailed:
            return "The file couldn't be rewritten."
        }
    }
}

/// Writes cover art directly into the audio file's own metadata (MP4 `covr`
/// atom or ID3v2 `APIC` frame) — no sidecar files, the image travels with the
/// music wherever the file goes.
enum ArtworkEmbedder {
    static func embed(imageData: Data, into url: URL) async throws {
        guard let jpeg = normalizedJPEG(from: imageData) else {
            throw ArtworkEmbedError.invalidImage
        }
        switch url.pathExtension.lowercased() {
        case "m4a", "m4b":
            try await embedInMPEG4(jpeg: jpeg, url: url)
        case "mp3":
            try embedInMP3(jpeg: jpeg, url: url)
        default:
            throw ArtworkEmbedError.unsupportedFormat(url.pathExtension)
        }
    }

    /// Downscales to a sane cover size and re-encodes as JPEG.
    private static func normalizedJPEG(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1400
        let largest = max(image.size.width, image.size.height)
        let scaled: UIImage
        if largest > maxSide, largest > 0 {
            let factor = maxSide / largest
            let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
            scaled = UIGraphicsImageRenderer(size: size).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        } else {
            scaled = image
        }
        return scaled.jpegData(compressionQuality: 0.85)
    }

    // MARK: - MP4 container (m4a/m4b)

    private static func embedInMPEG4(jpeg: Data, url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let existing = (try? await asset.load(.metadata)) ?? []
        let kept = existing.filter { $0.commonKey != .commonKeyArtwork }

        let artwork = AVMutableMetadataItem()
        artwork.identifier = .commonIdentifierArtwork
        artwork.value = jpeg as NSData
        artwork.dataType = kCMMetadataBaseDataType_JPEG as String

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw ArtworkEmbedError.exportFailed
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension)
        session.outputURL = tempURL
        session.outputFileType = .m4a
        session.metadata = kept + [artwork]
        await session.export()
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: tempURL)
            throw ArtworkEmbedError.exportFailed
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
    }

    // MARK: - ID3v2 (mp3)

    /// Rewrites the file's ID3v2 tag: keeps every existing frame except old
    /// artwork, appends a new APIC frame. Supports untagged files, v2.3, and
    /// v2.4; refuses v2.2 and unsynchronised tags rather than corrupt them.
    private static func embedInMP3(jpeg: Data, url: URL) throws {
        let original = try Data(contentsOf: url)
        var major: UInt8 = 3
        var keptFrames = Data()
        var audioStart = 0

        if original.count >= 10, original[0] == 0x49, original[1] == 0x44, original[2] == 0x33 {
            major = original[3]
            let flags = original[5]
            guard major == 3 || major == 4 else { throw ArtworkEmbedError.unsupportedTag }
            guard flags & 0x80 == 0 else { throw ArtworkEmbedError.unsupportedTag } // unsynchronised
            let tagSize = syncsafeInt(original, at: 6)
            let framesEnd = min(10 + tagSize, original.count)
            audioStart = framesEnd
            if flags & 0x10 != 0 { // v2.4 footer follows the frames
                audioStart = min(framesEnd + 10, original.count)
            }

            var offset = 10
            if flags & 0x40 != 0, offset + 4 <= framesEnd { // extended header
                let extSize = major == 4
                    ? syncsafeInt(original, at: offset)
                    : beInt(original, at: offset) + 4
                offset += max(extSize, 4)
            }
            while offset + 10 <= framesEnd {
                if original[offset] == 0 { break } // padding
                let frameID = original[offset..<offset + 4]
                let frameSize = major == 4
                    ? syncsafeInt(original, at: offset + 4)
                    : beInt(original, at: offset + 4)
                let total = 10 + frameSize
                guard frameSize > 0, offset + total <= framesEnd else { break }
                if String(data: frameID, encoding: .isoLatin1) != "APIC" {
                    keptFrames.append(original[offset..<offset + total])
                }
                offset += total
            }
        }

        var apicContent = Data([0x00]) // text encoding: ISO-8859-1
        apicContent.append(Data("image/jpeg".utf8))
        apicContent.append(0x00)
        apicContent.append(0x03) // picture type: front cover
        apicContent.append(0x00) // empty description
        apicContent.append(jpeg)

        var apic = Data("APIC".utf8)
        apic.append(major == 4 ? syncsafeBytes(apicContent.count) : beBytes(apicContent.count))
        apic.append(contentsOf: [0x00, 0x00])
        apic.append(apicContent)

        let frames = keptFrames + apic
        var output = Data("ID3".utf8)
        output.append(contentsOf: [major, 0x00, 0x00])
        output.append(syncsafeBytes(frames.count))
        output.append(frames)
        if audioStart < original.count {
            output.append(original[audioStart...])
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp3")
        try output.write(to: tempURL)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
    }

    private static func syncsafeInt(_ data: Data, at index: Int) -> Int {
        let i = data.startIndex + index
        return Int(data[i] & 0x7F) << 21 | Int(data[i + 1] & 0x7F) << 14
            | Int(data[i + 2] & 0x7F) << 7 | Int(data[i + 3] & 0x7F)
    }

    private static func beInt(_ data: Data, at index: Int) -> Int {
        let i = data.startIndex + index
        return Int(data[i]) << 24 | Int(data[i + 1]) << 16 | Int(data[i + 2]) << 8 | Int(data[i + 3])
    }

    private static func syncsafeBytes(_ value: Int) -> Data {
        Data([
            UInt8((value >> 21) & 0x7F),
            UInt8((value >> 14) & 0x7F),
            UInt8((value >> 7) & 0x7F),
            UInt8(value & 0x7F)
        ])
    }

    private static func beBytes(_ value: Int) -> Data {
        Data([
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ])
    }
}
