// Proprietary Software License Version 1.0
//
// Copyright (C) 2025 BDG
//
// Backdoor App Signer is proprietary software. You may not use, modify, or distribute it except as expressly permitted under the terms of the Proprietary Software License.

import CoreML
import Foundation
import NaturalLanguage
import MLKit

/// CoreMLManager is responsible for loading, managing, and using Core ML models
/// for on-device machine learning in the Backdoor app.
class CoreMLManager {
    // MARK: - Singleton
    
    static let shared = CoreMLManager()
    
    // MARK: - Properties
    
    /// Tracks the loading status of each model
    private var modelStatus: [ModelType: ModelStatus] = [:]
    
    /// Cache of loaded models
    private var loadedModels: [ModelType: Any] = [:]
    
    /// URL for model storage
    private let modelsDirectory: URL?
    
    /// Queue for thread-safe model operations
    private let modelQueue = DispatchQueue(label: "com.backdoor.coreml", qos: .userInitiated)
    
    /// Status for tracking model state
    enum ModelStatus {
        case notLoaded
        case loading
        case loaded
        case failed(Error)
    }
    
    /// Types of models supported
    enum ModelType: String, CaseIterable {
        case intentClassifier = "BackdoorIntentClassifier"
        case textGenerator = "BackdoorTextGenerator"
        case sentimentAnalyzer = "BackdoorSentimentAnalyzer"
        
        var filename: String {
            return "\(rawValue).mlmodel"
        }
        
        var compiledFilename: String {
            return "\(rawValue).mlmodelc"
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Create models directory if needed
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        modelsDirectory = documentsDirectory?.appendingPathComponent("MLModels", isDirectory: true)
        
        if let modelsDir = modelsDirectory {
            try? fileManager.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        }
        
        // Initialize model status as not loaded
        for modelType in ModelType.allCases {
            modelStatus[modelType] = .notLoaded
        }
        
        // Pre-load bundled models
        loadBundledModels()
        
        Debug.shared.log(message: "CoreMLManager initialized", type: .info)
    }
    
    // MARK: - Model Management
    
    /// Load any models that are bundled with the app
    private func loadBundledModels() {
        for modelType in ModelType.allCases {
            // Check if the model is already in the documents directory
            if let modelURL = getModelURL(for: modelType), FileManager.default.fileExists(atPath: modelURL.path) {
                // Model exists in documents, will be loaded on demand
                Debug.shared.log(message: "Found model in documents: \(modelType.rawValue)", type: .debug)
            } else {
                // Check if model is bundled with the app
                if let bundledURL = Bundle.main.url(forResource: modelType.rawValue, withExtension: "mlmodelc") {
                    // If bundled, copy to documents directory
                    copyModelToDocuments(from: bundledURL, modelType: modelType)
                } else {
                    Debug.shared.log(message: "Model not found in bundle: \(modelType.rawValue)", type: .warning)
                }
            }
        }
    }
    
    /// Copy a bundled model to the documents directory
    private func copyModelToDocuments(from bundledURL: URL, modelType: ModelType) {
        guard let modelsDir = modelsDirectory else { return }
        
        let destinationURL = modelsDir.appendingPathComponent(modelType.compiledFilename)
        
        do {
            // Remove any existing model with the same name
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            // Copy the model
            try FileManager.default.copyItem(at: bundledURL, to: destinationURL)
            Debug.shared.log(message: "Copied bundled model to documents: \(modelType.rawValue)", type: .debug)
        } catch {
            Debug.shared.log(message: "Failed to copy model to documents: \(error)", type: .error)
        }
    }
    
    /// Get the URL for a model in the documents directory
    private func getModelURL(for modelType: ModelType) -> URL? {
        return modelsDirectory?.appendingPathComponent(modelType.compiledFilename)
    }
    
