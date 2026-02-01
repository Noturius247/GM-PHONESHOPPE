# Google Sign-In Setup Guide for GM PhoneShoppe

## Overview
This guide will help you set up Google Sign-In for your Flutter web app. Once configured, users will be able to:
- Choose from Google accounts saved in their browser
- Sign in with a new Google account
- See a proper Google account picker interface

## Current Status
✅ Code is already configured to support account selection
✅ The `google_sign_in` package is installed
⚠️ You need to configure your Firebase/Google credentials

---

## Two Options for Setup

You can set up Google Sign-In using either:
1. **Firebase Console** (Recommended - Easier)
2. **Google Cloud Console** (Manual setup)

---

# Option 1: Using Firebase (RECOMMENDED)

This is the easiest method and includes additional features like analytics and authentication management.

## Setup Steps with Firebase

### 1. Create a Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click **Add Project** or select an existing project
3. Enter project name: **GM PhoneShoppe**
4. Disable Google Analytics (optional, can enable later)
5. Click **Create Project**

### 2. Add Web App to Firebase

1. In your Firebase project dashboard, click the **Web icon** `</>`
2. Register your app:
   - App nickname: **GM PhoneShoppe Web**
   - Check **"Also set up Firebase Hosting"** (optional)
   - Click **Register app**
3. **Copy the Firebase config** (you'll need this later if you want to add more Firebase features)
4. Click **Continue to console**

### 3. Enable Google Sign-In

1. In Firebase Console, go to **Authentication** (in the left sidebar)
2. Click **Get Started**
3. Go to **Sign-in method** tab
4. Click on **Google** provider
5. Click **Enable** toggle
6. Select a **Project support email** (your email)
7. Click **Save**

### 4. Get Your Web Client ID

1. Still in the Google sign-in provider settings, you'll see:
   - **Web SDK configuration** section
   - **Web client ID**: This is what you need!
2. **Copy the Web client ID** (it looks like: `123456789-abcdefg.apps.googleusercontent.com`)

### 5. Configure Authorized Domains

1. In Firebase Console, go to **Authentication** > **Settings** tab
2. Scroll to **Authorized domains**
3. By default, `localhost` is already authorized
4. When deploying to production, click **Add domain** and add your production domain

### 6. Update Your Code

Open `web/index.html` and replace line 25 with your Web client ID:

```html
<meta name="google-signin-client_id" content="YOUR_ACTUAL_CLIENT_ID_HERE.apps.googleusercontent.com">
```

### 7. Test Your Application

```bash
flutter run -d chrome
```

Click "Sign in with Google" - you should see the Google account picker!

---

# Option 2: Using Google Cloud Console (Manual Setup)

### 1. Create a Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Note your project name

### 2. Enable Google Sign-In API

1. In your Google Cloud Project, go to **APIs & Services** > **Library**
2. Search for "Google+ API" or "Google Identity"
3. Click **Enable**

### 3. Configure OAuth Consent Screen

1. Go to **APIs & Services** > **OAuth consent screen**
2. Choose **External** user type
3. Fill in the required information:
   - App name: **GM PhoneShoppe**
   - User support email: Your email
   - Developer contact email: Your email
4. Click **Save and Continue**
5. Skip the Scopes section (click **Save and Continue**)
6. Add test users if needed (or publish the app)
7. Click **Save and Continue**

### 4. Create OAuth 2.0 Credentials

1. Go to **APIs & Services** > **Credentials**
2. Click **Create Credentials** > **OAuth client ID**
3. Choose **Web application**
4. Configure:
   - **Name**: GM PhoneShoppe Web Client
   - **Authorized JavaScript origins**:
     - `http://localhost` (for local development)
     - `http://localhost:port` (replace `port` with your dev server port, usually 5000 or 8080)
     - Add your production domain when deploying (e.g., `https://yourdomain.com`)
   - **Authorized redirect URIs**:
     - `http://localhost` (for local development)
     - `http://localhost:port` (replace with your actual port)
     - Add your production domain when deploying

5. Click **Create**
6. **IMPORTANT**: Copy your **Client ID** - you'll need this!

### 5. Update Your Code

#### Update `web/index.html`
Replace `YOUR_WEB_CLIENT_ID.apps.googleusercontent.com` on line 25 with your actual Client ID:

```html
<meta name="google-signin-client_id" content="123456789-abcdefghijklmnop.apps.googleusercontent.com">
```

### 6. Test Your Application

1. Run your Flutter app in Chrome:
   ```bash
   flutter run -d chrome
   ```

2. Navigate to the Login or Sign Up page
3. Click "Sign in with Google" or "Sign up with Google"
4. You should see the Google account picker showing:
   - Accounts already signed in to your browser
   - Option to "Use another account" to sign in with a different account

## How It Works

### Account Selection Flow

When a user clicks the sign-in button:

1. **If user has saved Google accounts in browser**:
   - Google shows an account picker
   - User can choose an existing account
   - Or click "Use another account" to sign in with a new one

2. **If user has no saved accounts**:
   - Google shows the standard sign-in page
   - User enters email and password
   - Account gets saved to browser for future use

3. **After successful sign-in**:
   - If email is `admin@gm.com` → User goes to Admin Page
   - Any other email → User goes to User Page
   - Account info is saved locally using SharedPreferences

### Features Already Implemented

✅ Account picker automatically shows saved Google accounts
✅ "Use another account" option available
✅ Role-based routing (admin vs regular user)
✅ Session persistence (stays logged in after page refresh)
✅ Secure logout (clears both local storage and Google session)

## Troubleshooting

### Issue: "Authorization failed" or "Popup closed"
**Solution**: Make sure your OAuth client ID is correctly configured in `web/index.html` and your redirect URIs are set up in Google Cloud Console.

### Issue: No account picker shows up
**Solution**:
1. Clear your browser cache
2. Make sure you're signed in to at least one Google account in your browser
3. Check that the Client ID in `web/index.html` matches your Google Cloud Console

### Issue: "redirect_uri_mismatch" error
**Solution**: Add your current localhost URL (including port) to the Authorized redirect URIs in Google Cloud Console.

### Issue: Works locally but not in production
**Solution**: Add your production domain to both Authorized JavaScript origins and Authorized redirect URIs in Google Cloud Console.

## Security Notes

- Never commit your Client ID to public repositories if it's for production
- The current setup uses client-side authentication only (no backend)
- Admin access is determined by email address (`admin@gm.com`)
- All user data is stored locally in the browser using SharedPreferences

## Testing Admin vs User Access

1. **Test Admin Access**:
   - Sign in with a Google account that has email `admin@gm.com`
   - You'll be redirected to the Admin Page

2. **Test User Access**:
   - Sign in with any other Google account
   - You'll be redirected to the User Page

## Need Help?

If you encounter issues:
1. Check the browser console for error messages
2. Verify your Client ID is correct in `web/index.html`
3. Make sure your redirect URIs match in Google Cloud Console
4. Clear browser cache and try again

---

**Next Steps**: Follow steps 1-5 above to get your Google Sign-In working with account selection!
