// Proprietary Software License Version 1.0
//
// Copyright (C) 2025 BDG
//
// Backdoor App Signer is proprietary software. You may not use, modify, or distribute it except as expressly permitted under the terms of the Proprietary Software License.

import Foundation
import CoreML
import Natural
import Vision

/// Class responsible for managing the Core ML model, including loading, prediction, and on-device learning
final class CoreMLModelHandler {
    // MARK: - Singleton
    
    static let shared = CoreMLModelHandler()
    
    // MARK: - Properties
    
    /// URL to the default bundled model
    private let defaultModelURL: URL? = Bundle.main.url(forResource: "BackdoorAssistant", withExtension: "mlmodel", subdirectory: "Models")
    
    /// URL to the compiled model in the application support directory
    private var compiledModelURL: URL? {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return appSupportURL?.appendingPathComponent("BackdoorAssistant.mlmodelc")
    }
    
    /// The currently loaded model
    private var model: MLModel?
    
    /// Lock for thread safety
    private let modelLock = NSLock()
    
    /// Model prediction queue to avoid blocking the main thread
    private let predictionQueue = DispatchQueue(label: "com.backdoor.coreml.prediction", qos: .userInitiated)
    
    /// Feedback collection for model updates
    private var feedbackCollection = MLFeedbackCollection()
    
    /// Natural language tokenizer for processing text
    private let tokenizer = NLTokenizer(using: .word)
    
    /// Natural language tagger for part-of-speech analysis
    private let tagger = NLTagger(tagSchemes: [.lemma, .nameType, .lexicalClass])
    
    // MARK: - Initialization
    
    private init() {
        // Load the model on initialization
        loadModel()
        
        // Set up observers for app state
        setupAppStateObservers()
        
        Debug.shared.log(message: "Core ML Model Handler initialized", type: .info)
    }
    
    // MARK: - Model Management
    
    /// Load the Core ML model (either compiled version or bundled default)
    private func loadModel() {
        modelLock.lock()
        defer { modelLock.unlock() }
        
        do {
            // First try to load the compiled model if it exists
            if let compiledURL = compiledModelURL, FileManager.default.fileExists(atPath: compiledURL.path) {
                Debug.shared.log(message: "Loading compiled Core ML model from: \(compiledURL.path)", type: .info)
                model = try MLModel(contentsOf: compiledURL)
            }
            // If compiled model doesn't exist or fails to load, use the bundled model
            else if let defaultURL = defaultModelURL {
                Debug.shared.log(message: "Loading default Core ML model from bundle", type: .info)
                // Compile the model for better performance
                let compiledURL = try MLModel.compileModel(at: defaultURL)
                model = try MLModel(contentsOf: compiledURL)
                
                // Copy the compiled model to application support for future use
                if let targetURL = self.compiledModelURL {
                    try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), 
                                                         withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: compiledURL, to: targetURL)
                }
            } else {
                throw NSError(domain: "com.backdoor.coreml", code: 1, userInfo: [NSLocalizedDescriptionKey: "Default model not found in bundle"])
            }
            
