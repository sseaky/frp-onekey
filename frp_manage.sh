#!/usr/bin/env bash
# @Author: Seaky
# @Date:   2020/11/11 15:39

# bash frp_manage.sh install frps

#
# param
#
NAME="frp"
INSTALL_VERSION="201011"
FRP_VERSION=0.34.2
FRP_DOWNLOAD_GITHUB="https://github.com/fatedier/frp/releases/download"
FRP_DOWNLOAD_JP="https://download.fastgit.org/fatedier/frp/releases/download"
FRP_DOWNLOAD_HK="https://g.ioiox.com/${FRP_DOWNLOAD_GITHUB}"
#FRP_DOWNLOAD_SERVER=$FRP_DOWNLOAD_HK
LOCAL_CONFIG_DIR="/etc/${NAME}"
LOCAL_BIN_DIR="/usr/bin"
LOCAL_SYSTEMD_DIR="/lib/systemd/system"
LOCAL_LOG_DIR="/var/log/frp"

# 自动启动
INIT=true

#
# prepare
#

set_text_color(){
    COLOR_RED='\E[1;31m'
    COLOR_GREEN='\E[1;32m'
    COLOR_YELOW='\E[1;33m'
    COLOR_BLUE='\E[1;34m'
    COLOR_PINK='\E[1;35m'
    COLOR_PINKBACK_WHITEFONT='\033[45;37m'
    COLOR_GREEN_LIGHTNING='\033[32m \033[05m'
    COLOR_END='\E[0m'
}

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
#    elif grep -Eqi "Fedora" /etc/issue || grep -Eq "Fedora" /etc/*-release; then
#        OS=Fedora
#    elif   grep -Eqi "CentOS" /etc/issue || grep -Eq "CentOS" /etc/*-release; then
#        OS=CentOS
#        check_centos_version
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

show_title(){
    show_banner "FRP Onekey"
}

show_usage(){
    show_title
    echo "Usage:"
    echo "  bash `basename $0` {install|config} {frps|frpc}"
    echo "  bash `basename $0` uninstall"
    echo
    echo "If installed:"
    echo "  sudo systemctl {status|start|stop|restart} {frps|frpc}"
    echo
    echo "If frpc installed:"
    echo "  frpcc {status|reload}"
    echo
}

show_process(){
    echo -e "${COLOR_GREEN}- $1${COLOR_END}"
}

show_error(){
    echo -e "${COLOR_RED}* $1${COLOR_END}"
}

#
# install
#

pre_install(){
    show_process "Checking requirements of installment..."
    check_root
    check_os
    check_packet
}

install_download_frp(){
    BIN_FRPS=${LOCAL_BIN_DIR}/frps
    req_down=true
    if [ -s "${BIN_FRPS}" ]
    then
        exist_version=`${BIN_FRPS} -v`
        [ $exist_version == $FRP_VERSION ] && req_down=false
    fi
    $req_down || return 1
    tarball_stem="frp_${FRP_VERSION}_linux_${ARCHS}"
    frp_download_url="${FRP_DOWNLOAD_SERVER}/v${FRP_VERSION}/${tarball_stem}.tar.gz"

    show_process "Try retrieve ${frp_download_url}${COLOR_END}"
    rm -fr ${tarball_stem}
    if [ ! -s "${tarball_stem}.tar.gz" ]
    then
        if [ -z "$FRP_DOWNLOAD_SERVER" ]
        then
            echo
            echo -e "${COLOR_GREEN}Choice download source?:${COLOR_END}"
            echo    "1: Github (default)"
            echo    "2: JP"
            echo    "3: HK"
            echo    "-------------------------"
            read -e -p "Enter your choice (1, 2, 3 or exit. default [1]): " str_choice_source
            case "${str_choice_source}" in
                1)
                    FRP_DOWNLOAD_SERVER=$FRP_DOWNLOAD_GITHUB
                    ;;
                2)
                    FRP_DOWNLOAD_SERVER=$FRP_DOWNLOAD_JP
                    ;;
                3)
                    FRP_DOWNLOAD_SERVER=$FRP_DOWNLOAD_HK
                    ;;
                [eE][xX][iI][tT])
                    exit 1
                    ;;
                *)
                    FRP_DOWNLOAD_SERVER=$FRP_DOWNLOAD_GITHUB
                    ;;
            esac
        fi
        wget ${frp_download_url}
    fi
    if [ -s "${tarball_stem}.tar.gz" ]; then
        tar xzf ${tarball_stem}.tar.gz
        cp ${tarball_stem}/frps ${LOCAL_BIN_DIR}/
        cp ${tarball_stem}/frpc ${LOCAL_BIN_DIR}/
        cp ${tarball_stem}/systemd/frps.service ${LOCAL_SYSTEMD_DIR}
        cp ${tarball_stem}/systemd/frpc.service ${LOCAL_SYSTEMD_DIR}
    else
        show_error " ${COLOR_RED}Download failed${COLOR_END}"
        exit 1
    fi
}

