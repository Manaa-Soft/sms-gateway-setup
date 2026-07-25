# ERPNext / Frappe - SMS Gateway Webhook Integration

Step-by-step guide to send SMS notifications from ERPNext using the SMS Gateway private server.

---

## Prerequisites

- ERPNext/Frappe instance running on the same network as the SMS Gateway server
- SMS Gateway server running and accessible (see README.md)
- Android phone connected and showing **Online** in the SMS Gateway app
- Your SMS Gateway credentials (username and password from the app)

---

## Step 1: Generate Base64 Credentials

Your SMS Gateway app provides a username and password. You need to encode them as Base64 for the webhook Authorization header.

### On your ERPNext/Linux server:

```bash
echo -n "YOUR_USERNAME:YOUR_PASSWORD" | base64
```

**Example:**
```bash
echo -n "G9G_SA:swlnlea5h-bho2" | base64
```

**Output:** `RzlHX1NBOnN3bG5sZWE1aC1iaG8y`

> **Important:** Make sure there are no spaces after `-n` and the username:password is in quotes.
> To verify your encoding is correct:
> ```bash
> echo "RzlHX1NBOnN3bG5sZWE1aC1iaG8y" | base64 -d
> # Should output: G9G_SA:swlnlea5h-bho2
> ```

---

## Step 2: Test the Connection

Before creating the webhook, test manually that ERPNext can reach the SMS Gateway:

```bash
curl -X POST http://SMS_SERVER_IP:3000/api/3rdparty/v1/message \
  -u "YOUR_USERNAME:YOUR_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{"phoneNumbers":["+PHONE_NUMBER"],"textMessage":{"text":"Test from ERPNext server!"}}'
```

Replace:
- `SMS_SERVER_IP` — IP of your SMS Gateway server (e.g., `192.168.1.15`)
- `YOUR_USERNAME` — from the SMS Gateway app
- `YOUR_PASSWORD` — from the SMS Gateway app
- `PHONE_NUMBER` — a valid phone number with country code

**Expected response:** HTTP 202 with a JSON body containing `"state": "Pending"`

---

## Step 3: Create the Webhook in ERPNext

### 3.1 Open Webhook List

In ERPNext, go to:
```
Setup > Advanced > Webhook
```

Or navigate to: `http://YOUR_ERPNEXT_SITE/setup/workflow/workflow`

### 3.2 Create New Webhook

Click **"Add Webhook"** and fill in:

| Field | Value | Notes |
|-------|-------|-------|
| **Name** | `SMS Gateway - Sales Invoice` | Any descriptive name |
| **DocType** | `Sales Invoice` | Or any doctype you want |
| **Webhook Do Event** | `on_submit` | When the invoice is submitted |
| **Enabled** | `Yes` | Must be checked |
| **Request URL** | `http://SMS_SERVER_IP:3000/api/3rdparty/v1/message` | See note below |
| **Request Method** | `POST` | |
| **Request Structure** | `JSON` | |
| **Enable Security** | `No` | Not needed for internal HTTP |
| **Timeout** | `5` | Seconds |
| **Max Retries** | `3` | |
| **Background Jobs Queue** | `long` | For async processing |

> **Request URL:** Replace `SMS_SERVER_IP` with your server's actual IP address.
> The path **must** be `/api/3rdparty/v1/message` (NOT just `/message`).

---

## Step 4: Add Webhook Headers

Scroll down to the **"Webhook Headers"** table and add two rows:

### Header 1: Authorization

| Field | Value |
|-------|-------|
| **Key** | `Authorization` |
| **Value** | `Basic YOUR_BASE64_CREDENTIALS` |

**Example:**
```
Authorization: Basic RzlHX1NBOnN3bG5sZWE1aC1iaG8y
```

> **CRITICAL:** The value MUST start with `Basic ` (with a capital B and a space),
> followed by the Base64 string from Step 1.

### Header 2: Content-Type

| Field | Value |
|-------|-------|
| **Key** | `Content-Type` |
| **Value** | `application/json` |

---

## Step 5: Set the Request Body

In the **"Webhook JSON"** field, paste this:

