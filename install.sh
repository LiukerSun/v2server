#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)
script_dir=$(cd "$(dirname "$0")" && pwd)

[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "alpine"; then
    release="alpine"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "arch"; then
    release="arch"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

arch=$(uname -m)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64-v8a"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
fi

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
    exit 2
fi

if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release wget curl unzip tar crontabs socat ca-certificates -y >/dev/null 2>&1
        update-ca-trust force-enable >/dev/null 2>&1
    elif [[ x"${release}" == x"alpine" ]]; then
        apk add wget curl unzip tar socat ca-certificates >/dev/null 2>&1
        update-ca-certificates >/dev/null 2>&1
    elif [[ x"${release}" == x"debian" ]]; then
        apt-get update -y >/dev/null 2>&1
        apt install wget curl unzip tar cron socat ca-certificates -y >/dev/null 2>&1
        update-ca-certificates >/dev/null 2>&1
    elif [[ x"${release}" == x"ubuntu" ]]; then
        apt-get update -y >/dev/null 2>&1
        apt install wget curl unzip tar cron socat -y >/dev/null 2>&1
        apt-get install ca-certificates wget -y >/dev/null 2>&1
        update-ca-certificates >/dev/null 2>&1
    elif [[ x"${release}" == x"arch" ]]; then
        pacman -Sy --noconfirm >/dev/null 2>&1
        pacman -S --noconfirm --needed wget curl unzip tar cron socat >/dev/null 2>&1
        pacman -S --noconfirm --needed ca-certificates wget >/dev/null 2>&1
    fi
}

