# ThoseWho24

A minimal iOS 24-game app built with SwiftUI.

## Project Structure

- `ContentView.swift` — All app logic and UI (single-file architecture)
- `ThoseWho24App.swift` — App entry point (`Game24App`)
- `Assets.xcassets/` — App icon and accent color

## Architecture

Single-file SwiftUI app with these key components:

- `Fraction` — Rational number type with arithmetic operators and display formatting
- `NumberCard` — Card model with value and visibility state
- `GameViewModel` — ObservableObject with all game logic (puzzle gen, undo, timer, hints)
- `findAllSolutions()` — Recursive brute-force solver finding all ways to make 24
- `ContentView` — Root view switching between `GameView` and `CompletedView`

## Game Logic

- Players pick 4 numbers (1–13), combine them with +/−/×/÷ to reach 24
- Cards are selected then an operator, then a second card — the result replaces both
- Undo stack stores board snapshots before each operation
- Hint system reveals solution steps one at a time
- Timer runs per puzzle, stops on win

## Platform

- iOS (UIKit haptics via `UIImpactFeedbackGenerator`)
- SwiftUI-first, no storyboards
- Xcode project at `../ThoseWho24.xcodeproj`
