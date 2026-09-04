#!/bin/bash

# Hentikan eksekusi jika terjadi error
set -e

# --- KONFIGURASI NAMA ---
SECRET_ENGINE_PATH="omni-agen-syariah"
SECRET_PATH="my-app/config"
POLICY_NAME="my-app-policy-omni-agen-syariah"
APPROLE_MOUNT_PATH="my-app-role-omni-agen-syariah"
APPROLE_NAME="my-app-role"
APPROLE_DESC="AppRole Authentication Engine"

echo "=== 1. Mengaktifkan KV Secrets Engine v2 ==="
if vault secrets list -format=json | jq -e ".[\"${SECRET_ENGINE_PATH}/\"]" > /dev/null 2>&1; then
    echo "Secret engine '${SECRET_ENGINE_PATH}' sudah aktif, melewati langkah ini."
else
    vault secrets enable -path="${SECRET_ENGINE_PATH}" kv-v2
    echo "Secret engine '${SECRET_ENGINE_PATH}' berhasil diaktifkan."
fi

echo "=== 2. Membuat Initial Secret ==="
vault kv put "${SECRET_ENGINE_PATH}/${SECRET_PATH}" username="dbadmin" password="supersecretpassword"
echo "Secret berhasil disimpan di ${SECRET_ENGINE_PATH}/${SECRET_PATH}"

echo "=== 3. Membuat Policy ==="
vault policy write "${POLICY_NAME}" - <<EOF
# Akses read pada secret kv v2
path "${SECRET_ENGINE_PATH}/data/${SECRET_PATH}" {
  capabilities = ["read"]
}
EOF
echo "Policy '${POLICY_NAME}' berhasil dibuat."

echo "=== 4. Membuat Auth Method AppRole (Muncul di 'vault auth list') ==="
if vault auth list -format=json | jq -e ".[\"${APPROLE_MOUNT_PATH}/\"]" > /dev/null 2>&1; then
    echo "Auth method AppRole ('${APPROLE_MOUNT_PATH}/') sudah aktif. Memperbarui deskripsi..."
    vault auth tune -description="${APPROLE_DESC}" "${APPROLE_MOUNT_PATH}/"
else
    vault auth enable -path="${APPROLE_MOUNT_PATH}" -description="${APPROLE_DESC}" approle
    echo "Auth method AppRole ('${APPROLE_MOUNT_PATH}/') berhasil diaktifkan."
fi

echo "=== 5. Membuat Role di Dalam Auth Method AppRole ==="
vault write "auth/${APPROLE_MOUNT_PATH}/role/${APPROLE_NAME}" \
    secret_id_ttl=24h \
    token_num_uses=10 \
    token_ttl=1h \
    token_max_ttl=4h \
    policies="${POLICY_NAME}"
echo "Role '${APPROLE_NAME}' berhasil dibuat di dalam 'auth/${APPROLE_MOUNT_PATH}/role/'."

echo "=== 6. Mengambil Credentials AppRole untuk Aplikasi ==="
ROLE_ID=$(vault read -field=role_id "auth/${APPROLE_MOUNT_PATH}/role/${APPROLE_NAME}/role-id")
SECRET_ID=$(vault write -f -field=secret_id "auth/${APPROLE_MOUNT_PATH}/role/${APPROLE_NAME}/secret-id")

echo ""
echo "=================================================="
echo "          SETUP AUTOMATION SELESAI                "
echo "=================================================="
echo "Auth Method Path : auth/${APPROLE_MOUNT_PATH}/"
echo "Role Name        : ${APPROLE_NAME}"
echo "Role ID          : ${ROLE_ID}"
echo "Secret ID        : ${SECRET_ID}"
echo "=================================================="
