# ERPNext Enterprise SMS Integration

Complete enterprise solution for customer SMS notifications using SMS Gateway.

## Features

- **Balance Reminders**: Daily scheduled SMS to customers with outstanding balances
- **Payment Confirmations**: Instant SMS when payment is received
- **Invoice Notifications**: SMS when invoice is created/submitted
- **Overdue Alerts**: SMS for overdue invoices with days overdue
- **Payment Request Links**: SMS with payment instructions

---

## Architecture

```
ERPNext (Frappe)                    SMS Gateway Server          Android Phone
┌─────────────────┐                ┌──────────────────┐        ┌──────────────┐
│ Sales Invoice    │──webhook────> │                  │        │              │
│ Payment Entry    │──webhook────> │  POST /message   │──poll─>│  Send SMS    │
│ Scheduled Job    │──script────>  │  (queue)         │        │  via SIM     │
│ (daily 9 AM)    │               │                  │        │              │
└─────────────────┘                └──────────────────┘        └──────────────┘
```

---

## Step 1: Configure SMS Gateway Settings in ERPNext

### 1.1 Create a Custom Field on SMS Settings

Go to: **Setup > Custom Field > SMS Settings**

Add a field to store the SMS Gateway server URL:

| Field | Type | Value |
|-------|------|-------|
| **Label** | Data | `SMS Gateway Server URL` |
| **Fieldname** | Data | `sms_gateway_url` |
| **Default** | Data | `http://192.168.1.15:3000` |
| **Description** | Small Text | `Base URL of the SMS Gateway private server` |

### 1.2 Store Credentials Securely

Go to **Setup > Custom Field > SMS Settings** and add:

| Field | Type | Value |
|-------|------|-------|
| **Label** | Data | `SMS Gateway Username` |
| **Fieldname** | Data | `sms_gateway_username` |
| **Default** | Data | `G9G_SA` |

| Field | Type | Value |
|-------|------|-------|
| **Label** | Password | `SMS Gateway Password` |
| **Fieldname** | Data | `sms_gateway_password` |
| **Default** | Data | `swlnlea5h-bho2` |

> **Security Note:** For production, use Frappe's site_config.json or environment variables
> instead of storing passwords in the database.

---

## Step 2: Create the SMS Sending Server Script

Go to: **Setup > Server Script > New**

### Script 1: Send SMS API Function

| Field | Value |
|-------|-------|
| **Name** | `SMS Gateway API` |
| **Script Type** | `API` |
| **API Name** | `sms_gateway` |

**Script:**

