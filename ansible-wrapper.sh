#!/bin/bash
# Bridge script: converts Windows paths to WSL paths and runs ansible-playbook in WSL.
# Packer (Windows) calls this script via ansible-wrapper.cmd with all arguments.
#
# Authentication: ansible_ssh_pass (password) via sshpass – no issues with SELinux
# or transferring the private key through the Windows temp directory.
#
# Why key-based auth is unreliable:
#   1. CMD lacks single-quoting: '--ssh-extra-args' '-o IdentitiesOnly=yes' gets split
#      into 2 tokens ('-o and IdentitiesOnly=yes'), so ansible-playbook receives an invalid arg.
#   2. Copying the key from Windows TEMP to WSL /tmp happens without error handling;
#      a silent wslpath/cp failure causes authentication with an old/non-existent key.

export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_SCP_IF_SSH=y
export ANSIBLE_PIPELINING=True
export ANSIBLE_SSH_ARGS="-o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

args=()
drop_ssh_extra=false  # true while consuming tokens of the --ssh-extra-args value

for arg in "$@"; do
    # Consume the --ssh-extra-args value (CMD may split '-o X=y' into 2 tokens).
    # A token starting with ' but not ending with ' is the first half of a CMD-split value → keep waiting.
    if [[ "$drop_ssh_extra" == "true" ]]; then
        if [[ "$arg" == "'"* && "$arg" != *"'" ]]; then
            :  # first half of a split token, stay in drop mode
        else
            drop_ssh_extra=false  # last (or only) token of the value
        fi
        continue
    fi

    if [[ "$arg" == "--ssh-extra-args" ]]; then
        drop_ssh_extra=true
        continue
    fi

    # Drop ansible_ssh_private_key_file (key auth replaced by password via sshpass).
    # Also remove the preceding -e from args (compatible with bash < 4.3).
    if [[ "$arg" =~ ^ansible_ssh_private_key_file= ]]; then
        if [[ "${#args[@]}" -gt 0 && "${args[-1]}" == "-e" ]]; then
            args=("${args[@]:0:${#args[@]}-1}")
        fi
        continue
    fi

    # Translate standalone Windows paths (e.g. -i <inventory_file> or last arg = playbook)
    if [[ "$arg" =~ ^[a-zA-Z]:\\ ]]; then
        arg=$(wslpath -u "$arg")

    # Translate key=value where the value is a Windows path (e.g. other -e variables)
    elif [[ "$arg" =~ ^([^=]+=)([a-zA-Z]:\\.*) ]]; then
        prefix="${BASH_REMATCH[1]}"
        winpath="${BASH_REMATCH[2]}"
        arg="${prefix}$(wslpath -u "$winpath")"
    fi

    args+=("$arg")
done

exec ansible-playbook "${args[@]}"
