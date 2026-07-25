#!/bin/bash
# =============================================================
# SMS Gateway - Quick Test Script
# =============================================================
# Usage: ./test-sms.sh SERVER_IP USERNAME PASSWORD PHONE_NUMBER
#
# Example:
#   ./test-sms.sh 192.168.1.15 G9G_SA swlnlea5h-bho2 +967777715787
# =============================================================

# --- Configuration ---
SERVER_IP="${1:-192.168.1.15}"
USERNAME="${2:-}"
PASSWORD="${3:-}"
PHONE_NUMBER="${4:-}"
PORT=3000
BASE_URL="http://${SERVER_IP}:${PORT}"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "============================================"
echo "  SMS Gateway Test Script"
echo "============================================"
echo ""

# --- Check arguments ---
if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    echo -e "${RED}Usage:${NC} ./test-sms.sh <SERVER_IP> <USERNAME> <PASSWORD> <PHONE_NUMBER>"
    echo ""
    echo "Example:"
    echo "  ./test-sms.sh 192.168.1.15 G9G_SA swlnlea5h-bho2 +967777715787"
    exit 1
fi

# --- Test 1: Health Check ---
echo -e "${YELLOW}[1/3] Testing health endpoint...${NC}"
HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/health" --connect-timeout 5)
if [ "$HEALTH" = "200" ]; then
    echo -e "${GREEN}  ✓ Server is healthy (HTTP 200)${NC}"
else
    echo -e "${RED}  ✗ Health check failed (HTTP ${HEALTH})${NC}"
    echo "  Make sure the server is running at ${BASE_URL}"
    exit 1
fi
echo ""

# --- Test 2: Generate and verify Base64 credentials ---
echo -e "${YELLOW}[2/3] Verifying credentials...${NC}"
BASE64_CREDS=$(echo -n "${USERNAME}:${PASSWORD}" | base64)
DECODED=$(echo "${BASE64_CREDS}" | base64 -d 2>/dev/null)
if [ "$DECODED" = "${USERNAME}:${PASSWORD}" ]; then
    echo -e "${GREEN}  ✓ Base64 encoding correct: ${BASE64_CREDS}${NC}"
    echo "    Decodes to: ${DECODED}"
else
    echo -e "${RED}  ✗ Base64 encoding mismatch!${NC}"
    exit 1
fi
echo ""

# --- Test 3: Send Test SMS ---
echo -e "${YELLOW}[3/3] Sending test SMS...${NC}"
if [ -z "$PHONE_NUMBER" ]; then
    echo -e "${YELLOW}  ⚠ No phone number provided, skipping SMS send${NC}"
    echo "  Usage: ./test-sms.sh ${SERVER_IP} ${USERNAME} ${PASSWORD} +1234567890"
    exit 0
fi

RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "${BASE_URL}/api/3rdparty/v1/message" \
    -u "${USERNAME}:${PASSWORD}" \
    -H "Content-Type: application/json" \
    -d "{\"phoneNumbers\":[\"${PHONE_NUMBER}\"],\"textMessage\":{\"text\":\"Test from SMS Gateway - $(date)\"}}" \
    --connect-timeout 10)

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "202" ]; then
    echo -e "${GREEN}  ✓ SMS queued successfully (HTTP 202)${NC}"
    echo "  Response: ${BODY}" | head -c 200
    echo ""
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  All tests passed!${NC}"
    echo -e "${GREEN}============================================${NC}"
else
    echo -e "${RED}  ✗ SMS send failed (HTTP ${HTTP_CODE})${NC}"
    echo "  Response: ${BODY}"
    echo ""
    echo "Common fixes:"
    echo "  - Check username/password are correct"
    echo "  - Check server is running"
    echo "  - Check phone is Online in the app"
    exit 1
fi