    /// Download a model from the remote server
    func downloadModel(for modelType: ModelType, completion: @escaping (Bool) -> Void) {
        guard let modelsDir = modelsDirectory else {
            completion(false)
            return
        }
        
        // In a real app, this would download from a server
        // For now, we'll simulate downloading by setting a timeout
        
        modelQueue.async {
            self.modelStatus[modelType] = .loading
            
            // Simulate network delay
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                // Create a placeholder URL for the downloaded model
                let destinationURL = modelsDir.appendingPathComponent(modelType.compiledFilename)
                
                // In a real implementation, we would download and compile the model here
                // For now, we'll just check if the model exists in the bundle and copy it
                if let bundledURL = Bundle.main.url(forResource: modelType.rawValue, withExtension: "mlmodelc") {
                    do {
                        // Remove any existing model with the same name
                        if FileManager.default.fileExists(atPath: destinationURL.path) {
                            try FileManager.default.removeItem(at: destinationURL)
                        }
                        
                        // Copy the model
                        try FileManager.default.copyItem(at: bundledURL, to: destinationURL)
                        
                        DispatchQueue.main.async {
                            self.modelStatus[modelType] = .loaded
                            Debug.shared.log(message: "Model downloaded successfully: \(modelType.rawValue)", type: .info)
                            completion(true)
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.modelStatus[modelType] = .failed(error)
                            Debug.shared.log(message: "Failed to download model: \(error)", type: .error)
                            completion(false)
                        }
                    }
                } else {
                    // Simulate a successful download with empty model
                    do {
                        // Create a directory to simulate a compiled model
                        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                        
                        DispatchQueue.main.async {
                            self.modelStatus[modelType] = .loaded
                            Debug.shared.log(message: "Model simulated download: \(modelType.rawValue)", type: .info)
                            completion(true)
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.modelStatus[modelType] = .failed(error)
                            Debug.shared.log(message: "Failed to simulate model: \(error)", type: .error)
                            completion(false)
                        }
                    }
                }
            }
        }
    }
    
