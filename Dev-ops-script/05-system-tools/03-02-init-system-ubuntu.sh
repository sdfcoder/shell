#!/bin/bash
# 本脚本适用于ubuntu



# 带格式的echo函数
function echo_info() {
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m$@\033[0m"
}
function echo_warning() {
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[1;33mWARNING\033[0m] \033[1;37m$@\033[0m"
}
function echo_error() {
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31m$@\033[0m"
}

# 关闭swap
function close_swap(){
    sudo swapoff -a
    sed -i '/swap/s/^/#/' /etc/fstab
    echo_info 已关闭swap
}

#调整dns
function modify_dns(){
    sed -i '1i\nameserver 114.114.114.114\nnameserver 8.8.8.8' /etc/resolv.conf
    if [ greq -q "#DNS" /etc/systemd/resolved.conf ];then
        sed -i '/#DNS/s/^#//; /DNS=/s/$/ 114.114.114 192.168.2.10/' /etc/systemd/resolved.conf
    else
        sed -i '/\[Manager\]/a\DNS=114.144.114.114 192.168.2.10\' /etc/systemd/resolved.conf
    fi  
}

function create_user_rsu(){
    useradd -m -s /bin/bash rsu
    usermod -aG sudo rsu


}

function install_docker(){
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    apt update
    apt install -y docker-ce
    #systemctl status docker
    mkdir -p /etc/docker 
    touch /etc/docker/daemon.json
    cat > damone.json << EOF
{
      "registry-mirrors": ["https://hub-mirror.c.163.com"],
      "runtimes":
      {
        "nvidia":
        {
          "path":"nvidia-container-runtime",
          "runtimeArgs":[]
        }
      },
      "exec-opts": ["native.cgroupdriver=systemd"],
      "log-driver": "json-file",
      "log-opts": {
        "max-size": "200m",
        "max-file": "5"
      },
      "insecure-registries": ["192.168.2.10","harborserver.tyjt-ai.com"],
      "storage-driver": "overlay2"
}
EOF
    systemctl daemon-reload
    groupadd docker
    usermod -aG docker rsu
    systemctl restart docker 
    if [ $? -ne 0 ];then
        echo_error docker安装失败
    fi
    echo_info docker安装成功
    systemctl enable docker
}

function install_chrony(){
    apt install -y chrony
    sed -i '/pool/s/^/#/g; 1i\server ntp.aliyun.com iburst\nallow 192.168.0.0/16' /etc/chrony/chrony.conf
    systemctl restart chrony
    if [ $? -ne 0 ];then
        echo_error chrony安装失败，请排查
        exit 1
    fi    
    echo_info chrony安装成功
}

echo_info 配置hosts文件，解封github
cat >> /etc/hosts <<EOF

# generate by https://github.com/zhegeshijiehuiyouai/RoadToDevOps
13.229.188.59   github.com
52.74.223.119   www.github.com
199.232.69.194  github.global.ssl.fastly.net
185.199.108.153 assets-cdn.github.com
185.199.108.133 user-images.githubusercontent.com
EOF

echo_info 配置历史命令格式
cat > /etc/profile.d/init.sh << EOF
# 历史命令格式
USER_IP=\$(who -u am i 2>/dev/null| awk '{print \$NF}'|sed -e 's/[()]//g')
export HISTTIMEFORMAT="\${USER_IP} > %F %T [\$(whoami)@\$(hostname)] "
EOF

echo_info 调整文件最大句柄数量
grep -E "root.*soft.*nofile" /etc/security/limits.conf &> /dev/null
if [ $? -ne 0 ];then
    sed -i '/End of file/a root soft nofile 65536' /etc/security/limits.conf
fi
grep -E "root.*hard.*nofile" /etc/security/limits.conf &> /dev/null
if [ $? -ne 0 ];then
    sed -i '/root.*soft.*nofile/a root hard nofile 65536' /etc/security/limits.conf
fi

echo_info 内核参数调整
cat > /etc/sysctl.conf << EOF
# sysctl settings are defined through files in
# /usr/lib/sysctl.d/, /run/sysctl.d/, and /etc/sysctl.d/.
#
# Vendors settings live in /usr/lib/sysctl.d/.
# To override a whole file, create a new file with the same in
# /etc/sysctl.d/ and put new settings there. To override
# only specific settings, add a file with a lexically later
# name in /etc/sysctl.d/ and put new settings there.
#
# For more information, see sysctl.conf(5) and sysctl.d(5).

net.ipv4.ip_forward = 1
# 单个进程能打开2千万个句柄
fs.nr_open = 20000000
# 操作系统一共能打开5千万个文件句柄
fs.file-max = 50000000
EOF
sysctl -p &> /dev/null

echo_info 关闭防火墙，如有需求请使用iptables规则，不要使用firewalld
systemctl stop firewalld &> /dev/null
systemctl disable firewalld &> /dev/null
echo_info 关闭selinux
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
setenforce 0

echo_info 调整sshd配置
grep -E "^UseDNS" /etc/ssh/sshd_config &> /dev/null
if [ $? -eq 0 ];then
    sed -i 's/UseDNS.*/UseDNS no/g' /etc/ssh/sshd_config
else
    grep -E "^#UseDNS" /etc/ssh/sshd_config &> /dev/null
    if [ $? -eq 0 ];then
        sed -i 's/#UseDNS.*/UseDNS no/g' /etc/ssh/sshd_config
    else
        echo "UseDNS no" >> /etc/ssh/sshd_config
    fi
fi
systemctl restart sshd

echo_info 配置timezone
echo "Asia/Shanghai" > /etc/timezone

echo_info 禁止定时任务向root发送邮件
sed -i 's/^MAILTO=root/MAILTO=""/' /etc/crontab

echo_info 调整命令提示符显示格式
echo "PS1='\[\e]0;\u@\h: \w\a\]\[\033[01;31m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\\$ '" > /etc/profile.d/PS.sh

if [ -L /usr/bin/vi ];then
        echo_info 配置visudo语法高亮
        echo_info 已设置vi软链接 $(ls -lh /usr/bin/vi | awk '{for (i=9;i<=NF;i++)printf("%s ", $i);print ""}')
elif [ -f /usr/bin/vim ];then
    echo_info 配置visudo语法高亮
    mv -f /usr/bin/vi /usr/bin/vi_bak
    ln -s /usr/bin/vim /usr/bin/vi
fi

echo_warning 各系统参数已调整完毕，请执行 source /etc/profile 刷新环境变量；或者重新打开一个终端，在新终端里操作