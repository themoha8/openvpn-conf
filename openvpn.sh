#!/bin/bash

CLIENT_EASYRSA_PATH="${HOME}/.easy-rsa"
SERVER_EASYRSA_PATH="${HOME}/.easy-rsa-ca"
CLIENT_CONFIGS_PATH="${HOME}/.client-configs"
CCD_PATH="/etc/openvpn/ccd"
IPS_FILE="${HOME}/.client-configs/ips.txt"
CRL_PATH="/etc/openvpn/keys"
INDEX_TXT_PATH=${SERVER_EASYRSA_PATH}/pki/index.txt
USER_OPENVPN="nobody"

# Does not require confirmation
export EASYRSA_BATCH="yes"
set -e

welcome() {
  echo "1. Create a certificate for an openVPN user"
  echo "2. Show all openVPN users"
  echo "3. Revoke a client certificate"
  echo "4. Show clients that revoked"
  echo "5. Renew a client certificate"
  echo "6. Show expire date a client certificate"
  echo "7. Exit"
}

type_username() {
  while true; do
    read -p "Enter a username without spaces: " USERNAME
    if [[ "$USERNAME" =~ ^[a-zA-Z_]{3,}[0-9]*$ ]]; then
      break
    fi
    echo "Incorrect the username (use ASCII letters, _ sign and digit 0-9 at the end)"
  done
}

type_choice_pass() {
  while true; do
    echo "1. Without password"
    echo "2. With password"
    read -p "Enter the action number: " CHOICE
    if [[ "$CHOICE" =~ ^[12]$ ]]; then
       break
    fi
    echo "Incorrect the action number (type 1 or 2)"
  done
}

type_choice() {
  while true; do
    read -p "Enter the action number: " CHOICE
    if [[ "$CHOICE" =~ ^[1234567]$ ]]; then
       break
    fi
    echo "Incorrect the action number"
  done
}

create_cert() {
  type_username

  export EASYRSA_REQ_CN="$USERNAME"

  type_choice_pass

  echo ""
  echo ""
  echo "------------------------------------------------------------------------------------------"

  # Generate Certificate Request (CSR)
  cd "$CLIENT_EASYRSA_PATH"

  if [ "$CHOICE" == '2' ]; then
    ./easyrsa gen-req "$USERNAME" pass
  else
    ./easyrsa gen-req "$USERNAME" nopass
  fi

  # Copy the private key in directory client configs and copy CRS on the CA
  cp "pki/private/${USERNAME}.key" "${CLIENT_CONFIGS_PATH}/keys/"

  # Import and sign the client cert
  cd "$SERVER_EASYRSA_PATH"
  CA_P="$(gpg --quiet --decrypt "${CLIENT_CONFIGS_PATH}/easyrsa_p.txt.gpg")"
  ./easyrsa import-req "${CLIENT_EASYRSA_PATH}/pki/reqs/${USERNAME}.req" "$USERNAME"
  ./easyrsa --passin=pass:$CA_P sign-req client "$USERNAME"

  # Copy the client cert to directory client configs
  cp "pki/issued/${USERNAME}.crt" "${CLIENT_CONFIGS_PATH}/keys/"

  # Create the openVPN cert
  "${CLIENT_CONFIGS_PATH}/make_config.sh" "$USERNAME"

  # Search free ip address
  FREE_IP="$(grep -m1 -v "\-\-" $IPS_FILE)"
  FREE_IP_SED="$(echo -n "$FREE_IP" | sed "s/\./\\\./g")"

  # Mark $FREE_IP as busy now
  sed -i "s/${FREE_IP_SED}\$/& \-\- ${USERNAME}/" "$IPS_FILE"

  # Create fixed ip address for new client
  echo "ifconfig-push $FREE_IP 255.255.255.0" > "${CCD_PATH}/$USERNAME"
  #chmod 640 "${CCD_PATH}/$USERNAME"
  #chown :$USER_OPENVPN "${CCD_PATH}/$USERNAME"

  echo "CERTIFICATE CREATED"
  echo "------------------------------------------------------------------------------------------"
  echo ""
  echo ""
}

show_openvpn_users() {
  echo ""
  echo ""
  echo "----------------------------"
  grep "\-\-" "$IPS_FILE"
  echo "----------------------------"
  echo ""
  echo ""
}

revoke_cert() {
  type_username

  echo ""
  echo ""
  echo "------------------------------------------------------------------------------------------"

  # Revoke a client and generate crl.pem
  cd "$SERVER_EASYRSA_PATH"
  CA_P="$(gpg --quiet --decrypt "${CLIENT_CONFIGS_PATH}/easyrsa_p.txt.gpg")"
  ./easyrsa --passin=pass:$CA_P revoke "$USERNAME"
  ./easyrsa --passin=pass:$CA_P gen-crl

  # Mark ip as free
  sed -i "/${USERNAME}/s/ --.*//" "$IPS_FILE"

  rm -f "${CCD_PATH}/${USERNAME}"

  cp "${SERVER_EASYRSA_PATH}/pki/crl.pem" "${CRL_PATH}"
  chown :$USER_OPENVPN "${CRL_PATH}/crl.pem"
  chmod 660 "${CRL_PATH}/crl.pem"

  echo "CLIENT IS REVOKED"
  echo "------------------------------------------------------------------------------------------"
  echo ""
  echo ""
}

show_revoke_users() {
  echo ""
  echo ""
  echo "----------------------------"
  grep "^R" "$INDEX_TXT_PATH"
  echo "----------------------------"
  echo ""
  echo ""
}

renew_client_cert() {
  type_username

  export EASYRSA_REQ_CN="$USERNAME"

  type_choice_pass

  echo ""
  echo ""
  echo "------------------------------------------------------------------------------------------"

  cd "${SERVER_EASYRSA_PATH}"

  CA_P="$(gpg --quiet --decrypt "${CLIENT_CONFIGS_PATH}/easyrsa_p.txt.gpg")"

  if [ "$CHOICE" == '2' ]; then
    ./easyrsa --passin=pass:$CA_P renew "$USERNAME" pass
  else
    ./easyrsa --passin=pass:$CA_P renew "$USERNAME" nopass
  fi

  # Copy the client cert to directory client configs
  cp "pki/issued/${USERNAME}.crt" "${CLIENT_CONFIGS_PATH}/keys/"
  # Copy the private key in directory client configs and copy CRS on the CA
  cp "pki/private/${USERNAME}.key" "${CLIENT_CONFIGS_PATH}/keys/"

  # Create the openVPN cert
  "${CLIENT_CONFIGS_PATH}/make_config.sh" "$USERNAME"

  echo "CERTIFICATE IS RENEWED"
  echo "------------------------------------------------------------------------------------------"
  echo ""
  echo ""
}

show_expire_client_cert() {
  type_username
  echo ""
  openssl x509 -in "${CLIENT_CONFIGS_PATH}/keys/$USERNAME.crt" -text -noout | grep -A 2 Validity
  echo ""
}

show_openvpn_users2() {
  echo ""
  echo "All users: "
  ls "$CCD_PATH"
  echo ""
}

while true; do
  welcome
  type_choice

  case $CHOICE in
    1)
      create_cert
      ;;
    2)
      show_openvpn_users
      ;;
    3)
      show_openvpn_users2
      revoke_cert
      ;;
    4)
      show_revoke_users
      ;;
    5)
      show_openvpn_users2
      renew_client_cert
      ;;
    6)
      show_openvpn_users2
      show_expire_client_cert
      ;;
    7)
      break
      ;;
    *)
      echo "Incorrect choice. Try again."
      ;;
  esac
done