uninstall(){
    rm ${LOCAL_BIN_DIR}/frps ${LOCAL_BIN_DIR}/frpc
}

#
# config
#

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
# input configuration data
fun_input_bind_port(){
    def_server_port="57000"
    echo ""
    echo -n -e "Please input ${target} ${COLOR_GREEN}bind_port${COLOR_END} [1-65535]"
    read -e -p "(Default Server Port: ${def_server_port}):" serverport
    [ -z "${serverport}" ] && serverport="${def_server_port}"
    fun_check_port "bind" "${serverport}"
}
fun_input_dashboard_port(){
    def_dashboard_port="57500"
    echo ""
    echo -n -e "Please input ${target} ${COLOR_GREEN}dashboard_port${COLOR_END} [1-65535]"
    read -e -p "(Default : ${def_dashboard_port}):" input_dashboard_port
    [ -z "${input_dashboard_port}" ] && input_dashboard_port="${def_dashboard_port}"
    fun_check_port "dashboard" "${input_dashboard_port}"
}
fun_input_vhost_http_port(){
    def_vhost_http_port="57080"
    echo ""
    echo -n -e "Please input ${target} ${COLOR_GREEN}vhost_http_port${COLOR_END} [1-65535]"
    read -e -p "(Default : ${def_vhost_http_port}):" input_vhost_http_port
    [ -z "${input_vhost_http_port}" ] && input_vhost_http_port="${def_vhost_http_port}"
    fun_check_port "vhost_http" "${input_vhost_http_port}"
}
fun_input_vhost_https_port(){
    def_vhost_https_port="57443"
    echo ""
    echo -n -e "Please input ${target} ${COLOR_GREEN}vhost_https_port${COLOR_END} [1-65535]"
    read -e -p "(Default : ${def_vhost_https_port}):" input_vhost_https_port
    [ -z "${input_vhost_https_port}" ] && input_vhost_https_port="${def_vhost_https_port}"
    fun_check_port "vhost_https" "${input_vhost_https_port}"
}
fun_input_log_max_days(){
    def_max_days="30"
    def_log_max_days="3"
    echo ""
    echo -e "Please input ${target} ${COLOR_GREEN}log_max_days${COLOR_END} [1-${def_max_days}]"
    read -e -p "(Default : ${def_log_max_days} day):" input_log_max_days
    [ -z "${input_log_max_days}" ] && input_log_max_days="${def_log_max_days}"
    fun_check_number "log_max_days" "${def_max_days}" "${input_log_max_days}"
}
fun_input_max_pool_count(){
    def_max_pool="200"
    def_max_pool_count="50"
    echo ""
    echo -e "Please input ${target} ${COLOR_GREEN}max_pool_count${COLOR_END} [1-${def_max_pool}]"
    read -e -p "(Default : ${def_max_pool_count}):" input_max_pool_count
    [ -z "${input_max_pool_count}" ] && input_max_pool_count="${def_max_pool_count}"
    fun_check_number "max_pool_count" "${def_max_pool}" "${input_max_pool_count}"
}
fun_input_dashboard_user(){
    def_dashboard_user="admin"
    echo ""
    echo -n -e "Please input ${target} ${COLOR_GREEN}dashboard_user${COLOR_END}"
    read -e -p "(Default : ${def_dashboard_user}):" input_dashboard_user
    [ -z "${input_dashboard_user}" ] && input_dashboard_user="${def_dashboard_user}"
}
fun_input_dashboard_pwd(){
    def_dashboard_pwd=`fun_randstr 8`
    echo ""
    echo -n -e "Please input ${target} ${COLOR_GREEN}dashboard_pwd${COLOR_END}"
    read -e -p "(Default : ${def_dashboard_pwd}):" input_dashboard_pwd
    [ -z "${input_dashboard_pwd}" ] && input_dashboard_pwd="${def_dashboard_pwd}"
}
fun_input_token(){
    def_token=`fun_randstr 16`
    echo ""
    echo -n -e "Please input ${target} ${COLOR_GREEN}token${COLOR_END}"
    read -e -p "(Default : ${def_token}):" input_token
    [ -z "${input_token}" ] && input_token="${def_token}"
}
fun_input_subdomain_host(){
    def_subdomain_host="your.domain"
    echo ""
    echo -n -e "Please input ${target} ${COLOR_GREEN}subdomain_host${COLOR_END}"
    read -e -p "(Default : ${def_subdomain_host}):" input_subdomain_host
    [ -z "${input_subdomain_host}" ] && input_subdomain_host="${def_subdomain_host}"
}

