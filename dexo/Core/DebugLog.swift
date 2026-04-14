import Foundation

public func debugLog(_ object: Any, functionName: String = #function, fileName: String = #file, lineNumber: Int = #line) {
    #if DEBUG
    let className = (fileName as NSString).lastPathComponent
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    let timestamp = dateFormatter.string(from: Date())
    print("[\(timestamp)] <\(className)> \(functionName) [#\(lineNumber)]| \(object)\n")
    #endif
}
