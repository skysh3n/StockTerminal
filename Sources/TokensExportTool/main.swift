import DesignSystem
import Foundation

// 设计 tokens 导出工具：swift run tokens-export > tokens.json
// 输出平台无关的 tokens.json，供 iOS / Windows / Linux 端映射到各自原生 UI 类型。
print(DesignSpec.current.jsonString())