fun_create_log_dir(){
    mkdir -p $LOCAL_LOG_DIR
    chmod 777 ${LOCAL_LOG_DIR}
}

configure_frps_prompt(){
#    echo -e "Loading You Server IP, please wait..."
#    defIP=$(wget -qO- ip.clang.cn | sed -r 's/\r//')
#    echo -e "You Server IP:${COLOR_GREEN}${defIP}${COLOR_END}"
    echo -e "————————————————————————————————————————————"
    echo -e "     ${COLOR_RED}Please input your server setting:${COLOR_END}"
    echo -e "————————————————————————————————————————————"
    fun_input_param bind_addr "0.0.0.0"
    fun_input_bind_port
    [ -n "${input_port}" ] && set_bind_port="${input_port}"
    echo -e "${target} bind_port: ${COLOR_YELOW}${set_bind_port}${COLOR_END}"
    echo -e ""
    fun_input_vhost_http_port
    [ -n "${input_port}" ] && set_vhost_http_port="${input_port}"
    echo -e "${target} vhost_http_port: ${COLOR_YELOW}${set_vhost_http_port}${COLOR_END}"
    echo -e ""
    fun_input_vhost_https_port
    [ -n "${input_port}" ] && set_vhost_https_port="${input_port}"
    echo -e "${target} vhost_https_port: ${COLOR_YELOW}${set_vhost_https_port}${COLOR_END}"
    echo -e ""
    fun_input_dashboard_port
    [ -n "${input_port}" ] && set_dashboard_port="${input_port}"
    echo -e "${target} dashboard_port: ${COLOR_YELOW}${set_dashboard_port}${COLOR_END}"
    echo -e ""
    fun_input_dashboard_user
    [ -n "${input_dashboard_user}" ] && set_dashboard_user="${input_dashboard_user}"
    echo -e "${target} dashboard_user: ${COLOR_YELOW}${set_dashboard_user}${COLOR_END}"
    echo -e ""
    fun_input_dashboard_pwd
    [ -n "${input_dashboard_pwd}" ] && set_dashboard_pwd="${input_dashboard_pwd}"
    echo -e "${target} dashboard_pwd: ${COLOR_YELOW}${set_dashboard_pwd}${COLOR_END}"
    echo -e ""
    fun_input_token
    [ -n "${input_token}" ] && set_token="${input_token}"
    echo -e "${target} token: ${COLOR_YELOW}${set_token}${COLOR_END}"
    echo -e ""
    fun_input_subdomain_host
    [ -n "${input_subdomain_host}" ] && set_subdomain_host="${input_subdomain_host}"
    echo -e "${target} subdomain_host: ${COLOR_YELOW}${set_subdomain_host}${COLOR_END}"
    echo -e ""
    fun_input_max_pool_count
    [ -n "${input_number}" ] && set_max_pool_count="${input_number}"
    echo -e "${target} max_pool_count: ${COLOR_YELOW}${set_max_pool_count}${COLOR_END}"
    echo -e ""
    echo -e "Please select ${COLOR_GREEN}log_level${COLOR_END}"
    echo    "1: info (default)"
    echo    "2: warn"
    echo    "3: error"
    echo    "4: debug"
    echo    "-------------------------"
    read -e -p "Enter your choice (1, 2, 3, 4 or exit. default [1]): " str_log_level
    case "${str_log_level}" in
        1|[Ii][Nn][Ff][Oo])
            str_log_level="info"
            ;;
        2|[Ww][Aa][Rr][Nn])
            str_log_level="warn"
            ;;
        3|[Ee][Rr][Rr][Oo][Rr])
            str_log_level="error"
            ;;
        4|[Dd][Ee][Bb][Uu][Gg])
            str_log_level="debug"
            ;;
        [eE][xX][iI][tT])
            exit 1
            ;;
        *)
            str_log_level="info"
            ;;
    esac
    echo -e "log_level: ${COLOR_YELOW}${str_log_level}${COLOR_END}"
    echo -e ""
    fun_input_log_max_days
    [ -n "${input_number}" ] && set_log_max_days="${input_number}"
    echo -e "${target} log_max_days: ${COLOR_YELOW}${set_log_max_days}${COLOR_END}"
    echo -e ""
    echo -e "Please select ${COLOR_GREEN}log_file${COLOR_END}"
    echo    "1: enable (default)"
    echo    "2: disable"
    echo "-------------------------"
    read -e -p "Enter your choice (1, 2 or exit. default [1]): " str_log_file
    case "${str_log_file}" in
        1|[yY]|[yY][eE][sS]|[oO][nN]|[tT][rR][uU][eE]|[eE][nN][aA][bB][lL][eE])
            str_log_file="${LOCAL_LOG_DIR}/${target}.log"
            str_log_file_flag=true
            ;;
        0|2|[nN]|[nN][oO]|[oO][fF][fF]|[fF][aA][lL][sS][eE]|[dD][iI][sS][aA][bB][lL][eE])
            str_log_file="/dev/null"
            str_log_file_flag=false
            ;;
        [eE][xX][iI][tT])
            exit 1
            ;;
        *)
            str_log_file="${LOCAL_LOG_DIR}/${target}.log"
            str_log_file_flag=true
            ;;
    esac
    echo -e "log_file: ${COLOR_YELOW}${str_log_file_flag}${COLOR_END}"
    echo -e ""
    echo -e "Please select ${COLOR_GREEN}tcp_mux${COLOR_END}"
    echo    "1: enable (default)"
    echo    "2: disable"
    echo "-------------------------"
    read -e -p "Enter your choice (1, 2 or exit. default [1]): " str_tcp_mux
    case "${str_tcp_mux}" in
        1|[yY]|[yY][eE][sS]|[oO][nN]|[tT][rR][uU][eE]|[eE][nN][aA][bB][lL][eE])
            set_tcp_mux="true"
            ;;
        0|2|[nN]|[nN][oO]|[oO][fF][fF]|[fF][aA][lL][sS][eE]|[dD][iI][sS][aA][bB][lL][eE])
            set_tcp_mux="false"
            ;;
        [eE][xX][iI][tT])
            exit 1
            ;;
        *)
            set_tcp_mux="true"
            ;;
    esac
    echo -e "tcp_mux: ${COLOR_YELOW}${set_tcp_mux}${COLOR_END}"
    echo -e ""
    echo -e "Please select ${COLOR_GREEN}kcp support${COLOR_END}"
    echo    "1: enable (default)"
    echo    "2: disable"
    echo "-------------------------"
    read -e -p "Enter your choice (1, 2 or exit. default [1]): " str_kcp
    case "${str_kcp}" in
        1|[yY]|[yY][eE][sS]|[oO][nN]|[tT][rR][uU][eE]|[eE][nN][aA][bB][lL][eE])
            set_kcp="true"
            ;;
        0|2|[nN]|[nN][oO]|[oO][fF][fF]|[fF][aA][lL][sS][eE]|[dD][iI][sS][aA][bB][lL][eE])
            set_kcp="false"
            ;;
        [eE][xX][iI][tT])
            exit 1
            ;;
        *)
            set_kcp="true"
            ;;
    esac
    echo -e "kcp support: ${COLOR_YELOW}${set_kcp}${COLOR_END}"
    echo -e ""

    echo "============== Check your input =============="
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
    echo -e "Log level          : ${COLOR_GREEN}${str_log_level}${COLOR_END}"
    echo -e "Log max days       : ${COLOR_GREEN}${set_log_max_days}${COLOR_END}"
    $str_log_file_flag && echo -e "Log file           : ${COLOR_GREEN}${str_log_file}${COLOR_END}" || echo -e "Log file           : ${COLOR_RED}${str_log_file_flag}${COLOR_END}"
    echo "=============================================="
    echo ""
    echo "Press any key to start...or Press Ctrl+c to cancel"

    char=`get_char`
    echo $char
}

