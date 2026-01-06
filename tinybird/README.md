# EventFlowObserve - TinyBird Integration

Real-time analytics for captured network traffic from your iOS apps.

## Prerequisites

- TinyBird account ([sign up](https://www.tinybird.co/))
- TinyBird CLI installed (`pip install tinybird-cli`)

## Setup

### 1. Authenticate with TinyBird

```bash
cd tinybird
tb auth
```

Follow the prompts to authenticate with your TinyBird workspace.

### 2. Push the Data Source and Pipes

```bash
tb push
```

This will create:
- `tracking_events` - Data source for storing captured HTTP requests
- `events_by_host` - API endpoint for aggregating events by destination host
- `events_by_method` - API endpoint for aggregating events by HTTP method
- `schema_discovery` - API endpoint for discovering unique hosts and paths
- `hourly_volume` - API endpoint for tracking request volume over time
- `recent_events` - API endpoint for retrieving recent events with filtering

### 3. Create a Write-Only Token

In the TinyBird UI:
1. Go to **Tokens** in the left sidebar
2. Click **Create Token**
3. Name it (e.g., "ios-sdk-write")
4. Select **Append** scope for `tracking_events` data source only
5. Copy the token for use in your iOS app

## iOS SDK Configuration

```swift
import EventFlowObserve

let tinyBirdConfig = TinyBirdLoggerConfig(
    datasource: "tracking_events",
    authToken: "p.your_write_only_token",
    region: .eu  // or .us depending on your TinyBird region
)

let config = EventFlowObserveConfig(
    debugMode: true,
    tinyBirdLogging: tinyBirdConfig
)

EventFlowObserve.shared.start(config: config)
```

## API Endpoints

Once deployed, you can query your data via the published API endpoints:

### Events by Host
```bash
curl "https://api.eu-central-1.tinybird.co/v0/pipes/events_by_host.json?token=YOUR_READ_TOKEN"
```

### Events by Method
```bash
curl "https://api.eu-central-1.tinybird.co/v0/pipes/events_by_method.json?token=YOUR_READ_TOKEN"
```

### Schema Discovery
```bash
curl "https://api.eu-central-1.tinybird.co/v0/pipes/schema_discovery.json?token=YOUR_READ_TOKEN"
```

### Hourly Volume
```bash
curl "https://api.eu-central-1.tinybird.co/v0/pipes/hourly_volume.json?token=YOUR_READ_TOKEN"
```

### Recent Events (with filtering)
```bash
# All recent events
curl "https://api.eu-central-1.tinybird.co/v0/pipes/recent_events.json?token=YOUR_READ_TOKEN"

# Filter by host
curl "https://api.eu-central-1.tinybird.co/v0/pipes/recent_events.json?token=YOUR_READ_TOKEN&host_filter=%25mixpanel%25"

# Filter by method
curl "https://api.eu-central-1.tinybird.co/v0/pipes/recent_events.json?token=YOUR_READ_TOKEN&method_filter=POST"

# Limit results
curl "https://api.eu-central-1.tinybird.co/v0/pipes/recent_events.json?token=YOUR_READ_TOKEN&limit=50"
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
ENGINE_TTL "timestamp + toIntervalDay(90)"
```

## Troubleshooting

### Events not appearing

1. Check debug logs in your iOS app for TinyBird-related messages
2. Verify your auth token has write permissions
3. Ensure the datasource name matches exactly ("tracking_events")

### Region mismatch

If you see 401 errors, verify you're using the correct region:
- US: `TinyBirdRegion.us` (api.tinybird.co)
- EU: `TinyBirdRegion.eu` (api.eu-central-1.tinybird.co)