```python
"""
SMS Gateway API - Enterprise SMS Sender for ERPNext
Handles all SMS sending through the private SMS Gateway server.
"""

import requests
import json
import frappe

# SMS Gateway Configuration
# Option 1: Read from SMS Settings custom fields (recommended)
# Option 2: Hardcode here (simpler but less flexible)

SMS_GATEWAY_URL = "http://192.168.1.15:3000"
SMS_USERNAME = "G9G_SA"
SMS_PASSWORD = "swlnlea5h-bho2"


def _get_config():
    """Get SMS Gateway configuration from SMS Settings or defaults."""
    try:
        settings = frappe.get_single("SMS Settings")
        url = getattr(settings, "sms_gateway_url", None) or SMS_GATEWAY_URL
        username = getattr(settings, "sms_gateway_username", None) or SMS_USERNAME
        password = getattr(settings, "sms_gateway_password", None) or SMS_PASSWORD
        return url, username, password
    except Exception:
        return SMS_GATEWAY_URL, SMS_USERNAME, SMS_PASSWORD


def _send_to_gateway(phone_number, message_text):
    """
    Send a single SMS via the SMS Gateway server.
    Returns dict with status and details.
    """
    url, username, password = _get_config()

    try:
        response = requests.post(
            f"{url}/api/3rdparty/v1/message",
            auth=(username, password),
            headers={"Content-Type": "application/json"},
            json={
                "phoneNumbers": [phone_number],
                "textMessage": {"text": message_text}
            },
            timeout=15
        )

        if response.status_code == 202:
            result = response.json()
            return {
                "success": True,
                "message_id": result.get("id"),
                "state": result.get("state"),
                "phone": phone_number
            }
        else:
            return {
                "success": False,
                "error": f"HTTP {response.status_code}: {response.text}",
                "phone": phone_number
            }

    except requests.exceptions.ConnectionError:
        return {"success": False, "error": "Cannot connect to SMS Gateway server", "phone": phone_number}
    except requests.exceptions.Timeout:
        return {"success": False, "error": "SMS Gateway server timeout", "phone": phone_number}
    except Exception as e:
        return {"success": False, "error": str(e), "phone": phone_number}


# ============================================================
# PUBLIC API FUNCTIONS (called by notifications, hooks, etc.)
# ============================================================

@frappe.whitelist()
def send_sms(number, message):
    """
    Send a single SMS.
    Usage from client script or bench console:
        frappe.get_attr("sms_gateway.send_sms")("+967777715787", "Hello!")
    """
    if not number or not message:
        return {"success": False, "error": "Phone number and message are required"}

    # Clean phone number - ensure it starts with +
    number = str(number).strip()
    if not number.startswith("+"):
        # Try to add country code from customer defaults
        number = "+" + number

    return _send_to_gateway(number, message)


@frappe.whitelist()
def send_bulk_sms(recipients, message):
    """
    Send SMS to multiple recipients.
    recipients: list of phone number strings
    message: message text
    """
    results = []
    for recipient in recipients:
        result = _send_to_gateway(recipient, message)
        results.append(result)
    return results


@frappe.whitelist()
def send_invoice_notification(docname, event="created"):
    """
    Send SMS notification for Sales Invoice events.
    Called by webhook or server script.
    """
    try:
        invoice = frappe.get_doc("Sales Invoice", docname)
    except frappe.DoesNotExistError:
        return {"success": False, "error": "Invoice not found"}

    # Get customer phone number
    phone = _get_customer_phone(invoice.customer)
    if not phone:
        return {"success": False, "error": "No phone number for customer"}

    # Build message based on event
    if event == "created":
        message = (
            f"Dear {invoice.customer_name},\n"
            f"Sales Invoice {invoice.name} has been created.\n"
            f"Amount: {frappe.format_value(invoice.grand_total, {'fieldtype': 'Currency', 'options': invoice.currency})}\n"
            f"Due Date: {frappe.utils.formatdate(invoice.due_date, 'dd-MMM-yyyy')}\n"
            f"Thank you!"
        )
    elif event == "overdue":
        days_overdue = (frappe.utils.today() - str(invoice.due_date)).days if invoice.due_date else 0
        message = (
            f"Dear {invoice.customer_name},\n"
            f"Payment Reminder: Invoice {invoice.name} is {days_overdue} days overdue.\n"
            f"Amount Due: {frappe.format_value(invoice.outstanding_amount, {'fieldtype': 'Currency', 'options': invoice.currency})}\n"
            f"Please arrange payment at your earliest convenience.\n"
            f"Thank you!"
        )
    elif event == "payment_received":
        message = (
            f"Dear {invoice.customer_name},\n"
            f"Payment received for Invoice {invoice.name}.\n"
            f"Amount: {frappe.format_value(invoice.paid_amount, {'fieldtype': 'Currency', 'options': invoice.currency})}\n"
            f"Outstanding: {frappe.format_value(invoice.outstanding_amount, {'fieldtype': 'Currency', 'options': invoice.currency})}\n"
            f"Thank you for your payment!"
        )
    else:
        return {"success": False, "error": f"Unknown event: {event}"}

    return _send_to_gateway(phone, message)


@frappe.whitelist()
def send_balance_reminder():
    """
    Send balance reminders to all customers with overdue invoices.
    Designed to be called by a Scheduled Job (daily).
    """
    results = []

    # Find all Sales Invoices that are overdue and have outstanding balance
    overdue_invoices = frappe.db.sql("""
        SELECT
            si.name,
            si.customer,
            si.customer_name,
            si.outstanding_amount,
            si.due_date,
            si.currency,
            DATEDIFF(CURDATE(), si.due_date) as days_overdue
        FROM `tabSales Invoice` si
        WHERE si.status = 'Overdue'
        AND si.outstanding_amount > 0
        AND si.docstatus = 1
        AND si.due_date < CURDATE()
    """, as_dict=True)

    if not overdue_invoices:
        frappe.log_error("SMS Balance Reminder: No overdue invoices found", "SMS Gateway")
        return {"success": True, "message": "No overdue invoices", "count": 0}

    # Group by customer to avoid sending multiple SMS for same customer
    customer_invoices = {}
    for inv in overdue_invoices:
        customer_id = inv.customer
        if customer_id not in customer_invoices:
            customer_invoices[customer_id] = {
                "customer_name": inv.customer_name,
                "invoices": [],
                "total_due": 0,
                "oldest_overdue_days": 0
            }
        customer_invoices[customer_id]["invoices"].append(inv)
        customer_invoices[customer_id]["total_due"] += inv.outstanding_amount
        customer_invoices[customer_id]["oldest_overdue_days"] = max(
            customer_invoices[customer_id]["oldest_overdue_days"],
            inv.days_overdue
        )

    # Send SMS to each customer
    for customer_id, data in customer_invoices.items():
        phone = _get_customer_phone(customer_id)
        if not phone:
            frappe.log_error(
                f"SMS Reminder: No phone for customer {customer_id}",
                "SMS Gateway"
            )
            continue

        invoice_list = "\n".join([
            f"  - {inv.name}: {frappe.format_value(inv.outstanding_amount, {'fieldtype': 'Currency', 'options': inv.currency})}"
            for inv in data["invoices"][:5]  # Limit to 5 invoices in message
        ])

        if len(data["invoices"]) > 5:
            invoice_list += f"\n  ... and {len(data['invoices']) - 5} more"

        total_formatted = frappe.format_value(
            data["total_due"],
            {"fieldtype": "Currency", "options": data["invoices"][0].currency}
        )

        message = (
            f"Dear {data['customer_name']},\n"
            f"Payment Reminder ({data['oldest_overdue_days']} days overdue):\n"
            f"Outstanding Invoices:\n{invoice_list}\n"
            f"Total Due: {total_formatted}\n"
            f"Please arrange payment. Thank you!"
        )

        result = _send_to_gateway(phone, message)
        result["customer"] = customer_id
        results.append(result)

        # Log each SMS sent
        if result["success"]:
            frappe.get_doc({
                "doctype": "Comment",
                "comment_type": "Info",
                "reference_doctype": "Customer",
                "reference_name": customer_id,
                "content": f"SMS Balance Reminder sent: {result.get('message_id', 'N/A')}"
            }).insert(ignore_permissions=True)

    successful = sum(1 for r in results if r.get("success"))
    return {
        "success": True,
        "total_customers": len(customer_invoices),
        "sms_sent": successful,
        "sms_failed": len(results) - successful,
        "results": results
    }


# ============================================================
# HELPER FUNCTIONS
# ============================================================

def _get_customer_phone(customer_name):
    """Get phone number from Customer doc or its linked Contact."""
    try:
        customer = frappe.get_doc("Customer", customer_name)

        # Check customer's mobile_no field
        if customer.mobile_no:
            return _clean_phone(customer.mobile_no)

        # Check customer's phone field
        if customer.phone:
            return _clean_phone(customer.phone)

        # Check linked contacts
        contacts = frappe.get_all(
            "Dynamic Link",
            filters={"link_doctype": "Customer", "link_name": customer_name, "parenttype": "Contact"},
            fields=["parent"]
        )

        for contact_link in contacts:
            contact = frappe.get_doc("Contact", contact_link.parent)
            for phone in contact.phone_nos:
                if phone.is_primary_mobile:
                    return _clean_phone(phone.phone)
            # Fallback to any phone number
            for phone in contact.phone_nos:
                return _clean_phone(phone.phone)

    except Exception:
        pass

    return None


def _clean_phone(phone):
    """Clean and format phone number."""
    if not phone:
        return None
    phone = str(phone).strip().replace(" ", "").replace("-", "").replace("(", "").replace(")", "")
    if not phone.startswith("+"):
        phone = "+" + phone
    return phone
```

