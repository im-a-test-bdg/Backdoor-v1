// Proprietary Software License Version 1.0
//
// Copyright (C) 2025 BDG
//
// Backdoor App Signer is proprietary software. You may not use, modify, or distribute it except as expressly permitted under the terms of the Proprietary Software License.

import Foundation
import CoreML
import NaturalLanguage

/// Class responsible for encoding app context into a format suitable for the Core ML model
final class CoreMLContextEncoder {
    // MARK: - Singleton
    
    static let shared = CoreMLContextEncoder()
    
    // MARK: - Properties
    
    /// Maximum tokens for context encoding
    private let maxContextTokens = 500
    
    /// Natural language tokenizer for context processing
    private let tokenizer = NLTokenizer(using: .word)
    
    /// Processing queue to avoid blocking the main thread
    private let processingQueue = DispatchQueue(label: "com.backdoor.coreml.contextencoding", qos: .userInitiated)
    
    // MARK: - Encoding Methods
    
    /// Encode the app context for use with the Core ML model
    func encodeContext(_ context: AppContext) -> String {
        // Convert context to a structured format
        var encodedContext = "SCREEN:\(context.currentScreen)\n"
        
        // Add important context data with priority
        let priorityKeys = [
            "currentCertificate", 
            "downloadedApps", 
            "signedApps", 
            "certificates",
            "sources"
        ]
        
        // First add high priority keys
        for key in priorityKeys {
            if let value = context.additionalData[key] {
                encodedContext += "\(key.uppercased()):\(String(describing: value))\n"
            }
        }
        
        // Then add other context data
        for (key, value) in context.additionalData {
            if !priorityKeys.contains(key) {
                encodedContext += "\(key.uppercased()):\(String(describing: value))\n"
            }
        }
        
        // Truncate to max token length
        return truncateToMaxTokens(encodedContext)
    }
    
    /// Truncate text to maximum token length
    private func truncateToMaxTokens(_ text: String) -> String {
        tokenizer.string = text
        
        var tokenCount = 0
        var truncatedText = ""
        var lastIndex = text.startIndex
        
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            tokenCount += 1
            
            if tokenCount <= maxContextTokens {
                lastIndex = tokenRange.upperBound
            }
            
            return tokenCount <= maxContextTokens
        }
        
        if lastIndex != text.endIndex {
            truncatedText = String(text[..<lastIndex]) + "..."
        } else {
            truncatedText = text
        }
        
        return truncatedText
    }
    
    /// Encode user intent based on message
    func encodeUserIntent(_ message: String) -> String {
        // Use Natural Language processing to extract intent
        let tagger = NLTagger(tagSchemes: [.nameTypeOrLexicalClass, .lemma])
        tagger.string = message
        
        // Set language hint if possible
        let dominantLanguage = NLLanguageRecognizer.dominantLanguage(for: message)
        if let language = dominantLanguage {
            tagger.setLanguage(language, range: message.startIndex..<message.endIndex)
        }
        
        // Extract key nouns and verbs
        var keyTerms: [String] = []
        tagger.enumerateTags(in: message.startIndex..<message.endIndex, 
                            unit: .word, 
                            scheme: .nameTypeOrLexicalClass) { tag, tokenRange in
            if let tag = tag, 
               (tag == .noun || tag == .verb), 
               let range = Range(tokenRange, in: message) {
                let word = message[range]
                keyTerms.append(String(word))
            }
            return true
        }
        
        // Extract commands if present
        let commandPattern = "\\[(.*?):(.*?)\\]"
        let regex = try? NSRegularExpression(pattern: commandPattern)
        let nsString = message as NSString
        let matches = regex?.matches(in: message, range: NSRange(location: 0, length: nsString.length)) ?? []
        
        for match in matches {
            if match.numberOfRanges >= 3 {
                let commandRange = match.range(at: 1)
                let parameterRange = match.range(at: 2)
                
                let command = nsString.substring(with: commandRange)
                let parameter = nsString.substring(with: parameterRange)
                
                keyTerms.append("COMMAND:\(command)")
                keyTerms.append("PARAMETER:\(parameter)")
            }
        }
        
        // Combine terms into intent string
        let intent = keyTerms.joined(separator: "|")
        return intent.isEmpty ? "GENERAL" : intent
    }
    
    /// Asynchronously encode context
    func encodeContextAsync(_ context: AppContext, completion: @escaping (String) -> Void) {
        processingQueue.async {
            let encodedContext = self.encodeContext(context)
            DispatchQueue.main.async {
                completion(encodedContext)
            }
        }
    }
}