check_status() {
    if [[ ! -f ${install_dir}${app_name} ]]; then
        return 2
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(service ${app_name} status | awk '{print $3}')
        if [[ x"${temp}" == x"started" ]]; then
            return 0
        else
            return 1
        fi
    else
        temp=$(systemctl status ${app_name} | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
        if [[ x"${temp}" == x"running" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

check_ipv6_support() {
    if ip -6 addr | grep -q "inet6"; then
        echo "1"
    else
        echo "0"
    fi
}

parse_config_file() {
    local file=$1
    if [[ ! -f "$file" ]]; then
        echo -e "${red}配置文件不存在: $file${plain}"
        exit 1
    fi
    backend_url=$(grep "backend_url:" "$file" | head -1 | awk -F': ' '{print $2}' | tr -d '"' | tr -d "'")
    backend_key=$(grep "backend_key:" "$file" | head -1 | awk -F': ' '{print $2}' | tr -d '"' | tr -d "'")
    node_id=$(grep "node_id:" "$file" | head -1 | awk -F': ' '{print $2}' | tr -d '"' | tr -d "'")

    # V2bX 特有参数
    if [[ "$app_type" == "v2bx" ]]; then
        core_type=$(grep "core_type:" "$file" | head -1 | awk -F': ' '{print $2}' | tr -d '"' | tr -d "'")
        transport_type=$(grep "transport_type:" "$file" | head -1 | awk -F': ' '{print $2}' | tr -d '"' | tr -d "'")
        cert_domain=$(grep "cert_domain:" "$file" | head -1 | awk -F': ' '{print $2}' | tr -d '"' | tr -d "'")
    fi

    if [[ -z "$backend_url" || -z "$backend_key" || -z "$node_id" ]]; then
        echo -e "${red}配置文件缺少必要信息 (backend_url, backend_key, node_id)${plain}"
        exit 1
    fi
}

validate_config() {
    if [[ -z "$backend_url" || -z "$backend_key" || -z "$node_id" ]]; then
        echo -e "${red}缺少必要配置参数${plain}"
        exit 1
    fi

    # V2bX 需要额外参数
    if [[ "$app_type" == "v2bx" ]]; then
        if [[ -z "$core_type" || -z "$transport_type" ]]; then
            echo -e "${red}V2bX 需要指定 core_type 和 transport_type${plain}"
            exit 1
        fi
    fi
}

auto_generate_config_v2node() {
    mkdir -p ${config_dir}

    cat <<EOF > ${config_dir}config.json
{
    "Log": {
        "Level": "warning",
        "Output": "",
        "Access": "none"
    },
    "Nodes": [
        {
            "ApiHost": "$backend_url",
            "NodeID": $node_id,
            "ApiKey": "$backend_key",
            "Timeout": 15
        }
    ]
}
EOF

    if [[ x"${release}" == x"alpine" ]]; then
        service ${app_name} restart
    else
        systemctl restart ${app_name}
    fi
    check_status
    if [[ $? != 0 ]]; then
        echo -e "${red}${app_name} 运行状态异常${plain}"
        exit 1
    fi
}

auto_generate_config_v2bx() {
    local core="xray"
    local core_xray=false
    local core_sing=false
    local core_hysteria2=false

    core_type=$(echo "$core_type" | tr '[:upper:]' '[:lower:]')
    transport_type=$(echo "$transport_type" | tr '[:upper:]' '[:lower:]')

    if [[ "$core_type" == "xray" ]]; then
        core="xray"
        core_xray=true
    elif [[ "$core_type" == "singbox" || "$core_type" == "sing" ]]; then
        core="sing"
        core_sing=true
    elif [[ "$core_type" == "hysteria2" ]]; then
        core="hysteria2"
        core_hysteria2=true
    fi

    local node_type="$transport_type"
    local cert_mode="none"
    if [[ -n "$cert_domain" ]]; then
        cert_mode="file"
    fi

    local ipv6_support=$(check_ipv6_support)
    local listen_ip="0.0.0.0"
    if [ "$ipv6_support" -eq 1 ]; then
        listen_ip="::"
    fi

    local cores_config="["
    if [ "$core_xray" = true ]; then
        cores_config+="
    {
        \"Type\": \"xray\",
        \"Log\": {
            \"Level\": \"error\",
            \"ErrorPath\": \"${config_dir}error.log\"
        },
        \"OutboundConfigPath\": \"${config_dir}custom_outbound.json\",
        \"RouteConfigPath\": \"${config_dir}route.json\"
    },"
    fi
    if [ "$core_sing" = true ]; then
        cores_config+="
    {
        \"Type\": \"sing\",
        \"Log\": {
            \"Level\": \"error\",
            \"Timestamp\": true
        },
        \"NTP\": {
            \"Enable\": false,
            \"Server\": \"time.apple.com\",
            \"ServerPort\": 0
        },
        \"OriginalPath\": \"${config_dir}sing_origin.json\"
    },"
    fi
    if [ "$core_hysteria2" = true ]; then
        cores_config+="
    {
        \"Type\": \"hysteria2\",
        \"Log\": {
            \"Level\": \"error\"
        }
    },"
    fi
    cores_config+="]"
    cores_config=$(echo "$cores_config" | sed 's/},]$/}]/')

    local node_config=""
    if [ "$core_type" == "xray" ]; then
        node_config=$(cat <<EOF
{
            "Core": "$core",
            "ApiHost": "$backend_url",
            "ApiKey": "$backend_key",
            "NodeID": $node_id,
            "NodeType": "$node_type",
            "Timeout": 30,
            "ListenIP": "$listen_ip",
            "SendIP": "0.0.0.0",
            "DeviceOnlineMinTraffic": 200,
            "MinReportTraffic": 0,
            "EnableProxyProtocol": false,
            "EnableUot": true,
            "EnableTFO": true,
            "DNSType": "UseIPv4",
            "CertConfig": {
                "CertMode": "$cert_mode",
                "RejectUnknownSni": false,
                "CertDomain": "$cert_domain",
                "CertFile": "${config_dir}fullchain.cer",
                "KeyFile": "${config_dir}cert.key",
                "Email": "v2bx@github.com",
                "Provider": "cloudflare",
                "DNSEnv": {
                    "EnvName": "env1"
                }
            }
        }
EOF
)
    fi

    cat <<EOF > ${config_dir}config.json
{
    "Log": {
        "Level": "error",
        "Output": ""
    },
    "Cores": $cores_config,
    "Nodes": [$node_config]
}
EOF

    cat <<EOF > ${config_dir}custom_outbound.json
[
    {
        "tag": "IPv4_out",
        "protocol": "freedom",
        "settings": {
            "domainStrategy": "UseIPv4v6"
        }
    },
    {
        "tag": "IPv6_out",
        "protocol": "freedom",
        "settings": {
            "domainStrategy": "UseIPv6"
        }
    },
    {
        "protocol": "blackhole",
        "tag": "block"
    }
]
EOF

    cat <<EOF > ${config_dir}route.json
{
    "domainStrategy": "AsIs",
    "rules": [
        {
            "outboundTag": "block",
            "ip": [
                "geoip:private"
            ]
        },
        {
            "outboundTag": "block",
            "domain": [
                "geosite:category-ads-all"
            ]
        },
        {
            "outboundTag": "IPv4_out",
            "network": "udp,tcp"
        }
    ]
}
EOF

    if [ "$core_sing" = true ]; then
        if [[ ! -f ${config_dir}sing_origin.json ]]; then
            cat <<EOF > ${config_dir}sing_origin.json
{
    "log": {
        "level": "error"
    }
}
EOF
        fi
    fi

    if [[ x"${release}" == x"alpine" ]]; then
        service ${app_name} restart
    else
        systemctl restart ${app_name}
    fi
    check_status
    if [[ $? != 0 ]]; then
        echo -e "${red}${app_name} 运行状态异常${plain}"
        exit 1
    fi
}

