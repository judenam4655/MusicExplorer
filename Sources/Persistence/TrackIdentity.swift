import Foundation
import CryptoKit

/// Spotify's AppleScript/MediaRemote output doesn't reliably expose a stable
/// Spotify URI, so we derive our own cache key from normalized title+artist
/// and a duration bucket. This key is what everything (lyrics cache,
/// translations, song info, history) is stored against.
enum TrackIdentity {
    static func key(title: String, artist: String, durationMs: Int) -> String {
        let normTitle = normalize(title)
        let normArtist = normalize(artist)
        // Bucket to the nearest second so minor rounding differences between
        // providers (AppleScript vs MediaRemote) don't create duplicate keys.
        let durationBucketSec = Int((Double(durationMs) / 1000.0).rounded())

        let raw = "\(normTitle)|\(normArtist)|\(durationBucketSec)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
        let allowed = lowered.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == " "
        }
        let stripped = String(String.UnicodeScalarView(allowed))
        return stripped
            .split(separator: " ")
            .joined(separator: " ")
    }
}
