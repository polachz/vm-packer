# AlmaLinux OS 10 kickstart for VMware Hybrid Templates
url --url https://repo.almalinux.org/almalinux/10/BaseOS/x86_64/os
text
lang en_US.UTF-8
keyboard us
timezone UTC --utc
selinux --enforcing
firewall --disabled
services --enabled=sshd

bootloader --timeout=3 --location=mbr --append="quiet no_timer_check net.ifnames=0"

%pre --erroronfail
parted -s -a optimal /dev/sda -- mklabel gpt
parted -s -a optimal /dev/sda -- mkpart biosboot 1MiB 2MiB set 1 bios_grub on
parted -s -a optimal /dev/sda -- mkpart '"EFI System Partition"' fat32 2MiB 202MiB set 2 esp on
parted -s -a optimal /dev/sda -- mkpart boot xfs 202MiB 1226MiB
parted -s -a optimal /dev/sda -- mkpart root xfs 1226MiB 100%
%end

part biosboot --fstype=biosboot --onpart=sda1
part /boot/efi --fstype=efi --onpart=sda2
part /boot --fstype=xfs --onpart=sda3
part / --fstype=xfs --onpart=sda4

rootpw --plaintext almalinux
reboot --eject

%packages --exclude-weakdeps --inst-langs=en
dracut-config-generic
grub2-pc
pciutils
tar
python3
-dracut-config-rescue
-firewalld
-*firmware
%end

%addon com_redhat_kdump --disable
%end

%post --erroronfail
EX_NOINPUT=66
root_disk=$(grub2-probe --target=disk /boot/grub2)
if [[ "$root_disk" =~ ^"/dev/" ]]; then
    grub2-install --target=i386-pc "$root_disk"
else
    exit "$EX_NOINPUT"
fi
printf 'PermitRootLogin yes\nPasswordAuthentication yes\n' > /etc/ssh/sshd_config.d/01-permitrootlogin.conf

# Pre-create .ssh with correct SELinux context so Packer's SFTP upload of the
# Ansible public key writes into an already-correctly-labelled authorized_keys.
# Without this, sshd (SELinux enforcing) rejects the key: the file created by
# SFTP after the shell provisioner's restorecon runs gets unlabelled_t.
mkdir -m 700 -p /root/.ssh
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
restorecon -R /root/.ssh
%end
