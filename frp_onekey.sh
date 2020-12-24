#!/usr/bin/env bash
# @Author: Seaky
# @Date:   2020/11/11 15:39

# sudo bash frp_onekey.sh -a install -c {frps|frpc} [-t {instance}]

#########
# param #
#########

NAME="frp"
INSTALL_VERSION="201011"
FRP_VERSION=0.34.2
FRP_DOWNLOAD_GITHUB="https://github.com/fatedier/frp/releases/download"
FRP_DOWNLOAD_JP="https://download.fastgit.org/fatedier/frp/releases/download"
FRP_DOWNLOAD_HK="https://g.ioiox.com/${FRP_DOWNLOAD_GITHUB}"
LOCAL_CONFIG_DIR="/etc/${NAME}"
LOCAL_BIN_DIR="/usr/bin"
LOCAL_SYSTEMD_DIR="/lib/systemd/system"
LOCAL_LOG_DIR="/var/log/${NAME}"


###########
# prepare #
###########

set_text_color(){
    COLOR_RED='\E[1;31m'
    COLOR_GREEN='\E[1;32m'
    COLOR_YELLOW='\E[1;33m'
    COLOR_BLUE='\E[1;34m'
    COLOR_PINK='\E[1;35m'
    COLOR_PINKBACK_WHITEFONT='\033[45;37m'
    COLOR_GREEN_LIGHTNING='\033[32m \033[05m'
    COLOR_END='\E[0m'
}
set_text_color

get_char(){
    SAVEDSTTY=`stty -g`
    stty -echo
    stty cbreak
    dd if=/dev/tty bs=1 count=1 2> /dev/null
    stty -raw
    stty echo
    stty $SAVEDSTTY
}

fun_randstr(){
    strNum=$1
    [ -z "${strNum}" ] && strNum="16"
    strRandomPass=""
    strRandomPass=`tr -cd '[:alnum:]' < /dev/urandom | fold -w ${strNum} | head -n1`
    echo ${strRandomPass}
}

fun_randint(){
    min=$1
    max=$(($2-$min+1))
    num=$(($RANDOM+1000000000))
    echo $(($num%$max+$min))
}

check_root(){
    if [[ $EUID -ne 0 ]]; then
        echo "Error:This script must be run as root!" 1>&2
        exit 1
    fi
}

# Get CentOs version
centos_version_get(){
    if [[ -s /etc/redhat-release ]];then
        grep -oE  "[0-9.]+" /etc/redhat-release
    else
        grep -oE  "[0-9.]+" /etc/issue
    fi
}

# CentOS version
centos_version_diff(){
    local code=$1
    local version="`centos_version_get`"
    local main_ver=${version%%.*}
    if [ $main_ver == $code ];then
        return 0
    else
        return 1
    fi
}

check_centos_version(){
if centos_version_diff 5; then
    echo "Not support CentOS 5.x, please change to CentOS 6,7 or Debian or Ubuntu or Fedora and try again."
    exit 1
fi
}

# Check OS bit
check_os_bit(){
    ARCHS=""
    if [[ `getconf WORD_BIT` = '32' && `getconf LONG_BIT` = '64' ]] ; then
        Is_64bit='y'
        ARCHS="amd64"
    else
        Is_64bit='n'
        ARCHS="386"
    fi
}

