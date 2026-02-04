# PersonaPlex RunPod Deployment

This package deploys NVIDIA PersonaPlex-7B as a RunPod Serverless endpoint with support for persistent WebSocket connections for real-time full-duplex voice conversations.

## Prerequisites

1. **Docker** installed locally
2. **Docker Hub** account (or other container registry)
3. **RunPod** account with billing configured
4. **Hugging Face** account with PersonaPlex license accepted

## Setup Instructions

### Step 1: Accept PersonaPlex License

1. Go to [PersonaPlex on Hugging Face](https://huggingface.co/nvidia/personaplex-7b-v1)
2. Log in and accept the license agreement
3. Create an access token at [HuggingFace Settings](https://huggingface.co/settings/tokens)

### Step 2: Build the Docker Image

```bash
cd personaplex-runpod

# Build the image
docker build -t yourusername/personaplex-runpod:latest .

# Or with model pre-downloaded (larger image, faster cold start):
docker build --build-arg HF_TOKEN=your_token -t yourusername/personaplex-runpod:latest .
```

### Step 3: Push to Docker Hub

```bash
# Login to Docker Hub
docker login

# Push the image
docker push yourusername/personaplex-runpod:latest
```

### Step 4: Create RunPod Serverless Endpoint

1. Go to [RunPod Serverless](https://www.runpod.io/console/serverless)
2. Click "New Endpoint"
3. Select "Custom Container"
4. Configure:

| Setting | Value |
|---------|-------|
| Container Image | `yourusername/personaplex-runpod:latest` |
| GPU | A100 80GB (recommended) or A100 40GB |
| Min Workers | 0 (scales to zero) |
| Max Workers | Based on expected concurrent users |
| Idle Timeout | 300 seconds (5 min) for session gaps |
| Execution Timeout | **Disabled** or 86400 (24 hours) |
| Expose TCP Ports | `8998` |
| Expose Public IP | **Enabled** |

5. Add Environment Variables:

| Variable | Value |
|----------|-------|
| `HF_TOKEN` | Your Hugging Face token |
| `PERSONAPLEX_PORT` | `8998` |
| `CPU_OFFLOAD` | `false` (set `true` for lower VRAM GPUs) |

### Step 5: Configure Your Application

In your Speech Coaching AI application, update the voice service to connect to RunPod:

```typescript
// src/lib/personaplex-client.ts
const RUNPOD_ENDPOINT = "https://api.runpod.ai/v2/YOUR_ENDPOINT_ID";
const RUNPOD_API_KEY = process.env.RUNPOD_API_KEY;

async function startVoiceSession(sessionId: string) {
  // Start the worker
  const response = await fetch(`${RUNPOD_ENDPOINT}/run`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${RUNPOD_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      input: {
        session_id: sessionId,
      },
    }),
  });

  const { id: jobId } = await response.json();

  // Poll for connection info
  let connectionInfo = null;
  while (!connectionInfo) {
    const statusResponse = await fetch(`${RUNPOD_ENDPOINT}/status/${jobId}`, {
      headers: { "Authorization": `Bearer ${RUNPOD_API_KEY}` },
    });
    const status = await statusResponse.json();

    if (status.output?.connection) {
      connectionInfo = status.output.connection;
    } else {
      await new Promise(r => setTimeout(r, 1000));
    }
  }

  return { jobId, connectionInfo };
}

async function endVoiceSession(jobId: string) {
  // Cancel the worker to stop billing
  await fetch(`${RUNPOD_ENDPOINT}/cancel/${jobId}`, {
    method: "POST",
    headers: { "Authorization": `Bearer ${RUNPOD_API_KEY}` },
  });
}
```

## Scheduled Session Integration

For your scheduled session system:

```typescript
// Pre-warm worker 2-3 minutes before scheduled session
async function preWarmWorker(scheduledTime: Date) {
  const preWarmTime = new Date(scheduledTime.getTime() - 3 * 60 * 1000);

  // Schedule pre-warm
  scheduleJob(preWarmTime, async () => {
    const { jobId, connectionInfo } = await startVoiceSession(sessionId);
    // Store jobId for later cancellation
    await saveSessionJobId(sessionId, jobId);
  });
}

// End session and stop billing
async function endSession(sessionId: string) {
  const jobId = await getSessionJobId(sessionId);
  await endVoiceSession(jobId);
}
```

## Cost Optimization

- **Min Workers: 0** - No cost when idle
- **Pre-warm before sessions** - Reduces perceived latency
- **Cancel after sessions** - Stop billing immediately
- **No scheduling 12 AM - 7 AM EST** - Zero workers overnight

## GPU Options

| GPU | VRAM | Latency | Cost/hr | Recommended For |
|-----|------|---------|---------|-----------------|
| A100 80GB | 80GB | <200ms | ~$2.17 | Production |
| A100 40GB | 40GB | <200ms | ~$1.64 | Development |
| L4 24GB | 24GB | ~200ms | ~$0.55 | Testing |
| RTX 4090 | 24GB | ~200ms | ~$0.69 | Light production |

## Troubleshooting

### Server won't start
- Check HF_TOKEN is set correctly
- Verify license was accepted on Hugging Face
- Check GPU has sufficient VRAM (try CPU_OFFLOAD=true)

### High latency
- Ensure using A100 or better GPU
- Check network latency to RunPod region
- Consider pre-warming workers earlier

### Connection drops
- Verify Expose Public IP is enabled
- Check TCP port 8998 is exposed
- Verify execution timeout is disabled

## Files

- `rp_handler.py` - RunPod serverless handler
- `Dockerfile` - Container build instructions
- `README.md` - This file

## References

- [PersonaPlex on Hugging Face](https://huggingface.co/nvidia/personaplex-7b-v1)
- [PersonaPlex GitHub](https://github.com/NVIDIA/personaplex)
- [RunPod Serverless Docs](https://docs.runpod.io/serverless/overview)
- [RunPod Endpoint Configurations](https://docs.runpod.io/serverless/endpoints/endpoint-configurations)
