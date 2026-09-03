#!/usr/bin/env bash
# =============================================================================
# server_audit.sh  —  Linux 服务器入侵痕迹排查脚本（只读，不修改任何东西）
#
# 用法（以 root 运行）:
#   bash server_audit.sh > /root/audit_$(date +%F_%H%M).txt 2>&1
#   然后把生成的 txt 文件内容发回来分析即可。
#
# 说明:
#   * 脚本只做 读取 / 列举 / 统计，不会删除、修改、杀进程、改配置。
#   * 缺少的命令会自动跳过。
#   * 末尾有一个「自动标记」小结，列出脚本认为最可疑的项目。
# =============================================================================

export LC_ALL=C
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
FLAGS=()
flag() { FLAGS+=("$*"); echo "  [!!] $*"; }
hdr() { printf '\n\n==================== %s ====================\n' "$*"; }
sub() { printf '\n----- %s -----\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
run() { # run <描述> <命令...>
  local d="$1"; shift
  sub "$d"
  if have "$1"; then timeout 60 "$@" 2>&1 || true; else echo "(缺少命令: $1)"; fi
}

if [ "$(id -u)" != "0" ]; then
  echo "警告: 不是 root，部分检查会缺失。建议: sudo bash $0"
fi

hdr "0. 基本信息"
echo "hostname : $(hostname)"
echo "date     : $(date -u '+%F %T UTC')  (本地: $(date '+%F %T %Z'))"
echo "kernel   : $(uname -srmo)"
[ -f /etc/os-release ] && grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release
echo "uptime   : $(uptime)"
echo "last boot: $(who -b 2>/dev/null | tr -s ' ')"
sub "CPU/内存占用概览（挖矿木马通常会把 CPU 打满）"
have top && top -bn1 2>/dev/null | head -20
sub "磁盘"
df -h 2>/dev/null | grep -vE 'tmpfs|udev'

hdr "1. 账户与权限"
sub "UID=0 的账户（正常只应有 root）"
awk -F: '$3==0{print}' /etc/passwd
[ "$(awk -F: '$3==0' /etc/passwd | wc -l)" -gt 1 ] && flag "存在多个 UID=0 账户"
sub "拥有可登录 shell 的账户"
awk -F: '$7 !~ /(nologin|false|sync|halt|shutdown)$/ {print $1":"$3":"$6":"$7}' /etc/passwd
sub "空密码账户"
awk -F: '($2=="" ){print "  空密码: "$1}' /etc/shadow 2>/dev/null
awk -F: '($2=="" ){print}' /etc/shadow 2>/dev/null | grep -q . && flag "存在空密码账户"
sub "最近 30 天内改过密码的账户 (shadow 第3字段=距1970天数)"
today=$(( $(date +%s) / 86400 ))
awk -F: -v t="$today" '$3>0 && (t-$3)<30 {print "  "$1" 改密于 "(t-$3)" 天前"}' /etc/shadow 2>/dev/null
sub "账户相关文件修改时间"
ls -la --time-style=full-iso /etc/passwd /etc/shadow /etc/group /etc/sudoers /etc/gshadow 2>/dev/null
sub "sudo / wheel / adm / docker 组成员"
grep -E '^(sudo|wheel|adm|docker|root):' /etc/group
sub "sudoers 及 sudoers.d"
grep -vE '^\s*(#|$)' /etc/sudoers 2>/dev/null
for f in /etc/sudoers.d/*; do [ -f "$f" ] && { echo "--- $f"; grep -vE '^\s*(#|$)' "$f"; }; done
sub "最近创建的家目录"
ls -la --time-style=long-iso /home/ 2>/dev/null
sub "lastlog（每个账户最后一次登录）"
have lastlog && lastlog 2>/dev/null | grep -v 'Never logged in'

hdr "2. 登录记录"
sub "当前在线用户"
w 2>/dev/null
sub "最近 60 条成功登录 (last)"
last -a -F -n 60 2>/dev/null
sub "成功登录来源 IP 统计"
last -a -i 2>/dev/null | awk 'NF>=10 && $1!="reboot" && $1!="wtmp" {print $NF}' | grep -E '^[0-9]+\.' | sort | uniq -c | sort -rn | head -30
sub "失败登录次数 (lastb) 与来源 TOP 30"
if [ -r /var/log/btmp ]; then
  n=$(lastb 2>/dev/null | grep -c .)
  echo "btmp 失败登录总数: $n"
  lastb -a -i 2>/dev/null | awk '{print $NF}' | grep -E '^[0-9]+\.' | sort | uniq -c | sort -rn | head -30
  [ "${n:-0}" -gt 1000 ] && flag "失败登录次数很高($n)，说明 SSH 正在被暴力破解"
else
  echo "(无 /var/log/btmp)"
fi
sub "失败登录尝试的用户名 TOP 20"
lastb 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn | head -20
sub "wtmp/btmp/lastlog 文件状态（被清空/极小 = 可能被擦日志）"
ls -la --time-style=full-iso /var/log/wtmp /var/log/btmp /var/log/lastlog 2>/dev/null
for f in /var/log/wtmp /var/log/btmp; do [ -f "$f" ] && [ ! -s "$f" ] && flag "$f 为空文件，可能被清理过"; done

hdr "3. SSH 配置与密钥"
sub "sshd 生效配置中的关键项"
if have sshd; then
  sshd -T 2>/dev/null | grep -iE '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|permitemptypasswords|authorizedkeysfile|allowusers|denyusers|maxauthtries|usepam|kbdinteractiveauthentication|challengeresponseauthentication) '
else
  grep -iE '^\s*(Port|PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|PermitEmptyPasswords|AuthorizedKeysFile|AllowUsers)' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/* 2>/dev/null
fi
sshd -T 2>/dev/null | grep -qiE '^permitrootlogin yes' && flag "sshd 允许 root 直接密码登录 (PermitRootLogin yes)"
sshd -T 2>/dev/null | grep -qiE '^passwordauthentication yes' && flag "sshd 开启了密码认证 (PasswordAuthentication yes)"
sub "sshd 配置文件修改时间"
ls -la --time-style=full-iso /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ /etc/ssh/ssh_host_*key 2>/dev/null
sub "所有账户的 authorized_keys（陌生公钥 = 后门）"
for d in /root $(awk -F: '$3>=1000 && $6!="" {print $6}' /etc/passwd) /var/lib/*/ /home/*; do
  for f in "$d"/.ssh/authorized_keys "$d"/.ssh/authorized_keys2; do
    if [ -f "$f" ]; then
      echo "--- $f  ($(stat -c '%y' "$f" 2>/dev/null))"
      cat "$f"
      echo "    共 $(grep -cE '^(ssh|ecdsa|sk-)' "$f") 个 key"
    fi
  done
done 2>/dev/null
[ -f /root/.ssh/authorized_keys ] && flag "root 存在 authorized_keys，请逐条确认每个公钥都是你自己的 (见第3节)"
sub ".ssh 目录内容与时间"
ls -la --time-style=full-iso /root/.ssh /home/*/.ssh 2>/dev/null
sub "known_hosts 中的主机（攻击者从这台机器跳去哪里）"
[ -f /root/.ssh/known_hosts ] && wc -l /root/.ssh/known_hosts

hdr "4. 认证日志 (auth.log / secure / journal)"
AUTHLOGS=$(ls /var/log/auth.log* /var/log/secure* 2>/dev/null)
if [ -n "$AUTHLOGS" ]; then
  sub "成功的 SSH 登录 (Accepted) — 全部"
  zgrep -h 'Accepted' $AUTHLOGS 2>/dev/null | tail -100
  sub "成功登录来源 IP 统计"
  zgrep -h 'Accepted' $AUTHLOGS 2>/dev/null | grep -oE 'from [0-9a-f:.]+' | sort | uniq -c | sort -rn | head -30
  sub "失败登录来源 IP TOP 30"
  zgrep -hE 'Failed password|Invalid user|authentication failure' $AUTHLOGS 2>/dev/null | grep -oE 'from [0-9a-f:.]+|rhost=[0-9a-f:.]+' | sort | uniq -c | sort -rn | head -30
  sub "sudo / su 使用记录 (最近 50 条)"
  zgrep -hE 'sudo:|su\[|su:' $AUTHLOGS 2>/dev/null | tail -50
  sub "新增用户 / 改密 / 改组 记录"
  zgrep -hE 'useradd|userdel|usermod|groupadd|passwd\[|chpasswd|new user|new group' $AUTHLOGS 2>/dev/null | tail -50
else
  echo "(无 auth.log/secure，改用 journalctl)"
fi
if have journalctl; then
  sub "journal: sshd 成功登录 (Accepted)"
  journalctl --no-pager -q _COMM=sshd 2>/dev/null | grep 'Accepted' | tail -100
  sub "journal: sshd 成功登录来源统计"
  journalctl --no-pager -q _COMM=sshd 2>/dev/null | grep 'Accepted' | grep -oE 'from [0-9a-f:.]+' | sort | uniq -c | sort -rn | head -30
  sub "journal: 失败来源 TOP 30"
  journalctl --no-pager -q _COMM=sshd 2>/dev/null | grep -E 'Failed|Invalid user' | grep -oE 'from [0-9a-f:.]+' | sort | uniq -c | sort -rn | head -30
  sub "journal: useradd/passwd/sudo 相关"
  journalctl --no-pager -q 2>/dev/null | grep -E 'useradd|userdel|usermod|chpasswd|passwd\[|sudo:' | tail -50
  sub "journal: 日志覆盖的时间范围（如果只有最近几分钟 = 可能被清理）"
  journalctl --no-pager -q --list-boots 2>/dev/null | tail -5
  journalctl --no-pager -q 2>/dev/null | head -1
fi

hdr "5. 进程"
sub "CPU 占用 TOP 15"
ps -eo pid,ppid,user,%cpu,%mem,etime,stat,cmd --sort=-%cpu 2>/dev/null | head -16
sub "内存占用 TOP 10"
ps -eo pid,ppid,user,%cpu,%mem,etime,cmd --sort=-%mem 2>/dev/null | head -11
sub "完整进程树"
ps auxf 2>/dev/null
sub "疑似挖矿/木马进程名关键字"
ps -eo pid,user,cmd 2>/dev/null | grep -iE 'xmrig|xmr-stak|minerd|minergate|kdevtmpfsi|kinsing|kthreaddi|cryptonight|stratum\+tcp|nanopool|supportxmr|monero|c3pool|hashvault|\.rsync|tsunami|gates\.lod|bioset|\bsysupdate\b|\bnetworkservice\b|\bsysguard\b|\bmeshagent\b|xmrigDaemon|pnscan|masscan|zmap|\bnoxa\b|\.ss[hd]d\b|dbused|\bkswapd[0-9]\.|watchdogs' | grep -vE 'grep -iE' && flag "发现疑似挖矿/木马进程名，见第5节"
sub "二进制已被删除但仍在运行的进程（常见于恶意软件自删除）"
for p in /proc/[0-9]*; do
  exe=$(readlink "$p/exe" 2>/dev/null)
  case "$exe" in *"(deleted)"*) echo "  PID ${p#/proc/}: $exe  cmd: $(tr '\0' ' ' < "$p/cmdline" 2>/dev/null | head -c 200)";;
  esac
