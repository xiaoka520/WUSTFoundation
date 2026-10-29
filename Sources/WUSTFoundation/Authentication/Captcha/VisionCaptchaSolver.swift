import Foundation
import Vision

public enum CaptchaRecognitionError: Error {
    case noText //没识别到文字
    case invalidExpression //识别结果是不支持的算式
}

public struct VisionCaptchaSolver {
    public init() {}
    private func recognizaExpression(from imageData: Data) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        
        let handler = VNImageRequestHandler(data: imageData, options: [:])
        try handler.perform([request])
        
        guard let observations = request.results else {
            throw CaptchaRecognitionError.noText
        }
        var expression: String = ""
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else {
                throw CaptchaRecognitionError.noText
            }
            expression.append(candidate.string)
        }
        guard !expression.isEmpty else {
            throw CaptchaRecognitionError.noText
        }
        
        return expression
    }
    
    private func calculateAnswer(from expression: String) throws -> String {
        let text = expression
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "x", with: "*")
            .replacingOccurrences(of: "X", with: "*")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "o", with: "0")
            .replacingOccurrences(of: "O", with: "0")
        var operation: Character? = nil
        for character in text {
            if "+-*/".contains(character) {
                operation = character
                break
            }
        }
        guard let operation else {
            throw CaptchaRecognitionError.invalidExpression
        }
        
        let parts = text.split(
            separator: operation,
            omittingEmptySubsequences: false
        )
        guard parts.count == 2 else {
            throw CaptchaRecognitionError.invalidExpression
        }
        guard let left = Int(parts[0]), let right = Int(parts[1]) else {
            throw CaptchaRecognitionError.invalidExpression
        }
        switch operation {
        case "+":
            return String(left + right)
        case "-":
            return String(left - right)
        case "*":
            return String(left * right)
        case "/":
            guard right != 0 && left % right == 0 else {
                throw CaptchaRecognitionError.invalidExpression
            }
            return String(left / right)
        default:
            throw CaptchaRecognitionError.invalidExpression
        }
    }
    
    public func solve(imageData: Data) throws -> String {
        let expression = try recognizaExpression(from: imageData)
        return try calculateAnswer(from: expression)
    }
}
