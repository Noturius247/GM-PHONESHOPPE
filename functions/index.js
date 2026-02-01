const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const cors = require("cors")({origin: true});

admin.initializeApp();

// GM Phoneshoppe email configuration
// Email credentials are stored in .env file:
// EMAIL_USER=your-email@gmail.com
// EMAIL_PASS=your-16-char-app-password

const GM_PHONESHOPPE_NAME = "GM Phoneshoppe";

const getEmailConfig = () => {
  return {
    user: process.env.EMAIL_USER,
    pass: process.env.EMAIL_PASS,
  };
};

const getTransporter = () => {
  const emailConfig = getEmailConfig();

  if (emailConfig.user && emailConfig.pass) {
    return nodemailer.createTransport({
      service: "gmail",
      auth: {
        user: emailConfig.user,
        pass: emailConfig.pass,
      },
    });
  }

  // Fallback: Log email instead of sending (for development)
  return null;
};

// Send Email Cloud Function
exports.sendEmail = functions.https.onRequest((req, res) => {
  cors(req, res, async () => {
    // Only allow POST requests
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    try {
      const {to, subject, html, type} = req.body;

      if (!to || !subject || !html) {
        res.status(400).json({error: "Missing required fields: to, subject, html"});
        return;
      }

      const transporter = getTransporter();

      if (!transporter) {
        // Log the email for development
        console.log("=== Email would be sent ===");
        console.log("To:", to);
        console.log("Subject:", subject);
        console.log("Type:", type);
        console.log("HTML Length:", html.length);
        console.log("===========================");

        // Store in Firebase for record
        await admin.database().ref("email_logs").push({
          to,
          subject,
          type,
          status: "logged_not_sent",
          timestamp: admin.database.ServerValue.TIMESTAMP,
        });

        res.status(200).json({
          success: true,
          message: "Email logged (no email service configured)",
        });
        return;
      }

      // Send the email (always from GM Phoneshoppe official email)
      const emailConfig = getEmailConfig();
      const mailOptions = {
        from: `"${GM_PHONESHOPPE_NAME}" <${emailConfig.user}>`,
        to,
        subject,
        html,
      };

      await transporter.sendMail(mailOptions);

      // Log successful send
      await admin.database().ref("email_logs").push({
        to,
        subject,
        type,
        status: "sent",
        timestamp: admin.database.ServerValue.TIMESTAMP,
      });

      console.log("Email sent successfully to:", to);
      res.status(200).json({success: true, message: "Email sent successfully"});
    } catch (error) {
      console.error("Error sending email:", error);

      // Log failed attempt
      await admin.database().ref("email_logs").push({
        to: req.body.to,
        subject: req.body.subject,
        type: req.body.type,
        status: "failed",
        error: error.message,
        timestamp: admin.database.ServerValue.TIMESTAMP,
      });

      res.status(500).json({error: "Failed to send email", details: error.message});
    }
  });
});

// Callable function for sending invitations (more secure, requires authentication)
// eslint-disable-next-line no-unused-vars
exports.sendInvitationEmail = functions.https.onCall(async (data, context) => {
  // Optionally verify the caller is an admin
  // if (!context.auth) {
  //   throw new functions.https.HttpsError('unauthenticated', 'Must be logged in');
  // }

  const {recipientEmail, recipientName, invitedByName, invitationToken} = data;

  if (!recipientEmail) {
    throw new functions.https.HttpsError("invalid-argument", "Recipient email is required");
  }

  const transporter = getTransporter();

  const emailHtml = buildInvitationEmailHtml(recipientName, invitedByName, invitationToken);

  if (!transporter) {
    console.log("Invitation email logged for:", recipientEmail);
    return {success: true, message: "Email logged (no service configured)"};
  }

  try {
    const emailConfig = getEmailConfig();
    await transporter.sendMail({
      from: `"${GM_PHONESHOPPE_NAME}" <${emailConfig.user}>`,
      to: recipientEmail,
      subject: "You're Invited to Join GM Phoneshoppe!",
      html: emailHtml,
    });

    return {success: true, message: "Invitation sent"};
  } catch (error) {
    console.error("Failed to send invitation:", error);
    throw new functions.https.HttpsError("internal", "Failed to send email");
  }
});

