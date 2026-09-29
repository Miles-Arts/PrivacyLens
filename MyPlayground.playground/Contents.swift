import SwiftUI
import PlaygroundSupport

// MARK: - MeetXcode Playground
// Use this playground to experiment with components, data models, and views.

var greeting = "Hello, MeetXcode Playground!"
print(greeting)

// Example: Playground execution for MicroAdventure data models
struct MicroAdventureSample {
    let title: String
    let category: String
}

let sample = MicroAdventureSample(title: "Yosemite Point Trail", category: "Hiking")
print("Sample Adventure: \(sample.title) [\(sample.category)]")
