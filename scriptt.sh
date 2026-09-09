#!/bin/bash
set -e

# Jenkins otomatis menyediakan nilai String Parameter di atas sebagai Environment Variable
# Menggunakan nilai dari Jenkins Parameter, atau fallback jika kosong
POLICY_NAME="policy-${SECRET_ENGINE_PATH}"
APPROLE_MOUNT_PATH="approle-${SECRET_ENGINE_PATH}" # Disarankan tetap 'approle' agar tidak memenuhi Raft storage
APPROLE_NAME="approle-${SECRET_ENGINE_PATH}"
APPROLE_DESC="AppRole Authentication Engine"

echo "=== Processing Vault Setup for: ${SECRET_ENGINE_PATH} ==="

# 1. Check & Enable Secret Engine
if vault secrets list -format=json | jq -e ".[\"${SECRET_ENGINE_PATH}/\"]" > /dev/null 2>&1; then
    echo "Secret engine '${SECRET_ENGINE_PATH}' sudah ada."
else
    vault secrets enable -path="${SECRET_ENGINE_PATH}" kv-v2
fi

# 2. Put Secret
vault kv put "${SECRET_ENGINE_PATH}/${SECRET_PATH}" username="dbadmin" password="supersecretpassword"

# 3. Create Policy
vault policy write "${POLICY_NAME}" - <<EOF
path "${SECRET_ENGINE_PATH}/data/${SECRET_PATH}" {
  capabilities = ["read"]
}
EOF

# 4. Check & Enable Auth Method AppRole
if vault auth list -format=json | jq -e ".[\"${APPROLE_MOUNT_PATH}/\"]" > /dev/null 2>&1; then
    echo "Auth method '${APPROLE_MOUNT_PATH}' sudah aktif."
else
    vault auth enable -path="${APPROLE_MOUNT_PATH}" -description="${APPROLE_DESC}" approle
fi

# 5. Create Role
vault write "auth/${APPROLE_MOUNT_PATH}/role/${APPROLE_NAME}" \
    secret_id_ttl=24h \
    token_ttl=1h \
    policies="${POLICY_NAME}"

# 6. Fetch Credentials
ROLE_ID=$(vault read -field=role_id "auth/${APPROLE_MOUNT_PATH}/role/${APPROLE_NAME}/role-id")
SECRET_ID=$(vault write -f -field=secret_id "auth/${APPROLE_MOUNT_PATH}/role/${APPROLE_NAME}/secret-id")

echo "=========================================="
echo "SUCCESS!"
echo "Role Name : ${APPROLE_NAME}"
echo "Role ID   : ${ROLE_ID}"
echo "Secret ID : ${SECRET_ID}"
echo "=========================================="
