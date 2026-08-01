# DemoApp Setup Guide

## Quick Start

1. **Navigate to the DemoApp directory**:
   ```bash
   cd DemoApp
   ```

2. **Open the workspace** (not the .xcodeproj):
   ```bash
   open DemoApp.xcworkspace
   ```

3. **Build and Run**:
   - Select a simulator or device
   - Press Cmd+R to build and run

## What You'll See

The app displays:
- A title: "NetworkInspector Demo"
- Two buttons:
  - **Make Sync Request** (blue) - Fetches a post from JSONPlaceholder API
  - **Make Async Request** (green) - Fetches a user from JSONPlaceholder API
- A **floating purple button** (📊) in the bottom-right corner

## How to Use

1. **Make a Request**:
   - Tap either "Make Sync Request" or "Make Async Request"
   - Watch the response appear below the buttons
   - The request is automatically tracked by NetworkInspector

2. **View Recorded Requests**:
   - Tap the floating button (📊)
   - Browse all recorded network requests
   - View details: headers, body, response, timing, etc.
   - Export requests in multiple formats

## Key Features Demonstrated

### Sync Request (`mode: .sync`)
- Simple HTTP GET request
- Chain auto-closes when request completes
- Best for single-stage requests

### Async Request (`mode: .async`)
- HTTP GET with terminal condition check
- Demonstrates multi-stage flow support
- Chain stays open until terminal condition is met
- Shows how to handle fallbacks and retries

### NetworkInspector UI
- Lists all recorded requests
- Shows request/response details
- Displays timing information
- Supports multiple export formats

## Code Structure

```
DemoApp/
├── DemoApp/
│   ├── AppDelegate.swift          # Enables NetworkInspector
│   ├── MainViewController.swift   # Main UI with buttons
│   ├── APIClient.swift            # Network layer with NetworkInspector
│   └── Info.plist
├── Podfile                        # CocoaPods dependencies
└── README.md
```

## NetworkInspector Integration Points

1. **AppDelegate**: 
   ```swift
   NetworkInspector.shared.enable(...)
   ```

2. **APIClient**:
   ```swift
   let session = NetworkInspector.shared.makeSession(...)
   ```

3. **Making Requests**:
   ```swift
   session.dataTask(with: request, inspection: .init(...))
   ```

4. **Viewing Inspector**:
   ```swift
   NetworkInspector.shared.viewController()
   ```

## Troubleshooting

### Pod Install Issues
If you encounter pod install errors:
```bash
pod repo update
pod install
```

### Build Errors
1. Make sure you're opening `DemoApp.xcworkspace`, not `DemoApp.xcodeproj`
2. Clean build folder: Cmd+Shift+K
3. Rebuild: Cmd+B

### Network Errors
The app uses public JSONPlaceholder API. If requests fail:
- Check internet connection
- Verify the API endpoints are accessible
- Check Info.plist has NSAppTransportSecurity settings

## Next Steps

Try customizing the app:
- Add more request types (POST, PUT, DELETE)
- Implement fallback scenarios
- Add external completion sources
- Test timeout handling
- Experiment with chain correlation IDs

## Support

For NetworkInspector documentation, see:
- Main README: `../README.md`
- Source code: `../NetworkInspector/`
