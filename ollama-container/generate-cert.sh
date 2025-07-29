#!/bin/sh

# Certificate generation script for Nginx
set -e

SSL_DIR="/etc/nginx/ssl"
CERT_FILE="$SSL_DIR/server.crt"
KEY_FILE="$SSL_DIR/server.key"
DOMAIN="${CERT_DOMAIN:-localhost}"

# Create SSL directory if it doesn't exist
mkdir -p "$SSL_DIR"

# Check if certificates already exist and are valid
if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
    echo "SSL certificates already exist. Checking validity..."
    
    # Check if certificate is still valid (not expired)
    if openssl x509 -checkend 86400 -noout -in "$CERT_FILE" 2>/dev/null; then
        echo "Existing SSL certificates are valid. Skipping generation."
        exit 0
    else
        echo "Existing SSL certificates are expired. Regenerating..."
    fi
fi

echo "Generating self-signed SSL certificate for domain: $DOMAIN"

# Generate private key
openssl genrsa -out "$KEY_FILE" 2048

# Generate certificate signing request
openssl req -new -key "$KEY_FILE" -out "$SSL_DIR/server.csr" -subj "/C=US/ST=State/L=City/O=Organization/OU=OrgUnit/CN=$DOMAIN"

# Generate self-signed certificate (valid for 1 year)
openssl x509 -req -days 365 -in "$SSL_DIR/server.csr" -signkey "$KEY_FILE" -out "$CERT_FILE" \
    -extensions v3_req -extfile <(cat <<EOF
[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $DOMAIN
DNS.2 = localhost
DNS.3 = *.localhost
IP.1 = 127.0.0.1
IP.2 = ::1
EOF
)

# Clean up CSR file
rm -f "$SSL_DIR/server.csr"

# Set proper permissions
chmod 600 "$KEY_FILE"
chmod 644 "$CERT_FILE"

echo "SSL certificate generated successfully!"
echo "Certificate: $CERT_FILE"
echo "Private Key: $KEY_FILE"
echo "Valid for domain: $DOMAIN"

# Display certificate info
openssl x509 -in "$CERT_FILE" -text -noout | grep -E "(Subject:|Issuer:|Not Before:|Not After:|DNS:|IP Address:)" || true
