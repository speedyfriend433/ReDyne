import Foundation
import OSLog

class Logger {
    static let shared = Logger()

    private let logger: os.Logger

    private init() {
        self.logger = os.Logger(subsystem: "com.redyne.ReDyne", category: "general")
    }

    func debug(_ message: String) {
        logger.debug("\(message)")
    }

    func info(_ message: String) {
        logger.info("\(message)")
    }

    func warning(_ message: String) {
        logger.warning("\(message)")
    }

    func error(_ message: String) {
        logger.error("\(message)")
    }

    func fault(_ message: String) {
        logger.fault("\(message)")
    }

    // Convenience methods with context
    func logAnalysisStart(fileName: String) {
        info("Starting analysis for file: \(fileName)")
    }

    func logAnalysisComplete(fileName: String, duration: TimeInterval) {
        info("Analysis completed for file: \(fileName) in \(String(format: "%.2f", duration)) seconds")
    }

    func logError(_ error: Error, context: String) {
        self.error("Error in \(context): \(error.localizedDescription)")
    }

    func logPerformance(operation: String, duration: TimeInterval) {
        debug("Performance: \(operation) took \(String(format: "%.4f", duration)) seconds")
    }
}