check_os(){
    if grep -Eqi "Debian" /etc/issue || grep -Eq "Debian" /etc/*-release; then
        OS=Debian
    elif grep -Eqi "Ubuntu" /etc/issue || grep -Eq "Ubuntu" /etc/*-release; then
        OS=Ubuntu
    else
        echo "Not support OS!"
        exit 1
    fi
    check_os_bit
}

check_packet(){
    local wget_flag=''
    local killall_flag=''
    local netstat_flag=''
    wget --version > /dev/null 2>&1
    wget_flag=$?
    killall -V >/dev/null 2>&1
    killall_flag=$?
    netstat --version >/dev/null 2>&1
    netstat_flag=$?
    if [[ ${wget_flag} -gt 1 ]] || [[ ${killall_flag} -gt 1 ]] || [[ ${netstat_flag} -gt 6 ]];then
        show_process "Install support packs..."
        if [ "${OS}" == 'CentOS' ]; then
            yum install -y wget psmisc net-tools
        else
            apt-get -y update && apt-get -y install wget psmisc net-tools
        fi
    fi
}


show_banner(){
    str_repeat(){
        eval printf -- "$1%0.s" {1..$2}
    }
    indent=2
    title=$@
    len=$((${#title} + $indent + $indent))
    echo
    echo "+"$(str_repeat "-" $len)"+"
    printf "|%$((${len}+1))s\n" "|"
    printf "|%$((${#title} + $indent))s%$((${indent}+1))s\n" "$title" "|"
    printf "|%$((${len}+1))s\n" "|"
    echo "+"$(str_repeat "-" $len)"+"
    echo
}

fun_set_param(){
    eval set_${1}=$2
    echo -e "${INSTANCE_FULLNAME} $1: ${COLOR_YELLOW}${2}${COLOR_END}"
    echo -e
}

fun_input_param(){
    default_param=$2
    input_param=$2
    echo ""
    echo -n -e "Please input ${INSTANCE_FULLNAME} ${COLOR_GREEN}${1}${COLOR_END}"
    [ -n "$input_param" ] && echo -n -e "(Default : ${default_param})"
    read -e -p ": " input_param
    [ -z "$input_param" ] && input_param=${default_param}
    [ -z "$input_param" ] && show_error "$1 can't be empty." && exit 1
    fun_set_param $1 $input_param
}

fun_choice_yes_or_no(){
    unset _choice
    val_name=$1
    shift
    str_prompt=$@
    echo -e -n "${COLOR_GREEN}$@ ${COLOR_END}([y]es or [n]o, default [y]) "
    read _choice
    case "${_choice}" in
        1|yes|y)
            eval choice_${val_name}=true
            ;;
        2|no|n)
            eval choice_${val_name}=false
            ;;
        [eE][xX][iI][tT])
            exit 1
            ;;
        *)
            eval choice_${val_name}=true
            ;;
    esac
}

fun_get_local_ip(){
    echo `ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | grep -v '^168' |  sed -n '1p'`
}

show_title(){
    show_banner "FRP Onekey"
}

show_process(){
    echo -e "${COLOR_GREEN}- $1${COLOR_END}"
}

show_error(){
    echo -e "${COLOR_RED}* $1${COLOR_END}"
}

###########
# install #
###########

pre_install(){
    show_process "Checking requirements of installment..."
    check_root
    check_os
    check_packet
}

check_tarball(){
    if [ -s "${tarball_name}" ]
    then
        `tar ztf "${tarball_name}" > /dev/null 2>&1` || rm ${tarball_name}
    fi
}

install_download_frp(){
    BIN_FRP=${LOCAL_BIN_DIR}/${CHAR}
    req_down=true
    if [ -s "${BIN_FRP}" ]
    then
        exist_version=`${BIN_FRP} -v`
        [ $exist_version == $FRP_VERSION ] && req_down=false
    fi
    tarball_stem="frp_${FRP_VERSION}_linux_${ARCHS}"
    tarball_name="${tarball_stem}.tar.gz"
    $req_down || return 1

    check_tarball
    rm -fr ${tarball_stem}

    if [ ! -s "${tarball_name}" ]
    then
        if [ -z "$FRP_DOWNLOAD_SERVER" ]
        then
            echo
            echo -e "${COLOR_GREEN}Choice download server:${COLOR_END}"
            echo    "1: Github (default)"
            echo    "2: HK"
            echo    "3: JP"
            echo    "-------------------------"
            read -e -p "Enter your choice (1, 2, 3 or exit. default [1]): " str_choice_source
            case "${str_choice_source}" in
                1)
                    FRP_DOWNLOAD_SERVER=$FRP_DOWNLOAD_GITHUB
                    ;;
                2)
                    FRP_DOWNLOAD_SERVER=$FRP_DOWNLOAD_HK
                    ;;
                3)
                    FRP_DOWNLOAD_SERVER=$FRP_DOWNLOAD_JP
                    ;;
                [eE][xX][iI][tT])
                    exit 1
                    ;;
                *)
                    FRP_DOWNLOAD_SERVER=$FRP_DOWNLOAD_GITHUB
                    ;;
            esac
        fi
        frp_download_url="${FRP_DOWNLOAD_SERVER}/v${FRP_VERSION}/${tarball_name}"
        show_process "Try retrieve ${frp_download_url}${COLOR_END}"
        wget --no-check-certificate ${frp_download_url}
    fi
    if [ -s "${tarball_stem}.tar.gz" ]; then
        tar xzf ${tarball_name}
        cp ${tarball_stem}/${CHAR} ${LOCAL_BIN_DIR}/
    else
        show_error " ${COLOR_RED}Download failed${COLOR_END}"
        exit 1
    fi
}

##########
# config #
##########

# Check port
fun_check_port(){
    port_flag=""
    strCheckPort=""
    input_port=""
    port_flag="$1"
    strCheckPort="$2"
    if [ ${strCheckPort} -ge 1 ] && [ ${strCheckPort} -le 65535 ]; then
        checkServerPort=`netstat -ntulp | grep "\b:${strCheckPort}\b"`
        if [ -n "${checkServerPort}" ]; then
            echo ""
            echo -e "${COLOR_RED}Error:${COLOR_END} Port ${COLOR_GREEN}${strCheckPort}${COLOR_END} is ${COLOR_PINK}used${COLOR_END},view relevant port:"
            netstat -ntulp | grep "\b:${strCheckPort}\b"
            fun_input_${port_flag}_port
        else
            input_port="${strCheckPort}"
        fi
    else
        echo "Input error! Please input correct numbers."
        fun_input_${port_flag}_port
    fi
}

fun_check_number(){
    num_flag=""
    strMaxNum=""
    strCheckNum=""
    input_number=""
    num_flag="$1"
    strMaxNum="$2"
    strCheckNum="$3"
    if [ ${strCheckNum} -ge 1 ] && [ ${strCheckNum} -le ${strMaxNum} ]; then
        input_number="${strCheckNum}"
    else
        echo "Input error! Please input correct numbers."
        fun_input_${num_flag}
    fi
}

fun_create_log_dir(){
    mkdir -p $LOCAL_LOG_DIR
    chmod 777 ${LOCAL_LOG_DIR}
}

configure_frps_prompt(){
    echo -e "————————————————————————————————————————————"
    echo -e "     ${COLOR_RED}Please input $INSTANCE_FULLNAME setting:${COLOR_END}"
    echo -e "————————————————————————————————————————————"
    fun_input_param bind_addr "0.0.0.0"
    fun_input_param bind_port 57000
    fun_input_param token `fun_randstr 16`
    fun_input_param vhost_http_port 57080
    fun_input_param vhost_https_port 57443
    $IS_MAIN && _dashboard_port=57500 || _dashboard_port=`fun_randint 57501 57599`
    fun_input_param dashboard_port $_dashboard_port
    fun_set_param dashboard_user "admin"
    fun_input_param dashboard_pwd `fun_randstr 8`
    fun_input_param subdomain_host "your.domain"
    fun_set_param max_pool_count 30
    fun_set_param kcp true
    fun_set_param tcp_mux true
    fun_input_param log_file ${LOCAL_LOG_DIR}/${INSTANCE_FULLNAME}.log
    fun_set_param log_level "info"
    fun_set_param log_max_days 7

    echo "============== Instance of $INSTANCE_FULLNAME =============="
    echo -e "Bind address       : ${COLOR_GREEN}${set_bind_addr}${COLOR_END}"
    echo -e "Bind port          : ${COLOR_GREEN}${set_bind_port}${COLOR_END}"
    echo -e "kcp support        : ${COLOR_GREEN}${set_kcp}${COLOR_END}"
    echo -e "vhost http port    : ${COLOR_GREEN}${set_vhost_http_port}${COLOR_END}"
    echo -e "vhost https port   : ${COLOR_GREEN}${set_vhost_https_port}${COLOR_END}"
    echo -e "Dashboard port     : ${COLOR_GREEN}${set_dashboard_port}${COLOR_END}"
    echo -e "Dashboard user     : ${COLOR_GREEN}${set_dashboard_user}${COLOR_END}"
    echo -e "Dashboard password : ${COLOR_GREEN}${set_dashboard_pwd}${COLOR_END}"
    echo -e "token              : ${COLOR_GREEN}${set_token}${COLOR_END}"
    echo -e "subdomain_host     : ${COLOR_GREEN}${set_subdomain_host}${COLOR_END}"
    echo -e "tcp_mux            : ${COLOR_GREEN}${set_tcp_mux}${COLOR_END}"
    echo -e "Max Pool count     : ${COLOR_GREEN}${set_max_pool_count}${COLOR_END}"
    echo -e "Log level          : ${COLOR_GREEN}${set_log_level}${COLOR_END}"
    echo -e "Log max days       : ${COLOR_GREEN}${set_log_max_days}${COLOR_END}"
    echo -e "Log file           : ${COLOR_GREEN}${set_log_file}${COLOR_END}"
    echo "=============================================="
    echo ""
    echo "Press any key to start...or Press Ctrl+c to cancel"

    char=`get_char`
    echo $char
}

configure_frps_generate_ini(){
    [ -s $CONFIG_FILE ] && ( show_process "$CONFIG_FILE is exist, backup to ${CONFIG_FILE}.backup"; cp $CONFIG_FILE ${CONFIG_FILE}.backup )
    show_process "Write $INSTANCE_FULLNAME config to ${COLOR_YELLOW}${CONFIG_FILE}"

    # Config file
    cat > ${CONFIG_FILE} <<-EOF
# [common] is integral section
[common]
# A literal address or host name for IPv6 must be enclosed
# in square brackets, as in "[::1]:80", "[ipv6-host]:http" or "[ipv6-host%zone]:80"
bind_addr = 0.0.0.0
bind_port = ${set_bind_port}

# udp port used for kcp protocol, it can be same with 'bind_port'
# if not set, kcp is disabled in frps
kcp_bind_port = ${set_bind_port}

# auth token
token = ${set_token}

# if you want to configure or reload frps by dashboard, dashboard_port must be set
dashboard_port = ${set_dashboard_port}

# dashboard assets directory(only for debug mode)
dashboard_user = ${set_dashboard_user}
dashboard_pwd = ${set_dashboard_pwd}

# assets_dir = ./static
vhost_http_port = ${set_vhost_http_port}
vhost_https_port = ${set_vhost_https_port}

# console or real logFile path like ./frps.log
log_file = ${set_log_file}
# debug, info, warn, error
log_level = ${set_log_level}
log_max_days = ${set_log_max_days}

# It is convenient to use subdomain configure for http、https type when many people use one frps server together.
subdomain_host = ${set_subdomain_host}
# only allow frpc to bind ports you list, if you set nothing, there won't be any limit
#allow_ports = 1-65535

# pool_count in each proxy will change to max_pool_count if they exceed the maximum value
max_pool_count = ${set_max_pool_count}

# if tcp stream multiplexing is used, default is true
tcp_mux = ${set_tcp_mux}
EOF
    $fun_create_log_dir && fun_create_log_dir
}


configure_frpc_prompt(){
    echo -e "————————————————————————————————————————————"
    echo -e "     ${COLOR_RED}Please input $INSTANCE_FULLNAME setting:${COLOR_END}"
    echo -e "————————————————————————————————————————————"
    fun_input_param server_addr
    fun_input_param server_port 57000
    fun_input_param token
    fun_input_param client_name `hostname`

    fun_set_param admin_addr `fun_get_local_ip`
    $IS_MAIN && _admin_port=57001 || _admin_port=`fun_randint 57002 57099`
    fun_set_param admin_port $_admin_port
    fun_set_param admin_user "admin"
    fun_input_param admin_pwd `fun_randstr 8`

    fun_set_param protocol "tcp"
    fun_set_param max_pool_count 30
    fun_set_param tcp_mux true
    fun_input_param log_file ${LOCAL_LOG_DIR}/${INSTANCE_FULLNAME}.log
    fun_set_param log_level "info"
    fun_set_param log_max_days 7


    configure_frpc_prompt_ssh

    echo "============== Instance of $INSTANCE_FULLNAME =============="
    echo -e "FRP Server IP      : ${COLOR_GREEN}${set_server_addr}${COLOR_END}"
    echo -e "Bind port          : ${COLOR_GREEN}${set_server_port}${COLOR_END}"
    echo -e "token              : ${COLOR_GREEN}${set_token}${COLOR_END}"
    echo -e "Client Name        : ${COLOR_GREEN}${set_client_name}${COLOR_END}"
    echo -e "protocol           : ${COLOR_GREEN}${set_protocol}${COLOR_END}"
    echo -e "Max Pool count     : ${COLOR_GREEN}${set_max_pool_count}${COLOR_END}"
    echo -e "Admin addr         : ${COLOR_GREEN}${set_admin_addr}${COLOR_END}"
    echo -e "Admin port         : ${COLOR_GREEN}${set_admin_port}${COLOR_END}"
    echo -e "Admin user         : ${COLOR_GREEN}${set_admin_user}${COLOR_END}"
    echo -e "Admin pwd          : ${COLOR_GREEN}${set_admin_pwd}${COLOR_END}"
    echo -e "Log level          : ${COLOR_GREEN}${set_log_level}${COLOR_END}"
    echo -e "Log max days       : ${COLOR_GREEN}${set_log_max_days}${COLOR_END}"
    echo -e "Log file           : ${COLOR_GREEN}${set_log_file}${COLOR_END}"
    $ssh_fwd_enabled && echo -e "SSH Foward         : ${COLOR_GREEN}${set_server_addr}:${set_ssh_map_to_server_port} -> ${set_local_ssh_addr}:${set_local_ssh_port}${COLOR_END}"
    echo "=============================================="
    echo ""
    echo "Press any key to start...or Press Ctrl+c to cancel"

    char=`get_char`
    echo $char
}

configure_frpc_prompt_ssh(){
    sshd_config='/etc/ssh/sshd_config'
    ssh_fwd_enabled=false
    if [ -s "$sshd_config" ]
    then
        fun_choice_yes_or_no ssh_fwd "Enable ssh forward?"
        if $choice_ssh_fwd
        then
            fun_input_param local_ssh_addr "127.0.0.1"
            ssh_port=`grep -E "Port [0-9]+" $sshd_config | awk '{print $2}'`
            fun_input_param local_ssh_port ${ssh_port:-22}
            fun_input_param ssh_map_to_server_port `fun_randint 50000 56000`
            ssh_fwd_enabled=true
         fi
    fi
}

configure_frpc_generate_ini(){

    [ -s $CONFIG_FILE ] && ( show_process "$CONFIG_FILE is exist, backup to ${CONFIG_FILE}.backup"; cp $CONFIG_FILE ${CONFIG_FILE}.backup )
    show_process "Write ${INSTANCE_FULLNAME} config to ${COLOR_YELLOW}$CONFIG_FILE"

    # Config file
    cat > ${CONFIG_FILE} <<-EOF
[common]
server_addr = ${set_server_addr}
server_port = ${set_server_port}
token = ${set_token}

log_file = ${set_log_file}
log_level = ${set_log_level}
log_max_days = ${set_log_max_days}

admin_addr = ${set_admin_addr}
admin_port = ${set_admin_port}
admin_user = ${set_admin_user}
admin_pwd = ${set_admin_pwd}

tcp_mux = ${set_tcp_mux}
user = ${set_client_name}
protocol = ${set_protocol}

EOF

    if $ssh_fwd_enabled
    then
    cat >> ${CONFIG_FILE} <<-EOF
[ssh]
type = tcp
local_ip = $set_local_ssh_addr
local_port = $set_local_ssh_port
remote_port = $set_ssh_map_to_server_port

EOF
    fi

cat >> ${CONFIG_FILE} <<-EOF

#[ssh]
#type = tcp
#local_ip = 127.0.0.1
#local_port = 22
# limit bandwidth for this proxy, unit is KB and MB
#bandwidth_limit = 1MB
# true or false, if true, messages between frps and frpc will be encrypted, default is false
#use_encryption = false
# if true, message will be compressed
#use_compression = false
# remote port listen by frps
#remote_port = 6001

#[web01]
#type = http
#local_ip = 127.0.0.1
#local_port = 80
#use_encryption = false
#use_compression = true
# http username and password are safety certification for http protocol
# if not set, you can access this custom_domains without certification
#http_user = admin
#http_pwd = admin
# if domain for frps is frps.com, then you can access [web01] proxy by URL http://test.frps.com
#subdomain = web01
#custom_domains = web02.yourdomain.com
# locations is only available for http type
#locations = /,/pic
#host_header_rewrite = example.com
# params with prefix "header_" will be used to update http request headers
#header_X-From-Where = frp

EOF
    $fun_create_log_dir && fun_create_log_dir
}

service_enable(){
    [ "${SERVICE_MANAGER}" = "systemd" ] && systemctl enable $INSTANCE_FULLNAME || update-rc.d $INSTANCE_FULLNAME defaults
}

service_disable(){
    [ "${SERVICE_MANAGER}" = "systemd" ] && systemctl enable $INSTANCE_FULLNAME || update-rc.d -f $INSTANCE_FULLNAME remove
}


service_make_init(){
    show_process "make init file /etc/init.d/$INSTANCE_FULLNAME"
    cat > /etc/init.d/$INSTANCE_FULLNAME <<-EOF
#!/bin/bash
### BEGIN INIT INFO
# Provides:          $INSTANCE_FULLNAME
# Required-Start:    \$all
# Required-Stop:
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start service $INSTANCE_FULLNAME if it exist

### END INIT INFO

case "\$1" in
*)
    ${LOCAL_BIN_DIR}/$INSTANCE_FULLNAME \$1
;;
esac
EOF
    chmod +x /etc/init.d/${INSTANCE_FULLNAME}
}

service_install(){
    make_shortcut
    show_process "Enable $INSTANCE_FULLNAME service with ${COLOR_PINK}$SERVICE_MANAGER ${COLOR_GREEN}"
    if [ "${SERVICE_MANAGER}" = "systemd" ]
    then
        cp ${tarball_stem}/systemd/${CHAR}@.service ${LOCAL_SYSTEMD_DIR}
        sed -i "s/\/%i.ini/\/${CHAR}@%i.ini/" ${LOCAL_SYSTEMD_DIR}/${CHAR}@.service
    elif [ "${SERVICE_MANAGER}" = "init" ]
    then
        service_make_init
    fi
    service_enable
    ${LOCAL_BIN_DIR}/$INSTANCE_FULLNAME restart
#    systemctl status $INSTANCE_FULLNAME
    if [ $? -ne 0 ]
    then
        tail $LOCAL_LOG_DIR/${INSTANCE_FULLNAME}.log
    elif [ "$CHAR" = "frpc" ]
    then
        sleep 3
        $INSTANCE_FULLNAME status
    fi
}

make_shortcut(){
    if [ "$SERVICE_MANAGER" = "systemd" ]
    then
        if [ "$CHAR" = "frps" ]
        then
            cat > ${LOCAL_BIN_DIR}/$INSTANCE_FULLNAME <<-EOF
#!/bin/bash
[ -z "\$1" ] && echo "$INSTANCE_FULLNAME {start|stop|restart|status}" && exit 1
case "\$1" in
start|stop|restart)
    systemctl \$1 $INSTANCE_FULLNAME
    systemctl status $INSTANCE_FULLNAME
    ;;
status)
    systemctl status $INSTANCE_FULLNAME
    ;;
*)
    echo "$INSTANCE_FULLNAME {start|stop|restart}"
    ;;
esac
EOF
        else
            cat > ${LOCAL_BIN_DIR}/$INSTANCE_FULLNAME <<-EOF
#!/bin/bash
[ -z "\$1" ] && echo "$INSTANCE_FULLNAME {start|stop|restart|status|reload|config}" && exit 1

status(){
    ${LOCAL_BIN_DIR}/$CHAR -c ${LOCAL_CONFIG_DIR}/$INSTANCE_FULLNAME.ini status
}

reload(){
    ${LOCAL_BIN_DIR}/$CHAR -c ${LOCAL_CONFIG_DIR}/$INSTANCE_FULLNAME.ini reload
    status
}

config(){
    vi ${CONFIG_FILE}
    reload
}

case "\$1" in
start|stop|restart)
    systemctl \$1 $INSTANCE_FULLNAME
    systemctl status $INSTANCE_FULLNAME
    ;;
reload)
    reload
    ;;
status)
    status
    ;;
config)
    config
    ;;
*)
    echo "$INSTANCE_FULLNAME {start|stop|restart|status|reload}"
    ;;
esac
EOF
        fi
    else
        cat > ${LOCAL_BIN_DIR}/$INSTANCE_FULLNAME <<-EOF
#!/bin/bash

start(){
    ${LOCAL_BIN_DIR}/${CHAR} -c ${CONFIG_FILE} &
}

stop(){
    get_pid
    if [ -n "\$pid" ]
    then
        for p in \$pid
        do
            kill \$p
        done
    fi
}

restart(){
    stop
    start
}

get_pid(){
    pid=\`ps -ef | grep "${CONFIG_FILE}" | grep -v "grep" | awk '{print \$2}'\`
}

is_alive(){
    get_pid
    [ -n "\$pid" ] && echo \$pid || echo "service $INSTANCE_FULLNAME is stopped"
}

status(){
    is_alive
    sleep 1
    [ -n "\$pid" -a "${CHAR}" = "frpc" ] && ${LOCAL_BIN_DIR}/${CHAR} -c ${CONFIG_FILE} status
}

reload(){
    if [ "${CHAR}" != "frpc" ]
    then
        echo "reload is only for frpc"
        exit
    fi
    is_alive
    if [ -n "\$pid" ]
    then
        ${LOCAL_BIN_DIR}/${CHAR} -c ${CONFIG_FILE} reload
        ${LOCAL_BIN_DIR}/${CHAR} -c ${CONFIG_FILE} status
    fi
}

config(){
    vi ${CONFIG_FILE}
    reload
}

case "\$1" in
start)
    restart
    status
;;
stop)
    stop
    status
;;
restart)
    restart
    status
;;
status)
    status
;;
reload)
    reload
;;
config)
    config
;;
*)
    echo "$INSTANCE_FULLNAME {start|stop|restart|status|reload|config}"
esac
EOF
    fi
    chmod a+x ${LOCAL_BIN_DIR}/$INSTANCE_FULLNAME
    show_process "Create shortcut ${COLOR_YELLOW}${LOCAL_BIN_DIR}/${INSTANCE_FULLNAME}"
}


configure_frps(){
    configure_frps_prompt
    configure_frps_generate_ini
}

configure_frpc(){
    configure_frpc_prompt
    configure_frpc_generate_ini
}

configure(){
    [ ! -s "${LOCAL_BIN_DIR}/${CHAR}" ] && show_error "Bin ${LOCAL_BIN_DIR}/${CHAR} is not exist, install first!" && show_usage && exit 1
    mkdir -p $LOCAL_CONFIG_DIR
    CONFIG_FILE=$LOCAL_CONFIG_DIR/${INSTANCE_FULLNAME}.ini
    clear
    configure_${CHAR}
    show_process "Configure ${INSTANCE_FULLNAME} done"
}

uninstall_frp(){
    uninst(){
        show_process "Removing $1..."
        rm $LOCAL_SYSTEMD_DIR/$1.service $LOCAL_SYSTEMD_DIR/$1@.service 2> /dev/null
        rm /etc/init.d/$1 $LOCAL_SYSTEMD_DIR/$1@* 2> /dev/null
        rm $LOCAL_BIN_DIR/$1 $LOCAL_BIN_DIR/$1@* 2> /dev/null
    }
    show_title
    show_process "Removing frp ..."
    $INSTANCE_FULLNAME stop 2> /dev/null
    if [ "${SERVICE_MANAGER}" = "systemd" ]
    then
        for svs in `systemctl --plain list-units | grep -e "frp.*.service" | awk '{print $1}'`
        do
            systemctl stop ${svs//.service} 2> /dev/null
            systemctl disable ${svs//.service} 2> /dev/null
        done
    else
        cd /etc/init.d/
        for svs in `ls frp* 2> /dev/null`
        do
            /etc/init.d/${svs} stop 2> /dev/null
            update-rc.d -f ${svs} remove 2> /dev/null
            rm /etc/init.d/${svs} 2> /dev/null
        done
    fi
    uninst frps
    uninst frpc
    show_process "Frp is removed."
    show_process "Config path ${LOCAL_CONFIG_DIR}/ and Log path  $LOCAL_LOG_DIR/ are remained, remove it manually."
    echo
}

check_script_args(){
    if [ -z "$ACTION" ]; then
        fun_input_param ACTION install
        ACTION=$set_ACTION
    fi
    if [ -z "$CHAR" ]; then
        fun_input_param CHAR frpc
        CHAR=$set_CHAR
    fi
    if [ -z "$INSTANCE" ]; then
        fun_input_param INSTANCE main
        INSTANCE=$set_INSTANCE
    fi
}

check_charactor(){
    if [ "$CHAR" != "frps" -a "$CHAR" != "frpc" ]
    then
        show_usage
        exit 1
    fi
}

check_service_manager(){
    if `which systemctl > /dev/null`
    then
        SERVICE_MANAGER="systemd"
    elif `which update-rc.d > /dev/null`
    then
        SERVICE_MANAGER="init"
    else
        show_error "Need systemd or update-rc.d to install frp as service."
        exit 1
    fi
}

show_usage(){
    show_title
    echo "Usage:"
    echo "  bash `basename $0` -a <action> -c <character> [-t <instance>]"
    echo "Parameters:"
    echo "  -a    install/uninstall/config"
    echo "  -c    frps/frpc"
    echo '  -t    default: "main"'
    echo
    echo "If frps@<instance> is installed:"
    echo "  sudo frps@<instance> {start|stop|restart}"
    echo
    echo "If frpc@<instance> is installed:"
    echo "  sudo frpc@<instance> {start|stop|restart|status|reload}"
    echo
}

########
# main #
########


while getopts 'a:c:i:' opt
do
    case $opt in
        a) ACTION="$OPTARG" ;;
        c) CHAR="$OPTARG" ;;
        i) INSTANCE="$OPTARG" ;;
        *)
            show_usage
            exit
    esac
done

check_script_args

INSTANCE_FULLNAME=${CHAR}@${INSTANCE}
[ "$INSTANCE" = "main" ] && IS_MAIN=true || IS_MAIN=false

check_service_manager

case "$ACTION" in
install)
    check_charactor
    pre_install
    install_download_frp
    configure
    service_install
    rm -fr ${tarball_stem}
    ;;
config)
    check_charactor
    configure
    service_install
    ;;
uninstall)
    uninstall_frp
    ;;
*)
    show_usage
    ;;
esac

