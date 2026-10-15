#!/bin/bash
# Round 2 hardening script - Project A (Ubuntu server hardening portfolio)
# Run with: sudo bash round2.sh

if [ "$EUID" -ne 0 ]; then
  echo "Please run with sudo: sudo bash round2.sh"
  exit 1
fi

USERNAME="${SUDO_USER:-vboxuser}"
export DEBIAN_FRONTEND=noninteractive

step() { echo; echo "========== $1 =========="; }

step "31. Installing extra security packages"
apt-get update
apt-get install -y libpam-tmpdir apt-listchanges debsums apt-show-versions acct sysstat
sed -i 's/ENABLED="false"/ENABLED="true"/' /etc/default/sysstat
systemctl enable --now acct sysstat

step "32. Finishing SSH hardening"
cat >> /etc/ssh/sshd_config.d/01-hardening.conf <<'EOF'
LogLevel VERBOSE
MaxSessions 2
TCPKeepAlive no
AllowAgentForwarding no
EOF
if sshd -t; then
  systemctl restart ssh
  echo "SSH config OK and restarted"
else
  echo "SSH config error - SSH NOT restarted. Send this output to Claude."
fi

step "33. Password and file permission policy"
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/; s/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/' /etc/login.defs
if grep -q '^UMASK' /etc/login.defs; then
  sed -i 's/^UMASK.*/UMASK           027/' /etc/login.defs
else
  echo 'UMASK           027' >> /etc/login.defs
fi
grep -q '^SHA_CRYPT_MIN_ROUNDS' /etc/login.defs || printf 'SHA_CRYPT_MIN_ROUNDS 5000\nSHA_CRYPT_MAX_ROUNDS 10000\n' >> /etc/login.defs
chage -M 90 -m 1 "$USERNAME"
echo "Password policy applied for $USERNAME"

step "34. Disabling USB storage and unused protocols"
cat > /etc/modprobe.d/hardening.conf <<'EOF'
install usb-storage /bin/false
install dccp /bin/false
install sctp /bin/false
install rds /bin/false
install tipc /bin/false
blacklist usb-storage
blacklist dccp
blacklist sctp
blacklist rds
blacklist tipc
EOF

step "35. Adding auditd rules"
cat > /etc/audit/rules.d/hardening.rules <<'EOF'
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/sudoers -p wa -k sudo_changes
-w /etc/sudoers.d/ -p wa -k sudo_changes
-w /etc/ssh/sshd_config -p wa -k sshd_config
-w /etc/ssh/sshd_config.d/ -p wa -k sshd_config
EOF
augenrules --load
echo "Active audit rules (SCREENSHOT THIS as 13-auditd-rules.png):"
auditctl -l

step "36. Legal banner"
cat > /etc/issue <<'EOF'
WARNING: This is a private system. Access is restricted to authorized users only.
All connections and activity are monitored and recorded. Unauthorized access
or use is prohibited and may result in criminal prosecution under applicable law.
By continuing, you consent to these terms and to monitoring as evidence.
EOF
cp /etc/issue /etc/issue.net

step "37. Restricting compilers to root"
for f in /usr/bin/gcc* /usr/bin/cc /usr/bin/as; do
  if [ -e "$f" ]; then chmod o-rx "$(readlink -f "$f")"; fi
done

step "38. Installing AIDE file integrity (this takes 5-15 minutes, be patient)"
apt-get install -y --no-install-recommends aide
aideinit -y -f

step "Final Lynis audit"
lynis audit system | tee "/home/$USERNAME/final-lynis.txt"
chown "$USERNAME" "/home/$USERNAME/final-lynis.txt"
echo
echo "FINAL SCORE:"
grep hardening_index /var/log/lynis-report.dat
echo
echo "Done. Screenshot the Lynis summary above as 14-final-lynis-score.png"