---

## Step 3: Create Webhooks for Real-Time Events

### 3.1 Sales Invoice - On Submit

Go to: **Setup > Webhook > New**

| Field | Value |
|-------|-------|
| **Name** | `SMS - Invoice Created` |
| **DocType** | `Sales Invoice` |
| **Webhook Do Event** | `on_submit` |
| **Enabled** | Yes |
| **Request URL** | `http://192.168.1.15:8000/api/method/sms_gateway.send_invoice_notification` |
| **Request Method** | `POST` |
| **Request Structure** | `Form URL Encoded` |
| **Enable Security** | No |

**Webhook Data:**

| Key | Value |
|-----|-------|
| `docname` | `{{ doc.name }}` |
| `event` | `created` |

### 3.2 Payment Entry - On Submit

| Field | Value |
|-------|-------|
| **Name** | `SMS - Payment Received` |
| **DocType** | `Payment Entry` |
| **Webhook Do Event** | `on_submit` |
| **Enabled** | Yes |
| **Request URL** | `http://192.168.1.15:8000/api/method/sms_gateway.send_payment_notification` |
| **Request Method** | `POST` |
| **Request Structure** | `Form URL Encoded` |
| **Enable Security** | No |

**Webhook Data:**

| Key | Value |
|-----|-------|
| `docname` | `{{ doc.name }}` |

### 3.3 Add Payment Notification to Server Script