// Build invitation email HTML
function buildInvitationEmailHtml(recipientName, invitedByName, invitationToken) {
  const primaryColor = "#8B1A1A";
  const secondaryColor = "#1ABC9C";

  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>GM Phoneshoppe Invitation</title>
</head>
<body style="margin: 0; padding: 0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f5f5f5;">
  <table role="presentation" style="width: 100%; border-collapse: collapse;">
    <tr>
      <td align="center" style="padding: 40px 0;">
        <table role="presentation" style="width: 600px; max-width: 100%; border-collapse: collapse; background-color: #ffffff; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 20px rgba(0,0,0,0.15);">

          <!-- Header with Logo -->
          <tr>
            <td style="background: linear-gradient(135deg, ${primaryColor} 0%, #5D1212 100%); padding: 40px 30px; text-align: center;">
              <img src="https://firebasestorage.googleapis.com/v0/b/gmphoneshoppe-f0420.firebasestorage.app/o/logo%2Flogo.png?alt=media"
                   alt="GM Phoneshoppe Logo"
                   style="width: 120px; height: 120px; border-radius: 60px; border: 4px solid rgba(255,255,255,0.3); margin-bottom: 20px;">
              <h1 style="color: #ffffff; margin: 0; font-size: 28px; font-weight: bold; text-shadow: 0 2px 4px rgba(0,0,0,0.3);">
                GM Phoneshoppe
              </h1>
              <p style="color: rgba(255,255,255,0.9); margin: 10px 0 0 0; font-size: 14px;">
                Your Trusted Partner in Connectivity
              </p>
            </td>
          </tr>

          <!-- Main Content -->
          <tr>
            <td style="padding: 40px 30px;">
              <h2 style="color: ${primaryColor}; margin: 0 0 20px 0; font-size: 24px;">
                You're Invited!
              </h2>

              <p style="color: #333333; font-size: 16px; line-height: 1.6; margin: 0 0 20px 0;">
                Hello <strong>${recipientName || "there"}</strong>,
              </p>

              <p style="color: #333333; font-size: 16px; line-height: 1.6; margin: 0 0 20px 0;">
                <strong>${invitedByName || "An administrator"}</strong> has invited you to join the <strong>GM Phoneshoppe</strong> team!
                We're excited to have you on board.
              </p>

              <div style="background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%); border-radius: 12px; padding: 25px; margin: 25px 0; border-left: 4px solid ${secondaryColor};">
                <p style="color: #555555; font-size: 15px; line-height: 1.6; margin: 0;">
                  <strong style="color: ${primaryColor};">What's next?</strong><br><br>
                  To accept this invitation and access the GM Phoneshoppe app:
                </p>
                <ol style="color: #555555; font-size: 15px; line-height: 1.8; margin: 15px 0 0 0; padding-left: 20px;">
                  <li>Open the <strong>GM Phoneshoppe</strong> app on your device</li>
                  <li>Sign in with your Google account using this email address</li>
                  <li>Your account will be automatically activated!</li>
                </ol>
              </div>

              ${invitationToken ? `
              <div style="text-align: center; margin: 30px 0;">
                <div style="display: inline-block; background: linear-gradient(135deg, ${secondaryColor} 0%, #16a085 100%); padding: 15px 40px; border-radius: 30px;">
                  <span style="color: #ffffff; font-size: 16px; font-weight: bold;">
                    Your Invitation Code: ${invitationToken}
                  </span>
                </div>
              </div>
              ` : ""}

              <p style="color: #666666; font-size: 14px; line-height: 1.6; margin: 20px 0 0 0;">
                This invitation is valid for <strong>7 days</strong>. If you didn't expect this invitation,
                you can safely ignore this email.
              </p>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="background-color: #1A0A0A; padding: 30px; text-align: center;">
              <p style="color: rgba(255,255,255,0.7); font-size: 14px; margin: 0 0 10px 0;">
                &copy; 2024 GM Phoneshoppe. All rights reserved.
              </p>
              <p style="color: rgba(255,255,255,0.5); font-size: 12px; margin: 0;">
                Cignal &bull; GSAT &bull; Sky &bull; Satellite Services
              </p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>
`;
}