configure_acme_account() {
    local acme_account_conf="/root/.acme.sh/account.conf"
    mkdir -p /root/.acme.sh
    if [[ -z "$acme_email" ]]; then
        acme_email="${ACME_EMAIL}"
    fi
    local cf_key_value="$cf_key"
    local cf_email_value="$cf_email"
    if [[ -z "$cf_key_value" ]]; then
        cf_key_value="${CF_Key}"
    fi
    if [[ -z "$cf_email_value" ]]; then
        cf_email_value="${CF_Email}"
    fi
    if [[ -z "$acme_email" || -z "$cf_key_value" || -z "$cf_email_value" ]]; then
        echo -e "${red}缺少 ACME 邮箱或 Cloudflare 凭证${plain}"
        exit 1
    fi
    local acme_email_sanitized="${acme_email//\'/}"
    local cf_key_sanitized="${cf_key_value//\'/}"
    local cf_email_sanitized="${cf_email_value//\'/}"
    local default_acme_server="https://acme-v02.api.letsencrypt.org/directory"
    cat <<EOF > "$acme_account_conf"
#LOG_FILE="/root/.acme.sh/acme.sh.log"
#LOG_LEVEL=1

#AUTO_UPGRADE="1"

#NO_TIMESTAMP=1

UPGRADE_HASH='1bd2922bc37cddba97765af2ae12ad5441c91a74'
ACCOUNT_EMAIL='${acme_email_sanitized}'
SAVED_CF_Key='${cf_key_sanitized}'
SAVED_CF_Email='${cf_email_sanitized}'
USER_PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
DEFAULT_ACME_SERVER='${default_acme_server}'
EOF
}

issue_certificate() {
    if [[ -z "$cert_domain" ]]; then
        return 0
    fi
    if [[ -z "$acme_email" ]]; then
        acme_email="${ACME_EMAIL}"
    fi
    mkdir -p ${config_dir}
    local acme_sh="/root/.acme.sh/acme.sh"
    if [[ ! -f "$acme_sh" ]]; then
        if [[ -z "$acme_email" ]]; then
            echo -e "${red}缺少 ACME 邮箱，请使用 --acme-email 或设置 ACME_EMAIL${plain}"
            exit 1
        fi
        curl https://get.acme.sh | sh -s email="$acme_email"
    fi
    if [[ ! -f "$acme_sh" ]]; then
        echo -e "${red}acme.sh 安装失败${plain}"
        exit 1
    fi
    configure_acme_account
    if [[ -z "$cf_key" ]]; then
        cf_key="${CF_Key}"
    fi
    if [[ -z "$cf_email" ]]; then
        cf_email="${CF_Email}"
    fi
    if [[ -z "$cf_key" || -z "$cf_email" ]]; then
        local acme_account_conf="/root/.acme.sh/account.conf"
        if [[ -f "$acme_account_conf" ]]; then
            if [[ -z "$cf_key" ]]; then
                cf_key=$(grep -E "^SAVED_CF_Key=" "$acme_account_conf" | head -1 | cut -d"'" -f2)
            fi
            if [[ -z "$cf_email" ]]; then
                cf_email=$(grep -E "^SAVED_CF_Email=" "$acme_account_conf" | head -1 | cut -d"'" -f2)
            fi
        fi
    fi
    if [[ -z "$cf_key" || -z "$cf_email" ]]; then
        echo -e "${red}缺少 Cloudflare DNS 凭证 (CF_Key/CF_Email)${plain}"
        exit 1
    fi
    export CF_Key="$cf_key"
    export CF_Email="$cf_email"
    "$acme_sh" --force --issue -d "$cert_domain" --dns dns_cf
    if [[ $? != 0 ]]; then
        echo -e "${red}证书申请失败${plain}"
        exit 1
    fi
    local cert_source_dir="/root/.acme.sh/${cert_domain}_ecc"
    if [[ ! -f "${cert_source_dir}/fullchain.cer" || ! -f "${cert_source_dir}/${cert_domain}.key" ]]; then
        echo -e "${red}证书文件不存在，请检查 acme.sh 输出${plain}"
        exit 1
    fi
    cp "${cert_source_dir}/fullchain.cer" ${config_dir}fullchain.cer
    cp "${cert_source_dir}/${cert_domain}.key" ${config_dir}cert.key
}

