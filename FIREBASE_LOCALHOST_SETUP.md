# Quick Firebase Setup for Localhost

## Step-by-Step Guide to Get Google Sign-In Working

### 1. Create Firebase Project

1. Go to **https://console.firebase.google.com/**
2. Click **"Add project"**
3. Enter project name: `GM PhoneShoppe`
4. Click **Continue**
5. Disable Google Analytics (toggle off) - not needed for now
6. Click **Create project**
7. Wait for project to be created, then click **Continue**

---

### 2. Add Web App

1. On the Firebase project homepage, click the **Web icon** `</>`
2. Register app:
   - **App nickname**: `GM PhoneShoppe Web`
   - Leave "Firebase Hosting" unchecked (you can add it later)
3. Click **Register app**
4. You'll see Firebase SDK configuration - **you can skip this for now**
5. Click **Continue to console**

---

### 3. Enable Google Authentication

1. In the left sidebar, click **Authentication**
2. Click **Get started** button
3. Click the **Sign-in method** tab at the top
4. Find **Google** in the list of providers
5. Click on **Google**
6. Toggle the **Enable** switch to ON
7. **Project support email**: Select your email from dropdown
8. Click **Save**

---

### 4. Get Your Web Client ID

After enabling Google sign-in, you'll see:

1. **Web SDK configuration** section
2. **Web client ID**: `123456789-xxxxxxxxx.apps.googleusercontent.com`
3. **Copy this Client ID** - you'll need it in the next step

---

### 5. Configure Localhost (Important!)

Firebase **automatically authorizes `localhost`** for testing, so you don't need to do anything extra for localhost to work!

By default, these domains are pre-authorized:
- `localhost`
- `127.0.0.1`

To verify:
1. Go to **Authentication** → **Settings** tab
2. Scroll down to **Authorized domains**
3. You should see `localhost` already listed

✅ **You're good to go for local development!**

---

### 6. Update Your Code

1. Open `web/index.html` in your project
2. Find line 25:
   ```html
   <meta name="google-signin-client_id" content="YOUR_WEB_CLIENT_ID.apps.googleusercontent.com">
   ```

3. Replace `YOUR_WEB_CLIENT_ID.apps.googleusercontent.com` with your actual Client ID from step 4:
   ```html
   <meta name="google-signin-client_id" content="123456789-xxxxxxxxx.apps.googleusercontent.com">
   ```

---

### 7. Test Your App

1. Open terminal in your project folder
2. Run:
   ```bash
   flutter run -d chrome --web-port=5000
   ```

3. Your app will always run on `http://localhost:5000`
4. Wait for the app to load in Chrome
5. Click **"Sign in with Google"** or **"Sign up with Google"**
6. You should see:
   - **Google account picker** showing accounts signed into your browser
   - **"Use another account"** option to sign in with a different account
   - After selecting an account, you'll be signed in!

**Alternative**: Press **F5** in VSCode to run with the fixed port (uses `.vscode/launch.json` configuration)

---

## Testing Admin vs User

### Test as Admin:
- Sign in with `luzaresbenzgerald@gmail.com` or `gmphoneshoppe24@gmail.com`
- You'll be redirected to the **Admin Dashboard**

### Test as Regular User:
- Sign in with any other Google account
- You'll be redirected to the **User Dashboard**

---

## What Port Does Flutter Use?

With the `--web-port=5000` flag, your app will always run on:
- `http://localhost:5000`

This makes it easier to configure OAuth settings since the port is always the same.

Firebase automatically allows **any** localhost port, so you don't need to configure it!

---

## Troubleshooting

### Issue: "Authorization failed" error
**Solution**: Make sure you copied the correct Web Client ID to `web/index.html`

### Issue: Popup closes immediately
**Solution**:
1. Check that Google sign-in is **Enabled** in Firebase Console
2. Verify your Client ID in `web/index.html` matches Firebase

### Issue: "redirect_uri_mismatch"
**Solution**: This shouldn't happen with localhost, but if it does:
1. Go to Firebase Console → Authentication → Settings → Authorized domains
2. Make sure `localhost` is listed

### Issue: No account picker shows up
**Solution**:
1. Make sure you're signed into at least one Google account in Chrome
2. Clear browser cache and try again
3. Try signing in to a Google account in another Chrome tab first

---

## Summary Checklist

- [ ] Created Firebase project
- [ ] Added Web app to Firebase
- [ ] Enabled Google authentication
- [ ] Copied Web Client ID
- [ ] Updated `web/index.html` with Client ID
- [ ] Ran `flutter run -d chrome`
- [ ] Successfully signed in with Google account picker

---

## Next Steps After Local Testing

When you're ready to deploy to production:
1. Add your production domain to Firebase Console → Authentication → Settings → Authorized domains
2. Deploy your app
3. That's it! No other changes needed.

---

**Need Help?**
Check the full setup guide in `GOOGLE_SIGNIN_SETUP.md` or the Firebase Console documentation.