configure_frps_generate_ini(){
#    [ ! -d ${str_program_dir} ] && mkdir -p ${str_program_dir}
#    cd ${str_program_dir}
    [ -s $config_file ] && ( show_process "$config_file is exist, backup to ${config_file}.backup"; cp $config_file ${config_file}.backup )
    show_process "Write $target config to $config_file"

    # Config file
    if [[ "${set_kcp}" == "false" ]]; then
cat > ${config_file} <<-EOF
# [common] is integral section
[common]
# A literal address or host name for IPv6 must be enclosed
# in square brackets, as in "[::1]:80", "[ipv6-host]:http" or "[ipv6-host%zone]:80"
bind_addr = 0.0.0.0
bind_port = ${set_bind_port}
# udp port used for kcp protocol, it can be same with 'bind_port'
# if not set, kcp is disabled in frps
#kcp_bind_port = ${set_bind_port}
# if you want to configure or reload frps by dashboard, dashboard_port must be set
dashboard_port = ${set_dashboard_port}
# dashboard assets directory(only for debug mode)
dashboard_user = ${set_dashboard_user}
dashboard_pwd = ${set_dashboard_pwd}
# assets_dir = ./static
vhost_http_port = ${set_vhost_http_port}
vhost_https_port = ${set_vhost_https_port}
# console or real logFile path like ./frps.log
log_file = ${str_log_file}
# debug, info, warn, error
log_level = ${str_log_level}
log_max_days = ${set_log_max_days}
# auth token
token = ${set_token}
# It is convenient to use subdomain configure for http、https type when many people use one frps server together.
subdomain_host = ${set_subdomain_host}
# only allow frpc to bind ports you list, if you set nothing, there won't be any limit
#allow_ports = 1-65535
# pool_count in each proxy will change to max_pool_count if they exceed the maximum value
max_pool_count = ${set_max_pool_count}
# if tcp stream multiplexing is used, default is true
tcp_mux = ${set_tcp_mux}
EOF
    else
cat > ${config_file} <<-EOF
# [common] is integral section
[common]
# A literal address or host name for IPv6 must be enclosed
# in square brackets, as in "[::1]:80", "[ipv6-host]:http" or "[ipv6-host%zone]:80"
bind_addr = 0.0.0.0
bind_port = ${set_bind_port}
# udp port used for kcp protocol, it can be same with 'bind_port'
# if not set, kcp is disabled in frps
kcp_bind_port = ${set_bind_port}
# if you want to configure or reload frps by dashboard, dashboard_port must be set
dashboard_port = ${set_dashboard_port}
# dashboard assets directory(only for debug mode)
dashboard_user = ${set_dashboard_user}
dashboard_pwd = ${set_dashboard_pwd}
# assets_dir = ./static
vhost_http_port = ${set_vhost_http_port}
vhost_https_port = ${set_vhost_https_port}
# console or real logFile path like ./frps.log
log_file = ${str_log_file}
# debug, info, warn, error
log_level = ${str_log_level}
log_max_days = ${set_log_max_days}
# auth token
token = ${set_token}
# It is convenient to use subdomain configure for http、https type when many people use one frps server together.
subdomain_host = ${set_subdomain_host}
# only allow frpc to bind ports you list, if you set nothing, there won't be any limit
#allow_ports = 1-65535
# pool_count in each proxy will change to max_pool_count if they exceed the maximum value
max_pool_count = ${set_max_pool_count}
# if tcp stream multiplexing is used, default is true
tcp_mux = ${set_tcp_mux}
EOF
    fi
    $fun_create_log_dir && fun_create_log_dir
}

