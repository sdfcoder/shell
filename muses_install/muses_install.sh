#!/bin/sh
# 这个安装脚本, 默认操作系统的环境是cento7.9的环境, 如果是其他操作系统的环境, 请重写安装脚本, 该脚本可能执行不成功
# 安装脚本直接执行： sh install.sh
export DOCKER_CLIENT_TIMEOUT=1000
export COMPOSE_HTTP_TIMEOUT=1000
export PATH="/usr/local/bin":$PATH
INSTALLER=$(cd "$(dirname "$0")";pwd)

if [ "$(id -u)" != "0" ]; then
   echo "***** Error - This script must be run as root" 1>&2
   exit 1
fi

if [ $# -gt 0 ]; then
    echo -e "usage: sh install.sh"
    exit 1
fi

install_repository(){
    if [ -d "/tmp/repos.d" ]; then
        rm -rf /tmp/repos.d
    fi
    if [ ! -d "$INSTALLER/repository" ]; then
        echo "No repository directory found, exit"
        exit 1
    fi
    mkdir -p /tmp/repos.d
    mv -f /etc/yum.repos.d/* /tmp/repos.d/
    cd $INSTALLER/repository/ && sh deployer.sh
}

clean_repository(){
    if [ -f "/etc/yum.repos.d/CentOS-Local.repo" ]; then
        rm -f /etc/yum.repos.d/CentOS-Local.repo
    fi
    mv -f /tmp/repos.d/* /etc/yum.repos.d/
}

preparation(){
    echo "start to prepare some works..."
    if [ -f "/etc/selinux/config" ]; then
        setenforce 0
        sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
    fi

    systemctl stop firewalld.service
    systemctl disable firewalld.service

    if [ ! -d "/opt/work" ]; then
        mkdir -p /opt/work
    fi
    chmod 750 /opt/work

    install -p -D -m 0755 ${INSTALLER}/bin/gethash /usr/local/bin/gethash
    install -p -D -m 0755 ${INSTALLER}/bin/cert2xml /usr/local/bin/cert2xml
    install -p -D -m 0755 ${INSTALLER}/bin/decrypt /usr/local/bin/decrypt
    install -p -D -m 0755 ${INSTALLER}/bin/rc4 /usr/local/bin/rc4
    \cp ${INSTALLER}/bin/update.pub /etc/update.pub

    # 根据系统不同执行不同的操作
    if [ -f "/etc/debian_version" ]; then
        debian_ver_str=`cat /etc/debian_version`
        debian_ver=(${debian_ver_str//./ })  # 数组 [大版本号，小版本号]

        if [ ${debian_ver[0]} == "11" ];
        then
            # 如果是debian 11 系统，更新其source list
            if [ -f "/etc/apt/sources.list" ]; then
                sed -i "s/^deb cdrom:\[Debian GNU/#deb cdrom:\[Debian GNU/" /etc/apt/sources.list
            fi
            if [ -f "$INSTALLER/resources/tsinghua_source.list" ] && [ -d /etc/apt/sources.list.d ]; then
                \cp -f $INSTALLER/resources/tsinghua_source.list /etc/apt/sources.list.d/ 
            fi
            echo 'yes'
        fi 
    fi


}

install_docker(){
    echo "start to install docker components..."
    cd ${INSTALLER}/docker_install; sh ./install.sh

    # systemctl restart docker
    if [ -d ${INSTALLER}/docker_images ]
    then
        cd ${INSTALLER}/docker_images
        for image in `ls`
        do
            echo "start to load ${image} docker image..."
            extension=${image#*.}
            filename=${image%%.*}
            if [ $extension = "tar.gz" ]; then
                gzip -d ./${image}
            fi
            docker load -i ${filename}.tar
            echo "end to load ${image} docker image."
        done
    else
        echo "unable to load docker images!"
        exit 1
    fi
}

init_compose(){
    echo "start to init compose configure..."
    \cp -f ${INSTALLER}/docker-compose*.yml /opt/work/
    \cp -f ${INSTALLER}/compose_env_file /opt/work/.env
    # set FLOW_WORKER_NUM in /opt/work/.env
    PROCESSOR_NUM=$((`cat /proc/cpuinfo| grep "processor"| wc -l`))
    FLOW_WORKER_NUM=$(($PROCESSOR_NUM/4))
    if [ $FLOW_WORKER_NUM -lt 1 ]
        then FLOW_WORKER_NUM=1
    fi
    sed -i "s/^FLOW_WORKER_NUM.*/FLOW_WORKER_NUM=$FLOW_WORKER_NUM/" /opt/work/.env

    mkdir -p /var/lib/docker/share && ln -sf /var/lib/docker/share /opt/share
    mkdir -p /opt/share && mkdir -p /opt/share/muses_upload && mkdir -p /opt/share/muses_data/projects
    mkdir -p /opt/share/muses_data/report && mkdir -p /opt/share/etc
    \cp -rf ${INSTALLER}/nginx_config /opt/share/etc/
    echo "end to init compose configure."
}

install_muses(){
    echo "start to install muses code packages..."
    cd ${INSTALLER}
    if [ -f ${INSTALLER}/muses_ui.tar.gz ]; then
        tar -zxvf ${INSTALLER}/muses_ui.tar.gz -C /opt/work/
    else
        echo "can not find the muses_ui.tar.gz"
        exit 1
    fi

    if [ -f ${INSTALLER}/muses.tar.gz ]; then
        tar -zxvf ${INSTALLER}/muses.tar.gz -C /opt/work/
    else
        echo "can not find the muses.tar.gz"
        exit 1
    fi
}

deploy_smanager() {
    cd ${INSTALLER}

    if [ ! -f "/etc/resolv.conf" ]; then
        touch /etc/resolv.conf
    fi

    if ( docker image ls | grep smanager -q ); then
        echo "127.0.0.1 redis-server" >> /etc/hosts
        chattr -i /etc/resolv.conf
        sed -i '/nameserver 223.5.5.5/d' /etc/resolv.conf
        echo "nameserver 223.5.5.5" >> /etc/resolv.conf
        sed -i '/nameserver 127.0.0.11/d' /etc/resolv.conf
        sed -i '1i\nameserver 127.0.0.11' /etc/resolv.conf
        sed -i '/search localdomain/d' /etc/resolv.conf
        chattr +i /etc/resolv.conf

        if [ ! -d "/etc/sysconfig" ]; then
            mkdir -p /etc/sysconfig
        fi

    else
        echo "fail to deploy smanager component!"
        exit 1
    fi

    # if [ -d ${INSTALLER}/smanager ]; then
    #     echo "start to deploy smanager"
    #     cd ${INSTALLER}/smanager && sh ./deploy_smanager.sh
    #     echo "127.0.0.1 redis-server" >> /etc/hosts
    #     echo "end to deploy smanager"
    # else
    #     echo "can not find the smanager directory!"
    #     exit 1
    # fi
}

init_data() {
    echo "start to init..."

    # 创建命名卷
    # echo "start to create docker volume..."
    # docker volume create --name redis_data
    # docker volume create --name postgres_data
    # docker volume create --name scancode_data
    # docker volume create --name themis_data
    # docker volume ls
    # echo "end to create docker volume."

    cd /opt/work
    docker-compose up -d postgres-server
    sleep 10
    let i=1
    until docker-compose run --rm muses-web-server python webapi_manage.py makemigrations; do
        echo "check the postgres server whether to start..."
        if [ $i -gt 600 ]; then
            break
        fi
        let i=i+1
        sleep 10
    done

    # 初始化数据
    echo "start to init web data..."
    docker-compose run --rm muses-web-server python webapi_manage.py migrate
    docker-compose run --rm muses-web-server python webapi_manage.py loaddata init_database
    docker-compose run --rm muses-web-server python webapi_manage.py compilemessages
    echo "end to init web data."

    # 初始化themis的规则数据
    echo "start to init themis data..."
    cd /opt/work/
    if [ -d "/opt/data/themis" ];then
        rm -rf /opt/data/themis
    fi
    mkdir -p /opt/data/themis
    cp -rf ${INSTALLER}/data/themis.db /opt/data/themis/themis.db
    # docker-compose run --rm themis-server create_tables --verbose
    # docker-compose run --rm -v ${INSTALLER}/data:/opt/tmp themis-server init_db --verbose /opt/tmp/vulnerability.dat
    echo "end to init themis data."

    # 初始化缓存scancode的规则
    echo "start to init scancode cache..."
    docker-compose run --rm scancode-server python -c "from licensedcode.cache import get_index; get_index()"
    echo "end to init scancode cache."

    # cd /opt/work/muses/

    echo "start to init the smanager..."
    # PYTHONPATH='/opt/work/muses' /opt/work/smanager_env/bin/python ./smanager/smanager_cli.py create_tables
    # PYTHONPATH='/opt/work/muses' /opt/work/smanager_env/bin/python ./smanager/smanager_cli.py init_version
    docker-compose run --rm license-monitor python smanager_cli.py create_tables
    docker-compose run --rm license-monitor python smanager_cli.py init_version
    echo "end to init the smanager."

    # 初始化TEE所需数据
    docker-compose run --rm muses-web-server bash -c "mkdir -p /opt/share/muses_data/microsoft/Team\ Foundation/4.0/Configuration/TEE-Mementos/ && cp /usr/local/share/TEE-CLC-14.137.0/com.microsoft.tfs.client.productid.xml /opt/share/muses_data/microsoft/Team\ Foundation/4.0/Configuration/TEE-Mementos/"

    # 创建序列号
    echo "start to create product serial..."
    # PYTHONPATH='/opt/work/muses' /opt/work/smanager_env/bin/python ./smanager/smanager_cli.py gen_product_serial -s
    # docker-compose run --rm license-monitor python smanager_cli.py gen_product_serial -s
    /usr/local/bin/gethash > /opt/share/etc/product_serial
    serial=$(cat /opt/share/etc/product_serial)
    echo -e "\033[32m ${serial} \033[0m"
    echo "end to create product serial."
}

run_services(){
    # run all server and worker
    echo "start to up the all docker container, please wait..."
    cd /opt/work && docker-compose --compatibility up -d
    # sleep 30
    # echo "start to up the smanager workers, please wait..."
    # systemctl start supervisor
    # supervisorctl -c /opt/work/supervisor/supervisord.conf start all
    echo "finish to run all components"
}


install_allinone(){
    preparation
    install_docker
    install_muses
    deploy_smanager
    init_compose
    init_data
    run_services
}

install_allinone