done | tee /dev/stderr 2>/dev/null | grep -q . && flag "有进程的可执行文件已被删除 (deleted)，见第5节"
sub "从 /tmp /dev/shm /var/tmp /run 等临时目录运行的进程"
for p in /proc/[0-9]*; do
  exe=$(readlink "$p/exe" 2>/dev/null)
  cwd=$(readlink "$p/cwd" 2>/dev/null)
  case "$exe$cwd" in */tmp/*|*/dev/shm*|*/var/tmp*|*/run/user/*|*/root/.*|*/home/*/.[a-z]*)
    echo "  PID ${p#/proc/}: exe=$exe cwd=$cwd cmd: $(tr '\0' ' ' < "$p/cmdline" 2>/dev/null | head -c 200)";;
  esac
done
sub "ps 与 /proc 数量比对（差异大 = 可能有 rootkit 隐藏进程）"
a=$(ls -d /proc/[0-9]* 2>/dev/null | wc -l); b=$(ps -e --no-headers 2>/dev/null | wc -l)
echo "  /proc 进程数=$a   ps 进程数=$b"
[ $((a-b)) -gt 5 ] && flag "/proc 与 ps 进程数差异较大 ($a vs $b)，可能有隐藏进程"
sub "带有 LD_PRELOAD 环境变量的进程"
for p in /proc/[0-9]*; do tr '\0' '\n' < "$p/environ" 2>/dev/null | grep -q '^LD_PRELOAD=' && echo "  PID ${p#/proc/}: $(tr '\0' '\n' < "$p/environ" | grep '^LD_PRELOAD=')  $(tr '\0' ' ' < "$p/cmdline" | head -c 120)"; done

hdr "6. 网络"
sub "监听端口 (ss -tulpn)"
if have ss; then ss -tulpn 2>/dev/null; else netstat -tulpn 2>/dev/null; fi
sub "已建立的对外连接（注意陌生 IP 与 3333/4444/5555/7777/14444 等矿池常用端口）"
if have ss; then ss -tnp state established 2>/dev/null; else netstat -tnp 2>/dev/null | grep ESTABLISHED; fi
sub "对外连接的远端 IP 统计"
(ss -tn state established 2>/dev/null || netstat -tn 2>/dev/null) | awk 'NR>1{print $4}' | sed -E 's/:[0-9]+$//' | grep -vE '^(127\.|::1|\[::1\])' | sort | uniq -c | sort -rn | head -30
(ss -tn state established 2>/dev/null) | awk 'NR>1{print $4}' | grep -qE ':(3333|4444|5555|7777|14444|14433|45700|3334|3335|33333)$' && flag "存在连到矿池常用端口的连接，见第6节"
sub "/etc/hosts（是否被改，劫持域名）"
cat /etc/hosts 2>/dev/null
sub "/etc/resolv.conf"
grep -vE '^\s*#' /etc/resolv.conf 2>/dev/null
sub "防火墙规则"
have iptables && { echo "--- iptables -S"; iptables -S 2>/dev/null | head -80; echo "--- iptables -t nat -S"; iptables -t nat -S 2>/dev/null | head -40; }
have nft && { echo "--- nft"; nft list ruleset 2>/dev/null | head -120; }
have ufw && ufw status verbose 2>/dev/null
have firewall-cmd && firewall-cmd --list-all 2>/dev/null
sub "fail2ban 状态"
have fail2ban-client && fail2ban-client status 2>/dev/null && fail2ban-client status sshd 2>/dev/null

hdr "7. 持久化（开机自启 / 计划任务）"
sub "所有用户的 crontab"
for u in $(cut -d: -f1 /etc/passwd); do c=$(crontab -l -u "$u" 2>/dev/null); [ -n "$c" ] && { echo "--- $u"; echo "$c"; }; done
sub "/etc/crontab, /etc/cron.d, /etc/cron.{hourly,daily,weekly,monthly}, /var/spool/cron"
for f in /etc/crontab /etc/cron.d/* /etc/cron.hourly/* /etc/cron.daily/* /etc/cron.weekly/* /etc/cron.monthly/* /var/spool/cron/* /var/spool/cron/crontabs/*; do
  [ -f "$f" ] && { echo "--- $f ($(stat -c '%y' "$f"))"; grep -vE '^\s*(#|$)' "$f" | head -30; }
done
sub "cron 中含 curl/wget/base64/nc/python -c/bash -i 的可疑行"
grep -rhoE '.*(curl|wget|base64|/dev/tcp|nc -e|bash -i|python[23]? -c|chattr|\.onion|pastebin|transfer\.sh).*' /etc/crontab /etc/cron.d /etc/cron.hourly /etc/cron.daily /var/spool/cron 2>/dev/null | head -20 | tee /dev/stderr 2>/dev/null | grep -q . && flag "cron 中存在下载/编码类可疑命令，见第7节"
sub "at 任务"
have atq && atq 2>/dev/null
sub "systemd 已启用的服务"
have systemctl && systemctl list-unit-files --type=service --state=enabled --no-pager 2>/dev/null
sub "systemd 定时器"
have systemctl && systemctl list-timers --all --no-pager 2>/dev/null
sub "最近 30 天新增/修改的 systemd 单元文件"
find /etc/systemd /usr/lib/systemd/system /lib/systemd/system /run/systemd/system -type f -mtime -30 2>/dev/null | head -50
sub "自定义 systemd 单元 (/etc/systemd/system 下的 .service，逐个看 ExecStart)"
for f in /etc/systemd/system/*.service; do [ -f "$f" ] && { echo "--- $f ($(stat -c '%y' "$f"))"; grep -E '^(ExecStart|ExecStartPre|User|Description)=' "$f"; }; done
sub "运行中的失败/异常服务"
have systemctl && systemctl --failed --no-pager 2>/dev/null
sub "rc.local / init.d 近期修改"
ls -la --time-style=full-iso /etc/rc.local /etc/rc.d/rc.local 2>/dev/null
[ -f /etc/rc.local ] && grep -vE '^\s*(#|$)' /etc/rc.local
find /etc/init.d -type f -mtime -30 2>/dev/null
sub "/etc/ld.so.preload（存在即高度可疑，常见于用户态 rootkit）"
if [ -s /etc/ld.so.preload ]; then cat /etc/ld.so.preload; flag "/etc/ld.so.preload 存在且非空 —— 高度怀疑 rootkit"; else echo "(不存在或为空 — 正常)"; fi
ls -la /etc/ld.so.conf.d/ 2>/dev/null
sub "shell 启动文件近期修改（bashrc/profile/environment 被植入命令）"
ls -la --time-style=full-iso /etc/profile /etc/bash.bashrc /etc/bashrc /etc/environment /etc/profile.d/ /root/.bashrc /root/.profile /root/.bash_profile /root/.bash_logout /home/*/.bashrc /home/*/.profile 2>/dev/null
sub "启动文件中含 curl/wget/base64/nohup 的行"
grep -nE 'curl|wget|base64|nohup|/dev/tcp|LD_PRELOAD|alias (ls|ps|netstat|ss)=' /etc/profile /etc/bash.bashrc /etc/environment /etc/profile.d/* /root/.bashrc /root/.profile /home/*/.bashrc /home/*/.profile 2>/dev/null
sub "PAM 模块近期修改（后门常改 pam_unix.so）"
find /lib/security /lib64/security /usr/lib/security /usr/lib/x86_64-linux-gnu/security /lib/x86_64-linux-gnu/security -type f -mtime -60 2>/dev/null
ls -la --time-style=full-iso /etc/pam.d/sshd /etc/pam.d/common-auth /etc/pam.d/system-auth 2>/dev/null

hdr "8. 文件系统"
sub "/tmp /var/tmp /dev/shm 内容"
ls -la --time-style=full-iso /tmp /var/tmp /dev/shm 2>/dev/null
sub "临时目录中的可执行文件 / ELF 文件"
find /tmp /var/tmp /dev/shm /run/shm -type f \( -perm -u+x -o -name '*.sh' -o -name '*.py' -o -name '*.pl' \) 2>/dev/null | head -40 | tee /dev/stderr 2>/dev/null | grep -q . && flag "临时目录中存在可执行文件/脚本，见第8节"
find /tmp /var/tmp /dev/shm -type f 2>/dev/null | head -200 | while read -r f; do head -c 4 "$f" 2>/dev/null | grep -q 'ELF' && echo "  ELF二进制: $f"; done
sub "最近 7 天内修改的系统关键文件 (/etc /bin /sbin /usr/bin /usr/sbin /lib*)"
find /etc /bin /sbin /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin /lib /lib64 /usr/lib -xdev -type f -mtime -7 2>/dev/null | grep -vE '/etc/(mtab|resolv\.conf|ld\.so\.cache|adjtime|\.pwd\.lock|machine-id|hostname|motd|letsencrypt)|/etc/ssl/certs|/etc/cron\.daily/|__pycache__|\.pyc$|/usr/lib/python|/usr/lib/apt|/usr/lib/dpkg|/usr/lib/systemd/system$|/usr/lib/modules|/etc/apparmor|/etc/apt/|/etc/systemd/system/.*\.wants' | head -80
sub "最近 7 天内修改的 /root 与 /home 隐藏文件"
find /root /home -maxdepth 3 -name '.*' -type f -mtime -7 2>/dev/null | head -40
sub "全盘搜索：最近 3 天新建的可执行 ELF（排除 /proc /sys /var/lib/docker）"
timeout 120 find / -xdev \( -path /proc -o -path /sys -o -path /var/lib/docker -o -path /var/lib/containerd -o -path /snap \) -prune -o -type f -perm -u+x -ctime -3 -print 2>/dev/null | head -60
sub "带 immutable(i) 属性的文件（攻击者常用 chattr +i 防止清除）"
have lsattr && { lsattr -Ra /etc /usr/bin /usr/sbin /bin /sbin /root /tmp /var/spool/cron 2>/dev/null | grep -E '^....i' | head -30 | tee /dev/stderr 2>/dev/null | grep -q . && flag "存在带 immutable 属性的文件，见第8节"; }
sub "SUID/SGID 文件（对比常见清单，陌生的要注意）"
find / -xdev \( -path /proc -o -path /var/lib/docker \) -prune -o -type f \( -perm -4000 -o -perm -2000 \) -print 2>/dev/null | grep -vE '/(sudo|su|passwd|chsh|chfn|gpasswd|newgrp|mount|umount|fusermount3?|ping|ping6|pkexec|ssh-keysign|ssh-agent|chage|expiry|unix_chkpwd|dbus-daemon-launch-helper|polkit-agent-helper-1|at|crontab|wall|write|bwrap|mtr-packet|ntfs-3g|vmware-user-suid-wrapper|Xorg\.wrap|snap-confine|utempter|locate|mlocate|screen|ssh-keysign|dotlockfile|bsd-write|traceroute6\.iputils|pam_extrausers_chkpwd|lxc-user-nic|kismet_cap_.*|sudoedit|staprun|pppd|chrome-sandbox|cgroupfs)$' | head -40
sub "名字异常的隐藏目录/文件（'...', '. ', ' ' 等）"
find / -xdev \( -path /proc -o -path /sys -o -path /var/lib/docker \) -prune -o \( -name '...' -o -name '.. ' -o -name '. ' -o -name ' ' -o -name '.*  ' -o -name '.ICE-unix' -o -name '.X11-unix' \) -print 2>/dev/null | grep -vE '^/tmp/\.(ICE|X11)-unix$' | head -20
sub "根目录及 /root 下的隐藏文件"
ls -la --time-style=long-iso / /root 2>/dev/null | grep -E '^\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\.'
sub "/usr/bin /usr/sbin 中近期修改的常用工具（ps/ls/netstat/ss/lsof/find 被替换 = rootkit）"
ls -la --time-style=full-iso /bin/ps /usr/bin/ps /bin/ls /usr/bin/ls /bin/netstat /usr/bin/netstat /usr/bin/ss /usr/bin/lsof /usr/bin/find /usr/bin/top /usr/sbin/sshd /usr/bin/ssh /bin/login /usr/bin/passwd /usr/bin/sudo 2>/dev/null

hdr "9. 内核 / rootkit 迹象"
sub "已加载内核模块"
lsmod 2>/dev/null | head -80
lsmod 2>/dev/null | grep -iE 'diamorphine|reptile|suterusu|adore|knark|kbeast|rkit|hide' && flag "内核模块名可疑，见第9节"
sub "dmesg 最后 40 行（taint / segfault / module 加载 等）"
dmesg -T 2>/dev/null | tail -40
sub "内核 tainted 状态 (非 0 需留意，第 12/13 位=未签名/外部模块)"
cat /proc/sys/kernel/tainted 2>/dev/null
sub "/proc/modules 与 lsmod 数量对比"
echo "  /proc/modules: $(wc -l < /proc/modules 2>/dev/null)   lsmod: $(( $(lsmod 2>/dev/null | wc -l) - 1 ))"

hdr "10. 软件包完整性"
if have debsums; then
  sub "debsums：被修改的系统文件（只列 bin/sbin/lib 中的）"
  timeout 300 debsums -c 2>/dev/null | grep -E '^/(bin|sbin|usr/bin|usr/sbin|lib|lib64|usr/lib)' | head -40
elif have dpkg; then
  sub "dpkg -V（仅 5 位为 5 = 内容变化）"
  timeout 300 dpkg -V 2>/dev/null | grep -E '^..5' | grep -E ' /(bin|sbin|usr/bin|usr/sbin|lib|lib64|usr/lib)' | head -40
elif have rpm; then
  sub "rpm -Va（S.5 = 大小/校验变化）"
  timeout 300 rpm -Va 2>/dev/null | grep -E '^..5' | grep -E ' /(bin|sbin|usr/bin|usr/sbin|lib|lib64|usr/lib)' | head -40
else
  echo "(无 debsums/dpkg/rpm)"
fi
sub "最近安装/删除的软件包"
[ -f /var/log/dpkg.log ] && grep -E ' (install|remove) ' /var/log/dpkg.log 2>/dev/null | tail -30
[ -f /var/log/apt/history.log ] && grep -E '^(Start-Date|Commandline)' /var/log/apt/history.log 2>/dev/null | tail -20
[ -f /var/log/yum.log ] && tail -30 /var/log/yum.log 2>/dev/null
have dnf && dnf history list 2>/dev/null | head -15

hdr "11. Docker / 容器（Nginx Proxy Manager 通常跑在 Docker 里）"
if have docker; then
  sub "docker ps -a"
  docker ps -a --no-trunc --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}\t{{.Command}}' 2>/dev/null
  sub "镜像列表"
  docker images 2>/dev/null
  sub "特权容器 / 挂载了宿主机敏感目录的容器（/ , /etc, /root, docker.sock 等）"
  for c in $(docker ps -q 2>/dev/null); do
    docker inspect --format '{{.Name}} privileged={{.HostConfig.Privileged}} pid={{.HostConfig.PidMode}} net={{.HostConfig.NetworkMode}} caps={{.HostConfig.CapAdd}} binds={{.HostConfig.Binds}}' "$c" 2>/dev/null
  done
  docker ps -q 2>/dev/null | xargs -r docker inspect --format '{{.Name}} {{.HostConfig.Binds}}' 2>/dev/null | grep -E 'docker\.sock|:/etc|:/root|:/proc|:/sys| /:/' && flag "有容器挂载了宿主机敏感路径或 docker.sock，见第11节"
  sub "容器内 CPU 占用 (docker stats)"
  timeout 15 docker stats --no-stream 2>/dev/null
  sub "容器内运行的进程（看是否有 xmrig 之类）"
  for c in $(docker ps -q 2>/dev/null); do echo "--- $(docker inspect --format '{{.Name}}' "$c")"; docker top "$c" 2>/dev/null | head -15; done
  sub "docker 守护进程是否对外暴露 2375/2376 端口"
  (ss -tulpn 2>/dev/null || netstat -tulpn 2>/dev/null) | grep -E ':(2375|2376) ' && flag "Docker API 端口 2375/2376 对外监听 —— 极高风险（无认证远程控制）"
  sub "Nginx Proxy Manager 数据目录中的代理规则"
  for d in /data/nginx /opt/npm/data/nginx /root/npm/data/nginx $(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}/nginx{{end}}{{end}}' $(docker ps -q 2>/dev/null) 2>/dev/null); do
    [ -d "$d" ] && { echo "--- $d"; ls -la --time-style=long-iso "$d"/proxy_host "$d"/redirection_host "$d"/stream "$d"/custom 2>/dev/null; grep -rhE 'server_name|proxy_pass|set \$server|set \$port' "$d"/proxy_host/ 2>/dev/null | sort -u | head -40; }
  done
else
  echo "(未安装 docker)"
fi
have podman && podman ps -a 2>/dev/null

hdr "12. Shell 历史（攻击者常留下 wget/curl/chattr/useradd 等痕迹）"
for h in /root/.bash_history /root/.zsh_history /root/.ash_history /home/*/.bash_history /home/*/.zsh_history; do
  [ -f "$h" ] && { echo "--- $h ($(stat -c '%y' "$h"), $(wc -l < "$h") 行)"; tail -80 "$h"; }
done
ls -la /root/.bash_history 2>/dev/null | grep -q ' -> /dev/null' && flag "root 的 .bash_history 被链接到 /dev/null（典型的反取证手法）"
sub "历史中的可疑命令"
grep -hnE 'wget |curl |chattr|useradd|usermod|passwd |authorized_keys|base64|/dev/tcp|nc -|ncat|socat|xmrig|crontab -|history -c|unset HISTFILE|ld\.so\.preload|insmod|iptables -F|setenforce 0' /root/.bash_history /home/*/.bash_history 2>/dev/null | head -40

