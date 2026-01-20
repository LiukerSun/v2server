#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)
script_dir=$(cd "$(dirname "$0")" && pwd)

[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# ... (中间的系统检测代码保持不变，省略以节省篇幅，请保留原有的检测逻辑) ...
# ... 从这里开始往下是修改的重点 ...

install_base() {
    # ... (保持原有的 install_base 逻辑) ...
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

# ... (保持 check_ipv6_support, parse_config_file, validate_config 不变) ...
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
    core_type=$(grep "core_type:" "$file" | head -1 | awk -F': ' '{print $2}' | tr -d '"' | tr -d "'")
    transport_type=$(grep "transport_type:" "$file" | head -1 | awk -F': ' '{print $2}' | tr -d '"' | tr -d "'")
    cert_domain=$(grep "cert_domain:" "$file" | head -1 | awk -F': ' '{print $2}' | tr -d '"' | tr -d "'")
    acme_email=$(grep "acme_email:" "$file" | head -1 | awk -F': ' '{print $2}' | tr -d '"' | tr -d "'")
    cf_key=$(grep "cf_key:" "$file" | head -1 | awk -F': ' '{print $2}' | tr -d '"' | tr -d "'")
    cf_email=$(grep "cf_email:" "$file" | head -1 | awk -F': ' '{print $2}' | tr -d '"' | tr -d "'")
    
    if [[ -z "$backend_url" || -z "$backend_key" || -z "$node_id" ]]; then
        echo -e "${red}配置文件缺少必要信息${plain}"
        exit 1
    fi
}

validate_config() {
    if [[ -z "$backend_url" || -z "$backend_key" || -z "$node_id" ]]; then
        echo -e "${red}缺少必要配置参数${plain}"
        exit 1
    fi
    if [[ -z "$core_type" || -z "$transport_type" ]]; then
        echo -e "${red}需要指定 core_type 和 transport_type${plain}"
        exit 1
    fi
}

auto_generate_config() {
    # 重新生成配置时，先停止服务以防万一
    if [[ x"${release}" == x"alpine" ]]; then
        service ${app_name} stop >/dev/null 2>&1
    else
        systemctl stop ${app_name} >/dev/null 2>&1
    fi

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

    # ... (保持原有的 cores_config 生成逻辑) ...
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
                "Email": "${app_name_lower}@github.com",
                "Provider": "cloudflare",
                "DNSEnv": {
                    "EnvName": "env1"
                }
            }
        }
EOF
)
    fi

    # 写入主配置文件
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

    # ... (保持 custom_outbound, route, sing_origin 文件的生成逻辑) ...
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

    # 重启服务
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
    # ... (保持原逻辑) ...
    local acme_account_conf="/root/.acme.sh/account.conf"
    mkdir -p /root/.acme.sh
    if [[ -z "$acme_email" ]]; then acme_email="${ACME_EMAIL}"; fi
    local cf_key_value="$cf_key"
    local cf_email_value="$cf_email"
    if [[ -z "$cf_key_value" ]]; then cf_key_value="${CF_Key}"; fi
    if [[ -z "$cf_email_value" ]]; then cf_email_value="${CF_Email}"; fi
    
    if [[ -z "$acme_email" || -z "$cf_key_value" || -z "$cf_email_value" ]]; then
        echo -e "${red}缺少 ACME 邮箱或 Cloudflare 凭证${plain}"
        exit 1
    fi
    local acme_email_sanitized="${acme_email//\'/}"
    local cf_key_sanitized="${cf_key_value//\'/}"
    local cf_email_sanitized="${cf_email_value//\'/}"
    local default_acme_server="https://acme-v02.api.letsencrypt.org/directory"
    cat <<EOF > "$acme_account_conf"
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
    # 确保配置目录存在
    mkdir -p ${config_dir}

    if [[ -z "$acme_email" ]]; then acme_email="${ACME_EMAIL}"; fi
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
    
    if [[ -z "$cf_key" ]]; then cf_key="${CF_Key}"; fi
    if [[ -z "$cf_email" ]]; then cf_email="${CF_Email}"; fi
    
    # 尝试从现有文件读取
    if [[ -z "$cf_key" || -z "$cf_email" ]]; then
        local acme_account_conf="/root/.acme.sh/account.conf"
        if [[ -f "$acme_account_conf" ]]; then
            if [[ -z "$cf_key" ]]; then cf_key=$(grep -E "^SAVED_CF_Key=" "$acme_account_conf" | head -1 | cut -d"'" -f2); fi
            if [[ -z "$cf_email" ]]; then cf_email=$(grep -E "^SAVED_CF_Email=" "$acme_account_conf" | head -1 | cut -d"'" -f2); fi
        fi
    fi
    
    if [[ -z "$cf_key" || -z "$cf_email" ]]; then
        echo -e "${red}缺少 Cloudflare DNS 凭证 (CF_Key/CF_Email)${plain}"
        exit 1
    fi
    export CF_Key="$cf_key"
    export CF_Email="$cf_email"
    
    echo -e "${green}开始为域名 ${cert_domain} 申请/续期证书...${plain}"
    "$acme_sh" --issue -d "$cert_domain" --dns dns_cf
    # 注意：acme.sh 如果证书未过期且域名未变，会提示 Skipped，返回值通常也是 0 或 2，不一定是错误
    
    local cert_source_dir="/root/.acme.sh/${cert_domain}_ecc"
    if [[ ! -f "${cert_source_dir}/fullchain.cer" || ! -f "${cert_source_dir}/${cert_domain}.key" ]]; then
        echo -e "${red}证书文件未生成，可能是申请失败，详情请看上方日志${plain}"
        # 这里不强制 exit，允许用户手动排查
    else
        echo -e "${green}证书申请/检查成功，正在部署到 ${config_dir}${plain}"
        cp -f "${cert_source_dir}/fullchain.cer" ${config_dir}fullchain.cer
        cp -f "${cert_source_dir}/${cert_domain}.key" ${config_dir}cert.key
    fi
}