fun_input_param(){
    default_param=$2
    input_param=$2
    echo ""
    echo -n -e "Please input ${target} ${COLOR_GREEN}${1}${COLOR_END}"
    [ -n "$input_param" ] && echo -n -e "(Default : ${default_param})"
    read -e -p ": " input_param
    [ -z "$input_param" ] && input_param=${default_param}
    [ -z "$input_param" ] && show_error "$1 can't be empty." && exit 1
    echo -e "${target} $1: ${COLOR_YELOW}${input_param}${COLOR_END}"
    echo -e
    eval set_${1}=$input_param
}

fun_get_local_ip(){
    echo `ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | grep -v '^168' |  sed -n '1p'`
}

configure_frpc_prompt(){
    echo -e "————————————————————————————————————————————"
    echo -e "     ${COLOR_RED}Please input your Client setting:${COLOR_END}"
    echo -e "————————————————————————————————————————————"
    fun_input_param token
    fun_input_param server_addr
    fun_input_param server_port 57000
    fun_input_param client_name `hostname`

#    fun_input_param admin_addr `fun_get_local_ip`
#    fun_input_param admin_port 57001
#    fun_input_param admin_user admin
#    fun_input_param admin_pwd `fun_randstr 8`

    fun_input_max_pool_count
    [ -n "${input_number}" ] && set_max_pool_count="${input_number}"
    echo -e "${target} max_pool_count: ${COLOR_YELOW}${set_max_pool_count}${COLOR_END}"
    echo -e ""
    echo -e "Please select ${COLOR_GREEN}log_level${COLOR_END}"
    echo    "1: info (default)"
    echo    "2: warn"
    echo    "3: error"
    echo    "4: debug"
    echo    "-------------------------"
    read -e -p "Enter your choice (1, 2, 3, 4 or exit. default [1]): " str_log_level
    case "${str_log_level}" in
        1|[Ii][Nn][Ff][Oo])
            str_log_level="info"
            ;;
        2|[Ww][Aa][Rr][Nn])
            str_log_level="warn"
            ;;
        3|[Ee][Rr][Rr][Oo][Rr])
            str_log_level="error"
            ;;
        4|[Dd][Ee][Bb][Uu][Gg])
            str_log_level="debug"
            ;;
        [eE][xX][iI][tT])
            exit 1
            ;;
        *)
            str_log_level="info"
            ;;
    esac
    echo -e "log_level: ${COLOR_YELOW}${str_log_level}${COLOR_END}"
    echo -e ""
    fun_input_log_max_days
    [ -n "${input_number}" ] && set_log_max_days="${input_number}"
    echo -e "${target} log_max_days: ${COLOR_YELOW}${set_log_max_days}${COLOR_END}"
    echo -e ""
    echo -e "Please select ${COLOR_GREEN}log_file${COLOR_END}"
    echo    "1: enable (default)"
    echo    "2: disable"
    echo "-------------------------"
    read -e -p "Enter your choice (1, 2 or exit. default [1]): " str_log_file
    case "${str_log_file}" in
        1|[yY]|[yY][eE][sS]|[oO][nN]|[tT][rR][uU][eE]|[eE][nN][aA][bB][lL][eE])
            str_log_file="${LOCAL_LOG_DIR}/${target}.log"
            str_log_file_flag=true
            ;;
        0|2|[nN]|[nN][oO]|[oO][fF][fF]|[fF][aA][lL][sS][eE]|[dD][iI][sS][aA][bB][lL][eE])
            str_log_file="/dev/null"
            str_log_file_flag=false
            ;;
        [eE][xX][iI][tT])
            exit 1
            ;;
        *)
            str_log_file="${LOCAL_LOG_DIR}/${target}.log"
            str_log_file_flag=true
            ;;
    esac
    echo -e "log_file: ${COLOR_YELOW}${str_log_file_flag}${COLOR_END}"
    echo -e ""
    echo -e "Please select ${COLOR_GREEN}tcp_mux${COLOR_END}"
    echo    "1: enable (default)"
    echo    "2: disable"
    echo "-------------------------"
    read -e -p "Enter your choice (1, 2 or exit. default [1]): " str_tcp_mux
    case "${str_tcp_mux}" in
        1|[yY]|[yY][eE][sS]|[oO][nN]|[tT][rR][uU][eE]|[eE][nN][aA][bB][lL][eE])
            set_tcp_mux="true"
            ;;
        0|2|[nN]|[nN][oO]|[oO][fF][fF]|[fF][aA][lL][sS][eE]|[dD][iI][sS][aA][bB][lL][eE])
            set_tcp_mux="false"
            ;;
        [eE][xX][iI][tT])
            exit 1
            ;;
        *)
            set_tcp_mux="true"
            ;;
    esac
    echo -e "tcp_mux: ${COLOR_YELOW}${set_tcp_mux}${COLOR_END}"
    echo -e ""
    echo -e "Please select ${COLOR_GREEN}protocol${COLOR_END}"
    echo    "1: tcp (default)"
    echo    "2: kcp"
    echo "-------------------------"
    read -e -p "Enter your choice (1, 2 or exit. default [1]): " str_protocol
    case "${str_protocol}" in
        1|[yY]|[yY][eE][sS]|[oO][nN]|[tT][rR][uU][eE]|[eE][nN][aA][bB][lL][eE])
            set_protocol="tcp"
            ;;
        0|2|[nN]|[nN][oO]|[oO][fF][fF]|[fF][aA][lL][sS][eE]|[dD][iI][sS][aA][bB][lL][eE])
            set_protocol="kcp"
            ;;
        [eE][xX][iI][tT])
            exit 1
            ;;
        *)
            set_protocol="tcp"
            ;;
    esac
    echo -e "protocol: ${COLOR_YELOW}${set_protocol}${COLOR_END}"
    echo -e ""

    configure_frpc_prompt_ssh

    echo "============== Check your input =============="
    echo -e "FRP Server IP      : ${COLOR_GREEN}${set_server_addr}${COLOR_END}"
    echo -e "Bind port          : ${COLOR_GREEN}${set_server_port}${COLOR_END}"
    echo -e "token              : ${COLOR_GREEN}${set_token}${COLOR_END}"
    echo -e "Client Name        : ${COLOR_GREEN}${set_client_name}${COLOR_END}"
    echo -e "protocol           : ${COLOR_GREEN}${set_protocol}${COLOR_END}"
    echo -e "tcp_mux            : ${COLOR_GREEN}${set_tcp_mux}${COLOR_END}"
    echo -e "Max Pool count     : ${COLOR_GREEN}${set_max_pool_count}${COLOR_END}"
    echo -e "Log level          : ${COLOR_GREEN}${str_log_level}${COLOR_END}"
    echo -e "Log max days       : ${COLOR_GREEN}${set_log_max_days}${COLOR_END}"
    $str_log_file_flag && echo -e "Log file           : ${COLOR_GREEN}${str_log_file}${COLOR_END}" || echo -e "Log file           : ${COLOR_RED}${str_log_file_flag}${COLOR_END}"
    $ssh_fwd_enabled && echo -e "SSH Foward         : ${COLOR_GREEN}${set_server_addr}:${set_ssh_map_to_server_port} -> ${set_local_ssh_addr}:${set_local_ssh_port}${COLOR_END}"
    echo "=============================================="
    echo ""
    echo "Press any key to start...or Press Ctrl+c to cancel"

    char=`get_char`
    echo $char
}