hdr "13. 日志文件健康度（被清空/删除的日志）"
ls -la --time-style=full-iso /var/log/ 2>/dev/null | head -60
for f in /var/log/auth.log /var/log/secure /var/log/syslog /var/log/messages /var/log/wtmp /var/log/lastlog; do
  [ -e "$f" ] && [ ! -s "$f" ] && flag "$f 存在但为空，可能被擦除"
done
sub "journal 占用与保留"
have journalctl && journalctl --disk-usage 2>/dev/null

hdr "14. 其他"
sub "环境变量中的 LD_PRELOAD / PROMPT_COMMAND"
env | grep -E '^(LD_PRELOAD|LD_LIBRARY_PATH|PROMPT_COMMAND)='
sub "SELinux / AppArmor"
have getenforce && getenforce 2>/dev/null
have aa-status && aa-status --enabled 2>/dev/null && echo "AppArmor enabled"
sub "网卡是否处于混杂模式 (PROMISC = 有人在抓包)"
ip link 2>/dev/null | grep -i promisc && flag "网卡处于混杂模式"
sub "近期 .service/.timer 之外的 XDG autostart"
ls -la /etc/xdg/autostart 2>/dev/null
sub "python/perl/php 反弹 shell 特征进程"
ps -eo pid,user,cmd 2>/dev/null | grep -E '(python[23]?|perl|php|ruby|node) .*(socket|/dev/tcp|pty\.spawn|bash -i|sh -i)' | grep -v grep

hdr "15. 自动标记小结（脚本认为最值得优先核实的项目）"
if [ ${#FLAGS[@]} -eq 0 ]; then
  echo "  脚本未自动命中明显的入侵特征；仍请人工复核第 2/3/5/6/7 节。"
else
  for f in "${FLAGS[@]}"; do echo "  [!!] $f"; done
fi
echo
echo "=== 完成: $(date -u '+%F %T UTC') ==="
