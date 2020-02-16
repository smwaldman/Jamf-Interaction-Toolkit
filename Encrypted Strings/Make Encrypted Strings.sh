#!/bin/bash

SALT=$(openssl rand -hex 8)
K=$(openssl rand -hex 12)

function GenerateEncryptedString() {
    # Usage ~$ GenerateEncryptedString "String"
    local STRING="${1}"
    local ENCRYPTED
	ENCRYPTED=$(echo "${STRING}" | openssl enc -aes256 -a -A -S "${SALT}" -k "${K}")
    echo "Encrypted String: ${ENCRYPTED}"
    
}

arrary2Encrypt=()
addMore=true
while [[ "$addMore" == true ]] ; do

	echo "Please enter the string you want to encrypt. (leave blank to continue)"
	read -r Answer

	echo "$Answer"

	if [[ -n "$Answer" ]] ; then
		arrary2Encrypt+=("$Answer")
		echo "Do you want to add more? (y or n)"
		read -r addMoreYN

		if [[ "$addMoreYN" == y ]]; then
			addMore=true
		elif [[ "$addMoreYN" == n ]]; then
			addMore=false
		else
			echo "Wrong answer."
		fi
	else
		addMore=false
	fi

done

for string in "${arrary2Encrypt[@]}" ; do

	GenerateEncryptedString "$string"

done 

echo "Salt: ${SALT} | Passphrase: ${K}"

exit 0