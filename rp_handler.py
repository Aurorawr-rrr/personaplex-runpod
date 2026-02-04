"""
PersonaPlex RunPod Serverless Handler

This handler starts the PersonaPlex server and keeps it alive for real-time
full-duplex voice conversations. Designed for scheduled session system.

Usage:
- Worker is pre-warmed before scheduled session
- Handler starts PersonaPlex server, returns connection info
- Worker stays alive until explicit cancellation
- Cancel via RunPod API when session ends
"""

import os
import subprocess
import threading
import time
import socket
import runpod

# Configuration
PERSONAPLEX_PORT = int(os.getenv("PERSONAPLEX_PORT", "8998"))
SSL_DIR = os.getenv("SSL_DIR", "/app/ssl")
HF_TOKEN = os.getenv("HF_TOKEN", "")
CPU_OFFLOAD = os.getenv("CPU_OFFLOAD", "false").lower() == "true"

# Global process reference for cleanup
server_process = None


def get_public_ip():
    """Get the public IP exposed by RunPod."""
    return os.getenv("RUNPOD_PUBLIC_IP", os.getenv("RUNPOD_POD_IP", "localhost"))


def get_tcp_port():
    """Get the exposed TCP port from RunPod."""
    # RunPod exposes ports as RUNPOD_TCP_PORT_8998 for port 8998
    port_env = f"RUNPOD_TCP_PORT_{PERSONAPLEX_PORT}"
    return os.getenv(port_env, str(PERSONAPLEX_PORT))


def wait_for_server(host="localhost", port=PERSONAPLEX_PORT, timeout=120):
    """Wait for the PersonaPlex server to be ready."""
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                sock.settimeout(1)
                result = sock.connect_ex((host, port))
                if result == 0:
                    return True
        except socket.error:
            pass
        time.sleep(1)
    return False


def start_personaplex_server():
    """Start the PersonaPlex Moshi server."""
    global server_process

    cmd = [
        "/app/moshi/.venv/bin/python",
        "-m", "moshi.server",
        "--ssl", SSL_DIR,
        "--host", "0.0.0.0",
        "--port", str(PERSONAPLEX_PORT),
    ]

    # Add CPU offload if enabled (for GPUs with insufficient VRAM)
    if CPU_OFFLOAD:
        cmd.append("--cpu-offload")

    env = os.environ.copy()
    if HF_TOKEN:
        env["HF_TOKEN"] = HF_TOKEN

    server_process = subprocess.Popen(
        cmd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )

    return server_process


def handler(job):
    """
    RunPod handler for PersonaPlex.

    This handler:
    1. Starts the PersonaPlex server
    2. Waits for it to be ready
    3. Returns connection info for the client
    4. Keeps running until cancelled

    Job input (optional):
    {
        "session_id": "unique-session-id",
        "voice_prompt": "path/to/voice.pt",  # Optional voice conditioning
        "text_prompt": "You are a speech coach..."  # Optional persona
    }
    """
    global server_process

    job_input = job.get("input", {})
    session_id = job_input.get("session_id", job["id"])

    print(f"[PersonaPlex] Starting server for session: {session_id}")

    # Start the server
    try:
        server_process = start_personaplex_server()
    except Exception as e:
        return {"error": f"Failed to start PersonaPlex server: {str(e)}"}

    # Wait for server to be ready
    print(f"[PersonaPlex] Waiting for server on port {PERSONAPLEX_PORT}...")
    if not wait_for_server(timeout=120):
        if server_process:
            server_process.terminate()
        return {"error": "PersonaPlex server failed to start within timeout"}

    print("[PersonaPlex] Server is ready!")

    # Get connection info
    public_ip = get_public_ip()
    public_port = get_tcp_port()

    connection_info = {
        "status": "running",
        "session_id": session_id,
        "connection": {
            "protocol": "wss",  # WebSocket Secure
            "host": public_ip,
            "port": public_port,
            "url": f"wss://{public_ip}:{public_port}",
        },
        "server_port": PERSONAPLEX_PORT,
        "message": "PersonaPlex server is running. Connect via WebSocket."
    }

    # Send progress update with connection info
    # This allows the client to get connection details before handler completes
    runpod.serverless.progress_update(job, connection_info)

    # Keep the handler alive - server runs until cancelled
    # The client should call the RunPod cancel endpoint when session ends
    print(f"[PersonaPlex] Server running at {connection_info['connection']['url']}")
    print("[PersonaPlex] Waiting for cancellation signal...")

    try:
        # Monitor the server process
        while server_process and server_process.poll() is None:
            time.sleep(5)

            # Optional: Check for heartbeat/health
            if not wait_for_server(timeout=5):
                print("[PersonaPlex] Server health check failed, restarting...")
                server_process.terminate()
                server_process = start_personaplex_server()
                wait_for_server(timeout=60)

        # Server exited unexpectedly
        return_code = server_process.returncode if server_process else -1
        return {
            "status": "stopped",
            "reason": "server_exited",
            "return_code": return_code,
            "session_id": session_id,
        }

    except Exception as e:
        return {
            "status": "error",
            "error": str(e),
            "session_id": session_id,
        }
    finally:
        # Cleanup
        if server_process and server_process.poll() is None:
            print("[PersonaPlex] Shutting down server...")
            server_process.terminate()
            try:
                server_process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                server_process.kill()


def concurrency_modifier(current_concurrency):
    """
    Limit concurrency to 1 since PersonaPlex is 1:1 user-to-GPU.
    Each worker handles one conversation at a time.
    """
    return 1


if __name__ == "__main__":
    print("[PersonaPlex] Starting RunPod Serverless Worker...")
    print(f"[PersonaPlex] Port: {PERSONAPLEX_PORT}")
    print(f"[PersonaPlex] CPU Offload: {CPU_OFFLOAD}")

    runpod.serverless.start({
        "handler": handler,
        "concurrency_modifier": concurrency_modifier,
        "return_aggregate_stream": True,
    })