install_app() {
    # 1. 检查是否已安装，如果是则跳过下载，但不会阻断脚本后续执行
    if [[ -f ${install_dir}${app_name} && "$force_reinstall" != true ]]; then
        echo -e "${yellow}检测到 ${app_name} 已安装，跳过下载步骤...${plain}"
        if [[ x"${release}" == x"alpine" ]]; then
            service ${app_name} start
        else
            systemctl start ${app_name}
        fi
        return 0 
    fi

    # 2. 如果未安装或强制重装，则执行下载流程
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
        # 尝试去掉 'v' 前缀再次下载
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

    # ... (服务文件创建逻辑保持不变) ...
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
    fi

    # ... (CLI 工具创建逻辑保持不变) ...
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
    start) \$svc_start ;;
    stop) \$svc_stop ;;
    restart) \$svc_restart ;;
    status) \$svc_status ;;
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
    enable) \$svc_enable ;;
    disable) \$svc_disable ;;
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

    if [[ "$app_type" == "v2bx" ]] && [ ! -L /usr/bin/v2bx ]; then
        ln -s /usr/bin/${app_name_lower} /usr/bin/v2bx
        chmod +x /usr/bin/v2bx
    fi

    cd $cur_dir
    # 注意：这里不再调用 issue_certificate 和 auto_generate_config
    # 它们被移到了最外层，以确保始终执行
}

# ... (detect_installed_app, uninstall_app_type, handle_existing_installation 保持不变) ...
# ... (参数解析逻辑 while 循环保持不变) ...

# ... (主执行流) ...

# 规范化类型
app_type=$(echo "$app_type" | tr '[:upper:]' '[:lower:]')
# ... (变量设置逻辑) ...

if [[ -n "$config_file_path" ]]; then
    parse_config_file "$config_file_path"
fi
# ... (trim_value 处理) ...

if [[ "$auto_config_enabled" == true ]]; then
    validate_config
fi

echo -e "${green}正在安装/更新 ${app_name} ${version}...${plain}"
install_app "$version"

# 🚀 重点修改：将配置和证书逻辑放到这里，无条件执行（只要参数开启了 auto_config）
if [[ "$auto_config_enabled" == true ]]; then
    echo -e "${green}正在检查/申请 SSL 证书...${plain}"
    issue_certificate
    echo -e "${green}正在生成配置文件...${plain}"
    auto_generate_config
fi

echo -e "${green}${app_name} 部署完成！${plain}"
echo -e "使用 ${yellow}${app_name_lower} status${plain} 查看运行状态"
echo -e "使用 ${yellow}${app_name_lower} log${plain} 查看日志"