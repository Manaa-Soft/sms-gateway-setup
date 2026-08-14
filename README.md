# SMS Gateway Private Server - Setup Guide

Self-hosted SMS Gateway with **no domain and no public SSL certificate**.
Connect your Android phone as an SMS gateway and integrate with ERPNext/Frappe.

> **Note:** sending SMS works over plain HTTP, but webhook **delivery to Frappe**
> (delivery receipts / inbound SMS) still needs an `https://` webhook URL — the
> gateway server hard-rejects `http://` URLs. See
> [Incoming SMS / Webhooks](#incoming-sms--webhooks-https-requirement) below.

## Table of Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Option A: Docker Setup (Recommended)](#option-a-docker-setup-recommended)
- [Option B: Bare Metal Setup](#option-b-bare-metal-setup)
- [Configure the Android App](#configure-the-android-app)
- [Test the SMS Gateway](#test-the-sms-gateway)
- [Incoming SMS / Webhooks (HTTPS requirement)](#incoming-sms--webhooks-https-requirement)
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

## Incoming SMS / Webhooks (HTTPS requirement)

Webhook URLs **must start with `https://`** — the gateway server rejects anything
else with `400 Bad Request: url must start with https://`. There is **no
`allow_http` config option** (unknown YAML keys are silently ignored).

This still works fully offline on a private LAN: the phone reports events to the
server over HTTP (it never touches the webhook URL), and only the server POSTs
to your `https://` webhook URL. To make the server trust a private certificate:

1. Create a self-signed CA + server cert (SAN = your LAN IP).
2. Put an nginx `listen 443 ssl` → `proxy_pass http://127.0.0.1:80` (Frappe)
   block in front of your site.
3. Tell the gateway container to trust the CA by adding to **both** the
   `sms-gateway` and `sms-gateway-worker` services in `docker-compose.yml`:

   ```yaml
   environment:
     - SSL_CERT_FILE=/app/sms-ca.crt
   volumes:
     - /etc/nginx/ssl/sms-ca.crt:/app/sms-ca.crt:ro
   ```

   Then `docker compose up -d`.

4. Point SMS Relay at `https://192.168.1.15/api/method/sms_relay.api.webhook_receiver.incoming_webhook`
   (SMS Device → **Webhook Callback URL** or SMS Gateway Settings → **Webhook URL**)
   and re-run **Check Device**.

Full recipe: https://github.com/Manaa-Soft/sms_relay/wiki/Webhook-Delivery

---

## ERPNext / Frappe Integration

### Quick Start (Webhook)

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

See [ERPNEXT-WEBHOOK-SETUP.md](ERPNEXT-WEBHOOK-SETUP.md) for the complete webhook guide.

---

## Enterprise Integration (Recommended for Production)

For a full enterprise solution with **automated balance reminders, payment confirmations,
overdue alerts, and scheduled SMS**, see:

### [ERPNEXT-ENTERPRISE-SMS.md](ERPNEXT-ENTERPRISE-SMS.md)

This includes:

| Feature | Description |
|---------|-------------|
| **Daily Balance Reminders** | Automatic SMS to customers with overdue invoices |
| **Payment Confirmations** | Instant SMS when payment is received |
| **Invoice Notifications** | SMS when invoice is created or submitted |
| **Overdue Alerts** | Escalating reminders at 7/14/30/60/90 days |
| **Payment Request Links** | SMS with payment instructions |

### Quick Setup

1. **Create the SMS Gateway Server Script** in ERPNext (see Enterprise guide Step 2)
2. **Create Webhooks** for Invoice and Payment events (see Enterprise guide Step 3)
3. **Set up Scheduled Job** for daily balance reminders (see Enterprise guide Step 4)
4. **Test** from ERPNext Python Console:
   ```python
   frappe.get_attr("sms_gateway.send_sms")("+1234567890", "Test!")
   frappe.get_attr("sms_gateway.send_balance_reminder")()
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
├── README.md                        # This file
├── config.yml                       # Server configuration (edit this!)
├── docker-compose.yml               # Docker deployment
├── nginx.conf                       # Optional reverse proxy
├── ERPNEXT-WEBHOOK-SETUP.md        # Basic webhook integration guide
├── ERPNEXT-ENTERPRISE-SMS.md       # Enterprise solution (balances, reminders, payments)
├── test-sms.sh                      # Quick test script
├── .env.example                     # Docker environment template
└── .gitignore
```

---

## Credits

- [SMS Gateway for Android](https://github.com/capcom6/android-sms-gateway) by capcom6
- [SMS Gateway Server](https://github.com/android-sms-gateway/server)
- Licensed under Apache 2.0
