#!/bin/sh
CONF=/etc/config/qpkg.conf
QPKG_NAME="nas-tools"
QPKG_ROOT=`/sbin/getcfg $QPKG_NAME Install_Path -f ${CONF}`
APACHE_ROOT=`/sbin/getcfg SHARE_DEF defWeb -d Qweb -f /etc/config/def_share.info`

PYTHON_PATH=$(/sbin/getcfg Python3  Install_Path -f ${CONF})/python3/bin
#PYTHON_PATH=$(cat $CONF | grep 'Python3'| awk -F'Install_Path = ' ' {print $2}'| awk '$1=$1')/python3/bin
PYTHON_BIN=$PYTHON_PATH/python3

CONFIG_DIR=$QPKG_ROOT/config
CONFIG_FILE=$CONFIG_DIR/config.yaml

RUN_NAME=$QPKG_ROOT/nas-tools.py
DATA_FILE=$QPKG_ROOT/package.tgz

NASTOOL_AUTO_UPDATE=true   #关闭应用后再次启动时自动升级

TIMEOUT=30

cd $QPKG_ROOT
 
running_nastool() {
    PIDS=$(/bin/ps -ef | sed -e 's/^[ \t]*//' | grep -v grep | grep "${RUN_NAME}" | awk '{print $1}')
    for PID in ${PIDS}
	do
	  return 0
	done
	return 1
}

install() {
 
  if [ ! -d "${PYTHON_PATH}" ];then
    /sbin/log_tool  -N "nas-tools" -G "Error" -t2 -uSystem -p127.0.0.1 -mlocalhost -a "[nas-tools] 未发现Python3，请尝试安装Python3后再安装插件。"
    exit
  fi 
 
  if [ -d "${CONFIG_DIR}" ];then
     cp -r ${CONFIG_DIR} ${CONFIG_DIR}_bk
  fi
    
  if [  -f "${DATA_FILE}" ];then
     tar xzvf "${DATA_FILE}"  -C ./
     mv -f ./run.py "${RUN_NAME}"
     chown admin -R "$QPKG_ROOT"
     chmod +x -Rf "$QPKG_ROOT"
     rm -rf "${DATA_FILE}"
  fi
  
  if [ -d "${CONFIG_DIR}_bk" ];then
     cp -r ${CONFIG_DIR}_bk/* ${CONFIG_DIR}/
     rm -rf ${CONFIG_DIR}_bk
  fi
  # 安装pip
    [ ! -f "$PYTHON_PATH"/pip ] && "${PYTHON_BIN}" "./get-pip.py"
    #"${PYTHON_BIN}" ./get-pip.py
  # pip安装依赖包
    hash_old=$(sha256sum ./requirements.txt.old | awk -F ' ' '{print $1}')
    hash_new=$(sha256sum ./requirements.txt | awk -F ' ' '{print $1}')
    if [ "$hash_old" != "$hash_new" ]; then
        "${PYTHON_BIN}" -m pip install -r ./requirements.txt
        cp -rf ./requirements.txt ./requirements.txt.old
    fi
    

}

cron() {    # TODO
  sed -i '/nas-tools.sh update/d' /etc/config/crontab
  if [ "$NASTOOL_AUTO_UPDATE" == "true" ];then
    echo 30 \* \* \* \* /etc/init.d/nas-tools.sh update >>/etc/config/crontab
  fi
  crontab /etc/config/crontab
  /etc/init.d/crond.sh restart
}

update() { 
  v_old=$(cat $QPKG_ROOT/version.py| awk -F"="  ' {print $2}'| awk -F"'"  ' {print $2}'| awk -F"v"  ' {print $2}')
  v_new=$(curl -s "https://api.github.com/repos/jxxghp/nas-tools/releases/latest" |grep tag_name | awk -F":"  ' {print $2}'| awk -F"\""  ' {print $2}'| awk -F"v"  ' {print $2}')
  [ "$v_old" == "$v_new" ] && return 1

  wget -O /tmp/nastools.zip https://codeload.github.com/jxxghp/nas-tools/zip/refs/heads/master
  unzip /tmp/nastools.zip -d /tmp || return 2
  
  cd /tmp/nas-tools-master
#  sed -i 's/web_port: '3000'/web_port: '3003'/g' ./config/config.yaml
  tar czvf ${DATA_FILE} web utils service rmt pt message config *.py *.txt
  
  cd $QPKG_ROOT
  $0 restart
  
  v_new=$(cat $QPKG_ROOT/version.py| awk -F"'"  ' {print $2}'| awk -F"v"  ' {print $2}')
  /sbin/setcfg "$QPKG_NAME" Version $v_new -f ${CONF}
  /sbin/log_tool  -v -N "nas-tools" -G "App Installation" -t0 -uSystem -p127.0.0.1 -mlocalhost -a "[nas-tools] nas-tools 已完成自动升级, 新版本是$v_new"
  rm -rf /tmp/nas-tools-master
  rm -rf /tmp/nastools.zip
  
}

start() {  
  if [ -f "${DATA_FILE}" ];then
     install
  else
     [ "$NASTOOL_AUTO_UPDATE" == "true" ] && update  
  fi
  
	if ! running_nastool ; then
     export NASTOOL_CONFIG=${CONFIG_FILE}
     "${PYTHON_BIN}" "${RUN_NAME}" & 
	fi

    i=0
    while true; do
        if ! running_nastool ; then
#           echo "WAIT: ${i}s of ${TIMEOUT}s"
            sleep 2s
            i=$((i+5))
        else
            break
        fi
        [ $i -ge  ${TIMEOUT}  ] && break
    done

    # 检查进程状态
    if ! running_nastool ; then
        echo "nastool进程已死"
        stop
        return 1
    fi
    
#    web_port=$(cat $QPKG_ROOT/config/config.yaml| awk -F"web_port:"  ' {print $2}'| awk -F"'"  ' {print $2}')  
#    /sbin/setcfg "$QPKG_NAME" Web_Port $web_port -f ${CONF}
    
    return 0
}

# shellcheck disable=SC2120
stop() {
    # 检查进程状态
    if running_nastool ; then
      PIDS=$(/bin/ps -ef | sed -e 's/^[ \t]*//' | grep -v grep | grep "${RUN_NAME}" | awk '{print $1}' | cut -f1 -d' ')
      [ -z "${PIDS}" ] && return 0
      for PID in ${PIDS}
      do
        echo "Try to Kill the $1 process [ ${PID} ]"
        kill -15 "${PID}"
      done
      echo "Wait 3s..."
      sleep 3s
      if running_nastool ; then
        for PID in ${PIDS}
        do
          echo "Kill the $1 process [ ${PID} ]"
          kill -9 "${PID}"
        done
        sleep 2s
      fi
    fi

    return 0
}


case "$1" in
  start)
    ENABLED=$(/sbin/getcfg $QPKG_NAME Enable -u -d FALSE -f $CONF)
    if [ "$ENABLED" != "TRUE" ]; then
        echo "$QPKG_NAME is disabled."
        exit 1
    fi
    
    : ADD START ACTIONS HERE
    
	    start
      cron
    ;;

  stop)
    : ADD STOP ACTIONS HERE 
      stop
      cron
    ;;

  restart)
    stop
    $0 start
    ;;
  remove)
    ;;

  update)
     update
    ;;


  *)
    echo "Usage: $0 {start|stop|restart|update|cron}"
    exit 1
esac

exit 0
