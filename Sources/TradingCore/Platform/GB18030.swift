import Foundation
#if canImport(CoreFoundation)
import CoreFoundation
#endif

/// 腾讯行情快照是 GB18030 文本。编解码集中在这一处，行情客户端不再直接依赖 CoreFoundation。
enum GB18030 {
    static func decode(_ data: Data) -> String? {
        #if canImport(CoreFoundation)
        let encoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        if let text = String(data: data, encoding: encoding) {
            return text
        }
        #endif
        return String(data: data, encoding: .utf8)
    }
}
