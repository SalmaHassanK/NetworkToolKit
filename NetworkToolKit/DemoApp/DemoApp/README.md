# NetworkToolKit Demo App

A demo iOS application showcasing the NetworkToolKit pod functionality.

## Features

- **Sync Request Button**: Makes a synchronous HTTP request to demonstrate basic network inspection
- **Async Request Button (with Fallback)**: Demonstrates multi-stage async flow:
  - Primary request to non-existent endpoint (returns 404)
  - Automatically triggers fallback request
  - Both attempts share the same correlation ID (grouped in one chain)
  - **AttemptKind is automatically inferred**: first = `.primary`, subsequent = `.fallback(N)`
  - Shows how NetworkInspector tracks multi-attempt flows
  - **Uses reliable JSONPlaceholder endpoints** - works every time!
- **Floating Inspector Button** (📊): Opens the NetworkInspector UI to view all recorded requests

## Setup

1. Install dependencies:
   ```bash
   cd DemoApp
   pod install
   ```

2. Open the workspace:
   ```bash
   open DemoApp.xcworkspace
   ```

3. Build and run the app

## Usage

1. Launch the app
2. Tap "Make Sync Request" or "Make Async Request" to trigger network calls
3. Tap the floating purple button (📊) in the bottom-right corner to open the NetworkInspector
4. View detailed request/response information, headers, timing, and more

## Architecture

- **AppDelegate**: Initializes NetworkInspector on app launch
- **MainViewController**: Main UI with request buttons and floating inspector button
- **APIClient**: Network layer that uses NetworkInspector to track requests

## NetworkToolKit Integration

The app demonstrates:
- Enabling NetworkInspector at startup
- Creating URLSessions through NetworkInspector
- **Sync request mode** (auto-closes chain after single request)
- **Async request mode** (with terminal condition check and fallback)
  - **Simplified API**: No need to manually specify `.primary` or `.fallback`!
  - First request with a correlationId → automatically marked as `.primary`
  - Subsequent requests with same correlationId → automatically marked as `.fallback(N)`
  - Same `correlationId` groups them into one chain
  - Chain stays open until a 2xx response or timeout
- Accessing the inspector UI

All network requests are automatically tracked and can be inspected in the NetworkInspector UI. **Tap the async button and then check the inspector (📊) to see how the primary and fallback requests are grouped into a single chain with auto-inferred kinds!**
