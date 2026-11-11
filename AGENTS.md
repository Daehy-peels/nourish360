# Nourish360 - AI Coding & Architecture Rules

## 1. Architecture & Folder Structure

- Follow a strict **Feature-First Clean Architecture** inside `lib/features/`.
- Each feature must be separated into:
  - `data/`: Models, repositories, and Supabase data sources.
  - `domain/`: Business logic, entities, and use cases (if applicable).
  - `presentation/`: Riverpod providers, screens, and widgets.

## 2. State Management & Code Style

- Use **Flutter Riverpod** (`flutter_riverpod`) for all state management. Avoid raw `setState` for global or complex business logic.
- Use strong typing and immutability where possible.
- Every asynchronous operation (like fetching from Supabase) must handle loading, success, and error states gracefully with user-friendly error messages (e.g., using `AsyncValue` from Riverpod).

## 3. UI & Design System

- Build modern, clean interfaces using **Material 3**.
- Maintain consistent padding, margins, and border radii using app constants.
- Ensure all screens are responsive and avoid layout overflow errors.
