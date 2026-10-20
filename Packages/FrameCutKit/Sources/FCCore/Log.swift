import os

/// 统一日志（“控制台”App 中按子系统 com.lidedongsn.framecut 过滤查看）。
public enum Log {
    private static let subsystem = "com.lidedongsn.framecut"
    public static let project = Logger(subsystem: subsystem, category: "project")
    public static let media = Logger(subsystem: subsystem, category: "media")
    public static let export = Logger(subsystem: subsystem, category: "export")
    public static let transcribe = Logger(subsystem: subsystem, category: "transcribe")
    public static let cache = Logger(subsystem: subsystem, category: "cache")
}
