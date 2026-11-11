# Nourish360

**Nourish360** is a Flutter-based health and wellness application designed to help users build healthier daily habits by tracking their hydration, calorie intake, and personal wellness goals.

## Features

- **Hydration Tracking** – Track daily water consumption and monitor progress toward your hydration goal.
- **Weekly Hydration Overview** – Visualize hydration progress throughout the week.
- **Calorie Tracking** – Record meals and monitor daily calorie intake.
- **Personalized Profile** – Set up personal information and wellness goals.
- **Cloud Backend** – Use Supabase for authentication and data storage.

## Tech Stack

- **Frontend:** Flutter, Dart
- **Backend:** Supabase
- **Database:** Supabase
- **Development Environment:** Visual Studio Code / Android Studio

## Getting Started

### Prerequisites

Make sure you have installed:

- [Flutter SDK](https://docs.flutter.dev/get-started/install)
- [Dart SDK](https://dart.dev/get-dart)
- [Git](https://git-scm.com/)
- An IDE such as [Visual Studio Code](https://code.visualstudio.com/) or Android Studio

### Installation

1. Clone the repository:

   ```bash
   git clone https://github.com/YOUR-USERNAME/nourish360.git
   ```

2. Navigate to the project directory:

   ```bash
   cd nourish360
   ```

3. Install dependencies:

   ```bash
   flutter pub get
   ```

4. Configure your Supabase environment variables in a local `.env` file:

   ```env
   SUPABASE_URL=your_supabase_project_url
   SUPABASE_ANON_KEY=your_supabase_anon_key
   ```

   Replace the placeholder values with your own Supabase project credentials. Never commit your actual `.env` file or service-role key.

5. Run the application:

   ```bash
   flutter run
   ```

## Project Structure

```text
nourish360/
|-- android/
|-- ios/
|-- lib/
|   |-- features/
|   |   |-- hydration/
|   |   |-- profile/
|   |-- ...
|-- test/
|-- web/
|-- windows/
|-- linux/
|-- macos/
|-- pubspec.yaml
|-- pubspec.lock
|-- README.md
```

## Security

- Environment variables and local configuration files are excluded from version control.
- Never commit private API keys, passwords, or service-role credentials.
- Use only appropriate client-side credentials in the Flutter application.

## License

This project is currently not distributed under an open-source license.