            Debug.shared.log(message: "Core ML model loaded successfully", type: .success)
        } catch {
            Debug.shared.log(message: "Failed to load Core ML model: \(error.localizedDescription)", type: .error)
        }
    }
    
    /// Update the model with new training data
    func updateModel(with feedbackItems: [MLFeedbackEntry]) {
        modelLock.lock()
        defer { modelLock.unlock() }
        
        // Add feedback to collection
        for item in feedbackItems {
            feedbackCollection.appendEntry(item)
        }
        
        guard let model = model else {
            Debug.shared.log(message: "Cannot update model: No model loaded", type: .error)
            return
        }
        
        // Update the model asynchronously
        DispatchQueue.global(qos: .background).async {
            do {
                Debug.shared.log(message: "Starting model update with \(feedbackItems.count) feedback items", type: .info)
                
                // Create model update task
                let updateTask = try MLUpdateTask(forModelAt: self.compiledModelURL!, 
                                              trainingData: self.feedbackCollection,
                                              configuration: MLModelConfiguration(),
                                              completionHandler: { context in
                    if let error = context.error {
                        Debug.shared.log(message: "Model update failed: \(error.localizedDescription)", type: .error)
                        return
                    }
                    
                    Debug.shared.log(message: "Model updated successfully", type: .success)
                    
                    // Reload the updated model
                    DispatchQueue.main.async {
                        self.loadModel()
                    }
                })
                
                // Start the update task
                updateTask.resume()
            } catch {
                Debug.shared.log(message: "Failed to create model update task: \(error.localizedDescription)", type: .error)
            }
        }
    }
    
    // MARK: - Prediction
    
    /// Process user input and generate a response using the model
    func generateResponse(userInput: String, context: AppContext, conversationHistory: [String], completion: @escaping (Result<String, Error>) -> Void) {
        // Ensure we have a model loaded
        guard let model = model else {
            completion(.failure(CoreMLError.modelNotLoaded))
            return
        }
        
        // Process the prediction on a background queue
        predictionQueue.async {
            do {
                // Preprocess inputs
                let processedInput = self.preprocessText(userInput)
                let encodedContext = CoreMLContextEncoder.shared.encodeContext(context)
                let encodedHistory = self.encodeConversationHistory(conversationHistory)
                
                // Create input dictionary for the model
                let inputDictionary: [String: MLFeatureValue] = [
                    "userInput": MLFeatureValue(string: processedInput),
                    "appContext": MLFeatureValue(string: encodedContext),
                    "conversationHistory": MLFeatureValue(string: encodedHistory)
                ]
                
                // Create input for prediction
                let inputProvider = try MLDictionaryFeatureProvider(dictionary: inputDictionary)
                
                // Generate prediction
                let prediction = try model.prediction(from: inputProvider)
                
                // Extract response from prediction output
                if let responseValue = prediction.featureValue(for: "response"),
                   let response = responseValue.stringValue {
                    
                    // Post-process the response
                    let finalResponse = self.postprocessResponse(response)
                    
                    // Return result on main thread
                    DispatchQueue.main.async {
                        completion(.success(finalResponse))
                    }
                } else {
                    throw CoreMLError.invalidResponse
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Text Processing
    
    /// Preprocess text input for the model
    private func preprocessText(_ text: String) -> String {
        // Lowercase the text
        var processedText = text.lowercased()
        
        // Tag the text
        tagger.string = processedText
        
        // Apply lemmatization to normalize words
        var lemmatizedText = ""
        tagger.enumerateTags(in: NSRange(location: 0, length: processedText.utf16.count), 
                            unit: .word, 
                            scheme: .lemma) { tag, tokenRange, _ in
            if let tag = tag, let range = Range(tokenRange, in: processedText) {
                lemmatizedText += tag + " "
            } else if let range = Range(tokenRange, in: processedText) {
                lemmatizedText += processedText[range] + " "
            }
            return true
        }
        
        // Remove extra whitespace
        processedText = lemmatizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return processedText
    }
    
    /// Postprocess model response
    private func postprocessResponse(_ response: String) -> String {
        // Clean up any model artifacts
        var processedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure proper capitalization
        if !processedResponse.isEmpty {
            let firstChar = processedResponse.prefix(1).uppercased()
            let restOfString = processedResponse.dropFirst()
            processedResponse = firstChar + restOfString
        }
        
        // Ensure there's proper ending punctuation
        if !processedResponse.isEmpty && !".!?".contains(processedResponse.last!) {
            processedResponse += "."
        }
        
        return processedResponse
    }
    
    /// Encode conversation history for the model
    private func encodeConversationHistory(_ history: [String]) -> String {
        // Limit history to prevent input size issues
        let limitedHistory = history.suffix(5)
        
        // Join history into a single string
        return limitedHistory.joined(separator: " || ")
    }
    
    // MARK: - App State Handling
    
    private func setupAppStateObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        // Save any pending state when app goes to background
        saveFeedbackCollection()
    }
    
    @objc private func appWillEnterForeground() {
        // Make sure model is loaded when coming back to foreground
        if model == nil {
            loadModel()
        }
    }
    
    /// Save the feedback collection to disk
    private func saveFeedbackCollection() {
        do {
            let fileManager = FileManager.default
            let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            if let feedbackURL = appSupportURL?.appendingPathComponent("ModelFeedback.mlfc") {
                try fileManager.createDirectory(at: feedbackURL.deletingLastPathComponent(), 
                                               withIntermediateDirectories: true)
                try feedbackCollection.export(to: feedbackURL)
                Debug.shared.log(message: "Saved model feedback collection", type: .info)
            }
        } catch {
            Debug.shared.log(message: "Failed to save feedback collection: \(error.localizedDescription)", type: .error)
        }
    }
    
    // MARK: - Feedback
    
    /// Add feedback for model improvement
    func addFeedback(userInput: String, expectedResponse: String) {
        guard let model = model else {
            Debug.shared.log(message: "Cannot add feedback: No model loaded", type: .error)
            return
        }
        
        do {
            // Create input for feedback
            let inputDictionary: [String: MLFeatureValue] = [
                "userInput": MLFeatureValue(string: userInput),
                "expectedResponse": MLFeatureValue(string: expectedResponse)
            ]
            
            let inputProvider = try MLDictionaryFeatureProvider(dictionary: inputDictionary)
            
            // Create feedback entry
            let feedbackEntry = MLFeedbackEntry(
                input: inputProvider,
                output: nil, // For user-provided feedback, output may be nil
                expectedOutput: nil  // Expected output is encoded in the input
            )
            
            // Add to collection
            feedbackCollection.appendEntry(feedbackEntry)
            
            Debug.shared.log(message: "Added feedback for model improvement", type: .info)
        } catch {
            Debug.shared.log(message: "Failed to add feedback: \(error.localizedDescription)", type: .error)
        }
    }
}

// MARK: - Error Types

enum CoreMLError: Error, LocalizedError {
    case modelNotLoaded
    case invalidResponse
    case contextEncodingFailed
    case unknownPredictionError
    
    var errorDescription: String? {
        switch self {
            case .modelNotLoaded:
                return "AI model is not loaded"
            case .invalidResponse:
                return "AI model produced an invalid response"
            case .contextEncodingFailed:
                return "Failed to encode app context for AI model"
            case .unknownPredictionError:
                return "Unknown error during AI prediction"
        }
    }
}