fun_choice_yes_or_no(){
    unset _choice
    val_name=$1
    shift
    str_prompt=$@
    echo -e "${COLOR_GREEN_LIGHTNING}$@${COLOR_END}"
    echo -e ""
    echo -e "Please select ${COLOR_GREEN}choice${COLOR_END}"
    echo    "1: yes (default)"
    echo    "2: no"
    echo "-------------------------"
    read -e -p "Enter your choice (1, 2 or exit. default [1]): " _choice
    case "${_choice}" in
        1)
            eval choice_${val_name}=true
            ;;
        2)
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
#    [ ! -d ${str_program_dir} ] && mkdir -p ${str_program_dir}
#    cd ${str_program_dir}
    [ -s $config_file ] && ( show_process "$config_file is exist, backup to ${config_file}.backup"; cp $config_file ${config_file}.backup )
    show_process "Write $target config to $config_file"

    # Config file
    cat > ${config_file} <<-EOF
[common]
server_addr = ${set_server_addr}
server_port = ${set_server_port}
token = ${set_token}

log_file = ${str_log_file}
log_level = ${str_log_level}
log_max_days = ${set_log_max_days}

admin_addr = 127.0.0.1
admin_port = 57001
admin_user = admin
admin_pwd = admin

tcp_mux = ${set_tcp_mux}
user = ${set_client_name}
protocol = ${set_protocol}

