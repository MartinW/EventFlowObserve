# EventFlowObserve - TinyBird Integration

Real-time analytics for captured network traffic from your iOS apps.

## Prerequisites

- TinyBird account ([sign up](https://www.tinybird.co/))
- TinyBird CLI installed (`pip install tinybird-cli`)

## Important: Cloud-Only Workflow

> **Note:** TinyBird documentation may reference local Docker containers and `tb local start`. This is NOT required for cloud deployments. You can deploy directly to TinyBird Cloud without any local container setup.

Always use the `--cloud` flag to interact directly with TinyBird Cloud.

## Setup

### 1. Authenticate with TinyBird

```bash
tb login --host https://api.europe-west2.gcp.tinybird.co
```

Replace the host URL with your TinyBird region:
- `https://api.tinybird.co` - US
- `https://api.eu-central-1.tinybird.co` - EU (AWS)
- `https://api.europe-west2.gcp.tinybird.co` - EU West 2 (GCP)
- `https://api.europe-west3.gcp.tinybird.co` - EU West 3 (GCP)

This will open a browser for authentication. Works in Claude Code sessions too.

### 2. Deploy to TinyBird Cloud

```bash
cd tinybird
tb --cloud deploy
```

This will create:
- `tracking_events` - Data source for storing captured HTTP requests
- `events_by_host` - API endpoint for aggregating events by destination host
- `events_by_method` - API endpoint for aggregating events by HTTP method
- `schema_discovery` - API endpoint for discovering unique hosts and paths
- `hourly_volume` - API endpoint for tracking request volume over time
- `recent_events` - API endpoint for retrieving recent events with filtering
- `ios_sdk_write` - Append-only token for iOS SDK

### 3. Get the Write Token

The `ios_sdk_write` token is created automatically via the `TOKEN` directive in `tracking_events.datasource`.

Copy it to your clipboard:
```bash
tb --cloud token copy ios_sdk_write
```

Or list all tokens:
```bash
tb --cloud token ls
```

## CLI Command Reference

Always use `--cloud` flag to skip local container requirements:

```bash
# Login
tb login --host https://api.europe-west2.gcp.tinybird.co

# Deploy datasources and pipes
tb --cloud deploy

# List tokens
tb --cloud token ls

# Copy token to clipboard
tb --cloud token copy <token_name>

# List workspaces
tb --cloud workspace ls
```

## iOS SDK Configuration

```swift
import EventFlowObserve

let tinyBirdConfig = TinyBirdLoggerConfig(
    datasource: "tracking_events",
    authToken: "p.your_write_only_token",
    region: .euWest2  // or .us, .euCentral, .euWest3
)

let config = EventFlowObserveConfig(
    debugMode: true,
    tinyBirdLogging: tinyBirdConfig
)

EventFlowObserve.shared.start(config: config)
```

## API Endpoints

Once deployed, query your data via the published API endpoints. Replace the host with your region:

### Events by Host
```bash
curl "https://api.europe-west2.gcp.tinybird.co/v0/pipes/events_by_host.json?token=YOUR_READ_TOKEN"
```

### Events by Method
```bash
curl "https://api.europe-west2.gcp.tinybird.co/v0/pipes/events_by_method.json?token=YOUR_READ_TOKEN"
```

### Schema Discovery
```bash
curl "https://api.europe-west2.gcp.tinybird.co/v0/pipes/schema_discovery.json?token=YOUR_READ_TOKEN"
```

### Hourly Volume
```bash
curl "https://api.europe-west2.gcp.tinybird.co/v0/pipes/hourly_volume.json?token=YOUR_READ_TOKEN"
```

### Recent Events (with filtering)
```bash
# All recent events
curl "https://api.europe-west2.gcp.tinybird.co/v0/pipes/recent_events.json?token=YOUR_READ_TOKEN"

# Filter by host
curl "https://api.europe-west2.gcp.tinybird.co/v0/pipes/recent_events.json?token=YOUR_READ_TOKEN&host_filter=%25mixpanel%25"

# Filter by method
curl "https://api.europe-west2.gcp.tinybird.co/v0/pipes/recent_events.json?token=YOUR_READ_TOKEN&method_filter=POST"

# Limit results
curl "https://api.europe-west2.gcp.tinybird.co/v0/pipes/recent_events.json?token=YOUR_READ_TOKEN&limit=50"
```

## Data Schema

The `tracking_events` data source stores:

| Column | Type | Description |
|--------|------|-------------|
| `id` | String | Unique request ID |
| `timestamp` | DateTime64(3) | When the request was captured |
| `url` | String | Full request URL |
| `method` | String | HTTP method (GET, POST, etc.) |
| `host` | String | Destination host |
| `path` | String | URL path |
| `headers` | String | JSON-encoded request headers |
| `body` | Nullable(String) | Request body (if captured) |
| `bundle_id` | String | iOS app bundle ID |
| `app_version` | String | App version |
| `app_build` | String | App build number |
| `device_model` | String | Device model identifier |
| `os_version` | String | iOS version |

## Data Retention

The data source is configured with a 90-day TTL. Adjust this in `tracking_events.datasource`:

```
ENGINE_TTL "toDateTime(timestamp) + toIntervalDay(90)"
```

## Troubleshooting

### "No container runtime" errors

Ignore these errors. Use `--cloud` flag to bypass local container requirements:
```bash
tb --cloud deploy
```

### Events not appearing

1. Check debug logs in your iOS app for `[EventFlowObserve.TinyBird]` messages
2. Verify your auth token has write permissions
3. Ensure the datasource name matches exactly ("tracking_events")

### Region mismatch

If you see 401 errors, verify you're using the correct region in both:
- CLI: `tb login --host <correct_host>`
- iOS SDK: `TinyBirdLoggerConfig(region: .euWest2)`

Available regions:
- `.us` - api.tinybird.co
- `.euCentral` - api.eu-central-1.tinybird.co
- `.euWest2` - api.europe-west2.gcp.tinybird.co
- `.euWest3` - api.europe-west3.gcp.tinybird.co
