#!/usr/bin/env bash

# Hentikan eksekusi jika terjadi error
set -e

# --- KONFIGURASI ---
VAULT_ADDR="http://jkt-vault1:8200"
# Pastikan variabel VAULT_TOKEN sudah diexport di environment terminal Anda
# export VAULT_TOKEN="hvs.xxx..."

SECRET_ENGINE_PATH="sip-testing-restAPI"
SECRET_PATH="my-app/config"
POLICY_NAME="my-app-policy-${SECRET_ENGINE_PATH}"
APPROLE_MOUNT_PATH="my-app-role-${SECRET_ENGINE_PATH}"
APPROLE_NAME="my-app-role"
APPROLE_DESC="AppRole Authentication Engine"


echo "=== 1. Mengaktifkan KV Secrets Engine v2 via cURL ==="
MOUNT_LIST=$(curl -s --header "X-Vault-Token: ${VAULT_TOKEN}" "${VAULT_ADDR}/v1/sys/mounts")
if echo "$MOUNT_LIST" | jq -e ".[\"${SECRET_ENGINE_PATH}/\"]" > /dev/null 2>&1; then
    echo "Secret engine '${SECRET_ENGINE_PATH}' sudah aktif, melewati langkah ini."
else
    curl -s -X POST --header "X-Vault-Token: ${VAULT_TOKEN}" \
      --header "Content-Type: application/json" \
      --data "{\"type\": \"kv\", \"options\": {\"version\": \"2\"}, \"description\": \"KV v2 secret engine\"}" \
      "${VAULT_ADDR}/v1/sys/mounts/${SECRET_ENGINE_PATH}" > /dev/null
    echo "Secret engine '${SECRET_ENGINE_PATH}' berhasil diaktifkan."
fi

echo "=== 2. Membuat Initial Secret via cURL ==="
curl -s -X POST --header "X-Vault-Token: ${VAULT_TOKEN}" \
  --header "Content-Type: application/json" \
  --data '{"data": {"username": "dbadmin", "password": "supersecretpassword"}}' \
  "${VAULT_ADDR}/v1/${SECRET_ENGINE_PATH}/data/${SECRET_PATH}" > /dev/null
echo "Secret berhasil disimpan di ${SECRET_ENGINE_PATH}/data/${SECRET_PATH}"

echo "=== 3. Membuat Policy via cURL ==="
POLICY_HCL="path \"${SECRET_ENGINE_PATH}/data/${SECRET_PATH}\" {\n  capabilities = [\"read\"]\n}"
PAYLOAD_POLICY=$(jq -n --arg pol "$POLICY_HCL" '{policy: $pol}')

curl -s -X PUT --header "X-Vault-Token: ${VAULT_TOKEN}" \
  --header "Content-Type: application/json" \
  --data "$PAYLOAD_POLICY" \
  "${VAULT_ADDR}/v1/sys/policies/acl/${POLICY_NAME}" > /dev/null
echo "Policy '${POLICY_NAME}' berhasil dibuat."

echo "=== 4. Mengaktifkan Auth Method AppRole via cURL ==="
AUTH_LIST=$(curl -s --header "X-Vault-Token: ${VAULT_TOKEN}" "${VAULT_ADDR}/v1/sys/auth")
if echo "$AUTH_LIST" | jq -e ".[\"${APPROLE_MOUNT_PATH}/\"]" > /dev/null 2>&1; then
    echo "Auth method AppRole ('${APPROLE_MOUNT_PATH}/') sudah aktif. Memperbarui deskripsi..."
    curl -s -X POST --header "X-Vault-Token: ${VAULT_TOKEN}" \
      --header "Content-Type: application/json" \
      --data "{\"description\": \"${APPROLE_DESC}\"}" \
      "${VAULT_ADDR}/v1/sys/auth/${APPROLE_MOUNT_PATH}/tune" > /dev/null
else
    curl -s -X POST --header "X-Vault-Token: ${VAULT_TOKEN}" \
      --header "Content-Type: application/json" \
      --data "{\"type\": \"approle\", \"description\": \"${APPROLE_DESC}\"}" \
      "${VAULT_ADDR}/v1/sys/auth/${APPROLE_MOUNT_PATH}" > /dev/null
    echo "Auth method AppRole ('${APPROLE_MOUNT_PATH}/') berhasil diaktifkan."
fi

echo "=== 5. Membuat Role di Dalam Auth Method AppRole via cURL ==="
PAYLOAD_ROLE=$(jq -n \
  --arg ttl "24h" \
  --arg uses "10" \
  --arg tok_ttl "1h" \
  --arg max_ttl "4h" \
  --arg pols "${POLICY_NAME}" \
  '{secret_id_ttl: $ttl, token_num_uses: ($uses | tonumber), token_ttl: $tok_ttl, token_max_ttl: $max_ttl, policies: [$pols]}')

curl -s -X POST --header "X-Vault-Token: ${VAULT_TOKEN}" \
  --header "Content-Type: application/json" \
  --data "$PAYLOAD_ROLE" \
  "${VAULT_ADDR}/v1/auth/${APPROLE_MOUNT_PATH}/role/${APPROLE_NAME}" > /dev/null
echo "Role '${APPROLE_NAME}' berhasil dibuat di dalam 'auth/${APPROLE_MOUNT_PATH}/role/'."

echo "=== 6. Mengambil Credentials AppRole untuk Aplikasi via cURL ==="
ROLE_ID=$(curl -s --header "X-Vault-Token: ${VAULT_TOKEN}" \
  "${VAULT_ADDR}/v1/auth/${APPROLE_MOUNT_PATH}/role/${APPROLE_NAME}/role-id" | jq -r '.data.role_id')

SECRET_ID=$(curl -s -X POST --header "X-Vault-Token: ${VAULT_TOKEN}" \
  "${VAULT_ADDR}/v1/auth/${APPROLE_MOUNT_PATH}/role/${APPROLE_NAME}/secret-id" | jq -r '.data.secret_id')