Add this function to the Server Script from Step 2:

```python
@frappe.whitelist()
def send_payment_notification(docname):
    """Send SMS when payment is received."""
    try:
        payment = frappe.get_doc("Payment Entry", docname)
    except frappe.DoesNotExistError:
        return {"success": False, "error": "Payment not found"}

    # Get party phone
    phone = _get_customer_phone(payment.party_name)
    if not phone:
        return {"success": False, "error": "No phone number for customer"}

    # Build payment confirmation message
    if payment.party_type == "Customer":
        message = (
            f"Dear {payment.party_name},\n"
            f"Payment of {frappe.format_value(payment.paid_amount, {'fieldtype': 'Currency', 'options': payment.currency})} "
            f"received successfully.\n"
            f"Reference: {payment.name}\n"
            f"Date: {frappe.utils.formatdate(payment.posting_date, 'dd-MMM-yyyy')}\n"
            f"Thank you for your payment!"
        )
    else:
        return {"success": False, "error": "Not a customer payment"}

    result = _send_to_gateway(phone, message)

    # Also update linked Sales Invoice
    if payment.references:
        for ref in payment.references:
            if ref.reference_doctype == "Sales Invoice":
                try:
                    invoice = frappe.get_doc("Sales Invoice", ref.reference_name)
                    if invoice.outstanding_amount <= 0:
                        # Fully paid - send thank you
                        thank_msg = (
                            f"Dear {invoice.customer_name},\n"
                            f"Invoice {invoice.name} has been fully paid!\n"
                            f"Thank you for your business."
                        )
                        _send_to_gateway(phone, thank_msg)
                except Exception:
                    pass

    return result
```

---

## Step 4: Scheduled Job for Daily Balance Reminders

### 4.1 Create the Scheduled Job

Go to: **Setup > Scheduled Job Type > New**

| Field | Value |
|-------|-------|
| **Name** | `Send SMS Balance Reminders` |
| **Method** | `sms_gateway.send_balance_reminder` |
| **Frequency** | `Daily` |
| **Time** | `09:00:00` (9 AM) |
| **Enabled** | Yes |

### 4.2 Alternative: Using hooks.py

If you have a custom Frappe app, add to `hooks.py`:

```python
scheduler_events = {
    "daily": [
        "sms_gateway.send_balance_reminder"
    ],
    # Optional: Also send at specific times
    "cron": {
        "0 9 * * *": [  # 9 AM daily
            "sms_gateway.send_balance_reminder"
        ],
        "0 14 * * *": [  # 2 PM daily (second reminder)
            "sms_gateway.send_balance_reminder"
        ]
    }
}
```

---

## Step 5: Notification Configuration

### 5.1 Invoice Created Notification

Go to: **Setup > Notification > New**

| Field | Value |
|-------|-------|
| **Name** | `SMS - Invoice Created` |
| **Enabled** | Yes |
| **Document Type** | `Sales Invoice` |
| **Event** | `Value Change` or `Method` |
| **Channel** | `SMS` |
| **Recipients** | Based on Value (add row: `mobile_no`) |
| **Message** | Custom message (see below) |

### 5.2 Custom Notification via Server Script

For more control, use a Server Script triggered on document events:

Go to: **Setup > Server Script > New**

| Field | Value |
|-------|-------|
| **Name** | `Sales Invoice SMS Notification` |
| **Script Type** | `Document Event` |
| **Document Type** | `Sales Invoice` |
| **Event** | `After Insert` |

**Script:**

```python
"""
Auto-send SMS when Sales Invoice is created.
"""
if doc.mobile_no or doc.contact_mobile:
    phone = doc.mobile_no or doc.contact_mobile

    frappe.get_attr("sms_gateway.send_sms")(
        phone,
        f"Dear {doc.customer_name},\n"
        f"Invoice {doc.name} for {frappe.format_value(doc.grand_total, {'fieldtype': 'Currency', 'options': doc.currency})} "
        f"has been created.\n"
        f"Due Date: {frappe.utils.formatdate(doc.due_date, 'dd-MMM-yyyy')}\n"
        f"Thank you!"
    )
```

---

## Step 6: Payment Request Integration

### 6.1 Auto-SMS on Payment Request

Go to: **Setup > Server Script > New**

| Field | Value |
|-------|-------|
| **Name** | `Payment Request SMS` |
| **Script Type** | `Document Event` |
| **Document Type** | `Payment Request` |
| **Event** | `After Insert` |

**Script:**

