#!/bin/sh

INSTALLER=$(cd `dirname $0`; pwd)

if [ "$(id -u)" != "0" ]; then
   echo "***** Error - This script must be run as root" 1>&2
   exit 1
fi

remove_docker_images(){
    cd /opt/work
    docker-compose down
    # docker image ls -q | xargs docker rmi 1>/dev/null 2>&1
    image_names="scancode themis codeaudit muses-postgres muses-redis muses-nginx smanager muses firmware scanrepo aura"
    for name in ${image_names}
    do
        echo "Start to delete ${name} image"
        docker image ls | grep ${name} | awk '{print $3}' | xargs docker rmi 1>/dev/null 2>&1
        echo "complete to delete ${name} image"
    done
    docker system prune -f
}

remove_muses(){
    if [ -d "/opt/work/muses_ui" ]; then
        rm -rf /opt/work/muses_ui
    fi

    if [ -d "/opt/work/muses" ]; then
        rm -rf /opt/work/muses
    fi

    if [ -d "/opt/share" ]; then
        rm -rf /opt/share
    fi

    if [ -L "/opt/share" ]; then
        rm -rf /opt/share
    fi

    if [ -d "/var/lib/share" ]; then
        rm -rf /var/lib/share
    fi

    if [ -d "/var/lib/docker/share" ]; then
        rm -rf /var/lib/docker/share
    fi

    if [ -d "/var/log/webapi" ]; then
        rm -rf /var/log/webapi
    fi

    if [ -d "/opt/data/themis" ];then
        rm -rf /opt/data/themis
    fi

    if [ -d "/opt/data/aura" ];then
        rm -rf /opt/data/aura
    fi

    chattr -i /etc/resolv.conf
    sed -i '/nameserver 127.0.0.11/d' /etc/resolv.conf
}

remove_smanager(){
    if (systemctl status -q supervisor &> /dev/null); then
        systemctl stop supervisor
        systemctl disable supervisor
        pkill -9 supervisord
        if (ps uax | grep -q python); then
            pkill -9 python
        fi
        rm -rf /usr/lib/systemd/system/supervisor.service
        if [ -S "/var/lib/supervisor.sock" ]; then
            rm -rf /var/lib/supervisor.sock
        fi
        if [ -d "/opt/work/supervisor" ]; then
            rm -rf /opt/work/supervisor
        fi
        rm -rf /usr/bin/supervisorctl
        rm -rf /usr/bin/supervisord
        if [ -d "/opt/work/smanager_env" ]; then
            rm -rf /opt/work/smanager_env
        fi
        if [ -d "/var/log/supervisor" ]; then
            rm -rf /var/log/supervisor
        fi
    fi
    sed -i '/127.0.0.1 redis-server/d' /etc/hosts
}

remove_compose(){
    if [ -f "/opt/work/docker-compose.yml" ]; then
        rm -rf /opt/work/docker-compose.yml
    fi
    if [ -f "/opt/work/.env" ]; then
        rm -rf /opt/work/.env
    fi
    if ( docker volume ls | grep -q postgres_data ); then
        docker volume rm work_postgres_data
    fi
    if ( docker volume ls | grep -q redis_data ); then
        docker volume rm work_redis_data
    fi
    if ( docker volume ls | grep -q scancode_data ); then
        docker volume rm work_scancode_data
    fi
    if ( docker volume ls | grep -q themis_data ); then
        docker volume rm work_themis_data
    fi
    if ( docker volume ls | grep -q codeaudit_data ); then
        docker volume rm work_codeaudit_data
    fi
    if ( docker volume ls | grep -q codeaudit_conf ); then
        docker volume rm work_codeaudit_conf
    fi
    if ( docker volume ls | grep -q smanager_data ); then
        docker volume rm work_smanager_data
    fi

    if [ -d "/var/log/codeaudit" ]; then
        rm -rf /var/log/codeaudit
    fi

    docker volume prune -f
    docker network prune -f
}

uninstall_mongodb(){
    if [ -d "/opt/work/mongodb" ]; then
        cd /opt/work/mongodb
        docker-compose down
    else
        if ( docker ps -a | grep "mongodb_mongodb-server" -q ); then
            docker stop work_mongodb-server_1; docker rm work_mongodb-server_1
        fi
    fi

    if ( docker image ls | grep -q "mongodb" ); then
        docker image ls | grep "mongodb" | awk '{print $3}' | xargs docker rmi
    fi
    if ( docker volume ls | grep -q mongodb_data ); then
        docker volume rm mongodb_mongodb_data
        docker volume prune -f
    fi
    if ( docker volume ls | grep -q mongodb_log ); then
        docker volume rm mongodb_mongodb_log
        docker volume prune -f
    fi

    if [ -d "/opt/work/mongodb" ]; then
        rm -rf /opt/work/mongodb
    fi
}

uninstall_allinone(){
    echo "start to uninstall the muses system"
    uninstall_mongodb
    remove_docker_images
    remove_smanager
    remove_muses
    remove_compose
    echo "end to uninstall the muses system"
}

uninstall_allinone