EOF

    if $ssh_fwd_enabled
    then
    cat >> ${config_file} <<-EOF
[ssh]
type = tcp
local_ip = $set_local_ssh_addr
local_port = $set_local_ssh_port
remote_port = $set_ssh_map_to_server_port

EOF
    fi

cat >> ${config_file} <<-EOF

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
    show_process "enable $target service..."
    systemctl enable $target
    systemctl restart $target
    systemctl status $target
    if [ $? -ne 0 ]
    then
        tail $LOCAL_LOG_DIR/${target}.log
    elif [ "$target" = "frpc" ]
    then
        ping -c 1 > /dev/null 2>&1
        frpcc status
    fi
}

configure_frps(){
    configure_frps_prompt
    configure_frps_generate_ini
}

gen_frpcc(){
    cat > ${LOCAL_BIN_DIR}/frpcc <<-EOF
#!/bin/bash
[ -z "\$1" ] && echo "frpcc {status|reload}" && exit 1
${LOCAL_BIN_DIR}/frpc -c ${LOCAL_CONFIG_DIR}/frpc.ini \$@
EOF
    chmod a+x ${LOCAL_BIN_DIR}/frpcc
    show_process "create ${LOCAL_BIN_DIR}/frpcc"
}

configure_frpc(){
    configure_frpc_prompt
    configure_frpc_generate_ini
    gen_frpcc
}