```python
"""
Send SMS with payment request details when a Payment Request is created.
"""
if doc.mobile_no:
    grand_total = frappe.format_value(doc.grand_total, {'fieldtype': 'Currency', 'options': doc.currency})

    message = (
        f"Dear {doc.customer_name},\n"
        f"Payment Request: {doc.name}\n"
        f"Amount: {grand_total}\n"
        f"Due Date: {frappe.utils.formatdate(doc.due_date, 'dd-MMM-yyyy')}\n"
        f"Please make payment at your earliest convenience.\n"
        f"Thank you!"
    )

    frappe.get_attr("sms_gateway.send_sms")(doc.mobile_no, message)
```

---

## Step 7: Overdue Invoice Reminders (Cron Job)

### 7.1 Create Overdue Reminder Script

Go to: **Setup > Server Script > New**

| Field | Value |
|-------|-------|
| **Name** | `Overdue Invoice SMS Reminder` |
| **Script Type** | `API` |
| **API Name** | `overdue_reminder` |

**Script:**

```python
"""
Send reminders for overdue invoices.
Can be triggered by:
- Scheduled Job (daily)
- Manual trigger from bench
- ERPNext Scheduler
"""

import frappe

@frappe.whitelist()
def check_and_send_overdue_reminders():
    """Check for overdue invoices and send SMS reminders."""

    # Get overdue invoices with outstanding balance
    overdue = frappe.db.sql("""
        SELECT
            si.name,
            si.customer,
            si.customer_name,
            si.outstanding_amount,
            si.due_date,
            si.currency,
            DATEDIFF(CURDATE(), si.due_date) as days_overdue
        FROM `tabSales Invoice` si
        WHERE si.status = 'Overdue'
        AND si.outstanding_amount > 0
        AND si.docstatus = 1
        AND si.due_date < CURDATE()
        AND DATEDIFF(CURDATE(), si.due_date) IN (7, 14, 30, 60, 90)
        ORDER BY si.due_date ASC
    """, as_dict=True)

    if not overdue:
        return {"status": "no_overdue", "count": 0}

    sent_count = 0
    for inv in overdue:
        phone = frappe.get_attr("sms_gateway._get_customer_phone")(inv.customer)
        if not phone:
            continue

        message = (
            f"Dear {inv.customer_name},\n"
            f"OVERDUE NOTICE ({inv.days_overdue} days):\n"
            f"Invoice: {inv.name}\n"
            f"Amount Due: {frappe.format_value(inv.outstanding_amount, {'fieldtype': 'Currency', 'options': inv.currency})}\n"
            f"Original Due Date: {frappe.utils.formatdate(inv.due_date, 'dd-MMM-yyyy')}\n"
            f"Please pay immediately to avoid service interruption.\n"
            f"Thank you!"
        )

        result = frappe.get_attr("sms_gateway.send_sms")(phone, message)
        if result.get("success"):
            sent_count += 1

    return {"status": "completed", "overdue_count": len(overdue), "sms_sent": sent_count}
```

---

## Quick Reference: All SMS Triggers

| Trigger | When | Message Type |
|---------|------|-------------|
| Sales Invoice - After Insert | Invoice created | Invoice details + amount |
| Sales Invoice - On Submit | Invoice submitted | Payment instructions |
| Sales Invoice - Overdue (daily cron) | 7/14/30/60/90 days overdue | Payment reminder |
| Payment Entry - On Submit | Payment received | Payment confirmation |
| Payment Request - After Insert | Payment request created | Payment link |
| Delivery Note - After Insert | Delivery completed | Delivery confirmation |

---

## Testing

### Test SMS from ERPNext Console

Go to: **Setup > Developer > Python Console**

```python
# Test 1: Simple SMS
frappe.get_attr("sms_gateway.send_sms")("+967777715787", "Test from ERPNext!")

# Test 2: Invoice notification
frappe.get_attr("sms_gateway.send_invoice_notification")("ACC-SINV-2026-00198", "created")

# Test 3: Balance reminder (runs for ALL overdue invoices)
frappe.get_attr("sms_gateway.send_balance_reminder")()
```

### Test from Command Line

```bash
# On the ERPNext server
bench --site your-site.local execute sms_gateway.send_balance_reminder
```

---

## Monitoring

### Check SMS Gateway Logs

```bash
# Docker
docker logs -f sms-gateway

# Look for:
# "POST /api/3rdparty/v1/message" → 202 (success)
# "POST /api/method/sms_gateway.*" → 200 (ERPNext API call)
```

### Check ERPNext Webhook Logs

Go to: **Setup > Webhook Request Log**

### Check ERPNext Error Logs

Go to: **Setup > Error Log**

Filter by: `SMS Gateway` to see SMS-related errors.
