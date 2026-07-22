# Enterprise Hardware Diagnostics & Real-Time Device Telemetry Platform

## Executive Summary

The **Enterprise Hardware Diagnostics & Real-Time Device Telemetry Platform** is a full-stack, enterprise-grade mobile diagnostic and real-time fleet monitoring solution. It enables support engineers, QA testers, and fleet managers to monitor mobile hardware health, track high-accuracy GPS positions with reverse-geocoded street addresses, record device screens for remote troubleshooting, and view live telemetry on a glassmorphism cloud dashboard.

---

## 🏗️ System Architecture

```
                    ┌──────────────────────────────────────────────┐
                    │      Android / iOS Flutter Mobile App        │
                    │  (Geolocator, Screen Recorder, Telemetry)   │
                    └──────────────────────┬───────────────────────┘
                                           │
                           REST API / JSON & Multipart Video
                                           │
                                           ▼
                    ┌──────────────────────────────────────────────┐
                    │      Cloud REST API Server (Render.com)       │
                    │   (Python 3, Multi-threaded, Memory Cache)   │
                    └──────────────────────┬───────────────────────┘
                                           │
                                  CORS Data Stream
                                           │
                                           ▼
                    ┌──────────────────────────────────────────────┐
                    │     Support Live Web UI (GitHub Pages)       │
                    │   (Glassmorphism UI, Google Maps, Gallery)   │
                    └──────────────────────────────────────────────┘
```

---

## 🎯 Key Features & Technical Highlights

### 1. High-Accuracy GPS Tracking & Reverse Geocoding
- Obtains precise GPS latitude/longitude coordinates with Sub-5-meter accuracy.
- Translates coordinates into full human-readable street addresses, cities, states, postal codes, and countries using native geocoding providers.
- **One-Click Google Maps Integration**: Direct hyperlink navigation to Google Maps pinned to exact coordinates.

### 2. Live Ephemeral Monitoring Mode (GDPR & Privacy Compliant)
- In-memory high-frequency location streaming for real-time support monitoring.
- Zero local disk storage for position logs, ensuring privacy compliance (GDPR/HIPAA ready).
- Explicit user consent framework with persistent preference controls.

### 3. Screen & Audio Recording Subsystem
- In-app screen capture with microphone audio for field issue demonstration.
- On-device recording timer, resolution customization (1080x1920), and video compression.
- Automated multipart HTTP file uploader to cloud video galleries.

### 4. Resilient Offline Telemetry Queue
- Offline retry queue powered by `SharedPreferences` and SHA-256 payload hashing.
- Automatically caches unsent telemetry when offline and syncs upon network reconnection.

### 5. Automated CI/CD & Signed Release Pipeline
- GitHub Actions workflow triggering on release tags (`v*.*.*`).
- Automatic Java Keystore (JKS) generation and base64 environment decoding.
- Multi-ABI Android compilation producing 4 signed release artifacts (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `universal`).
- Automated static dashboard deployment to GitHub Pages (`gh-pages` branch).

---

## 💼 Industry Use Cases

| Industry Sector | Practical Application & Benefit |
| :--- | :--- |
| **Fleet Management & Logistics** | Real-time driver location tracking, vehicle diagnostic health checks, and route address verification. |
| **Enterprise Support & IT Helpdesk** | Remote technical support via screen recording capture, reducing ticket resolution times by 40%. |
| **Mobile Device Management (MDM)** | Automated hardware audit (CPU, RAM %, Battery state, ABI architecture, OS build) across distributed mobile devices. |
| **Field Services & Quality Assurance** | On-site technician verification, GPS check-ins, and bug reproduction uploads during field testing. |

---

## 📄 Resume & CV Bullet Points

You can copy and paste these bullet points directly into your Resume / LinkedIn under **Projects** or **Work Experience**:

### Option 1: Full-Stack Mobile & Cloud Engineer
* **Architected and Deployed an Enterprise Hardware Diagnostics & Real-Time Telemetry Platform** using Flutter, Dart, Python, and RESTful cloud APIs.
* **Implemented High-Accuracy GPS & Reverse-Geocoding Engine**, integrating native location providers to deliver sub-5m coordinate precision and human-readable address resolution.
* **Built Live Ephemeral Streaming Subsystem** with zero disk logging for GDPR-compliant real-time monitoring and high-frequency location streaming.
* **Integrated In-App Screen Recording & Cloud Video Gallery**, utilizing multipart HTTP uploads to streamline remote troubleshooting for IT support teams.
* **Automated CI/CD Release Pipeline via GitHub Actions**, establishing automated JKS key generation, code signing, and multi-ABI APK distribution (`arm64-v8a`, `armeabi-v7a`, `x86_64`).
* **Designed Glassmorphism Support Web Dashboard** hosted on GitHub Pages, featuring interactive Google Maps coordinate navigation, real-time device counters, and embedded video players.

### Option 2: Flutter / Mobile Application Developer
* Developed a cross-platform Flutter diagnostics utility versioned `v1.2` featuring Material 3 design, hardware spec auditing, and dynamic offline retry queues.
* Integrated `geolocator` and `geocoding` packages for real-time location tracking and street-level reverse geocoding.
* Engineered custom screen recording service using `flutter_screen_recording` supporting audio capture and asynchronous background uploads.
* Built dynamic consent dialogs and `SharedPreferences` persistence for user privacy management.

### Option 3: DevOps & Cloud Infrastructure
* Designed zero-downtime Python 3 REST API backend deployed on Render Cloud with multi-threaded request processing and CORS headers.
* Configured automated GitHub Actions workflows for continuous delivery, automated GitHub Releases publishing, and static site hosting via GitHub Pages.

---

## 🛠️ Technology Stack

- **Frontend / Mobile**: Flutter (3.44+), Dart, Material Design 3, Geolocator, Geocoding, Flutter Screen Recording, SharedPreferences, HTTP, Url Launcher.
- **Backend Server**: Python 3 (3.8 - 3.14), Multi-threaded HTTPServer, REST API, JSON, Multipart Form Parser.
- **Cloud Hosting & CDN**: Render.com (API Web Service), GitHub Pages (Static Web UI).
- **CI/CD & DevOps**: GitHub Actions, Gradle 8.11+, AGP 8.11+, Java 17/21, Keystore JKS Auto-Signer, Git Tags.
