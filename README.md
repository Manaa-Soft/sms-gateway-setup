# SMS Gateway Private Server - Setup Guide

Self-hosted SMS Gateway with **no domain, no SSL certificate, no HTTPS required**.
Connect your Android phone as an SMS gateway and integrate with ERPNext/Frappe.

## Table of Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Option A: Docker Setup (Recommended)](#option-a-docker-setup-recommended)
- [Option B: Bare Metal Setup](#option-b-bare-metal-setup)
- [Configure the Android App](#configure-the-android-app)
- [Test the SMS Gateway](#test-the-sms-gateway)
- [ERPNext / Frappe Integration](#erpnext--frappe-integration)
- [Troubleshooting](#troubleshooting)
- [Security Notes](#security-notes)

---

## Architecture

```
┌──────────────┐     HTTP (no HTTPS)     ┌──────────────────┐
│  ERPNext /   │ ──────────────────────> │  SMS Gateway     │
│  Frappe      │   POST /api/3rdparty    │  Private Server  │
│  Webhook     │   /v1/message           │  (Docker/Port    │
└──────────────┘                         │   3000)          │
                                         └────────┬─────────┘
                                                  │
                                         SSE / Poll│
                                                  │
                                         ┌────────▼─────────┐
                                         │  Android Phone   │
                                         │  (SMS Gateway    │
                                         │   App)           │
                                         └──────────────────┘
```

**How it works:**
1. Your private server runs on your own machine (no cloud needed)
2. The Android app connects to your private server via HTTP
3. ERPNext sends webhooks to your private server when events occur
4. The server queues messages and the phone picks them up and sends SMS

---

## Prerequisites

- **Linux server** (Ubuntu 20.04+ / Debian 11+) with Docker installed
  - OR any machine that can run Docker
- **Android phone** with Android 5.0+ and an active SIM card
- **MySQL/MariaDB** database (can run in Docker too)
- **Same local network** (or VPN) between ERPNext server, SMS Gateway server, and phone

---

## Option A: Docker Setup (Recommended)

### Step 1: Clone this repository

```bash
git clone https://github.com/Manaa-Soft/sms-gateway-setup.git
cd sms-gateway-setup
```

### Step 2: Edit the configuration

```bash
cp config.yml.example config.yml
nano config.yml
```

**Minimum changes needed:**

```yaml
gateway:
  private_token: CHANGE_THIS_TO_A_STRONG_SECRET    # e.g. openssl rand -base64 32
```

### Step 3: Start everything with Docker Compose

```bash
# Start MySQL and SMS Gateway server
docker compose up -d

# Check status
docker compose ps

# View logs
docker compose logs -f sms-gateway
```

This starts:
- **MySQL** on port `3306`
- **SMS Gateway Server** on port `3000`

### Step 4: Verify the server is running

```bash
curl http://localhost:3000/health
```

Expected output:
```json
{"status":"pass","version":"1.45.2",...}
```

---

## Option B: Bare Metal Setup

### Step 1: Install dependencies

```bash
# Install Go 1.24+
sudo apt update
sudo apt install -y golang-go git

# Install MySQL/MariaDB
sudo apt install -y mariadb-server mariadb-client
sudo systemctl enable mariadb
sudo systemctl start mariadb

# Secure the installation
sudo mysql_secure_installation
```

### Step 2: Create the database

```bash
sudo mysql -u root -p
```

```sql
CREATE DATABASE sms_gateway_db;
CREATE USER 'sms_user'@'localhost' IDENTIFIED BY 'CHANGE_THIS_PASSWORD';
GRANT ALL PRIVILEGES ON sms_gateway_db.* TO 'sms_user'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

### Step 3: Build the server from source

```bash
git clone https://github.com/android-sms-gateway/server.git
cd server
go build -o sms-gateway ./cmd/sms-gateway
chmod +x sms-gateway
```

### Step 4: Run database migrations

```bash
./sms-gateway db:migrate up
```

### Step 5: Copy and edit configuration

```bash
cp ../sms-gateway-setup/config.yml ./config.yml
nano config.yml
```

### Step 6: Start the server

```bash
./sms-gateway
```

**Optional: Run as a systemd service**

```bash
sudo tee /etc/systemd/system/sms-gateway.service << 'EOF'
[Unit]
Description=SMS Gateway Server
After=network.target mariadb.service

[Service]
Type=simple
User=root
WorkingDirectory=/path/to/server
ExecStart=/path/to/server/sms-gateway
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable sms-gateway
sudo systemctl start sms-gateway
```

### Step 7 (Optional): Start the background worker

```bash
# Docker
docker compose up -d sms-gateway-worker

# Bare metal
./sms-gateway worker
```

---

## Configure the Android App

### Step 1: Download and install the INSECURE APK

Download `app-insecure.apk` from:
https://github.com/capcom6/android-sms-gateway/releases/latest

> **Important:** Use the **insecure** build, NOT the release build.
> The insecure build allows HTTP connections (no SSL certificate required).

### Step 2: Open the app and go to Settings

1. Tap the **Settings** tab
2. Tap **Cloud Server**

### Step 3: Enter your private server details

| Field | Value |
|-------|-------|
| **API URL** | `http://YOUR_SERVER_IP:3000/api/mobile/v1` |
| **Private Token** | Your `private_token` from config.yml |

Example: `http://192.168.1.15:3000/api/mobile/v1`

> **Note:** The URL MUST end with `/api/mobile/v1`. Using just the base URL will not work.

### Step 4: Connect to the server

1. Go back to the **Home** tab
2. Enable the **Cloud Server** toggle
3. Tap the **Offline** button at the bottom to connect
4. Wait for it to change to **Online**

### Step 5: Save your credentials

After successful connection, the app shows your auto-generated credentials:

| Field | Example |
|-------|---------|
| **Username** | `ABC123` |
| **Password** | `xyz789...` |

**Save these!** You'll need them for ERPNext integration.

---

## Test the SMS Gateway

### Test 1: Health check

```bash
curl http://YOUR_SERVER_IP:3000/health
```

### Test 2: Send a test SMS

Replace `USERNAME`, `PASSWORD`, and `PHONE_NUMBER`:

```bash
curl -X POST http://YOUR_SERVER_IP:3000/api/3rdparty/v1/message \
  -u "USERNAME:PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{"phoneNumbers":["+PHONE_NUMBER"],"textMessage":{"text":"Hello from SMS Gateway!"}}'
```

### Test 3: Check server logs

```bash
# Docker
docker compose logs -f sms-gateway

# Bare metal
# Logs are printed to stdout
```

---

## ERPNext / Frappe Integration

See [ERPNEXT-WEBHOOK-SETUP.md](ERPNEXT-WEBHOOK-SETUP.md) for the complete step-by-step guide.

### Quick Summary

1. In ERPNext, go to **Setup > Webhook**
2. Create a new webhook:
   - **DocType:** Sales Invoice (or any doctype)
   - **Event:** on_submit
   - **Request URL:** `http://SMS_SERVER_IP:3000/api/3rdparty/v1/message`
   - **Request Method:** POST
3. Add headers:
   - `Authorization: Basic BASE64_ENCODED_CREDENTIALS`
   - `Content-Type: application/json`
4. Set the request body:

```json
{
  "phoneNumbers": ["{{ doc.mobile_no or doc.contact_mobile }}"],
  "textMessage": {
    "text": "Hello {{ doc.customer_name }}, your Sales Invoice {{ doc.name }} for {{ doc.grand_total }} has been generated."
  }
}
```

5. Generate the Base64 credentials:

```bash
echo -n "USERNAME:PASSWORD" | base64
```

---

## Troubleshooting

### Phone shows "Offline" / Connection refused

1. Make sure the SMS Gateway server is running: `docker compose ps`
2. Check the phone and server are on the same network
3. Open port 3000: `sudo ufw allow 3000`
4. Test from phone's browser: `http://SERVER_IP:3000/health`

### "401 Unauthorized" from ERPNext

- Your Base64 credentials are wrong. Regenerate:

```bash
echo -n "USERNAME:PASSWORD" | base64
```

- Verify what the current value decodes to:

```bash
echo "YOUR_CURRENT_BASE64" | base64 -d
```

### Messages stuck in "Pending"

- Make sure the phone shows **Online** in the app
- Check the phone has an active internet connection to the server
- Check logs: `docker compose logs -f sms-gateway`

### "Handshake failed" on the app

- This is the SSE push notification connection failing
- **It is not critical** — the app still receives commands when active
- The server tries to reach `api.sms-gate.app` for push notifications, which may be blocked on your network

### ERPNext webhook shows "Failed" in Webhook Request Log

- Check the URL is correct: `http://SERVER_IP:3000/api/3rdparty/v1/message`
- Check credentials are correct (Base64 decoded)
- Check the server is reachable from the ERPNext server
- Check `docker compose logs sms-gateway` for errors

---

## Security Notes

### This setup is for PRIVATE/INTERNAL use only

- **No HTTPS** — data is sent in plain HTTP
- Only use on a **trusted local network** or **VPN**
- Never expose port 3000 to the public internet without HTTPS

### Strengthen your configuration

1. **Change the private token** to a strong secret:

```bash
openssl rand -base64 32
```

2. **Change the MySQL password** to a strong password

3. **Firewall:** Only allow port 3000 from your local network:

```bash
# Allow from local network only
sudo ufw allow from 192.168.1.0/24 to any port 3000
```

4. **If you need public access**, put nginx with SSL in front:

```bash
# Install nginx and certbot
sudo apt install nginx certbot python3-certbot-nginx

# Configure nginx (see nginx.conf in this repo)
# Get SSL certificate
sudo certbot --nginx -d your-domain.com
```

---

## File Structure

```
sms-gateway-setup/
├── README.md                    # This file
├── config.yml                   # Server configuration (edit this!)
├── docker-compose.yml           # Docker deployment
├── nginx.conf                   # Optional reverse proxy
├── ERPNEXT-WEBHOOK-SETUP.md    # ERPNext integration guide
└── test-sms.sh                  # Quick test script
```

---

## Credits

- [SMS Gateway for Android](https://github.com/capcom6/android-sms-gateway) by capcom6
- [SMS Gateway Server](https://github.com/android-sms-gateway/server)
- Licensed under Apache 2.0
