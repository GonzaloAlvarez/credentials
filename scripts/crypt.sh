#!/bin/bash

export GPG_TTY=$(tty)
function clean {
    if [ -d "$GNUPGHOME" ]; then
        _info "Cleaning up temporary path [$GNUPGHOME]"
        rm -Rf "$GNUPGHOME" 2>/dev/null
    fi
}

function input_privatekey {
    VIM="$(which vim)"
    VIM_CMD="$VIM -u NONE --cmd \"set statusline=PrivateKey\" --cmd \"set paste\" --cmd \"set nocompatible\" +start"
    export PRIVATEKEY_PATH="$GNUPGHOME/PrivateKey.pem"
    eval "$VIM_CMD $PRIVATEKEY_PATH"
    chmod 600 "$PRIVATEKEY_PATH"
}

restart_agent(){
	# Restart the gpg agent.
	# shellcheck disable=SC2046
    _info "Killing existing agents"
	kill -9 $(ps -A | grep -m1 scdaemon | awk '{print $1}') >/dev/null 2>&1 || true
	# shellcheck disable=SC2046
	kill -9 $(ps -A | grep -m1 gpg-agent | awk '{print $1}') >/dev/null 2>&1 || true
    _info "Starting new agents"
    eval "$(gpg-agent --daemon --quiet --log-file ${GNUPGHOME}/.gpg-agent.log --enable-ssh-support)"
	gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
}

function init_gpg {
    clean
    GPG=$(which gpg)
    [[ -x "$GPG" ]] || _fatal "gpg not installed, but required"
    export GPG
    PINENTRY="$(which pinentry)"
    [[ -x "$PINENTRY" ]] || _fatal "pinentry not installed, but required"

    TEMP_FOLDER="$(mktemp -d)"
    export GNUPGHOME="${GPG_HOME:-"$TEMP_FOLDER"}/.enc-env"
    _info "Creating folder on [$GNUPGHOME]"
    mkdir -p "$GNUPGHOME"
    chmod 700 "$GNUPGHOME"
    export GPG_CMD="$GPG -q --home $GNUPGHOME"

	# Create the gpg config file.
	_info "Setting up gpg.conf..."
	cat <<-EOF > "${GNUPGHOME}/gpg.conf"
	use-agent
	personal-cipher-preferences AES256 AES192 AES CAST5
	personal-digest-preferences SHA512 SHA384 SHA256 SHA224
	default-preference-list SHA512 SHA384 SHA256 SHA224 AES256 AES192 AES CAST5 ZLIB BZIP2 ZIP Uncompressed
	cert-digest-algo SHA512
	s2k-digest-algo SHA512
	s2k-cipher-algo AES256
	charset utf-8
	fixed-list-mode
	no-comments
	no-emit-version
	keyid-format 0xlong
	list-options show-uid-validity
	verify-options show-uid-validity
	with-fingerprint
	EOF

	_info "Setting up gpg-agent.conf..."
	cat <<-EOF > "${GNUPGHOME}/gpg-agent.conf"
	pinentry-program ${PINENTRY}
	enable-ssh-support
	default-cache-ttl 600
	max-cache-ttl 7200
	EOF

    export SSH_AUTH_SOCK="$GNUPGHOME/S.gpg-agent.ssh"
    restart_agent
}

function import_publickey {
    PUBLICKEY_PATH="$BASE_PATH/GPG/GonzaloAlvarez-MasterGPG-pubkey.pem"
    $GPG_CMD --import "$PUBLICKEY_PATH"
}

function yubikey_init {
    $GPG_CMD --no-tty --card-status -q --batch 2>&1 >/dev/null
    if [ $? -ne 0 ]; then
        _fatal "Yubikey not inserted or not working. Try removing and inserting again."
    fi
    _info "Yubikey inserted and working properly"
}

function import_yk_publickey {
    KEY_ID=$(< "$BASE_PATH/GPG/GonzaloAlvarez-MasterGPG-pubkey.keyid")

    yubikey_init

    _info "Trying to retrieve key from the Internet"
    echo "admin"$'\n'"fetch"$'\n'quit$'\n' | $GPG_CMD -q --card-edit --expert --batch --display-charset utf-8 --no-tty --command-fd 0 2>/dev/null
    KEY_LIST_OUTPUT="$($GPG_CMD -k --batch | tr -d ' ' | grep "$KEY_ID" | head -n 1)"
    if [ "${#KEY_LIST_OUTPUT}" -le 0 ]; then
        _warn "Cannot retrieve from Internet. Falling back to less secure local key"
        import_publickey
    fi
    _info "Trusting key"
    echo "trust"$'\n'5$'\n'y$'\n'quit$'\n' | $GPG_CMD -q --expert --batch --display-charset utf-8 --command-fd 0 --no-tty --edit-key "$KEY_ID" 
    [[ $? -eq 0 ]] || _fail "Cannot trust the key with ID [$KEY_ID]"
}

