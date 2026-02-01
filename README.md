# GM PhoneShoppe

A Flutter application for managing GM PhoneShoppe services including Cignal, Satlite, GSAT, and Sky.

## Features

- **Landing Page**: Welcome screen with login and sign-up options
- **Authentication**: Login and Sign Up pages with form validation
- **Admin Dashboard**: Main admin page with service navigation and quick stats
- **Service Management**: Individual pages for each service:
  - Cignal (TV Services)
  - Satlite (Satellite Services)
  - GSAT (Global Satellite)
  - Sky (Cable Services)

## Project Structure

```
lib/
├── main.dart                 # App entry point
└── pages/
    ├── landing_page.dart     # Welcome/landing screen
    ├── login_page.dart       # User login
    ├── signup_page.dart      # User registration
    ├── main_admin_page.dart  # Admin dashboard
    ├── cignal_page.dart      # Cignal service management
    ├── satlite_page.dart     # Satlite service management
    ├── gsat_page.dart        # GSAT service management
    └── sky_page.dart         # Sky service management
```

## Getting Started

### Prerequisites

- Flutter SDK (version 3.38.1 or higher)
- Android Studio / VS Code with Flutter extensions
- Android SDK for Android development
- Xcode for iOS development (macOS only)

### Installation

1. Clone the repository
2. Navigate to the project directory:
   ```bash
   cd GM-PHONESHOPPE
   ```

3. Install dependencies:
   ```bash
   flutter pub get
   ```

4. Run the app:
   ```bash
   flutter run
   ```

### Login Credentials

The app includes role-based authentication with separate access levels:

**Admin Access (Full Management):**
- Email: `admin@gm.com`
- Password: `admin123`

**User Access (Browse Only):**
- Email: `user@gm.com`
- Password: `user123`

For detailed information, see [CREDENTIALS.md](CREDENTIALS.md)

### Build Commands

#### Android
```bash
# Debug build
flutter build apk --debug

# Release build
flutter build apk --release
```

#### iOS (macOS only)
```bash
flutter build ios
```

#### Web
```bash
flutter build web
```

#### Windows
```bash
flutter build windows
```

## Code Quality

The project passes all Flutter analysis checks with no issues:

```bash
flutter analyze
```

Result: ✅ No issues found!

## Design Features

- Material Design 3 UI components
- Google Fonts (Poppins typography)
- Gradient backgrounds
- Color-coded service pages:
  - Cignal: Blue theme
  - Satlite: Green theme
  - GSAT: Orange theme
  - Sky: Purple theme
- Responsive cards and layouts
- Form validation
- Sample customer data

## Technologies Used

- **Flutter**: Cross-platform framework
- **Material Design 3**: Modern UI design system
- **Google Fonts**: Custom typography (Poppins)
- **Dart**: Programming language

## Future Enhancements

- Backend integration for real customer data
- User authentication with Firebase/API
- Database integration
- Push notifications
- Real-time updates
- Payment processing
- Customer reports and analytics

## License

Copyright © 2024 GM PhoneShoppe. All rights reserved.

---

🤖 Generated with Claude Code