configure(){
    [ ! -s "${LOCAL_BIN_DIR}/${target}" ] && show_error "Bin ${LOCAL_BIN_DIR}/${target} is not exist, install first!" && show_usage && exit 1
    mkdir -p $LOCAL_CONFIG_DIR
    config_file=$LOCAL_CONFIG_DIR/${target}.ini
    clear
    configure_${target}
    show_process "configure $target done"
}


uninstall_frp(){
    uninst(){
        show_process "Removing $1..."
        systemctl stop $1 2> /dev/null
        systemctl disable $1 2> /dev/null
        rm $LOCAL_SYSTEMD_DIR/$1.service 2> /dev/null
        rm $LOCAL_LOG_DIR/$1.log 2> /dev/null
        rm $LOCAL_BIN_DIR/$1 2> /dev/null
    }
    show_title
    uninst frps
    uninst frpc
    rm $LOCAL_BIN_DIR/frpcc 2> /dev/null
    rmdir $LOCAL_LOG_DIR 2> /dev/null
    show_process "Frp is removed."
    show_process "Config path ${LOCAL_CONFIG_DIR}/ is remained, remove it manually."
    echo
}

check_target(){
    if [ "$target" != "frps" -a "$target" != "frpc" ]
    then
        show_usage
        exit 1
    fi
}

#
# main
#

action=$1
target=$2

set_text_color

case "$action" in
install)
    check_target
    pre_install
    install_download_frp
    configure
    service_enable
    ;;
config)
    check_target
    configure
    service_enable
    ;;
uninstall)
    uninstall_frp
    ;;
*)
    show_usage
#    target='frpc'
#    service_enable $target
    ;;
esac