install_app() {
    if [[ -f ${install_dir}${app_name} && "$force_reinstall" != true ]]; then
        if [[ x"${release}" == x"alpine" ]]; then
            service ${app_name} start
        else
            systemctl start ${app_name}
        fi
        return 0
    fi
    if [[ -e ${install_dir} ]]; then
        rm -rf ${install_dir}
    fi

    mkdir ${install_dir} -p
    cd ${install_dir}

    last_version=${1:-${default_version}}
    if [[ -z "$repo_base_url" ]]; then
        echo -e "${red}必须提供仓库地址用于下载安装包${plain}"
        exit 1
    fi
    local remote_zip=""
    local package_name="${app_name_lower}-linux-${arch}.zip"

    if [[ "$repo_base_url" == *"/releases/download" ]]; then
        remote_zip="${repo_base_url}/${last_version}/${package_name}"
    else
        remote_zip="${repo_base_url}/scripts/packages/${last_version}/${package_name}"
    fi

    curl -fL --retry 3 --connect-timeout 10 --max-time 300 -o ${install_dir}${app_name_lower}-linux.zip "$remote_zip" >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        if [[ "$last_version" == v* ]]; then
            local alt_version="${last_version#v}"
            if [[ "$repo_base_url" == *"/releases/download" ]]; then
                remote_zip="${repo_base_url}/${alt_version}/${package_name}"
            else
                remote_zip="${repo_base_url}/scripts/packages/${alt_version}/${package_name}"
            fi
            curl -fL --retry 3 --connect-timeout 10 --max-time 300 -o ${install_dir}${app_name_lower}-linux.zip "$remote_zip" >/dev/null 2>&1
        fi
    fi
    if [[ $? != 0 ]]; then
        echo -e "${red}下载 ${app_name} 安装包失败${plain}"
        exit 1
    fi

    unzip ${app_name_lower}-linux.zip
    rm ${app_name_lower}-linux.zip -f
    chmod +x ${app_name}
    mkdir ${config_dir} -p
    cp geoip.dat ${config_dir}
    cp geosite.dat ${config_dir}

    if [[ x"${release}" == x"alpine" ]]; then
        rm /etc/init.d/${app_name} -f
        cat <<EOF > /etc/init.d/${app_name}
#!/sbin/openrc-run

name="${app_name}"
description="${app_name}"

command="${install_dir}${app_name}"
command_args="server"
command_user="root"

pidfile="/run/${app_name}.pid"
command_background="yes"

depend() {
        need net
}
EOF
        chmod +x /etc/init.d/${app_name}
        rc-update add ${app_name} default
        :
    else
        rm /etc/systemd/system/${app_name}.service -f
        cat <<EOF > /etc/systemd/system/${app_name}.service
[Unit]
Description=${app_name} Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Group=root
Type=simple
LimitAS=infinity
LimitRSS=infinity
LimitCORE=infinity
LimitNOFILE=999999
WorkingDirectory=${install_dir}
ExecStart=${install_dir}${app_name} server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl stop ${app_name}
        systemctl enable ${app_name}
        :
    fi

    if [[ ! -f ${config_dir}config.json ]]; then
        if [[ "$app_type" == "v2bx" ]]; then
            cp config.json ${config_dir}
        fi
        first_install=true
    else
        if [[ x"${release}" == x"alpine" ]]; then
            service ${app_name} start
        else
            systemctl start ${app_name}
        fi
        sleep 2
        check_status
        if [[ $? != 0 ]]; then
            echo -e "${red}${app_name} 可能启动失败，请稍后使用 ${app_name_lower} log 查看日志信息${plain}"
        fi
        first_install=false
    fi

    # V2bX 需要额外的配置文件
    if [[ "$app_type" == "v2bx" ]]; then
        if [[ ! -f ${config_dir}dns.json ]]; then
            cp dns.json ${config_dir}
        fi
        if [[ ! -f ${config_dir}route.json ]]; then
            cp route.json ${config_dir}
        fi
        if [[ ! -f ${config_dir}custom_outbound.json ]]; then
            cp custom_outbound.json ${config_dir}
        fi
        if [[ ! -f ${config_dir}custom_inbound.json ]]; then
            cp custom_inbound.json ${config_dir}
        fi
    fi

    cat <<EOF > /usr/bin/${app_name_lower}
#!/bin/bash
cmd="\$1"
if [[ -z "\$cmd" ]]; then
    echo "用法: ${app_name_lower} {start|stop|restart|status|log|logs|enable|disable|config}"
    exit 1
fi
if command -v systemctl >/dev/null 2>&1; then
    svc_start="systemctl start ${app_name}"
    svc_stop="systemctl stop ${app_name}"
    svc_restart="systemctl restart ${app_name}"
    svc_status="systemctl status ${app_name} --no-pager"
    svc_enable="systemctl enable ${app_name}"
    svc_disable="systemctl disable ${app_name}"
else
    svc_start="service ${app_name} start"
    svc_stop="service ${app_name} stop"
    svc_restart="service ${app_name} restart"
    svc_status="service ${app_name} status"
    svc_enable="rc-update add ${app_name} default"
    svc_disable="rc-update del ${app_name} default"
fi
case "\$cmd" in
    start)
        \$svc_start
        ;;
    stop)
        \$svc_stop
        ;;
    restart)
        \$svc_restart
        ;;
    status)
        \$svc_status
        ;;
    log|logs)
        if command -v journalctl >/dev/null 2>&1; then
            journalctl -u ${app_name} -e --no-pager
        elif [[ -f ${config_dir}error.log ]]; then
            tail -n 200 ${config_dir}error.log
        else
            echo "未找到日志"
            exit 1
        fi
        ;;
    enable)
        \$svc_enable
        ;;
    disable)
        \$svc_disable
        ;;
    config)
        if [[ -f ${config_dir}config.json ]]; then
            cat ${config_dir}config.json
        else
            echo "未找到配置文件"
            exit 1
        fi
        ;;
    version)
        if [[ -f ${install_dir}${app_name} ]]; then
            ${install_dir}${app_name} version
        else
            echo "未找到程序文件"
            exit 1
        fi
        ;;
    *)
        echo "用法: ${app_name_lower} {start|stop|restart|status|log|logs|enable|disable|config|version}"
        exit 1
        ;;