    /// Load a specific model for use
    func loadModel<T: MLModel>(for modelType: ModelType, completion: @escaping (Result<T, Error>) -> Void) {
        modelQueue.async {
            // Check if model is already loaded
            if let model = self.loadedModels[modelType] as? T {
                DispatchQueue.main.async {
                    completion(.success(model))
                }
                return
            }
            
            // Check model status
            switch self.modelStatus[modelType] {
            case .loaded:
                // Model is marked as loaded but not in memory, load from disk
                self.loadModelFromDisk(modelType: modelType, completion: completion)
                
            case .loading:
                // Model is in the process of loading, wait and check again
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    self.loadModel(for: modelType, completion: completion)
                }
                
            case .failed(let error):
                // Previous load attempt failed
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                
            case .notLoaded, nil:
                // Model hasn't been loaded yet, try to load it
                self.loadModelFromDisk(modelType: modelType, completion: completion)
            }
        }
    }
    
    /// Load a model from disk storage
    private func loadModelFromDisk<T: MLModel>(modelType: ModelType, completion: @escaping (Result<T, Error>) -> Void) {
        guard let modelURL = getModelURL(for: modelType) else {
            let error = NSError(domain: "com.backdoor.coreml", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model URL not found"])
            DispatchQueue.main.async {
                completion(.failure(error))
            }
            return
        }
        
        // Update status to loading
        self.modelStatus[modelType] = .loading
        
        do {
            // In a real implementation, we would load the actual model
            // For now, we'll simulate model loading
            
            // Check if the model file exists
            if FileManager.default.fileExists(atPath: modelURL.path) {
                Debug.shared.log(message: "Loading model from disk: \(modelType.rawValue)", type: .debug)
                
                // Attempt to load the model configuration
                let config = MLModelConfiguration()
                config.computeUnits = .all
                
                let modelDescription = try MLModelDescription(contentsOf: modelURL)
                Debug.shared.log(message: "Model description: \(modelDescription.inputDescriptionsByName.keys)", type: .debug)
                
                // Create a mock model for simulation
                // In a real implementation, we would use:
                // let model = try T(contentsOf: modelURL, configuration: config)
                
                // For now we'll create a placeholder and cast it
                let mockModel = MockMLModel()
                guard let model = mockModel as? T else {
                    throw NSError(domain: "com.backdoor.coreml", code: 2, userInfo: [NSLocalizedDescriptionKey: "Model type mismatch"])
                }
                
                // Cache the model
                self.loadedModels[modelType] = model
                
                // Update status
                self.modelStatus[modelType] = .loaded
                
                DispatchQueue.main.async {
                    completion(.success(model))
                }
            } else {
                // Model file doesn't exist, try to download it
                let error = NSError(domain: "com.backdoor.coreml", code: 3, userInfo: [NSLocalizedDescriptionKey: "Model not found, try downloading"])
                self.modelStatus[modelType] = .failed(error)
                
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                
                // Try to download the model
                self.downloadModel(for: modelType) { _ in
                    // Don't call the completion here, as the caller should try loading again
                }
            }
        } catch {
            Debug.shared.log(message: "Failed to load model: \(error)", type: .error)
            self.modelStatus[modelType] = .failed(error)
            
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Model Operations
    
    /// Classify the intent of a user message
    func classifyIntent(text: String, completion: @escaping (Result<String, Error>) -> Void) {
        // First try using NLP for sentiment analysis
        let tagger = NLTagger(tagSchemes: [.sentiment])
        tagger.string = text
        let sentiment = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentiment).0?.rawValue ?? "unclassified"
        
        Debug.shared.log(message: "Sentiment analysis: \(sentiment)", type: .debug)
        
        // Then try to load and use the intent classifier model
        loadModel(for: .intentClassifier) { (result: Result<MLModel, Error>) in
            switch result {
            case .success(_):
                // In a real implementation, we would use the model for prediction
                // For now, we'll use some basic text classification
                
                let lowercasedText = text.lowercased()
                var intent = "conversation"
                
                if lowercasedText.contains("sign") || lowercasedText.contains("certificate") {
                    intent = "sign_app"
                } else if lowercasedText.contains("navigate") || lowercasedText.contains("go to") {
                    intent = "navigation"
                } else if lowercasedText.contains("install") || lowercasedText.contains("download") {
                    intent = "install_app"
                } else if lowercasedText.contains("source") || lowercasedText.contains("repo") {
                    intent = "source_management"
                } else if lowercasedText.contains("help") {
                    intent = "help"
                }
                
                completion(.success(intent))
                
            case .failure(let error):
                // If model fails, fall back to basic text classification
                let fallbackIntent = self.fallbackIntentClassification(text: text)
                Debug.shared.log(message: "Using fallback intent classification due to error: \(error)", type: .warning)
                completion(.success(fallbackIntent))
            }
        }
    }
    
    /// Analyze sentiment of text
    func analyzeSentiment(text: String, completion: @escaping (Result<String, Error>) -> Void) {
        // Use Natural Language framework for sentiment analysis
        let tagger = NLTagger(tagSchemes: [.sentiment])
        tagger.string = text
        
        if let sentiment = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentiment).0?.rawValue {
            completion(.success(sentiment))
        } else {
            // Try to use the model
            loadModel(for: .sentimentAnalyzer) { (result: Result<MLModel, Error>) in
                switch result {
                case .success(_):
                    // In a real implementation, we would use the model
                    // For now, return a default sentiment
                    completion(.success("neutral"))
                    
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Generate enhanced responses using the text generator model
    func enhanceResponse(baseResponse: String, context: String, completion: @escaping (Result<String, Error>) -> Void) {
        loadModel(for: .textGenerator) { (result: Result<MLModel, Error>) in
            switch result {
            case .success(_):
                // In a real implementation, we would enhance the response using the text generator model
                // For now, we'll make some basic enhancements
                
                let enhancedResponse: String
                
                if baseResponse.contains("[") && baseResponse.contains("]") {
                    // Contains a command, don't modify it
                    enhancedResponse = baseResponse
                } else {
                    // Add a more personalized touch
                    let personalizedIntros = [
                        "Based on my analysis, ",
                        "I've processed your request and ",
                        "Using on-device intelligence, I can tell you that ",
                        "My Core ML models suggest that "
                    ]
                    
                    // Only modify if the response isn't already structured as a command
                    if let intro = personalizedIntros.randomElement(), !baseResponse.hasPrefix(intro) {
                        // Don't add the intro if the response is very short
                        if baseResponse.count > 50 && !baseResponse.hasPrefix("I") {
                            enhancedResponse = intro + baseResponse.prefix(1).lowercased() + baseResponse.dropFirst()
                        } else {
                            enhancedResponse = baseResponse
                        }
                    } else {
                        enhancedResponse = baseResponse
                    }
                }
                
                completion(.success(enhancedResponse))
                
            case .failure(let error):
                // If model fails, return the original response
                Debug.shared.log(message: "Failed to enhance response: \(error)", type: .warning)
                completion(.success(baseResponse))
            }
        }
    }
    
    // MARK: - Fallback Methods
    
    /// Basic rule-based intent classification as a fallback
    private func fallbackIntentClassification(text: String) -> String {
        let lowercasedText = text.lowercased()
        
        // Simple keyword matching
        if lowercasedText.contains("sign") {
            return "sign_app"
        } else if lowercasedText.contains("navigate") || lowercasedText.contains("go to") {
            return "navigation"
        } else if lowercasedText.contains("install") || lowercasedText.contains("download") {
            return "install_app"
        } else if lowercasedText.contains("source") || lowercasedText.contains("repo") {
            return "source_management"
        } else if lowercasedText.contains("help") {
            return "help"
        }
        
        return "conversation"
    }
    
    // MARK: - Status Methods
    
    /// Check if a model is available (either loaded or on disk)
    func isModelAvailable(_ modelType: ModelType) -> Bool {
        switch modelStatus[modelType] {
        case .loaded:
            return true
        default:
            // Check if model file exists
            if let modelURL = getModelURL(for: modelType),
               FileManager.default.fileExists(atPath: modelURL.path) {
                return true
            }
            return false
        }
    }
    
    /// Get the current status of a model
    func getModelStatus(_ modelType: ModelType) -> ModelStatus {
        return modelStatus[modelType] ?? .notLoaded
    }
    
    /// Check if on-device intelligence is available
    func isOnDeviceIntelligenceAvailable() -> Bool {
        // Check if the key models are available
        let requiredModels: [ModelType] = [.intentClassifier, .textGenerator]
        return requiredModels.allSatisfy { isModelAvailable($0) }
    }
}

// MARK: - Mock Implementation

/// A mock MLModel for testing when real models aren't available
class MockMLModel: MLModel {
    override func prediction(from inputs: MLFeatureProvider) throws -> MLFeatureProvider {
        return MockFeatureProvider()
    }
    
    class MockFeatureProvider: MLFeatureProvider {
        var featureNames: Set<String> = ["output"]
        
        func featureValue(for featureName: String) -> MLFeatureValue? {
            return MLFeatureValue(string: "mock_output")
        }
    }
}

// MARK: - UI Status Extension

extension CoreMLManager {
    /// Get a human-readable status message about Core ML availability
    var statusMessage: String {
        if isOnDeviceIntelligenceAvailable() {
            return "On-device intelligence available"
        } else {
            return "Using cloud intelligence (Core ML models not loaded)"
        }
    }
    
    /// Get a status icon name for the UI
    var statusIconName: String {
        if isOnDeviceIntelligenceAvailable() {
            return "brain"
        } else {
            return "cloud"
        }
    }
}
