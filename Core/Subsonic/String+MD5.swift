import Foundation
import CryptoKit

extension String {
    /// MD5 hex（Subsonic API 认证需要）
    var md5: String {
        Insecure.MD5.hash(data: Data(utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