```json
{
  "phoneNumbers": ["{{ doc.mobile_no or doc.contact_mobile }}"],
  "textMessage": {
    "text": "Hello {{ doc.customer_name }}, your Sales Invoice {{ doc.name }} for {{ doc.grand_total }} has been generated."
  }
}
```

### Customization Examples

**Payment reminder:**
```json
{
  "phoneNumbers": ["{{ doc.mobile_no or doc.contact_mobile }}"],
  "textMessage": {
    "text": "Reminder: {{ doc.customer_name }}, your invoice {{ doc.name }} for {{ doc.grand_total }} is due on {{ doc.due_date }}."
  }
}
```

**Payment received:**
```json
{
  "phoneNumbers": ["{{ doc.mobile_no or doc.contact_mobile }}"],
  "textMessage": {
    "text": "Thank you {{ doc.customer_name }}! Payment of {{ doc.grand_total }} received for invoice {{ doc.name }}."
  }
}
```

**Delivery notification (Sales Order):**
```json
{
  "phoneNumbers": ["{{ doc.contact_mobile }}"],
  "textMessage": {
    "text": "Dear {{ doc.customer_name }}, your order {{ doc.name }} has been dispatched and will be delivered soon."
  }
}
```

---

## Step 6: Save and Test

1. Click **Save** on the webhook
2. Create or submit a Sales Invoice in ERPNext
3. Check the webhook log:

```
Setup > Advanced > Webhook Request Log
```

4. Check the SMS Gateway logs:

```bash
# Docker
docker compose logs -f sms-gateway

# Look for lines like:
# "POST /api/3rdparty/v1/message" → 202 (success)
# or errors like "401 Unauthorized" (wrong credentials)
```

---

## Step 7: Add Webhooks for Other Events (Optional)

You can create multiple webhooks for different events:

### On Payment Entry (payment received):
- **DocType:** `Payment Entry`
- **Event:** `on_submit`
- **Body:**
```json
{
  "phoneNumbers": ["{{ doc.party_phone or doc.contact_phone }}"],
  "textMessage": {
    "text": "Payment of {{ doc.paid_amount }} received from {{ doc.party_name }} for {{ doc.remarks }}."
  }
}
```

### On Sales Order (order confirmation):
- **DocType:** `Sales Order`
- **Event:** `on_submit`
- **Body:**
```json
{
  "phoneNumbers": ["{{ doc.contact_mobile }}"],
  "textMessage": {
    "text": "Order {{ doc.name }} confirmed! Total: {{ doc.grand_total }}. Thank you {{ doc.customer_name }}!"
  }
}
```

---

## Common Errors and Fixes

### 401 Unauthorized

**Cause:** Wrong username/password or wrong Base64 encoding.

**Fix:**
1. Get your current credentials from the SMS Gateway app
2. Re-encode:
```bash
echo -n "USERNAME:PASSWORD" | base64
```
3. Verify:
```bash
echo "YOUR_BASE64" | base64 -d
```
4. Update the webhook Authorization header

### Connection Refused / Timeout

**Cause:** The SMS Gateway server is not reachable from the ERPNext server.

**Fix:**
1. Check the server is running: `docker compose ps`
2. Check from ERPNext server: `curl http://SMS_SERVER_IP:3000/health`
3. Check firewall: `sudo ufw allow 3000`

### Message stays "Pending" forever

**Cause:** The Android app is offline or not connected to the server.

**Fix:**
1. Open the SMS Gateway app on the phone
2. Make sure it shows **Online** (not Offline)
3. Make sure the phone has network access to the server

### "textMessage" field error

**Cause:** Wrong JSON structure in the webhook body.

**Fix:** The API requires this structure:
```json
{
  "phoneNumbers": ["+number"],
  "textMessage": {
    "text": "Your message here"
  }
}
```
NOT:
```json
{
  "phoneNumbers": ["+number"],
  "message": "Your message here"    // WRONG!
}
```

---

## Security Considerations

1. **Network:** Only use on trusted local networks or VPN
2. **Credentials:** Store Base64 credentials securely in ERPNext
3. **Firewall:** Restrict port 3000 to only ERPNext server IP
4. **For production:** Consider using HTTPS with a reverse proxy (see nginx.conf in this repo)
