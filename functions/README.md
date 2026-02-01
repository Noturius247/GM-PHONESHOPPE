# GM Phoneshoppe - Firebase Cloud Functions

This folder contains Firebase Cloud Functions for the GM Phoneshoppe app, specifically for sending invitation emails.

## Setup Instructions

### 1. Install Firebase CLI (if not already installed)
```bash
npm install -g firebase-tools
```

### 2. Login to Firebase
```bash
firebase login
```

### 3. Initialize Functions (if not already done)
```bash
cd d:\parkingapp\GM-PHONESHOPPE
firebase init functions
```
Select your existing project: `gmphoneshoppe-f0420`

### 4. Install Dependencies
```bash
cd functions
npm install
```

### 5. Configure Email Service

All invitation emails are sent from `gmphoneshoppe24@gmail.com` regardless of which admin sends the invitation.

#### Setup Gmail App Password:

1. Login to Google as `gmphoneshoppe24@gmail.com`
2. Go to: https://myaccount.google.com
3. Security > 2-Step Verification (enable if not already)
4. App passwords > Generate a new app password for "Mail"
5. Copy the 16-character password
6. Set the Firebase config:

```bash
firebase functions:config:set email.pass="your-16-char-app-password"
```

**Note:** Only the password is needed. The email address is hardcoded to `gmphoneshoppe24@gmail.com`.

### 6. Upload Logo to Firebase Storage

Upload the GM Phoneshoppe logo to Firebase Storage:
1. Go to Firebase Console > Storage
2. Create folder `logo`
3. Upload `logo.png`
4. Make the file public or update the URL in the email templates

### 7. Deploy Functions
```bash
firebase deploy --only functions
```

### 8. Test the Function

After deployment, your function URL will be:
```
https://us-central1-gmphoneshoppe-f0420.cloudfunctions.net/sendEmail
```

Test with curl:
```bash
curl -X POST https://us-central1-gmphoneshoppe-f0420.cloudfunctions.net/sendEmail \
  -H "Content-Type: application/json" \
  -d '{"to":"test@example.com","subject":"Test","html":"<p>Hello</p>","type":"test"}'
```

## Functions Available

### `sendEmail` (HTTP)
General purpose email sending function.

**Request Body:**
```json
{
  "to": "recipient@example.com",
  "subject": "Email Subject",
  "html": "<p>HTML content</p>",
  "type": "invitation|approval|etc"
}
```

### `sendInvitationEmail` (Callable)
Specifically for sending user invitations. Can be called from the Flutter app using Firebase Functions SDK.

## Email Logs

All email attempts are logged to Firebase Realtime Database under `/email_logs` for debugging and audit purposes.

## Troubleshooting

1. **"Email logged (no email service configured)"** - Set up email config with `firebase functions:config:set`

2. **Gmail auth errors** - Make sure 2FA is enabled and you're using an App Password, not your regular password

3. **CORS errors** - The function includes CORS handling, but ensure your app's domain is allowed

## Local Development

To test locally:
```bash
firebase emulators:start --only functions
```

Then use the local URL: `http://localhost:5001/gmphoneshoppe-f0420/us-central1/sendEmail`