esac
EOF
    chmod +x /usr/bin/${app_name_lower}

    # 创建别名
    if [[ "$app_type" == "v2bx" ]] && [ ! -L /usr/bin/v2bx ]; then
        ln -s /usr/bin/${app_name_lower} /usr/bin/v2bx
        chmod +x /usr/bin/v2bx
    fi

    cd $cur_dir

    if [[ "$auto_config_enabled" == true ]]; then
        if [[ "$app_type" == "v2bx" ]]; then
            issue_certificate
            auto_generate_config_v2bx
        else
            auto_generate_config_v2node
        fi
    fi
}

install_base

# 默认参数
app_type="v2node"
config_file_path=""
version=""
backend_url=""
backend_key=""
node_id=""
core_type=""
transport_type=""
cert_domain=""
acme_email=""
cf_key=""
cf_email=""
cf_token=""
cf_account_id=""
auto_config_enabled=false
force_reinstall=false

trim_value() {
    local v="$1"
    v="${v//\`/}"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    echo "$v"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --type|-t)
            app_type="$2"
            shift 2
            ;;
        --config|-c)
            config_file_path="$2"
            auto_config_enabled=true
            shift 2
            ;;
        --version|-v)
            version="$2"
            shift 2
            ;;
        --repo-base|-r)
            repo_base_url="$2"
            shift 2
            ;;
        --backend-url)
            backend_url="$2"
            auto_config_enabled=true
            shift 2
            ;;
        --backend-key)
            backend_key="$2"
            auto_config_enabled=true
            shift 2
            ;;
        --node-id)
            node_id="$2"
            auto_config_enabled=true
            shift 2
            ;;
        --core-type)
            core_type="$2"
            auto_config_enabled=true
            shift 2
            ;;
        --transport-type)
            transport_type="$2"
            auto_config_enabled=true
            shift 2
            ;;
        --cert-domain)
            cert_domain="$2"
            auto_config_enabled=true
            shift 2
            ;;
        --force-reinstall)
            force_reinstall=true
            shift
            ;;
        --acme-email)
            acme_email="$2"
            auto_config_enabled=true
            shift 2
            ;;
        --cf-key)
            cf_key="$2"
            auto_config_enabled=true
            shift 2
            ;;
        --cf-email)
            cf_email="$2"
            auto_config_enabled=true
            shift 2
            ;;
        --cf-token)
            cf_token="$2"
            auto_config_enabled=true
            shift 2
            ;;
        --cf-account-id)
            cf_account_id="$2"
            auto_config_enabled=true
            shift 2
            ;;
        *.yml|*.yaml)
            config_file_path="$1"
            auto_config_enabled=true
            shift
            ;;
        *)
            if [[ -z "$version" ]]; then
                version="$1"
            fi
            shift
            ;;
    esac