function import_privatekey {
    input_privatekey
    $GPG_CMD --import "$PRIVATEKEY_PATH"
}

function list_keys {
    $GPG_CMD --list-keys
    $GPG_CMD --list-secret-keys
}

function upload_keys {
    BASE_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    KEY_ID=$(< "$BASE_PATH/GPG/GonzaloAlvarez-MasterGPG-pubkey.keyid")
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "The commands that you need to execute are:"
    echo "  toggle"
    echo "  keytocard  (first prompt: y  second prompt: 1 to move it to signature)"
    echo "  quit"
    echo ""
    echo "NOTE: the default admin PIN is 12345678"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    $GPG_CMD --edit-key "$KEY_ID"
}

function generate_subkeys(){
    SUBKEY_LENGTH=${SUBKEY_LENGTH:=2048}
    SUBKEY_EXPIRE=${SUBKEY_EXPIRE:=0}

	echo "Printing local secret keys..."
	$GPG_CMD --list-secret-keys

	echo "Generating subkeys..."

	echo "Generating signing subkey..."
	echo addkey$'\n'4$'\n'$SUBKEY_LENGTH$'\n'"$SUBKEY_EXPIRE"$'\n'save$'\n' | \
		$GPG_CMD --expert --batch --display-charset utf-8 \
		--command-fd 0 --edit-key "$KEY_ID"

	echo "Generating encryption subkey..."
	echo addkey$'\n'6$'\n'$SUBKEY_LENGTH$'\n'"$SUBKEY_EXPIRE"$'\n'save$'\n' | \
		$GPG_CMD --expert --batch --display-charset utf-8 \
		--command-fd 0 --edit-key "$KEY_ID"

	echo "Generating authentication subkey..."
	echo addkey$'\n'8$'\n'S$'\n'E$'\n'A$'\n'q$'\n'$SUBKEY_LENGTH$'\n'"$SUBKEY_EXPIRE"$'\n'save$'\n' | \
		$GPG_CMD --expert --batch --display-charset utf-8 \
		--command-fd 0 --edit-key "$KEY_ID"

	echo "Printing local secret keys..."
	$GPG_CMD --list-secret-keys

    TMP_FOLDER=$(mktemp -d)
    echo "Exporting public keys to [$TMP_FOLDER]..."
    $GPG_CMD --armor --export --output $TMP_FOLDER/keys.pem "$KEY_ID"
}

move_keys_to_card(){
	echo "Moving signing subkey to card..."
	echo "key 2"$'\n'keytocard$'\n'1$'\n'y$'\n'save$'\n' | \
		$GPG_CMD --expert --batch --display-charset utf-8 \
		--command-fd 0 --edit-key "$KEY_ID"

	echo "key 3"$'\n'keytocard$'\n'2$'\n'y$'\n'save$'\n' | \
		$GPG_CMD --expert --batch --display-charset utf-8 \
		--command-fd 0 --edit-key "$KEY_ID"

	echo "key 4"$'\n'keytocard$'\n'3$'\n'y$'\n'save$'\n' | \
		$GPG_CMD --expert --batch --display-charset utf-8 \
		--command-fd 0 --edit-key "$KEY_ID"

	echo "Printing card status..."
	$GPG_CMD --card-status
}

update_cardinfo(){
	# Edit the smart card name and info values.
	echo "Updating card holder name..."
	echo admin$'\n'name$'\n'$SURNAME$'\n'$GIVENNAME$'\n'quit$'\n' | \
		$GPG_CMD --expert --batch --display-charset utf-8 \
		--command-fd 0 --card-edit

	echo "Updating card language..."
	echo admin$'\n'lang$'\n'en$'\n'quit$'\n' | \
		$GPG_CMD --expert --batch --display-charset utf-8 \
		--command-fd 0 --card-edit

	echo "Updating card login..."
	echo admin$'\n'login$'\n'"$EMAIL"$'\n'quit$'\n' | \
		$GPG_CMD --expert --batch --display-charset utf-8 \
		--command-fd 0 --card-edit

	echo "Updating card public key url..."
	echo admin$'\n'url$'\n'$PUBLIC_KEY_URL$'\n'quit$'\n' | \
		$GPG_CMD --expert --batch --display-charset utf-8 \
		--command-fd 0 --card-edit

	echo "Updating card sex..."
	echo admin$'\n'sex$'\n'$SEX$'\n'quit$'\n' | \
		$GPG_CMD --expert --batch --display-charset utf-8 \
		--command-fd 0 --card-edit
}


