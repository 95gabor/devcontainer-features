#!/usr/bin/env bash
set -e

KUBECOLOR_VERSION="${VERSION:-"latest"}"
KUBECOLOR_SHA256="${SHA256:-"automatic"}"
KUBECOLOR_ALIAS="${ALIAS:-"true"}"

# Figure out correct version of a three part version number is not passed
find_version_from_git_tags() {
    local variable_name=$1
    local requested_version=${!variable_name}
    if [ "${requested_version}" = "none" ]; then return; fi
    local repository=$2
    local prefix=${3:-"tags/v"}
    local separator=${4:-"."}
    local last_part_optional=${5:-"false"}
    if [ "$(echo "${requested_version}" | grep -o "." | wc -l)" != "2" ]; then
        local escaped_separator=${separator//./\\.}
        local last_part
        if [ "${last_part_optional}" = "true" ]; then
            last_part="(${escaped_separator}[0-9]+)?"
        else
            last_part="${escaped_separator}[0-9]+"
        fi
        local regex="${prefix}\\K[0-9]+${escaped_separator}[0-9]+${last_part}$"
        local version_list="$(git ls-remote --tags ${repository} | grep -oP "${regex}" | tr -d ' ' | tr "${separator}" "." | sort -rV)"
        if [ "${requested_version}" = "latest" ] || [ "${requested_version}" = "current" ] || [ "${requested_version}" = "lts" ]; then
            declare -g ${variable_name}="$(echo "${version_list}" | head -n 1)"
        else
            set +e
            declare -g ${variable_name}="$(echo "${version_list}" | grep -E -m 1 "^${requested_version//./\\.}([\\.\\s]|$)")"
            set -e
        fi
    fi
    if [ -z "${!variable_name}" ] || ! echo "${version_list}" | grep "^${!variable_name//./\\.}$" > /dev/null 2>&1; then
        echo -e "Invalid ${variable_name} value: ${requested_version}\nValid values:\n${version_list}" >&2
        exit 1
    fi
    echo "${variable_name}=${!variable_name}"
}

apt_get_update()
{
    if [ "$(find /var/lib/apt/lists/* | wc -l)" = "0" ]; then
        echo "Running apt-get update..."
        apt-get update -y
    fi
}

# Checks if packages are installed and installs them if not
check_packages() {
    if ! dpkg -s "$@" > /dev/null 2>&1; then
        apt_get_update
        apt-get -y install --no-install-recommends "$@"
    fi
}

# Ensure apt is in non-interactive to avoid prompts
export DEBIAN_FRONTEND=noninteractive

# Install dependencies
check_packages curl ca-certificates coreutils
if ! type git > /dev/null 2>&1; then
    check_packages git
fi

architecture="$(uname -m)"

case $architecture in
    x86_64) architecture="amd64";;
    aarch64 | armv8*) architecture="arm64";;
    ppc64le) architecture="ppc64le";;
    *) echo "(!) Architecture $architecture unsupported"; exit 1 ;;
esac

# Install kubecolor, verify checksum
if [ "${KUBECOLOR_VERSION}" != "none" ] && ! type kubecolor > /dev/null 2>&1; then

    echo "Downloading kubecolor..."

    find_version_from_git_tags KUBECOLOR_VERSION https://github.com/kubecolor/kubecolor

    KUBECOLOR_VERSION="${KUBECOLOR_VERSION}"

    curl -sSL -o /tmp/kubecolor-linux-${architecture}.tar.gz "https://github.com/kubecolor/kubecolor/releases/download/v${KUBECOLOR_VERSION}/kubecolor_${KUBECOLOR_VERSION}_linux_${architecture}.tar.gz"

    if [ "$KUBECOLOR_SHA256" = "automatic" ]; then
        KUBECOLOR_SHA256="$(curl -sSL "https://github.com/kubecolor/kubecolor/releases/download/v${KUBECOLOR_VERSION}/checksums.txt" | grep kubecolor_${KUBECOLOR_VERSION}_linux_${architecture}.tar.gz | cut -f1 -d' ')"
        echo $KUBECOLOR_SHA256
    fi
    ([ "${KUBECOLOR_SHA256}" = "dev-mode" ] || (echo "${KUBECOLOR_SHA256} */tmp/kubecolor-linux-${architecture}.tar.gz" | sha256sum -c -))
    tar -xf /tmp/kubecolor-linux-${architecture}.tar.gz --directory /usr/local/bin/
    chmod 0755 /usr/local/bin/kubecolor
    rm /tmp/kubecolor-linux-${architecture}.tar.gz
    if ! type kubecolor > /dev/null 2>&1; then
        echo '(!) kubecolor installation failed!'
        exit 1
    fi
else
    if ! type kubecolor > /dev/null 2>&1; then
        echo "Skipping kubecolor."
    else
        echo "kubecolor already instaled"
    fi
fi

if [ "${KUBECOLOR_ALIAS}" = "true" ]; then
    echo alias kubectl=kubecolor >> /etc/bash.bashrc
fi

# Clean up
rm -rf /var/lib/apt/lists/*

echo -e "\nDone!"
