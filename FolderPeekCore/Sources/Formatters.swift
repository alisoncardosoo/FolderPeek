import Foundation

public enum FolderPeekFormatters {
    public static func sizeString(_ bytes: Int64?) -> String {
        guard let bytes else { return "--" }
        if bytes == 0 { return "0 KB" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    public static func dateString(_ date: Date?) -> String {
        guard let date else { return "--" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    public static func itemCountString(_ count: Int, reachedLimit: Bool) -> String {
        let suffix = count == 1 ? "item" : "itens"
        return reachedLimit ? "\(count)+ \(suffix)" : "\(count) \(suffix)"
    }
}