done

# 规范化类型
app_type=$(echo "$app_type" | tr '[:upper:]' '[:lower:]')
if [[ "$app_type" != "v2node" && "$app_type" != "v2bx" ]]; then
    echo -e "${red}不支持的类型: $app_type，请使用 v2node 或 v2bx${plain}"
    exit 1
fi

# 获取最新版本
get_latest_version() {
    local repo=$1
    local version=$(curl -s "https://api.github.com/repos/$repo/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ -z "$version" ]]; then
        local url=$(curl -Ls -o /dev/null -w %{url_effective} "https://github.com/$repo/releases/latest")
        version=${url##*/}
    fi
    echo "$version"
}

# 根据类型设置变量
if [[ "$app_type" == "v2node" ]]; then
    app_name="v2node"
    app_name_lower="v2node"
    install_dir="/usr/local/v2node/"
    config_dir="/etc/v2node/"
    latest_version=$(get_latest_version "LiukerSun/v2node")
    default_version="${latest_version:-v0.2.7}"
    repo_base_url="${REPO_BASE_URL:-https://github.com/LiukerSun/v2node/releases/download}"
elif [[ "$app_type" == "v2bx" ]]; then
    app_name="V2bX"
    app_name_lower="V2bX"
    install_dir="/usr/local/V2bX/"
    config_dir="/etc/V2bX/"
    latest_version=$(get_latest_version "LiukerSun/v2bx")
    default_version="${latest_version:-v0.4.1}"
    repo_base_url="${REPO_BASE_URL:-https://github.com/LiukerSun/v2bx/releases/download}"
fi

# 设置版本
if [[ -z "$version" ]]; then
    version="${default_version}"
fi
if [[ "$version" != v* ]]; then
    version="v$version"
fi

repo_base_url=$(trim_value "$repo_base_url")
backend_url=$(trim_value "$backend_url")
cert_domain=$(trim_value "$cert_domain")

if [[ -n "$config_file_path" ]]; then
    parse_config_file "$config_file_path"
fi

if [[ "$auto_config_enabled" == true ]]; then
    validate_config
fi

echo -e "${green}正在安装 ${app_name} ${version}...${plain}"
install_app "$version"
echo -e "${green}${app_name} 安装完成！${plain}"
echo -e "使用 ${yellow}${app_name_lower} status${plain} 查看运行状态"
echo -e "使用 ${yellow}${app_name_lower} log${plain} 查看日志"
