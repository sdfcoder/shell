#!/bin/bash

# 全文变量
install_dir=/data/apps-com/mysql
src_dir=/data/apps-com/mysql/src
port=3306
mysql_passwd=tyjt@123
mysql_version=8.0.27

file=mysql-${mysql_version}-el7-x86_64
mysql_tgz=${file}.tar.gz


# 解压文件，参数是文件名和解压目录
function untar_tgz(){
  echo -e "\033[32m[+] 解压$1中\033[0m"
  tar xf $1
  if [ $? -ne 0 ];then
    echo -e "\033[31m[*] 解压出错，请检查！\033[0m"
    exit 2
  fi
}

# 语法： download_tar_gz 保存的目录 下载链接
# 使用示例： download_tar_gz /data/openssh-update https://mirrors.cloud.tencent.com/openssl/source/openssl-1.1.1h.tar.gz
function download_tar(){

  back_dir=$(pwd)
  file_in_the_dir=$1
  download_file_name=$(echo $2|awk -F'/' '{print $NF}')
  
  cd $file_in_the_dir
  if [ $? -ne 0 ];then
    echo -e "\033[32m文件存放路径${file_in_the_dir}不存在，创建目录\033[0m"
    mkdir -p $file_in_the_dir && cd $file_in_the_dir
    if [ $? -ne 0 ];then
      echo -e "\033[33m目录${file_in_the_dir}创建失败，请检查\033[0m"
      exit 1
    fi
  fi

  ls $download_file_name &> /dev/null
  if [ $? -ne 0 ];then
    echo -e "\033[33m开始下载文件：${download_file_name}\033[0m"
    wget $2
    if [ $? -ne 0 ];then
      echo -e "${download_file_name}下载失败"
      exit 1
    fi
  else
    echo -e "${download_file_name}文件已存在，不需要重复下载"
  fi
  cd $back_dir

}

function add_group_user(){
  if id -g $1 >/dev/null 2>&1;then
    echo -e "$1用户组已存在"
  else
    echo -e "$1用户组不存在，准备创建用户组"
    groupadd $1
  fi

  if id -u $1 >/dev/null 2>&1;then
    echo -e "$1用户已存在"
  else
    echo -e "$1用户不存在，准备创建用户"
    useradd -M -g $1 -s /sbin/nologin $1
  fi
}

download_tar $src_dir https://downloads.mysql.com/archives/get/p/23/file/${mysql_tgz}
cd ${src_dir}
untar_tgz ${mysql_tgz}
mv -f ${file} ${install_dir}/mysql8.0

add_group_user mysql

echo "初始化mysql......"
mkdir -p ${install_dir}/mysql8.0/data
chown -R mysql:mysql ${install_dir}/mysql8.0
cd ${install_dir}/mysql8.0
bin/mysqld --initialize --basedir=${install_dir}/mysql8.0 --datadir=${install_dir}/mysql8.0/data --pid-file=${install_dir}/mysql8.0/data/mysql.pid >/dev/null 2>&1
echo "mysql初始化完毕"
echo "++++++++++++++++++++++++++++++++++++"
chown -R mysql:mysql ${install_dir}/mysql8.0

if [ -f /etc/my.cnf ];then
  mv -f /etc/my.cnf /etc/my.cnf_`date +%F`
  echo -e "\033[31m备份/etc/my.cnf_`date +%F`\033[0m"
fi
echo "初始化/etc/my.cnf......"
cat > /etc/my.cnf << EOF
[client]
socket=${install_dir}/mysql8.0/data/mysql.sock

[mysql]
default-character-set=utf8mb4
socket=${install_dir}/mysql8.0/data/mysql.sock

[mysqld]
skip-grant-tables
skip-name-resolve
port=${port}
socket=${install_dir}/mysql8.0/data/mysql.sock
basedir=${install_dir}/mysql8.0
datadir=${install_dir}/mysql8.0/data
max_connections=200
character-set-server=utf8mb4
default-storage-engine=INNODB
max_allowed_packet=16M
lower_case_table_names = 1
EOF
echo "/etc/my.cnf初始化完毕"


# 设置systemctl控制
if [ -f /lib/systemd/system/mysql.service ];then
  mv -f /lib/systemd/system/mysql.service /lib/systemd/system/mysql.service_`date +%F`
  echo -e "\033[31m备份/lib/systemd/system/mysql.service_`date +%F`\033[0m"
fi
echo -e "设置systemctl启动文件，之后使用systemctl start mysql启动"
cat > /lib/systemd/system/mysql.service << EOF
[Unit]
Description=mysql
After=network.target
[Service]
Type=forking
ExecStart=${install_dir}/mysql8.0/support-files/mysql.server start
ExecStop=${install_dir}/mysql8.0/support-files/mysql.server stop
ExecRestart=${install_dir}/mysql8.0/support-files/mysql.server restart
ExecReload=${install_dir}/mysql8.0/support-files/mysql.server reload
PrivateTmp=true
Restart=always
[Install]
WantedBy=multi-user.target
EOF


echo "export PATH=\${PATH}:${install_dir}/mysql8.0/bin" > /etc/profile.d/mysql.sh
source /etc/profile
if [ -f /usr/local/bin/mysql ];then
  echo "/usr/local/bin/mysql目录有未删除的mysql相关文件，请检查！"
fi
if [ -f /usr/bin/mysql ];then
  echo "/usr/bin/mysql目录有未删除的mysql相关文件，请检查！"
fi
echo "设置完毕"

systemctl enable mysql.service >/dev/null 2>&1
systemctl restart mysql.service
if [ $? -ne 0 ];then
  echo -e "\n\033[31mmysql启动失败，请查看错误信息\033[0m"
  rm -rf ${install_dir}/mysql8.0
  exit 1
else
  echo -e "mysql启动成功，端口号为：\033[32m${port}\033[0m\n"
  cat << EOF
mysql控制命令：
    启动：systemctl start mysql
    重启：systemctl restart mysql
    停止：systemctl stop mysql
EOF

fi


# 修改mysql密码
source /etc/profile
echo "开始修改mysql密码"
echo -e "use mysql;update user set authentication_string = '' where user = 'root'; flush privileges;ALTER USER 'root'@'localhost' IDENTIFIED BY '${mysql_passwd}' PASSWORD EXPIRE NEVER; flush privileges;"
mysql -e "use mysql;update user set authentication_string = '' where user = 'root'; flush privileges;ALTER USER 'root'@'localhost' IDENTIFIED BY '${mysql_passwd}' PASSWORD EXPIRE NEVER; flush privileges;"
if [ $? -ne 0 ];then
  echo -e "\003[31m执行mysql命令修改密码失败，请排查"
  exit 2
else
  echo "mysql修改密码成功"
fi
# 注释/etc/my.cnf中的skip-grant-tables
sed -i "s/skip-grant-tables/# skip-grant-tables/" /etc/my.cnf 
echo -e "\033[32m执行systemctl restart mysql命令，重启mysql中......\033[0m"
systemctl restart mysql
if [ $? -ne 0 ];then
  echo -e "\033[31mmysql重启失败，请查看。\033[0m"
  exit 1
else
  echo -e "\033[32mmysql重启成功。\033[0m"
fi

echo -e "\033[32mmysql安装成功！\033[0m"
