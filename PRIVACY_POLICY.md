# Privacy Policy for Capture

**Last Updated:** January 27, 2026

**Developer:** Maximilian Glasmacher  
**Contact:** maxdevelopertools@gmail.com

---

## 1. Introduction

Welcome to Capture ("we," "our," or "us"). This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application Capture (the "App"). Please read this privacy policy carefully. If you do not agree with the terms of this privacy policy, please do not access the App.

We reserve the right to make changes to this Privacy Policy at any time and for any reason. We will alert you about any changes by updating the "Last Updated" date of this Privacy Policy. You are encouraged to periodically review this Privacy Policy to stay informed of updates.

---

## 2. Information We Collect

### Information You Provide

| Data Type | How It's Collected | Purpose |
|-----------|-------------------|---------|
| **Google Account Information** (name, email address, profile photo) | When you sign in with Google | To authenticate you and display your profile in the App |
| **Screenshots** | When you use the capture feature | To analyze images and extract calendar event information |

### Information Collected Automatically

| Data Type | How It's Collected | Purpose |
|-----------|-------------------|---------|
| **Google OAuth Tokens** | During Google Sign-In | To access Google Calendar API on your behalf |
| **Capture History** | When events are created | To display your recent captures in the App (stored locally on your device) |
| **Analytics Data** | Through PostHog SDK | To understand how the App is used and improve functionality |

### Information We Do NOT Collect

- We do not collect passwords (authentication is handled entirely by Google)
- We do not collect location data
- We do not collect contacts or phone data
- We do not access your existing calendar events (we only create new ones)

---

## 3. How We Use Your Information

We use the information we collect to:

- **Authenticate you** via Google Sign-In
- **Analyze screenshots** using artificial intelligence to extract event details (title, date, time, location)
- **Create calendar events** in your Google Calendar on your behalf
- **Display your capture history** within the App
- **Improve the App** through anonymized usage analytics
- **Provide customer support** when you contact us

---

## 4. Third-Party Services

We use the following third-party services to operate the App. Each service has its own privacy policy governing the use of your information:

| Service | Purpose | Privacy Policy |
|---------|---------|----------------|
| **Google** (OAuth, Calendar API) | Authentication and calendar access | [Google Privacy Policy](https://policies.google.com/privacy) |
| **OpenAI** (GPT-4 Vision) | AI-powered screenshot analysis | [OpenAI Privacy Policy](https://openai.com/policies/privacy-policy) |
| **PostHog** | Usage analytics | [PostHog Privacy Policy](https://posthog.com/privacy) |
| **Railway** | Backend server hosting | [Railway Privacy Policy](https://railway.app/legal/privacy) |

### Important Note About Screenshot Processing

When you capture a screenshot, the image is sent to our backend server and then to OpenAI's API for analysis. OpenAI processes the image to extract event information. According to OpenAI's API data usage policy, data sent through their API is not used to train their models. However, please be mindful of the content in your screenshots, as they are transmitted to third-party servers for processing.

---

## 5. Data Retention

| Data Type | Retention Period |
|-----------|-----------------|
| **Screenshots** | Processed in memory only; not permanently stored on our servers |
| **Capture History** | Stored locally on your device until you sign out or delete the App |
| **Account Information** | Retained until you disconnect your Google account from the App |
| **Analytics Data** | Retained according to PostHog's data retention policies |

---

## 6. Data Security

We implement appropriate technical and organizational security measures to protect your information:

- **Secure Authentication:** OAuth tokens are stored in the iOS Keychain, which provides hardware-level encryption
- **Encrypted Communications:** All data transmitted between the App and our servers uses HTTPS/TLS encryption
- **No Password Storage:** We never store your Google password; authentication is handled entirely by Google's secure OAuth system
- **Minimal Data Storage:** Screenshots are processed in memory and not permanently stored

While we strive to use commercially acceptable means to protect your information, no method of transmission over the Internet or electronic storage is 100% secure, and we cannot guarantee absolute security.

---

## 7. Your Privacy Rights

### For All Users

You have the right to:

- **Access your data:** Contact us to request information about what data we have about you
- **Delete your data:** Use the "Disconnect Account" feature in the App to remove your account and local data
- **Opt-out of analytics:** Contact us if you wish to opt out of analytics tracking

### For European Union Residents (GDPR)

If you are a resident of the European Economic Area (EEA), you have additional rights under the General Data Protection Regulation (GDPR):

- **Right to Access:** You can request copies of your personal data
- **Right to Rectification:** You can request that we correct inaccurate information
- **Right to Erasure:** You can request that we delete your personal data
- **Right to Restrict Processing:** You can request that we limit how we use your data
- **Right to Data Portability:** You can request a copy of your data in a machine-readable format
- **Right to Object:** You can object to our processing of your personal data

To exercise any of these rights, please contact us at maxdevelopertools@gmail.com.

### For California Residents (CCPA)

If you are a California resident, you have rights under the California Consumer Privacy Act (CCPA):

- **Right to Know:** You can request information about the categories and specific pieces of personal information we have collected
- **Right to Delete:** You can request deletion of your personal information
- **Right to Non-Discrimination:** We will not discriminate against you for exercising your privacy rights

To exercise your rights, please contact us at maxdevelopertools@gmail.com.

---

## 8. Children's Privacy

The App is not intended for use by children under the age of 13. We do not knowingly collect personal information from children under 13. If you are a parent or guardian and believe that your child has provided us with personal information, please contact us at maxdevelopertools@gmail.com so that we can take appropriate action.

---

## 9. International Data Transfers

Your information may be transferred to and processed in countries other than your own, including the United States (where OpenAI is located) and the European Union (where our analytics are processed). These countries may have data protection laws that are different from the laws of your country.

By using the App, you consent to the transfer of your information to these countries. We ensure that appropriate safeguards are in place to protect your information in accordance with this Privacy Policy.

---

## 10. Changes to This Privacy Policy

We may update this Privacy Policy from time to time. We will notify you of any changes by:

- Updating the "Last Updated" date at the top of this Privacy Policy
- Posting a notice in the App when significant changes are made

You are advised to review this Privacy Policy periodically for any changes. Changes to this Privacy Policy are effective when they are posted on this page.

---

## 11. Contact Us

If you have any questions or concerns about this Privacy Policy or our data practices, please contact us:

**Email:** maxdevelopertools@gmail.com

**Developer:** Maximilian Glasmacher

---

## 12. Consent

By using the Capture App, you consent to:

- The collection and use of your information as described in this Privacy Policy
- The transfer of your information to third-party services (Google, OpenAI, PostHog) as described above
- The processing of your screenshots by AI services to extract calendar event information

If you do not consent to any of the above, please do not use the App.
