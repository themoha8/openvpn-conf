#!/bin/bash

CLIENT_EASYRSA_PATH="${HOME}/easy-rsa"
SERVER_EASYRSA_PATH="${HOME}/easy-rsa-ca"
CLIENT_CONFIGS_PATH="${HOME}/client-configs"
CCD_PATH="/etc/openvpn/ccd"
IPS_FILE="${HOME}/client-configs/ips.txt"
CRL_PATH="/etc/openvpn/keys"
INDEX_TXT_PATH=${SERVER_EASYRSA_PATH}/pki/index.txt

export EASYRSA_BATCH="yes"
set -e

while true; do
	echo "1. Create a certificate for an openVPN user"
	echo "2. Show all openVPN users"
	echo "3. Revoke a client certificate"
	echo "4. Show clients that revoked"
	echo "5. Show current iptables rules"
	echo "6. Allow access to local resorse for an openVPN user"
	echo "7. Exit"
	read -p "Enter the action number: " CHOICE

	case $CHOICE in
		1)
			read -p "Enter a username without spaces: " USERNAME			
            echo "1. Without password"
            echo "2. With password"
			read -p "Enter the action number: " CHOICE

			echo ""
			echo ""			
			echo "------------------------------------------------------------------------------------------"

			export EASYRSA_REQ_CN="$USERNAME"
			
			# Generate Certificate Request (CSR)
			cd "$CLIENT_EASYRSA_PATH"
			
			if [ "$CHOICE" == '2' ]; then
				./easyrsa gen-req "$USERNAME" pass
			else
				./easyrsa gen-req "$USERNAME" nopass
			fi

			# Copy the private key in directory client configs
			cp "pki/private/${USERNAME}.key" "${CLIENT_CONFIGS_PATH}/keys/"

			# Import and sign the client cert
			cd "$SERVER_EASYRSA_PATH"
			CA_P="$(gpg --quiet --decrypt "${CLIENT_CONFIGS_PATH}/easyrsa_p.txt.gpg")"
			./easyrsa import-req "${CLIENT_EASYRSA_PATH}/pki/reqs/${USERNAME}.req" "$USERNAME"
			./easyrsa --passin=pass:$CA_P sign-req client "$USERNAME"
			#./easyrsa sign-req client "$USERNAME"

			# Copy the client cert to directory client configs
			cp "pki/issued/${USERNAME}.crt" "${CLIENT_CONFIGS_PATH}/keys/"

			# Create the openVPN cert
			"${CLIENT_CONFIGS_PATH}/make_config.sh" "$USERNAME"

			# Search free ip address
			FREE_IP="$(grep -m1 -v "\-\-" $IPS_FILE)"
			FREE_IP_SED="$(echo -n "$FREE_IP" | sed "s/\./\\\./g")"

			#su - root -c "echo \"ifconfig-push $FREE_IP 255.255.255.0\" > ${CCD_PATH}/$USERNAME ; chmod 640 ${CCD_PATH}/$USERNAME ; chown :nobody ${CCD_PATH}/$USERNAME"

			# Create fixed ip address for new client
			echo "ifconfig-push $FREE_IP 255.255.255.0" > "${CCD_PATH}/$USERNAME"
			chmod 640 "${CCD_PATH}/$USERNAME"
			chown :nobody "${CCD_PATH}/$USERNAME"

			echo "CERTIFICATE CREATED"	
			echo "------------------------------------------------------------------------------------------"
			echo ""
			echo ""			

			# Mark $FREE_IP as used
			sed -i "s/${FREE_IP_SED}\$/& \-\- ${USERNAME}/" "$IPS_FILE"
			;;
		2)
			echo ""
			echo ""
			echo "----------------------------"
			grep "\-\-" "$IPS_FILE"
			echo "----------------------------"
			echo ""
			echo ""
			;;
		3)
			read -p "Enter a username without spaces: " USERNAME

			echo ""
			echo ""			
			echo "------------------------------------------------------------------------------------------"
			

			# Revoke a client and generate crl.pem
			cd ${SERVER_EASYRSA_PATH}/
			CA_P="$(gpg --quiet --decrypt "${CLIENT_CONFIGS_PATH}/easyrsa_p.txt.gpg")"
			./easyrsa --passin=pass:$CA_P revoke "$USERNAME"
			./easyrsa --passin=pass:$CA_P gen-crl

			echo "CLIENT IS REVOKED"
			echo "------------------------------------------------------------------------------------------"
			echo ""
			echo ""			

			# Mark ip as free
			sed -i "/${USERNAME}/s/ --.*//" "$IPS_FILE"

			# Copy crl.pem in openVPN directory and delete client ip from ccd directory
			#su - root -c "cp ${SERVER_EASYRSA_PATH}/pki/crl.pem ${CRL_PATH} ; chown nobody ${CRL_PATH}/crl.pem ; chmod 600 ${CRL_PATH}/crl.pem ; rm ${CCD_PATH}/${USERNAME} ; systemctl restart openvpn-server@vpn_themoha_xyz"

			cp "${SERVER_EASYRSA_PATH}/pki/crl.pem" "${CRL_PATH}"
			#chown :nobody "${CRL_PATH}/crl.pem"
			#chmod 660 "${CRL_PATH}/crl.pem"

			rm -f "${CCD_PATH}/${USERNAME}"

			#su - root -c "systemctl restart openvpn-server@vpn_themoha_xyz"
			;;
		4)
			echo ""
			echo ""
			echo "----------------------------"
			grep "^R" "$INDEX_TXT_PATH"
			echo "----------------------------"
			echo ""
			echo ""
			;;
		5)
			echo "TODO 5"
			;;
		6)
			echo "TODO 6"
			;;
		7)
			break
			;;
		*)
			echo "Incorrect choice. Try again."
			;;
	esac
done
