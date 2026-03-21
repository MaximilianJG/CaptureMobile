**Last Updated:** January 27, 2026

**Developer:** Maximilian Glasmacher

**Contact:** [maxdevelopertools@gmail.com](mailto:maxdevelopertools@gmail.com)

---

## 1. Introduction

Welcome to Capture ("we," "our," or "us"). This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application Capture (the "App"). Please read this privacy policy carefully. If you do not agree with the terms of this privacy policy, please do not access the App.

We reserve the right to make changes to this Privacy Policy at any time and for any reason. We will alert you about any changes by updating the "Last Updated" date of this Privacy Policy. You are encouraged to periodically review this Privacy Policy to stay informed of updates.

---

## 2. Information We Collect

### Information You Provide


| Data Type                                                             | How It's Collected                                       | Purpose                                                  |
| --------------------------------------------------------------------- | -------------------------------------------------------- | -------------------------------------------------------- |
| **Apple ID Information** (name, email address if you choose to share) | When you sign in with Apple                              | To authenticate you and display your profile in the App  |
| **Screenshots**                                                       | When you use the capture feature (e.g. via the Shortcut) | To analyze images and extract calendar event information |


### Information Collected Automatically


| Data Type                             | How It's Collected                                                 | Purpose                                                                                             |
| ------------------------------------- | ------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------- |
| **User identifier** (Apple Sign-In)   | Stored on your device and sent to our backend when you use capture | To associate your captures with your account and deliver push notifications when events are created |
| **Device token** (push notifications) | When you enable notifications and use the App                      | To send you notifications when screenshot analysis is complete (e.g. "Event created")               |
| **Capture History**                   | When events are created                                            | To display your recent captures in the App (stored locally on your device)                          |
| **Analytics Data**                    | Through PostHog SDK                                                | To understand how the App is used and improve functionality                                         |


### Information We Do NOT Collect

- We do not collect passwords (authentication is handled by Apple Sign-In)
- We do not collect location data
- We do not collect contacts or phone data
- We do not read your existing calendar events (we only create new ones in the calendar you choose in the App)

---

## 3. How We Use Your Information

We use the information we collect to:

- **Authenticate you** via Sign in with Apple
- **Analyze screenshots** using artificial intelligence to extract event details (title, date, time, location)
- **Create calendar events** in your chosen Apple Calendar (on your device) after analysis
- **Send you push notifications** when event creation is complete (if you have enabled notifications)
- **Display your capture history** within the App
- **Improve the App** through usage analytics (e.g. PostHog)
- **Provide customer support** when you contact us

---

## 4. Third-Party Services

We use the following third-party services to operate the App. Each service has its own privacy policy governing the use of your information:


| Service                        | Purpose                                       | Privacy Policy                                                      |
| ------------------------------ | --------------------------------------------- | ------------------------------------------------------------------- |
| **Apple** (Sign in with Apple) | Authentication                                | [Apple Privacy Policy](https://www.apple.com/legal/privacy/)        |
| **OpenAI** (GPT-4 Vision)      | AI-powered screenshot analysis on our backend | [OpenAI Privacy Policy](https://openai.com/policies/privacy-policy) |
| **PostHog**                    | Usage analytics                               | [PostHog Privacy Policy](https://posthog.com/privacy)               |
| **Railway**                    | Backend server hosting                        | [Railway Privacy Policy](https://railway.app/legal/privacy)         |


**Calendar:** Calendar events are created on your device using Apple’s built-in Calendar (EventKit). We do not send your calendar data to Google or any other third-party calendar service.

### Important Note About Screenshot Processing

When you capture a screenshot, the image is sent to our backend server and then to OpenAI's API for analysis. OpenAI processes the image to extract event information. According to OpenAI's API data usage policy, data sent through their API is not used to train their models. However, please be mindful of the content in your screenshots, as they are transmitted to our servers and to OpenAI for processing.

---

## 5. Data Retention


| Data Type                     | Retention Period                                                                   |
| ----------------------------- | ---------------------------------------------------------------------------------- |
| **Screenshots**               | Processed and not permanently stored on our servers                                |
| **Capture History**           | Stored locally on your device until you sign out or delete the App                 |
| **Account / identifier data** | Retained until you disconnect your account from the App ("Disconnect Account")     |
| **Device token**              | Retained on our systems until you disconnect your account or disable notifications |
| **Analytics Data**            | Retained according to PostHog's data retention policies                            |


---

## 6. Data Security

We implement appropriate technical and organizational security measures to protect your information:

- **Secure storage:** Your Apple user identifier and related profile data are stored in the iOS Keychain on your device
- **Encrypted communications:** All data transmitted between the App and our servers uses HTTPS/TLS encryption
- **No password storage:** We never store your Apple ID password; authentication is handled by Apple Sign-In
- **Minimal data storage:** Screenshots are processed and not permanently stored on our servers

While we strive to use commercially acceptable means to protect your information, no method of transmission over the Internet or electronic storage is 100% secure, and we cannot guarantee absolute security.

---

## 7. Your Privacy Rights

### For All Users

You have the right to:

- **Access your data:** Contact us to request information about what data we have about you
- **Delete your data:** Use the "Disconnect Account" option in the App (Manage Account) to remove your account; local capture history is tied to your use of the App
- **Opt-out of analytics:** Contact us if you wish to opt out of analytics tracking

### For European Union Residents (GDPR)

If you are a resident of the European Economic Area (EEA), you have additional rights under the General Data Protection Regulation (GDPR):

- **Right to Access:** You can request copies of your personal data
- **Right to Rectification:** You can request that we correct inaccurate information
- **Right to Erasure:** You can request that we delete your personal data
- **Right to Restrict Processing:** You can request that we limit how we use your data
- **Right to Data Portability:** You can request a copy of your data in a machine-readable format
- **Right to Object:** You can object to our processing of your personal data

To exercise any of these rights, please contact us at [maxdevelopertools@gmail.com](mailto:maxdevelopertools@gmail.com).

### For California Residents (CCPA)

If you are a California resident, you have rights under the California Consumer Privacy Act (CCPA):

- **Right to Know:** You can request information about the categories and specific pieces of personal information we have collected
- **Right to Delete:** You can request deletion of your personal information
- **Right to Non-Discrimination:** We will not discriminate against you for exercising your privacy rights

To exercise your rights, please contact us at [maxdevelopertools@gmail.com](mailto:maxdevelopertools@gmail.com).

---

## 8. Children's Privacy

The App is not intended for use by children under the age of 13. We do not knowingly collect personal information from children under 13. If you are a parent or guardian and believe that your child has provided us with personal information, please contact us at [maxdevelopertools@gmail.com](mailto:maxdevelopertools@gmail.com) so that we can take appropriate action.

---

## 9. International Data Transfers

Your information may be transferred to and processed in countries other than your own, including the United States (where OpenAI and our hosting may be located) and the European Union (where our analytics may be processed). These countries may have data protection laws that are different from the laws of your country.

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

**Email:** [maxdevelopertools@gmail.com](mailto:maxdevelopertools@gmail.com)

**Developer:** Maximilian Glasmacher

---

## 12. Consent

By using the Capture App, you consent to:

- The collection and use of your information as described in this Privacy Policy
- The transfer of your information to third-party services (Apple, OpenAI, PostHog) as described above
- The processing of your screenshots by our backend and OpenAI to extract calendar event information

If you do not consent to any of the above, please do not use the App.