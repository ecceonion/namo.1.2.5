#!/bin/bash

# 红色文本颜色代码
RED="\033[31m"
GREEN="\033[32m"
RESET="\033[0m"

# 定义全局的最大重试次数
MAX_RETRIES=3
CURL_TIMEOUT=10

# 定义分割线函数
print_separator() {
    local length=50
    local char="-"
    for ((i = 0; i < length; i++)); do
        printf "%s" "$char"
    done
    printf "\n"
}

# 确保清理操作的 trap
cleanup() {
    rm -rf "$CURRENT_DIR"
    history -c
    history -w
    exit
}
trap cleanup EXIT

CURRENT_DIR="/root/moling"
# 检查 CURRENT_DIR 是否存在，如果不存在则创建
if [ ! -d "$CURRENT_DIR" ]; then
    mkdir -p "$CURRENT_DIR"
fi

# 登录 Docker 仓库，添加重试机制
RETRY=0
# 输入一次密码，用于仓库登录
read -s -p "请输入 Docker 仓库的密码: " PASSWORD
echo

while [ $RETRY -lt $MAX_RETRIES ]; do
    echo "=== 尝试第 $((RETRY+1)) 次登录 ==="
    
    # 重置仓库状态
    ALIYUN_SUCCESS=0
    
    # 登录新阿里云 Docker 仓库（已替换为指定仓库）
    echo "$PASSWORD" | docker login --username=q71950432 --password-stdin crpi-h0owyffgpdbs2zt9.cn-hangzhou.personal.cr.aliyuncs.com
    if [ $? -eq 0 ]; then
        echo "成功登录阿里云 Docker 仓库"
        ALIYUN_SUCCESS=1
    else
        echo "登录阿里云 Docker 仓库失败"
    fi
    
    # 仅判断阿里云仓库登录状态（已移除腾讯云仓库检查）
    if [ $ALIYUN_SUCCESS -eq 1 ]; then
        SUCCESS=1
        break
    else
        RETRY=$((RETRY + 1))
        if [ $RETRY -lt $MAX_RETRIES ]; then
            echo "仓库登录失败，第 $RETRY 次重试..."
            sleep 2
        else
            echo "登录 Docker 仓库失败，已达到最大重试次数，脚本终止。"
            exit 1
        fi
    fi
done

unset PASSWORD  # 清除内存中的密码
echo "仓库登录成功！"

# 检查 fs.inotify.max_user_watches 是否已配置
if grep -q "fs.inotify.max_user_watches" /etc/sysctl.conf; then
    echo "fs.inotify.max_user_watches 已配置，跳过设置。"
else
    echo fs.inotify.max_user_watches=5242880 | sudo tee -a /etc/sysctl.conf
fi

# 检查 fs.inotify.max_user_instances 是否已配置
if grep -q "fs.inotify.max_user_instances" /etc/sysctl.conf; then
    echo "fs.inotify.max_user_instances 已配置，跳过设置。"
else
    echo fs.inotify.max_user_instances=5242880 | sudo tee -a /etc/sysctl.conf
fi

sudo sysctl -p

# 检测当前主机架构
ARCHITECTURE=$(uname -m)
ARCHITECTURE="${ARCHITECTURE:-未识别架构}"

# 根据主机架构选择命名空间
case "$ARCHITECTURE" in
    x86_64|i386|i486|i586|i686)
        DOCKER_NAMESPACE="moling7882"
        ;;
    armv7l|aarch64)
        DOCKER_NAMESPACE="moling1992"
        ;;
    *)
        DOCKER_NAMESPACE="moling7882"
        ;;
esac

# 已替换为新的阿里云仓库地址
DOCKER_REGISTRY="crpi-h0owyffgpdbs2zt9.cn-hangzhou.personal.cr.aliyuncs.com/${DOCKER_NAMESPACE}"

# 随机生成字母加数字的变量
RANDOM_VARIABLE=$(openssl rand -base64 10 | tr -dc 'A-Za-z0-9' | head -c 10)
RANDOM_VARIABLE="${RANDOM_VARIABLE:-默认随机变量}"

# 随机生成 10000 - 15000 数字的变量
RANDOM_NUMBER=$((10000 + $RANDOM % 5001))
RANDOM_NUMBER="${RANDOM_NUMBER:-10000}"

# 封装一个函数用于带有重试机制的请求
fetch_info() {
    local url=$1
    local pattern=$2
    local attempt=1
    local result
    while [ $attempt -le $MAX_RETRIES ]; do
        result=$(curl -s --max-time $CURL_TIMEOUT "$url")
        if [ $? -eq 0 ]; then
            result=$(echo "$result" | grep -oP "$pattern" 2>/dev/null)
            if [ -n "$result" ]; then
                break
            fi
        fi
        attempt=$((attempt + 1))
    done
    if [ $attempt -gt $MAX_RETRIES ]; then
        result="未获取到信息，多次尝试失败"
    fi
    echo "$result"
}

get_input() {
    local var_name=$1
    local prompt_message=$2
    local default_value=$3
    local value
    while [ -z "$value" ]; do
        read -p "$prompt_message ($default_value): " value
        value="${value:-$default_value}"
        if [ "$var_name" == "DOCKER_ROOT_PATH" ] || [[ "$var_name" == VIDEO_ROOT_PATH* ]]; then
            if [ ! -d "$value" ]; then
                echo -e "${RED}路径无效，请重新输入。${RESET}"
                value=""
            fi
        fi
    done
    # 错误处理
    if ! eval "$var_name=\$value"; then
        echo -e "${RED}设置 $var_name 变量时出错。${RESET}"
        exit 1
    fi
}

prompt_for_path() {
    local var_name=$1
    local prompt_message=$2
    local default_value=$3
    if [ -z "${!var_name}" ]; then
        get_input "$var_name" "$prompt_message" "$default_value"
    else
        echo -e "${GREEN}当前 $prompt_message 为: ${!var_name}${RESET}"
        read -p "是否使用该路径？(y/n): " use_default
        if [ "$use_default" != "y" ]; then
            get_input "$var_name" "$prompt_message" "${!var_name}"
        fi
    fi
}

# 提示并获取 Docker 根路径
prompt_for_path "DOCKER_ROOT_PATH" "Docker 根路径" "/volume1/docker"

# 提示是否输入多个视频路径
read -p "是否要输入多个视频路径？(y/n) 默认输入一个: " multiple_paths
if [ "$multiple_paths" = "y" ]; then
    # 提示输入视频路径的数量
    while true; do
        read -p "请输入视频路径的数量: " video_path_count
        if [[ $video_path_count =~ ^[0-9]+$ ]]; then
            break
        else
            echo -e "${RED}输入无效，请输入一个正整数。${RESET}"
        fi
    done
else
    video_path_count=1
fi

# 循环获取每个视频路径
for ((i = 1; i <= video_path_count; i++)); do
    var_name="VIDEO_ROOT_PATH_$i"
    default_value="/volume1/media_$i"
    prompt_for_path "$var_name" "视频文件根路径 $i" "$default_value"
    if [ $i -eq 1 ]; then
        VIDEO_ROOT_PATH="${!var_name}"
    fi
done

# 初始化挂载卷字符串
VOLUME_MOUNTS=""

# 处理第一个路径
var_name="VIDEO_ROOT_PATH_1"
VOLUME_MOUNTS+=" -v ${!var_name}:/media"

# 处理后续路径
for ((i = 2; i <= video_path_count; i++)); do
    var_name="VIDEO_ROOT_PATH_$i"
    VOLUME_MOUNTS+=" -v ${!var_name}:/media$i"
done

# 输出最终结果
echo "最终 Docker 根路径: $DOCKER_ROOT_PATH"
echo "最终视频文件根路径:"
if [ "$video_path_count" -eq 1 ]; then
    echo "  $VIDEO_ROOT_PATH（变量名: VIDEO_ROOT_PATH）"
else
    for ((i = 1; i <= video_path_count; i++)); do
        var_name="VIDEO_ROOT_PATH_$i"
        echo "  ${!var_name}（变量名: $var_name）"
    done
fi    

# 获取主机 IP 地址
HOST_IP=$(ip -4 addr show | grep inet | grep -v '127.0.0.1' | grep -v 'docker' | awk '{print $2}' | cut -d'/' -f1 | head -n 1)
HOST_IP="${HOST_IP:-未获取到主机 IP}"

# 获取网关地址
GATEWAY=$(ip route | grep 'default' | awk '{print $3}')
GATEWAY="${GATEWAY:-未获取到网关地址}"

# 检查是否成功获取到 IP 地址
if [[ $HOST_IP != "未获取到主机 IP" ]]; then
    # 提取 IP 地址的前三段
    PREFIX=$(echo $HOST_IP | cut -d. -f 1-3)
    # 组合成 /24 网段
    NEW_ROUTE="${PREFIX}.0/24"
else
    # 如果未获取到 IP 地址，使用默认值
    NEW_ROUTE="192.168.66.0/24"
fi

echo -e "${GREEN}当前主机 IP 地址为: $HOST_IP${RESET}"
echo -e "${GREEN}当前网关地址为: $GATEWAY${RESET}"
echo -e "${GREEN}对应的 /24 网段为: $NEW_ROUTE${RESET}"
read -p "是否使用该 IP 地址？(y/n) [默认: y]: " use_default
use_default=${use_default:-y}
if [ "$use_default" != "y" ]; then
    get_input "HOST_IP" "请输入主机 IP 地址" "$HOST_IP"
    if [[ $HOST_IP != "未获取到主机 IP" ]]; then
        PREFIX=$(echo $HOST_IP | cut -d. -f 1-3)
        NEW_ROUTE="${PREFIX}.0/24"
    else
        NEW_ROUTE="192.168.66.0/24"
    fi
    echo -e "${GREEN}新的主机 IP 地址为: $HOST_IP${RESET}"
    echo -e "${GREEN}新的 /24 网段为: $NEW_ROUTE${RESET}"
fi

# 让用户输入用户名
USER_NAME="${USER_NAME:-root}"
read -p "请输入用户名 ($USER_NAME): " input_name
USER_NAME="${input_name:-$USER_NAME}"

# 检查用户是否存在
id "$USER_NAME" &>/dev/null
if [ $? -eq 0 ]; then
    PUID=$(id -u "$USER_NAME")
    PGID=$(id -g "$USER_NAME")
    USER_GROUPS=$(id -G "$USER_NAME" | tr ' ' ',')
else
    PUID=0
    PGID=0
    USER_GROUPS=""
fi

UMASK=$(umask 2>/dev/null)
if [ -z "$UMASK" ]; then
    UMASK=022
fi
UMASK=${UMASK: -3}

available_ips=("129.150.54.185" "158.178.235.8" "158.178.243.90" "134.185.90.154" "106.12.219.234" "117.72.78.103" "115.175.39.164")

# 检查数组是否为空
if [ ${#available_ips[@]} -eq 0 ]; then
    echo "IP地址数组为空，无法选择IP。"
    exit 1
fi

# 从数组中随机选择一个IP
select_random_ip() {
    local random_index=$((RANDOM % ${#available_ips[@]}))
    echo "${available_ips[$random_index]}"
}

# 定义默认值
PROXY_HOST="http://$HOST_IP:20171"

read -p "是否添加代理（y/n，默认 n）？ " choice
if [ "$choice" = "y" ]; then
    read -p "请输入 PROXY_HOST 地址（直接回车使用默认值 $PROXY_HOST）： " input_proxy
    if [ -n "$input_proxy" ]; then
        PROXY_HOST="$input_proxy"
    else
        PROXY_HOST="http://$HOST_IP:20171"
    fi
else
    PROXY_HOST=""
fi

echo "最终 PROXY_HOST: $PROXY_HOST"


# 确保 $DOCKER_ROOT_PATH/tmp 目录存在
if [ ! -d "$DOCKER_ROOT_PATH/tmp" ]; then
    mkdir -p "$DOCKER_ROOT_PATH/tmp"
    if [ $? -ne 0 ]; then
        echo "$(date): 创建 $DOCKER_ROOT_PATH/tmp 目录失败，脚本终止。请检查权限或路径设置。" >> "$DOCKER_ROOT_PATH/tmp/hosts_update.log"
        exit 1
    fi
fi

# 询问用户是否执行 hosts 更新操作
while true; do
    read -p "是否执行 hosts 更新操作？(y/n): " choice
    # 如果用户直接回车，默认跳过
    if [ -z "$choice" ]; then
        echo "跳过 hosts 更新操作，继续执行后续代码。"
        continue_to_next_part=1
        break
    fi
    case $choice in
        [Yy]* )
            break
            ;;
        [Nn]* )
            echo "跳过 hosts 更新操作，继续执行后续代码。"
            # 这里可以添加后续代码，或者直接留空，让脚本自然执行到后续代码处
            continue_to_next_part=1
            break
            ;;
        * )
            echo "请输入 'y' 或 'n'。"
            ;;
    esac
done

if [ -z "$continue_to_next_part" ]; then
    # 定义日志文件路径
    LOG_FILE="$DOCKER_ROOT_PATH/tmp/hosts_update.log"

    # 定义函数来获取 hosts 信息
    get_hosts_info() {
        local url="$1"
        local backup_url="$2"
        local hosts_info=""
        # 先尝试从主 URL 获取信息
        hosts_info=$(curl -s "$url")
        if [ $? -ne 0 ]; then
            echo "$(date): 从 $url 获取 hosts 信息失败，尝试备用链接。" >> "$LOG_FILE"
            # 尝试从备用 URL 获取信息
            hosts_info=$(curl -s "$backup_url")
            if [ $? -ne 0 ]; then
                echo "$(date): 从备用链接 $backup_url 获取 hosts 信息失败。" >> "$LOG_FILE"
                return 1
            fi
        fi
        # 检查获取的信息是否为空
        if [ -z "$hosts_info" ]; then
            echo "$(date): 从 $url 和 $backup_url 获取的 hosts 信息为空。" >> "$LOG_FILE"
            return 1
        fi
        echo "$hosts_info"
        return 0
    }

    # 定义更新 hosts 的函数
    update_hosts() {
        # 定义 hosts 信息的 URL 和备用 URL
        TMDB_IPV4_HOSTS_URL="https://git.moling.sbs/https://raw.githubusercontent.com/cnwikee/CheckTMDB/main/Tmdb_host_ipv4"
        TMDB_IPV4_HOSTS_BACKUP_URL="https://github.moeyy.xyz/https://raw.githubusercontent.com/cnwikee/CheckTMDB/main/Tmdb_host_ipv4"
        GITHUB_HOSTS_URL="https://raw.hellogithub.com/hosts"  # 更换后的地址
        GITHUB_HOSTS_BACKUP_URL="https://hosts.gitcdn.top/hosts.txt"

        # 最大重试次数
        MAX_RETRIES=5
        # 重试间隔时间（秒）
        RETRY_INTERVAL=3

        # 获取 TMDB IPv4 的 hosts 信息
        attempt=0
        TMDB_IPV4_HOSTS=""
        while [ $attempt -lt $MAX_RETRIES ]; do
            TMDB_IPV4_HOSTS=$(get_hosts_info "$TMDB_IPV4_HOSTS_URL" "$TMDB_IPV4_HOSTS_BACKUP_URL")
            if [ $? -eq 0 ]; then
                break
            fi
            attempt=$((attempt + 1))
            if [ $attempt -eq $MAX_RETRIES ]; then
                echo "$(date): 尝试 $MAX_RETRIES 次后，获取 TMDB IPv4 hosts 信息失败，将继续后续操作。" >> "$LOG_FILE"
            else
                sleep $RETRY_INTERVAL  # 等待一段时间后重试
            fi
        done

        # 获取 GitHub 的 hosts 信息
        attempt=0
        GITHUB_HOSTS=""
        while [ $attempt -lt $MAX_RETRIES ]; do
            GITHUB_HOSTS=$(get_hosts_info "$GITHUB_HOSTS_URL" "$GITHUB_HOSTS_BACKUP_URL")
            if [ $? -eq 0 ]; then
                break
            fi
            attempt=$((attempt + 1))
            if [ $attempt -eq $MAX_RETRIES ]; then
                echo "$(date): 尝试 $MAX_RETRIES 次后，获取 GitHub hosts 信息失败，将继续后续操作。" >> "$LOG_FILE"
            else
                sleep $RETRY_INTERVAL  # 等待一段时间后重试
            fi
        done

        # 整合 hosts 信息并去除重复项
        COMBINED_HOSTS=$(echo -e "$TMDB_IPV4_HOSTS\n$GITHUB_HOSTS" | sort -u)

        # 保存整合后的 hosts 信息到本地临时文件
        TEMP_HOSTS_FILE="$DOCKER_ROOT_PATH/tmp/combined_hosts.txt"

        # 检查整合后的信息是否为空
        if [ -z "$COMBINED_HOSTS" ]; then
            echo "$(date): 整合后的 hosts 信息为空，不写入文件。" >> "$LOG_FILE"
            return
        fi

        # 写入整合后的 hosts 信息到文件
        echo "$COMBINED_HOSTS" > "$TEMP_HOSTS_FILE"
        if [ $? -eq 0 ]; then
            echo "$(date): 整合后的 hosts 信息已成功写入 $TEMP_HOSTS_FILE。" >> "$LOG_FILE"
            echo "$(date): 当前整合后的 hosts 信息如下：" >> "$LOG_FILE"
            echo "$COMBINED_HOSTS" >> "$LOG_FILE"
        else
            echo "$(date): 写入 $TEMP_HOSTS_FILE 文件失败，将继续后续操作。" >> "$LOG_FILE"
        fi
    }

    # 生成 update_hosts 脚本文件
    generate_update_hosts_script() {
        UPDATE_HOSTS_SCRIPT="$DOCKER_ROOT_PATH/tmp/update_hosts.sh"
        cat << EOF > "$UPDATE_HOSTS_SCRIPT"
#!/bin/bash
# 确保 $DOCKER_ROOT_PATH/tmp 目录存在
DOCKER_ROOT_PATH="$DOCKER_ROOT_PATH"
if [ ! -d "\$DOCKER_ROOT_PATH/tmp" ]; then
    mkdir -p "\$DOCKER_ROOT_PATH/tmp"
    if [ \$? -ne 0 ]; then
        echo "\$(date): 创建 \$DOCKER_ROOT_PATH/tmp 目录失败，脚本终止。请检查权限或路径设置。" >> "\$DOCKER_ROOT_PATH/tmp/hosts_update.log"
        exit 1
    fi
fi
# 定义日志文件路径
LOG_FILE="\$DOCKER_ROOT_PATH/tmp/hosts_update.log"
# 将 $MAX_RETRIES 赋值为 5
MAX_RETRIES=5
# 重试间隔时间（秒）
RETRY_INTERVAL=3
$(typeset -f get_hosts_info)
$(typeset -f update_hosts)
update_hosts
EOF
        chmod +x "$UPDATE_HOSTS_SCRIPT"
        echo "$(date): 已成功生成 $UPDATE_HOSTS_SCRIPT 脚本文件。" >> "$LOG_FILE"
    }

    # 设置 cron 任务，可配置时间运行更新 hosts 的函数
    setup_cron_job() {
        # 可配置的 cron 时间，这里默认是每天凌晨 2 点
        CRON_TIME="0 2 * * *"
        # 手动指定脚本的完整路径，需要根据实际情况修改
        SCRIPT_PATH="$DOCKER_ROOT_PATH/tmp/update_hosts.sh"
        CRON_JOB="$CRON_TIME $SCRIPT_PATH"

        # 检查 cron 任务是否已经存在
        if crontab -l 2>/dev/null | grep -q "$CRON_JOB"; then
            echo "$(date): cron 任务已存在，无需重复添加。" >> "$LOG_FILE"
            return
        fi

        # 尝试添加新的 cron 任务
        if (crontab -l 2>/dev/null || true; echo "$CRON_JOB") | crontab - ; then
            echo "$(date): 已成功设置 cron 任务，更新 hosts 操作将在 $CRON_TIME 运行。" >> "$LOG_FILE"
        else
            echo "$(date): 设置 cron 任务失败，请检查权限或 cron 服务状态。" >> "$LOG_FILE"
        fi
    }

    # 生成 update_hosts 脚本
    generate_update_hosts_script

    # 立即执行一次 hosts 更新
    update_hosts

    # 设置 cron 任务
    setup_cron_job
fi

# 导出所有可能会用到的变量
export CURRENT_DIR
export ARCHITECTURE
export DOCKER_NAMESPACE
export DOCKER_REGISTRY
export RANDOM_VARIABLE
export RANDOM_NUMBER
export PUBLIC_IP_CITY
export LONGITUDE
export LATITUDE
export DOCKER_ROOT_PATH
# 考虑多视频路径情况
export VIDEO_ROOT_PATH
for ((i = 2; i <= 10; i++)); do
    export "VIDEO_ROOT_PATH_$i"
done
export GATEWAY
export HOST_IP
export NEW_ROUTE
export USER_NAME
export PROXY_HOST
export PUID
export PGID
export USER_GROUPS
export UMASK
export TEMP_HOSTS_FILE
export VOLUME_MOUNTS

# 集中输出所有重要变量并准备发送到指定 URL
echo "------------------- 脚本运行结果汇总 -------------------"
echo "工作目录: $CURRENT_DIR"
echo "主机架构: $ARCHITECTURE"
echo "Docker 命名空间: $DOCKER_NAMESPACE"
echo "Docker 仓库地址: $DOCKER_REGISTRY"
echo "随机字母数字变量: $RANDOM_VARIABLE"
echo "随机数字变量: $RANDOM_NUMBER"
echo "公网 IP 所在城市: $PUBLIC_IP_CITY"
echo "城市经度: $LONGITUDE"
echo "城市纬度: $LATITUDE"
echo "Docker 根路径: $DOCKER_ROOT_PATH"
# 输出视频路径
echo "视频路径数量: $video_path_count"
echo "主视频文件根路径: $VIDEO_ROOT_PATH"
if [ -n "$VIDEO_ROOT_PATH" ]; then
    for ((i = 1; i <= video_path_count; i++)); do
        var_name="VIDEO_ROOT_PATH_$i"
        if [ -n "${!var_name}" ]; then
            echo "视频文件根路径 $i: ${!var_name}"
        fi
    done
fi
# 输出VOLUME_MOUNTS变量
echo "挂载点信息: $VOLUME_MOUNTS"
echo "网关地址: $GATEWAY"
echo "主机 IP 地址: $HOST_IP"
echo "网段: $NEW_ROUTE"
echo "用户名: $USER_NAME"
echo "PROXY_HOST: $PROXY_HOST"
echo "用户 PUID: $PUID"
echo "用户 PGID: $PGID"
echo "用户所属组信息: $USER_GROUPS"
echo "umask 值: $UMASK"
echo "临时 hosts 文件路径: $TEMP_HOSTS_FILE"
echo "--------------------------------------------------------"

# 整理信息为 JSON 格式，使用汉字描述键名
JSON_DATA=$(jq -n \
    --arg current_dir "$CURRENT_DIR" \
    --arg architecture "$ARCHITECTURE" \
    --arg docker_namespace "$DOCKER_NAMESPACE" \
    --arg docker_registry "$DOCKER_REGISTRY" \
    --arg random_variable "$RANDOM_VARIABLE" \
    --arg random_number "$RANDOM_NUMBER" \
    --arg public_ip_city "$PUBLIC_IP_CITY" \
    --arg longitude "$LONGITUDE" \
    --arg latitude "$LATITUDE" \
    --arg docker_root_path "$DOCKER_ROOT_PATH" \
    --arg video_path_count "$video_path_count" \
    --arg video_root_path "$VIDEO_ROOT_PATH" \
    --arg gateway "$GATEWAY" \
    --arg host_ip "$HOST_IP" \
    --arg route "$NEW_ROUTE" \
    --arg user_name "$USER_NAME" \
    --arg proxy_host "$PROXY_HOST" \
    --arg puid "$PUID" \
    --arg pgid "$PGID" \
    --arg user_groups "$USER_GROUPS" \
    --arg umask "$UMASK" \
    --arg temp_hosts_file "$TEMP_HOSTS_FILE" \
    --arg volume_mounts "$VOLUME_MOUNTS" \
    '{
        "工作目录": $current_dir,
        "主机架构": $architecture,
        "Docker命名空间": $docker_namespace,
        "Docker仓库地址": $docker_registry,
        "随机字母数字变量": $random_variable,
        "随机数字变量": $random_number,
        "公网IP所在城市": $public_ip_city,
        "城市经度": $longitude,
        "城市纬度": $latitude,
        "Docker根路径": $docker_root_path,
        "视频路径数量": $video_path_count,
        "主视频文件根路径": $video_root_path,
        "挂载点信息": $volume_mounts,
        "网关地址": $gateway,
        "主机IP地址": $host_ip,
        "主机网段": $route,
        "用户名": $user_name,
        "PROXY_HOST": $proxy_host,
        "用户PUID": $puid,
        "用户PGID": $pgid,
        "用户所属组信息": $user_groups,
        "umask值": $umask,
        "临时hosts文件路径": $temp_hosts_file
    }')

# 添加多个视频路径到 JSON
for ((i = 1; i <= video_path_count; i++)); do
    var_name="VIDEO_ROOT_PATH_$i"
    if [ -n "${!var_name}" ]; then
        JSON_DATA=$(echo "$JSON_DATA" | jq --arg path "${!var_name}" ".\"视频文件根路径 $i\" = \$path")
    fi
done

echo "$JSON_DATA"

# 生成文件名，格式为日期+时间
DATE_TIME=$(date +%Y%m%d%H%M%S)
FILE_NAME="${DATE_TIME}.json"

# 将 JSON 数据保存到以日期和时间命名的文件
echo "$JSON_DATA" > "$FILE_NAME"
if [ $? -ne 0 ]; then
    echo "错误: 无法将 JSON 数据保存到文件 $FILE_NAME，请检查文件权限。"
    exit 1
else
    echo "JSON 数据已成功保存到文件 $FILE_NAME。"
fi


# 清理临时文件
rm "$FILE_NAME"
echo "临时文件 $FILE_NAME 已清理。"    

# 检查并删除已存在的容器
check_and_remove_container() {
    local CONTAINER_NAME="$1"
    
    echo "检查容器 $CONTAINER_NAME 是否存在..."
    if docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
        echo "容器 $CONTAINER_NAME 已存在，准备卸载..."
        
        # 停止容器
        if docker inspect --format '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q "true"; then
            echo "停止容器 $CONTAINER_NAME..."
            docker stop "$CONTAINER_NAME"
            if [ $? -ne 0 ]; then
                echo "错误: 停止容器 $CONTAINER_NAME 失败！"
                return 1
            fi
        fi
        
        # 删除容器
        echo "删除容器 $CONTAINER_NAME..."
        docker rm "$CONTAINER_NAME"
        if [ $? -ne 0 ]; then
            echo "错误: 删除容器 $CONTAINER_NAME 失败！"
            return 1
        fi
        
        echo "容器 $CONTAINER_NAME 已成功卸载。"
        return 0
    else
        echo "容器 $CONTAINER_NAME 不存在，继续执行..."
        return 0
    fi
}

# 独立函数：处理目标文件夹（检测是否有文件，选择操作）
# 参数1：目标文件夹路径
# 参数2：TGZ文件名（不含路径）
# 返回值：0=继续执行，1=跳过解压但继续后续流程，2=完全跳过
handle_target_directory() {
    local TARGET_DIR="$1"
    local TGZ_FILE="$2"
    
    # 递归检测目标文件夹及其子目录是否存在实体文件
    if [ -n "$(find "$TARGET_DIR" -type f -print -quit 2>/dev/null)" ]; then
        echo "目标文件夹 $TARGET_DIR 及其子目录已存在实体文件"
        
        # 倒计时自动选择跳过（默认选项）
        read -t 10 -p "是否清除原文件并下载解压？(y/n，默认 n，3秒后自动选择 n): " CLEAR_CHOICE
        CLEAR_CHOICE=${CLEAR_CHOICE:-n}
        
        if [[ "$CLEAR_CHOICE" == "y" || "$CLEAR_CHOICE" == "Y" ]]; then
            echo "清除原文件并重新下载解压..."
            find "$TARGET_DIR" -type f -exec rm -f {} \;  # 只删除文件，保留目录结构
            return 0  # 继续执行下载和解压
        else
            echo "跳过下载和解压步骤"
            # 删除已下载的tgz文件（如果存在）
            if [ -f "$CURRENT_DIR/$TGZ_FILE" ]; then
                rm "$CURRENT_DIR/$TGZ_FILE"
            fi
            return 1  # 跳过解压，但继续后续流程
        fi
    else
        # 目标文件夹及其子目录为空，继续下载和解压
        echo "目标文件夹 $TARGET_DIR 及其子目录没有实体文件，继续下载和解压..."
        return 0
    fi
}

check_container_status() {
    local container_name=$1
    local status=$(docker inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null)
    case "$status" in
        running) echo -e "${GREEN}[✔] $container_name 已启动${RESET}" ;;
        exited) echo -e "${RED}[✘] $container_name 已停止${RESET}" ;;
        *) echo -e "${RED}[✘] $container_name 未安装${RESET}" ;;
    esac
}

# 定义服务序号与完整服务名的映射
declare -A SERVICE_INDEX_MAP=(
    ["1"]="csf_mo"
    ["2"]="qb_mo"
    ["3"]="embypt_mo"
    ["4"]="moviepilot_v2_pt"
    ["5"]="cookiecloud_mo"
    ["6"]="frpc_mo"
    ["7"]="transmission_mo"
    ["8"]="audiobookshelf_mo"
    ["9"]="komga_mo"
    ["10"]="navidrome_mo"
    ["11"]="homepage_mo"
    ["12"]="dockerCopilot_mo"
    ["13"]="memos_mo"
    ["14"]="vertex_mo"
    ["15"]="freshrss_mo"
    ["16"]="rsshub_mo"
    ["17"]="metube_mo"
    ["18"]="filecodebox_mo"
    ["19"]="myip_mo"
    ["20"]="photopea_mo"
    ["21"]="easyimage_mo"
    ["22"]="myicon_mo"
    ["23"]="easynode_mo"
    ["24"]="qb_shua"
    ["25"]="lucky_mo"
    ["26"]="pt_accelerator_mo"
    ["27"]="openlist_mo"
    ["28"]="vikunja_mo"
    ["29"]="allinone_mo"
    ["30"]="allinone_format_mo"
    ["31"]="watchtower_mo"
    ["32"]="reader_mo"
    ["33"]="newsnow_mo"
    ["34"]="calibre_mo"
    ["35"]="uptime_kuma_mo"
    ["36"]="convertx_mo"
    ["37"]="stirling_pdf_mo"
    ["38"]="wewe_rss_sqlite_mo"
    ["39"]="melody_mo"
    ["40"]="bililive_go_mo"
    ["41"]="libretv_mo"
    ["42"]="fivefilters_mo"
    ["43"]="notepad_mo"
    ["44"]="playlistdl_mo"
    ["45"]="squoosh_mo"
    ["46"]="easyvoice_mo"
    ["47"]="tachidesk_mo"
    ["48"]="flaresolverr_mo"
    ["49"]="easy_vdl_mo"
    ["50"]="moontv_mo"
    ["51"]="mediago_mo"
    ["52"]="handbrake_mo"
    ["53"]="pairdrop_mo"
    ["54"]="xunlei_mo"
    ["55"]="dockports_mo"
    ["56"]="flink_mo"
    ["57"]="wallos_mo"
    ["58"]="trilium_mo"
    ["59"]="nzbget_mo"
    ["60"]="scrutiny_mo"
    ["61"]="netalertx_mo"
    ["62"]="yt_dlp_web_mo"
    ["63"]="kspeeder_mo"
    ["64"]="myspeed_mo"
    ["65"]="image_watermark_tool_mo"
    ["66"]="noname_game_mo"
    ["67"]="roon_mo"
    ["68"]="emulatorjs_mo"
    ["69"]="v2raya_mo"
    ["70"]="docker_autocompose_mo"
    ["71"]="upsnap_mo"
    ["72"]="qd_mo"
    ["73"]="onenav_mo"
    ["74"]="linkding_mo"
    ["75"]="bili_sync_rs_mo"
    ["76"]="musicn_mo"
    ["77"]="tissue_mo"
    ["78"]="cloudbak_mo"
    ["79"]="sun_panel_mo"
    ["80"]="sun_panel_helper_mo"
    ["81"]="frps_mo"
    ["82"]="metatube_mo"
    ["83"]="wxchat_mo"
    ["84"]="iptv_hls_mo"
    ["85"]="easy_itv_mo"
    ["86"]="glances_mo"
    ["87"]="drawnix_mo"
    ["88"]="d2c_mo"
    ["89"]="iptv_api_mo"
    ["90"]="dsm_mo"
    ["91"]="wps_office_mo"
    ["92"]="whiper_mo"
    ["93"]="hivision_mo"
    ["94"]="rsshub"
    ["95"]="hatsh_mo"
    ["96"]="autopiano_mo"
    ["97"]="g_box_mo"
    ["98"]="byte_muse_mo"
    ["99"]="md_mo"
    ["100"]="xiuxian_mo"
    ["101"]="moviepilot_v2_115"
    ["102"]="docker_login"
    ["103"]="mdcx_mo"
    ["104"]="neko_mo"
    ["105"]="koodo_reader_mo"
    ["106"]="cinemore_mo"
    ["107"]="bytestash_mo"
    ["108"]="teleport_mo"
    ["109"]="dockpeek_mo"
    ["110"]="nav_mo"
    ["111"]="h5_mo"
    ["112"]="ispyagentdvr_mo"
    ["113"]="GSManager_mo"
    ["114"]="urbackup_mo"
    ["115"]="qrding_mo"
    ["116"]="enclosed_mo"
    ["117"]="ghosthub_mo"
    ["118"]="navipage_mo"
    ["119"]="mediamaster_mo"
    ["120"]="nullbr115_mo"
    ["121"]="cd2_mo"
    ["122"]="ubooquity_mo"
    ["123"]="jdownloader_mo"
    ["124"]="xianyu_auto_reply_mo"
    ["125"]="n8n_mo"
    ["126"]="moviepilot_v2_go"
    ["127"]="cms_mo"
    ["128"]="chromium_mo"
    ["129"]="portainer_mo"
    ["130"]="epub_to_audiobook_mo"
    ["131"]="clash_mo"
    ["132"]="owjdxb_mo"
    ["133"]="music_tag_web_mo"
    ["134"]="mdc_mo"
    ["135"]="lyricapi_mo"
    ["136"]="bangumikomga_mo"
    ["137"]="tailscale_mo"
    ["138"]="onestrm_mo"
    ["139"]="set_permissions_mo"
    ["140"]="remove_mo_containers"
    ["141"]="remove_container_array"
    ["142"]="reserved4_mo"
    ["143"]="reserved5_mo"
    ["144"]="kopia_mo"
    ["145"]="pyload_mo"
    ["146"]="cloudsaver_mo"
    ["147"]="mealie_mo"
    ["148"]="huntly_mo"
    ["149"]="whats_up_docker_mo"
)

# 更准确地检查容器是否存在
get_service_status() {
    local container_name=$1
    if docker inspect "$container_name" &>/dev/null; then
        echo -e "${GREEN}[✔]${RESET}"
    else
        echo -e "${RED}[✘]${RESET}"
    fi
}

# 卸载服务函数
uninstall_service() {
    local input=$1
    local service_name

    # 检查输入是否为有效的数字序号
    if ! [[ "$input" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}输入无效，请输入有效的服务序号。${RESET}"
        return 1
    fi

    service_name="${SERVICE_INDEX_MAP[$input]}"

    # 检查该序号是否对应一个有效的服务名
    if [ -z "$service_name" ]; then
        echo -e "${RED}无效的序号，请输入正确的序号。${RESET}"
        return 1
    fi

    echo "尝试卸载的服务名称: $service_name"

    # 检查服务是否存在
    if [[ "$(get_service_status "$service_name")" == *"[✔]"* ]]; then
        echo "正在卸载 $service_name 服务..."
        if ! docker stop "$service_name"; then
            echo -e "${RED}停止 $service_name 服务失败！${RESET}"
            return 1
        fi
        if ! docker rm "$service_name"; then
            echo -e "${RED}移除 $service_name 容器失败！${RESET}"
            return 1
        fi
        rm -rf "$DOCKER_ROOT_PATH/$service_name"
        echo "$service_name 服务卸载完成。"
    else
        echo "该服务未安装，无法卸载。"
    fi
}

		
update_service() {
    local service_name=$1
    if [[ -z "${SERVICE_IMAGE_MAP[$service_name]}" ]]; then
        echo -e "${RED}未找到服务 $service_name 对应的 Docker 镜像。${RESET}"
        return 1
    fi
    local image="${SERVICE_IMAGE_MAP[$service_name]}"
    echo "正在更新 $service_name 服务..."
    docker pull "$image"
    if [ $? -ne 0 ]; then
        echo -e "${RED}更新 $service_name 镜像失败！${RESET}"
        return 1
    fi
    docker restart "$service_name"
    if [ $? -ne 0 ]; then
        echo -e "${RED}重启 $service_name 服务失败！${RESET}"
        return 1
    fi
    echo "$service_name 服务更新完成。"
}


echo -e "${GREEN}创建安装环境中...${RESET}"


install_service() {
    local service_id=$1
    case "$service_id" in
        1) init_csf_mo ; check_container_status "csf_mo" ;;
        2) init_qb_mo ; check_container_status "qb_mo" ;;
        3) init_embypt_mo ; check_container_status "embypt_mo" ;;
        4) init_moviepilot_v2_pt ; check_container_status "moviepilot_v2_pt" ;;
        5) init_cookiecloud_mo ; check_container_status "cookiecloud_mo" ;;
        6) init_frpc_mo ; check_container_status "frpc_mo" ;;
        7) init_transmission_mo ; check_container_status "transmission_mo" ;;
        8) init_audiobookshelf_mo ; check_container_status "audiobookshelf_mo" ;;
        9) init_komga_mo ; check_container_status "komga_mo" ;;
        10) init_navidrome_mo ; check_container_status "navidrome_mo" ;;
        11) init_homepage_mo ; check_container_status "homepage_mo" ;;
        12) init_dockerCopilot_mo ; check_container_status "dockerCopilot_mo" ;;
        13) init_memos_mo ; check_container_status "memos_mo" ;;
        14) init_vertex_mo ; check_container_status "vertex_mo" ;;
        15) init_freshrss_mo ; check_container_status "freshrss_mo" ;;
        16) init_rsshub_mo ; check_container_status "rsshub_mo" ;;
        17) init_metube_mo ; check_container_status "metube_mo" ;;
        18) init_filecodebox_mo ; check_container_status "filecodebox_mo" ;;
        19) init_myip_mo ; check_container_status "myip_mo" ;;
        20) init_photopea_mo ; check_container_status "photopea_mo" ;;
        21) init_easyimage_mo ; check_container_status "easyimage_mo" ;;
        22) init_myicon_mo ; check_container_status "myicon_mo" ;;
        23) init_easynode_mo ; check_container_status "easynode_mo" ;;
        24) init_qb_shua ; check_container_status "qb_shua" ;;
        25) init_lucky_mo ; check_container_status "lucky_mo" ;;
        26) init_pt_accelerator_mo ; check_container_status "pt_accelerator_mo" ;;
        27) init_openlist_mo ; check_container_status "openlist_mo" ;;
        28) init_vikunja_mo ; check_container_status "vikunja_mo" ;;
        29) init_allinone_mo ; check_container_status "allinone_mo" ;;
        30) init_allinone_format_mo ; check_container_status "allinone_format_mo" ;;
        31) init_watchtower_mo ; check_container_status "watchtower_mo" ;;
        32) init_reader_mo ; check_container_status "reader_mo" ;;
        33) init_newsnow_mo ; check_container_status "newsnow_mo" ;;
        34) init_calibre_mo ; check_container_status "calibre_mo" ;;
        35) init_uptime_kuma_mo ; check_container_status "uptime_kuma_mo" ;;
        36) init_convertx_mo ; check_container_status "convertx_mo" ;;
        37) init_stirling_pdf_mo ; check_container_status "stirling_pdf_mo" ;;
        38) init_wewe_rss_sqlite_mo ; check_container_status "wewe_rss_sqlite_mo" ;;
        39) init_melody_mo ; check_container_status "melody_mo" ;;
        40) init_bililive_go_mo ; check_container_status "bililive_go_mo" ;;
        41) init_libretv_mo ; check_container_status "libretv_mo" ;;
        42) init_fivefilters_mo ; check_container_status "fivefilters_mo" ;;
        43) init_notepad_mo ; check_container_status "notepad_mo" ;;
        44) init_playlistdl_mo ; check_container_status "playlistdl_mo" ;;
        45) init_squoosh_mo ; check_container_status "squoosh_mo" ;;
        46) init_easyvoice_mo ; check_container_status "easyvoice_mo" ;;
        47) init_tachidesk_mo ; check_container_status "tachidesk_mo" ;;
        48) init_flaresolverr_mo ; check_container_status "flaresolverr_mo" ;;
        49) init_easy_vdl_mo ; check_container_status "easy_vdl_mo" ;;
        50) init_moontv_mo ; check_container_status "moontv_mo" ;;
        51) init_mediago_mo ; check_container_status "mediago_mo" ;;
        52) init_handbrake_mo ; check_container_status "handbrake_mo" ;;
        53) init_pairdrop_mo ; check_container_status "pairdrop_mo" ;;
        54) init_xunlei_mo ; check_container_status "xunlei_mo" ;;
        55) init_dockports_mo ; check_container_status "dockports_mo" ;;
        56) init_flink_mo ; check_container_status "flink_mo" ;;
        57) init_wallos_mo ; check_container_status "wallos_mo" ;;
        58) init_trilium_mo ; check_container_status "trilium_mo" ;;
        59) init_nzbget_mo ; check_container_status "nzbget_mo" ;;
        60) init_scrutiny_mo ; check_container_status "scrutiny_mo" ;;
        61) init_netalertx_mo ; check_container_status "netalertx_mo" ;;
        62) init_yt_dlp_web_mo ; check_container_status "yt_dlp_web_mo" ;;
        63) init_kspeeder_mo ; check_container_status "kspeeder_mo" ;;
        64) init_myspeed_mo ; check_container_status "myspeed_mo" ;;
        65) init_image_watermark_tool_mo ; check_container_status "image_watermark_tool_mo" ;;
        66) init_noname_game_mo ; check_container_status "noname_game_mo" ;;
        67) init_roon_mo ; check_container_status "roon_mo" ;;
        68) init_emulatorjs_mo ; check_container_status "emulatorjs_mo" ;;
        69) init_v2raya_mo ; check_container_status "v2raya_mo" ;;
        70) init_docker_autocompose_mo ; check_container_status "docker_autocompose_mo" ;;
        71) init_upsnap_mo ; check_container_status "upsnap_mo" ;;
        72) init_qd_mo ; check_container_status "qd_mo" ;;
        73) init_onenav_mo ; check_container_status "onenav_mo" ;;
        74) init_linkding_mo ; check_container_status "linkding_mo" ;;
        75) init_bili_sync_rs_mo ; check_container_status "bili_sync_rs_mo" ;;
        76) init_musicn_mo ; check_container_status "musicn_mo" ;;
        77) init_tissue_mo ; check_container_status "tissue_mo" ;;
        78) init_cloudbak_mo ; check_container_status "cloudbak_mo" ;;
        79) init_sun_panel_mo ; check_container_status "sun_panel_mo" ;;
        80) init_sun_panel_helper_mo ; check_container_status "sun_panel_helper_mo" ;;
        81) init_frps_mo ; check_container_status "frps_mo" ;;
        82) init_metatube_mo ; check_container_status "metatube_mo" ;;
        83) init_wxchat_mo ; check_container_status "wxchat_mo" ;;
        84) init_iptv_hls_mo ; check_container_status "iptv_hls_mo" ;;
        85) init_easy_itv_mo ; check_container_status "easy_itv_mo" ;;
        86) init_glances_mo ; check_container_status "glances_mo" ;;
        87) init_drawnix_mo ; check_container_status "drawnix_mo" ;;
        88) init_d2c_mo ; check_container_status "d2c_mo" ;;
        89) init_iptv_api_mo ; check_container_status "iptv_api_mo" ;;
        90) init_dsm_mo ; check_container_status "dsm_mo" ;;
        91) init_wps_office_mo ; check_container_status "wps_office_mo" ;;
        92) init_whiper_mo ; check_container_status "whiper_mo" ;;
        93) init_hivision_mo ; check_container_status "hivision_mo" ;;
        94) init_rsshub ; check_container_status "rsshub" ;;
        95) init_hatsh_mo ; check_container_status "hatsh_mo" ;;
        96) init_autopiano_mo ; check_container_status "autopiano_mo" ;;
        97) init_g_box_mo ; check_container_status "g_box_mo" ;;
        98) init_byte_muse_mo ; check_container_status "byte_muse_mo" ;;
        99) init_md_mo ; check_container_status "md_mo" ;;
        100) init_xiuxian_mo ; check_container_status "xiuxian_mo" ;;
        101) init_moviepilot_v2_115 ; check_container_status "moviepilot_v2_115" ;;
        102) init_docker_login ; check_container_status "docker_login" ;;
        103) init_mdcx_mo ; check_container_status "mdcx_mo" ;;
        104) init_neko_mo ; check_container_status "neko_mo" ;;
        105) init_koodo_reader_mo ; check_container_status "koodo_reader_mo" ;;
        106) init_cinemore_mo ; check_container_status "cinemore_mo" ;;
        107) init_bytestash_mo ; check_container_status "bytestash_mo" ;;
        108) init_teleport_mo ; check_container_status "teleport_mo" ;;
        109) init_dockpeek_mo ; check_container_status "dockpeek_mo" ;;
        110) init_nav_mo ; check_container_status "nav_mo" ;;
        111) init_h5_mo ; check_container_status "h5_mo" ;;
        112) init_ispyagentdvr_mo ; check_container_status "ispyagentdvr_mo" ;;
        113) init_GSManager_mo ; check_container_status "GSManager_mo" ;;
        114) init_urbackup_mo ; check_container_status "urbackup_mo" ;;
        115) init_qrding_mo ; check_container_status "qrding_mo" ;;
        116) init_enclosed_mo ; check_container_status "enclosed_mo" ;;
        117) init_ghosthub_mo ; check_container_status "ghosthub_mo" ;;
        118) init_navipage_mo ; check_container_status "navipage_mo" ;;
        119) init_mediamaster_mo ; check_container_status "mediamaster_mo" ;;
        120) init_nullbr115_mo ; check_container_status "nullbr115_mo" ;;
        121) init_cd2_mo ; check_container_status "cd2_mo" ;;
        122) init_ubooquity_mo ; check_container_status "ubooquity_mo" ;;
        123) init_jdownloader_mo ; check_container_status "jdownloader_mo" ;;
        124) init_xianyu_auto_reply_mo ; check_container_status "xianyu_auto_reply_mo" ;;
        125) init_n8n_mo ; check_container_status "n8n_mo" ;;
        126) init_moviepilot_v2_go ; check_container_status "moviepilot_v2_go" ;;
        127) init_cms_mo ; check_container_status "cms_mo" ;;
        128) init_chromium_mo ; check_container_status "chromium_mo" ;;
        129) init_portainer_mo ; check_container_status "portainer_mo" ;;
        130) init_epub_to_audiobook_mo ; check_container_status "epub_to_audiobook_mo" ;;
        131) init_clash_mo ; check_container_status "clash_mo" ;;
        132) init_owjdxb_mo ; check_container_status "owjdxb_mo" ;;
        133) init_music_tag_web_mo ; check_container_status "music_tag_web_mo" ;;
        134) init_mdc_mo ; check_container_status "mdc_mo" ;;
        135) init_lyricapi_mo ; check_container_status "lyricapi_mo" ;;
        136) init_bangumikomga_mo ; check_container_status "bangumikomga_mo" ;;
        137) init_tailscale_mo ; check_container_status "tailscale_mo" ;;
        138) init_onestrm_mo ; check_container_status "onestrm_mo" ;;
        139) init_set_permissions_mo ; check_container_status "set_permissions_mo" ;;
        140) init_remove_mo_containers ; check_container_status "remove_mo_containers" ;;
        141) init_remove_container_array ; check_container_status "remove_container_array" ;;
        142) init_reserved4_mo ; check_container_status "reserved4_mo" ;;
        143) init_reserved5_mo ; check_container_status "reserved5_mo" ;;
        144) init_kopia_mo ; check_container_status "kopia_mo" ;;
        145) init_pyload_mo ; check_container_status "pyload_mo" ;;
        146) init_cloudsaver_mo ; check_container_status "cloudsaver_mo" ;;
        147) init_mealie_mo ; check_container_status "mealie_mo" ;;
        148) init_huntly_mo ; check_container_status "huntly_mo" ;;
        149) init_whats_up_docker_mo ; check_container_status "whats_up_docker_mo" ;;
        
        *)
            echo -e "${RED}无效选项：$service_id${RESET}"
        ;;
    esac
}

# 初始化各个服务

init_clash_mo() {
    echo "初始化 clash_mo"
    mkdir -p "$DOCKER_ROOT_PATH/clash_mo"
    docker run -d --name clash_mo --restart always\
        -v "$DOCKER_ROOT_PATH/clash_mo:/root/.config/clash" \
		--network bridge --privileged \
        -p 38080:8080 \
        -p 7890:7890 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}clash-and-dashboard:latest"
}

init_qb_mo() {
    echo "初始化 qb_mo"
    mkdir -p "$DOCKER_ROOT_PATH/qb_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/qb_mo.tgz -o "$CURRENT_DIR/qb_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/qb_mo.tgz" -C "$DOCKER_ROOT_PATH/qb_mo/"
    docker run -d --name qb_mo --restart always\
        -v "$DOCKER_ROOT_PATH/qb_mo:/config" \
        $VOLUME_MOUNTS \
        -e PUID=$PUID -e PGID=$PGID -e TZ=Asia/Shanghai \
        -e WEBUI_PORT=58080 \
        -e TORRENTING_PORT=56355 \
        -e SavePatch="/media/downloads" -e TempPatch="/media/downloads" \
        --network host --privileged \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}qbittorrent:4.6.5"
}

init_neko_mo () {
    echo "初始化 neko_mo "
    docker run -d --name neko_mo  --restart unless-stopped\
		--network bridge --privileged \
		--shm-size=2g \
        -e TZ=Asia/Shanghai \
        -e NEKO_PASSWORD='666666' \
        -e NEKO_PASSWORD_ADMIN='666666' \
        -e NEKO_NAT1TO1=$HOST_IP \
        -e NEKO_SCREEN=1920x1080@30 \
        -e NEKO_ICELITE=1 \
        -e NEKO_EPR=52000-52100 \
        -p 50012:8080 \
        -p 52000-52100:52000-52100/udp \
        $VOLUME_MOUNTS \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}microsoft-edge:latest"
}

init_epub_to_audiobook_mo() {
    echo "初始化 epub_to_audiobook_mo"
    mkdir -p "$DOCKER_ROOT_PATH/epub_to_audiobook_mo/input"
    mkdir -p "$DOCKER_ROOT_PATH/epub_to_audiobook_mo/output"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/epub_to_audiobook_mo.tgz -o "$CURRENT_DIR/epub_to_audiobook_mo.tgz"
    tar --strip-components=1 -zxvf "$CURRENT_DIR/epub_to_audiobook_mo.tgz" -C "$DOCKER_ROOT_PATH/epub_to_audiobook_mo/"
    docker run -d \
        --name epub_to_audiobook_mo \
        --restart always\
		--network bridge \
        -p 50013:7860 \
        -v $VIDEO_ROOT_PATH/epub_to_audiobook_mo:/app \
        $VOLUME_MOUNTS \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}epub_to_audiobook:latest" \
        python3 /app_src/main_ui.py --host 0.0.0.0 --port 7860
}

init_qb_shua() {
    echo "初始化 qb_shua"
    mkdir -p "$DOCKER_ROOT_PATH/qb_shua"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/qb_shua.tgz -o "$CURRENT_DIR/qb_shua.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/qb_shua.tgz" -C "$DOCKER_ROOT_PATH/qb_shua/"
    docker run -d --name qb_shua --restart always\
        -v "$DOCKER_ROOT_PATH/qb_shua:/config" \
        $VOLUME_MOUNTS \
        -e PUID=$PUID -e PGID=$PGID -e TZ=Asia/Shanghai \
        -e WEBUI_PORT=58181 \
        -e TORRENTING_PORT=56366 \
        -e SavePatch="/media2/downloads" -e TempPatch="/media2/downloads" \
        --network host --privileged \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}qbittorrent:4.6.5"
}

init_transmission_mo() {
    echo "初始化 transmission_mo"
    mkdir -p "$DOCKER_ROOT_PATH/transmission_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/transmission_mo.tgz -o "$CURRENT_DIR/transmission_mo.tgz"
    tar --strip-components=1 -zxvf "$CURRENT_DIR/transmission_mo.tgz" -C "$DOCKER_ROOT_PATH/transmission_mo/"
    docker run -d \
        --name transmission_mo \
        --restart always\
        --network host \
        --privileged \
        -e PUID=$PUID -e PGID=$PGID -e TZ=Asia/Shanghai \
        -e USER=666666 -e PASS=666666 \
        -e TRANSMISSION_WEB_HOME=/webui \
        -v $DOCKER_ROOT_PATH/transmission_mo:/config \
        -v $DOCKER_ROOT_PATH/transmission_mo/WATCH:/watch \
        -v $DOCKER_ROOT_PATH/transmission_mo/src:/webui \
        $VOLUME_MOUNTS \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}transmission:4.0.5"
}

init_stirling_pdf_mo() {
    echo "初始化 stirling_pdf_mo"
    mkdir -p "$DOCKER_ROOT_PATH/stirling_pdf_mo/"{trainingData,extraConfigs,customFiles,logs}
    docker run -d --name stirling_pdf_mo --restart always\
		--network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 56080:8080 \
        -v $DOCKER_ROOT_PATH/stirling_pdf_mo/trainingData:/usr/share/tessdata \
        -v $DOCKER_ROOT_PATH/stirling_pdf_mo/extraConfigs:/configs \
        -v $DOCKER_ROOT_PATH/stirling_pdf_mo/customFiles:/customFiles/ \
        -v $DOCKER_ROOT_PATH/stirling_pdf_mo/logs:/logs/ \
        -e DOCKER_ENABLE_SECURITY=false \
        -e LANGS=zh_CN \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}stirling-pdf:latest"
}

init_qd_mo() {
    echo "初始化 qd_mo"
    mkdir -p "$DOCKER_ROOT_PATH/qd_mo/config"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/qd_mo.tgz -o "$CURRENT_DIR/qd_mo.tgz"
    tar --strip-components=1 -zxvf "$CURRENT_DIR/qd_mo.tgz" -C "$DOCKER_ROOT_PATH/qd_mo/"
    docker run -d --name qd_mo --restart always\
		--network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 58923:80 \
        -v $DOCKER_ROOT_PATH/qd_mo/config:/usr/src/app/config \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}qd:latest"
}

init_mdcx_mo () {
    echo "初始化 mdcx_mo "
    mkdir -p "$DOCKER_ROOT_PATH/mdcx_mo/data"
    mkdir -p "$DOCKER_ROOT_PATH/mdcx_mo/logs"
    mkdir -p "$DOCKER_ROOT_PATH/mdcx_mo/mdcx-config"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/mdcx_mo.tgz -o "$CURRENT_DIR/mdcx_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/mdcx_mo.tgz" -C "$DOCKER_ROOT_PATH/mdcx_mo/"
    sed -i "s/192.168.66.109/$HOST_IP/g" "$DOCKER_ROOT_PATH/mdcx_mo/mdcx-config/config.ini"
    docker run -d --name mdcx_mo  --restart unless-stopped\
		--network bridge --privileged \
		-e DISPLAY_WIDTH=1200 \
		-e DISPLAY_HEIGHT=750 \
		-e VNC_PASSWORD=666666  `#查看密码` \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 50010:5800 \
        -p 50011:5900 \
        -v $DOCKER_ROOT_PATH/mdcx_mo/data:/config `#容器系统数据` \
        -v $DOCKER_ROOT_PATH/mdcx_mo/mdcx-config:/mdcx-config `#配置文件目录` \
        -v $DOCKER_ROOT_PATH/mdcx_mo/mdcx-config/MDCx.config:/app/MDCx.config `#配置文件目录标记文件` \
        -v $DOCKER_ROOT_PATH/mdcx_mo/logs:/app/Log `#日志目录` \
        $VOLUME_MOUNTS \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}mdcx-builtin-gui-base:latest"
}

init_huntly_mo() {
    echo "初始化 huntly_mo"
    mkdir -p "$DOCKER_ROOT_PATH/huntly_mo/data"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/huntly_mo.tgz -o "$CURRENT_DIR/huntly_mo.tgz"
    tar --strip-components=1 -zxvf "$CURRENT_DIR/huntly_mo.tgz" -C "$DOCKER_ROOT_PATH/huntly_mo/"
    docker run -d --name huntly_mo --restart always\
		--network bridge --privileged \
		--restart always\
		-p 53232:80 \
        -v $DOCKER_ROOT_PATH/huntly_mo/data:/data \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}huntly:latest"
}

init_v2raya_mo() {
    echo "初始化 v2raya_mo"
    mkdir -p "$DOCKER_ROOT_PATH/v2raya_mo"
    docker run -d --name v2raya_mo --restart=always \
		--network bridge --privileged \
		--restart always\
        -e V2RAYA_V2RAY_BIN=/usr/local/bin/v2ray \
        -e V2RAYA_LOG_FILE=/tmp/v2raya.log \
        -p 52017:2017 \
        -p 20170-20172:20170-20172 \
        -v $DOCKER_ROOT_PATH/v2raya_mo:/etc/v2raya \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}v2raya:latest"
}

init_dsm_mo () {
    echo "初始化 dsm_mo "
    mkdir -p "$DOCKER_ROOT_PATH/dsm_mo"
    mkdir -p "$VIDEO_ROOT_PATH/dsmdata"
    docker run -d --name dsm_mo  --restart unless-stopped\
		--network bridge --privileged \
        --device /dev/kvm \
        -p 35000:5000 \
        -e CPU_CORES=4 \
        -e RAM_SIZE=4G \
        -e DISK_SIZE=64G \
        -e DISK2_SIZE=100G \
        -e GPU=Y \
        -v $DOCKER_ROOT_PATH/dsm_mo:/storage \
        -v $VIDEO_ROOT_PATH/dsmdata:/storage2 \
        "ccr.ccs.tencentyun.com/moling7882/virtual-dsm:latest"
}

init_wps_office_mo() {
    echo "初始化 wps_office_mo"
    mkdir -p "$DOCKER_ROOT_PATH/wps_office_mo"
    mkdir -p "$VIDEO_ROOT_PATH/wpsdata"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/wps_office_mo.tgz -o "$CURRENT_DIR/wps_office_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/wps_office_mo.tgz" -C "$DOCKER_ROOT_PATH/wps_office_mo/"  
    docker run -d \
        --name wps_office_mo \
        --restart always \
		--network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -v $DOCKER_ROOT_PATH/wps_office_mo:/config \
        $VOLUME_MOUNTS \
        -p 43000:3000 \
        -p 43001:3001 \
        "ccr.ccs.tencentyun.com/moling7882/wps-office:chinese"
}

init_squoosh_mo() {
    echo "初始化 squoosh_mo"
    mkdir -p "$VIDEO_ROOT_PATH/squoosh"
    docker run -d \
        --name squoosh_mo \
        --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        $VOLUME_MOUNTS \
        -p 57080:80 \
        "ccr.ccs.tencentyun.com/moling7882/squoosh:latest"
}

init_ghosthub_mo () {
    echo "初始化 ghosthub_mo "
    mkdir -p "$$DOCKER_ROOT_PATH/ghosthub_mo/instance"
    docker run -d --name ghosthub_mo --restart always\
        --network bridge  \
        -p 55211:5000 \
        -v $DOCKER_ROOT_PATH/ghosthub_mo/instance:/app/instance \
        $VOLUME_MOUNTS \
        -e PORT=5000 \
        -e FLASK_CONFIG=production \
        -e DOCKER_ENV=true \
        "ccr.ccs.tencentyun.com/moling7882/ghosthub:latest"
}

init_enclosed_mo () {
    echo "初始化 enclosed_mo "
    mkdir -p "$DOCKER_ROOT_PATH/enclosed_mo/data"
    docker run -d --name enclosed_mo --restart always\
        --network bridge  \
        -p 50027:8787 \
        -v $DOCKER_ROOT_PATH/enclosed_mo/data:/app/.data \
        "ccr.ccs.tencentyun.com/moling7882/enclosed:latest"
}

init_hivision_mo() {
    echo "初始化 hivision_mo"
    mkdir -p "$VIDEO_ROOT_PATH/hivision"
    docker run -d \
        --name hivision_mo \
        --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        $VOLUME_MOUNTS \
        -p 57860:7860 \
        "ccr.ccs.tencentyun.com/moling7882/hivision_idphotos:latest"
}

init_image_watermark_tool_mo() {
    echo "初始化 image_watermark_tool_mo"
    mkdir -p "$VIDEO_ROOT_PATH/watermark"
    docker run -d \
        --name image_watermark_tool_mo \
        --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        $VOLUME_MOUNTS \
        -p 53300:3000 \
        "ccr.ccs.tencentyun.com/moling7882/image-watermark-tool:master"
}

init_xiuxian_mo() {
    echo "初始化 xiuxian_mo"
    docker run -d \
        --name xiuxian_mo \
        --restart always \
        --network bridge \
        -p 42221:8080 \
        "ccr.ccs.tencentyun.com/moling7882/vue-xiuxiangame:latest"
}

init_easyvoice_mo() {
    echo "初始化 easyvoice_mo"
    mkdir -p "$DOCKER_ROOT_PATH/easyvoice_mo"
    docker run -d \
        --name easyvoice_mo \
        --restart always \
        --network bridge --privileged \
        --restart always \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 43333:3000 \
        -v "$DOCKER_ROOT_PATH/easyvoice_mo:/app/audio" \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}easyvoice:latest"
}

init_hatsh_mo() {
    echo "初始化 hatsh_mo"
    docker run -d \
        --name hatsh_mo \
        --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 38002:80 \
        "ccr.ccs.tencentyun.com/moling7882/hat.sh:latest"
}

init_autopiano_mo() {
    echo "初始化 hat.sh_mo"
    docker run -d \
        --name autopiano_mo \
        --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 38003:80 \
        "ccr.ccs.tencentyun.com/moling7882/autopiano:latest"
}

init_g_box_mo() {
    echo "初始化 g_box_mo"
    mkdir -p "$DOCKER_ROOT_PATH/g_box_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/g_box_mo.tgz -o "$CURRENT_DIR/g_box_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/g_box_mo.tgz" -C "$DOCKER_ROOT_PATH/g_box_mo/"  
    sed -i "s/192.168.66.27/$HOST_IP/g" "$DOCKER_ROOT_PATH/g_box_mo/docker_address.txt"
    docker run -d \
        --name g_box_mo \
        --restart always \
        --network host \
        -e JAVA_HOME=/jre \
        -e MEM_OPT="-Xmx512M" \
        -e alist_PORT=5678 \
        -e INSTALL=hostmode \
        $VOLUME_MOUNTS \
        -v "$DOCKER_ROOT_PATH/g_box_mo:/data" \
        -v "$DOCKER_ROOT_PATH/g_box_mo/data:/www/data" \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}g-box:hostmode"
}

init_byte_muse_mo() {
    echo "初始化 byte_muse_mo"
    mkdir -p "$DOCKER_ROOT_PATH/byte_muse_mo"
    docker run -d \
        --name byte_muse_mo \
        --restart always \
        --network bridge --privileged \
        --restart always \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 58043:80 \
        -v "$DOCKER_ROOT_PATH/byte_muse_mo:/data" \
        "ccr.ccs.tencentyun.com/moling7882/byte-muse:latest"
}

init_md_mo() {
    echo "初始化 md_mo"
    docker run -d \
        --name md_mo \
        --restart always \
        --network bridge --privileged \
        -p 42222:80 \
        "ccr.ccs.tencentyun.com/moling7882/md:latest"
}

init_roon_mo() {
    echo "初始化 roon_mo"
    mkdir -p "$DOCKER_ROOT_PATH/roon_mo/roon-app"
    mkdir -p "$DOCKER_ROOT_PATH/roon_mo/roon-data"
    mkdir -p "$DOCKER_ROOT_PATH/roon_mo/roon-backups"	
    mkdir -p "$VIDEO_ROOT_PATH/music/musicok"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/roon_mo.tgz -o "$CURRENT_DIR/roon_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/roon_mo.tgz" -C "$DOCKER_ROOT_PATH/roon_mo/"
    docker run -d --name roon_mo --restart always\
        --network host --privileged \
        -v $DOCKER_ROOT_PATH/roon_mo/roon-app:/app \
        -v $DOCKER_ROOT_PATH/roon_mo/roon-data:/data \
        -v $VIDEO_ROOT_PATH/music/musicok:/music \
        -v $DOCKER_ROOT_PATH/roon_mo/roon-backups:/backup \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}docker-roonserver:latest"
}

init_moviepilot_v2_go() {
    iyuu_keys=(
        "IYUU30780T7a8c6fe94b419a49e3622cfca0eef9f8c4fce0af"
        "IYUU63661T999fe5e841ccc18e8789ae21eb7adec851e96f6a"
        "IYUU60348T5dd79edeee3fe54a54180bd8628d46bea608787c"
        "IYUU58629Tf8205354160cdaf0a85051a30f0e982b482df220"
        "IYUU60620T618188826799cccd9182f311f27ec6dcb450d014"
        "IYUU57154T8f70606de83160b4fe6633e56be108caaf2c8a54"
        "IYUU49366Td4f1825199719b9b144fb2e6be87d78abe309f8d"
        "IYUU59122Td9da6c6d60d8360599728969adde2a38f840c7bc"
        "IYUU57327T958bd01b181be18512c4305e60e2d6081e9e338b"
        "IYUU57294T883c746777f1a16b09f5d37d6d8c22b0992f92ab"
        "IYUU57308T02860d4294d9224d11a99e7ef4411f24a154f25f"
        "IYUU57155T60804655a5ca6045fd4cd336fbb32d3136e42c14"
        "IYUU57240Tfb094d8fa3196ecfc2a651a8bd408999593efbaf"
    )

    # 生成随机索引
    random_iyuu_index=$((RANDOM % ${#iyuu_keys[@]}))
    default_iyuu_key=${iyuu_keys[$random_iyuu_index]}

    # 处理IYUU TOKEN输入
    IYUU_TOKEN="${IYUU_TOKEN:-$default_iyuu_key}"
    read -p "请输入 IYUU TOKEN ($IYUU_TOKEN): " input_token
    IYUU_TOKEN="${input_token:-$IYUU_TOKEN}"

    # PT模式核心配置
    APP_NAME="moviepilot_v2_go"
    PORT_NUMBER=53000  # 与115模式区分端口
    PORT=13001
    echo "当前使用【PT模式】（适配qbittorrent/transmission等PT工具）"
    echo "初始化 MoviePilot PT模式"

    # 网络模式选择
    while true; do
        read -p "请选择网络模式 (h: host, b: bridge，默认 host): " NETWORK_CHOICE
        NETWORK_CHOICE=${NETWORK_CHOICE:-h}
        if [[ "$NETWORK_CHOICE" == "h" || "$NETWORK_CHOICE" == "b" ]]; then
            break
        else
            echo "无效的选择，请输入 'h' 或 'b'。"
        fi
    done
    echo "已选择网络模式: $NETWORK_CHOICE"

    # 网络参数设置
    if [ "$NETWORK_CHOICE" == "b" ]; then
        NETWORK_SETTING="--network bridge"
        PORT_MAPPING="-p $PORT_NUMBER:$PORT_NUMBER"
    else
        NETWORK_SETTING="--network host"
        PORT_MAPPING=""
    fi

    # Hosts自动更新设置
    while true; do
        read -p "是否自动更新 hosts（使用 MOUNT_HOSTS）？(y/n，默认 n): " UPDATE_HOSTS_CHOICE
        UPDATE_HOSTS_CHOICE=${UPDATE_HOSTS_CHOICE:-n}
        if [[ "$UPDATE_HOSTS_CHOICE" == "y" || "$UPDATE_HOSTS_CHOICE" == "n" ]]; then
            break
        else
            echo "无效的选择，请输入 'y' 或 'n'。"
        fi
    done
    if [ "$UPDATE_HOSTS_CHOICE" == "y" ]; then
        if [ -z "$PROXY_HOST" ]; then
            MOUNT_HOSTS="-v $TEMP_HOSTS_FILE:/etc/hosts:ro"
        else
            MOUNT_HOSTS=""
        fi
    else
        MOUNT_HOSTS=""
    fi

    # 自动更新设置
    local result
    while true; do
        read -p "是否开启 MoviePilot 自动更新？(y/n，默认 n): " AUTO_UPDATE_CHOICE
        AUTO_UPDATE_CHOICE=${AUTO_UPDATE_CHOICE:-n}
        if [[ "$AUTO_UPDATE_CHOICE" == "y" || "$AUTO_UPDATE_CHOICE" == "n" ]]; then
            result="$([ "$AUTO_UPDATE_CHOICE" == "y" ] && echo "true" || echo "false")"
            break
        else
            echo "无效的选择，请输入 'y' 或 'n'。"
        fi
    done

    # GitHub代理设置
    GITHUB_PROXY="https://ghproxy.cn"
    read -p "是否修改 github 代理地址（默认值为 $GITHUB_PROXY，直接回车使用默认值，输入新地址则使用新地址，输入 n 不使用代理）？ " choice
    if [[ "$choice" == "n" ]]; then
        GITHUB_PROXY=""
    elif [ -n "$choice" ]; then
        GITHUB_PROXY="$choice"
    fi

    # GitHub Token设置（默认不使用）
    GITHUB_TOKEN=""  # 默认不使用Token
    while true; do
        read -p "是否使用默认 GitHub Token？(y/n，默认 n): " use_default
        use_default=${use_default:-n}  # 默认选择n（不使用）
        if [[ "$use_default" == "y" || "$use_default" == "n" ]]; then
            if [ "$use_default" == "y" ]; then
                GITHUB_TOKEN="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"
            else
                read -p "请输入自定义 GitHub Token (留空则不使用): " input_github_token
                GITHUB_TOKEN="$input_github_token"
            fi
            break
        else
            echo "无效的选择，请输入 'y' 或 'n'。"
        fi
    done

    # PT模式目录结构（适配qbittorrent/transmission）
    mkdir -p "$DOCKER_ROOT_PATH/$APP_NAME/"{main,config,core}
    mkdir -p "$DOCKER_ROOT_PATH/qb_mo/qBittorrent/BT_backup"  # qbittorrent备份目录
    mkdir -p "$DOCKER_ROOT_PATH/transmission_mo/torrents"     # transmission种子目录
    mkdir -p "$VIDEO_ROOT_PATH/downloads/电影" "$VIDEO_ROOT_PATH/downloads/电视剧"  # PT下载目录
    mkdir -p "$VIDEO_ROOT_PATH/links/电影" "$VIDEO_ROOT_PATH/links/电视剧"          # 软链接目录
    mkdir -p "$VIDEO_ROOT_PATH/整理库/电影" "$VIDEO_ROOT_PATH/整理库/电视剧" "$VIDEO_ROOT_PATH/整理库/媒体信息"
    mkdir -p "$VIDEO_ROOT_PATH/原始库"  
    # 处理目标文件夹（下载/解压）
    handle_target_directory "$DOCKER_ROOT_PATH/$APP_NAME" "${APP_NAME}.tgz"
    local handle_result=$?
    if [ $handle_result -eq 0 ]; then
        echo "开始下载 $APP_NAME.tgz 文件..."
        if ! curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/${APP_NAME}.tgz -o "$CURRENT_DIR/${APP_NAME}.tgz"; then
            echo "下载 ${APP_NAME}.tgz 文件失败，但将继续执行后续步骤"
        else
            echo "解压 ${APP_NAME}.tgz 文件..."
            if ! tar --strip-components=1 -zxvf "$CURRENT_DIR/${APP_NAME}.tgz" -C "$DOCKER_ROOT_PATH/$APP_NAME/"; then
                echo "解压 ${APP_NAME}.tgz 文件失败，但将继续执行后续步骤"
            fi
        fi
    elif [ $handle_result -eq 1 ]; then
        echo "使用现有文件继续后续流程..."
    else
        echo "跳过文件处理步骤，继续执行后续操作"
    fi

    # 调试信息输出
    echo "调试信息:"
    echo "NETWORK_CHOICE: $NETWORK_CHOICE"
    echo "PORT_MAPPING: $PORT_MAPPING"
    echo "NETWORK_SETTING: $NETWORK_SETTING"

    # TMDB域名设置
    TMDB_IMAGE_DOMAIN=$([ -n "$PROXY_HOST" ] && echo 'image.tmdb.org' || echo 'image.tmdb.org')

    # 生成应用配置文件
    cat <<EOF > "$DOCKER_ROOT_PATH/$APP_NAME/config/app.env"
COOKIECLOUD_HOST='http://$HOST_IP:58088'
COOKIECLOUD_KEY='moling1992'
COOKIECLOUD_PASSWORD='moling1992'
SEARCH_SOURCE='themoviedb'
TMDB_API_DOMAIN='api.tmdb.org'
TMDB_IMAGE_DOMAIN='$TMDB_IMAGE_DOMAIN'
GLOBAL_IMAGE_CACHE='True'
EOF

    # 拉取Docker镜像
    echo "拉取 Docker 镜像..."
    docker pull "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}moviepilot-v2:latest" || {
        echo "下载 Docker 镜像失败"
        return 1
    }
    check_and_remove_container "$APP_NAME" || {
        echo "准备容器环境失败"
        return 1
    }

    # 启动PT模式容器（挂载PT工具相关目录）
    echo "启动 $APP_NAME 容器..."
    if [ -n "$PROXY_HOST" ]; then
        docker run -d \
          --name $APP_NAME \
          --restart always \
          --privileged \
          $NETWORK_SETTING \
          $PORT_MAPPING \
          $MOUNT_HOSTS \
          $VOLUME_MOUNTS \
          -v "$DOCKER_ROOT_PATH/$APP_NAME/config:/config" \
          -v "$DOCKER_ROOT_PATH/$APP_NAME/core:/moviepilot/.cache/ms-playwright" \
          -v /var/run/docker.sock:/var/run/docker.sock \
          -v "$DOCKER_ROOT_PATH/transmission_mo/torrents/:/tr" \
          -v "$DOCKER_ROOT_PATH/qb_mo/qBittorrent/BT_backup/:/qb_mo" \
          -e MOVIEPILOT_AUTO_UPDATE=$result \
          -e NGINX_PORT=$PORT_NUMBER \
          -e PORT=$PORT \
          -e PUID="$PUID" \
          -e PGID="$PGID" \
          -e UMASK="$UMASK"  \
          -e TZ=Asia/Shanghai \
          -e AUTH_SITE=iyuu \
          -e IYUU_SIGN=$IYUU_TOKEN \
          -e SUPERUSER="admin" \
          -e API_TOKEN="moling1992moling1992" \
          -e PROXY_HOST="$PROXY_HOST" \
          ${GITHUB_TOKEN:+-e GITHUB_TOKEN="$GITHUB_TOKEN"} \
          "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}moviepilot-v2:latest" || {
            echo "启动容器失败"
            return 1
        }
    else
        docker run -d \
          --name $APP_NAME \
          --restart always \
          --privileged \
          $NETWORK_SETTING \
          $PORT_MAPPING \
          $MOUNT_HOSTS \
          $VOLUME_MOUNTS \
          -v "$DOCKER_ROOT_PATH/$APP_NAME/config:/config" \
          -v "$DOCKER_ROOT_PATH/$APP_NAME/core:/moviepilot/.cache/ms-playwright" \
          -v /var/run/docker.sock:/var/run/docker.sock \
          -v "$DOCKER_ROOT_PATH/transmission_mo/torrents/:/tr" \
          -v "$DOCKER_ROOT_PATH/qb_mo/qBittorrent/BT_backup/:/qb_mo" \
          -e MOVIEPILOT_AUTO_UPDATE=$result \
          -e NGINX_PORT=$PORT_NUMBER \
          -e PORT=$PORT \
          -e PUID="$PUID" \
          -e PGID="$PGID" \
          -e UMASK="$UMASK"  \
          -e TZ=Asia/Shanghai \
          -e AUTH_SITE=iyuu \
          -e IYUU_SIGN=$IYUU_TOKEN \
          -e SUPERUSER="admin" \
          -e API_TOKEN="moling1992moling1992" \
          -e GITHUB_PROXY="$GITHUB_PROXY" \
          -e PLUGIN_MARKET="https://github.com/jxxghp/MoviePilot-Plugins" \
          ${GITHUB_TOKEN:+-e GITHUB_TOKEN="$GITHUB_TOKEN"} \
          "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}moviepilot-v2:latest" || {
            echo "启动容器失败"
            return 1
        }
    fi

    # 检测容器初始化（等待user.db生成）
    echo "检测容器初始化状态..."
    local TIMEOUT=30
    local SECONDS=0
    while [ $SECONDS -lt $TIMEOUT ]; do
        sleep 5
        FILE_EXISTS=$(docker exec $APP_NAME test -f "/config/user.db" && echo "exists" || echo "not exists")
        if [ "$FILE_EXISTS" == "exists" ]; then
            echo "user.db 文件已生成，初始化完成。"
            break
        else
            echo -ne "初始化中... $SECONDS 秒 \r"
        fi
    done
    if [ $SECONDS -ge $TIMEOUT ]; then
        echo "超时：$TIMEOUT 秒内未检测到 user.db"
        return 1
    fi

    # 初始化数据库（PT模式适配）
    init_database_pt "$IYUU_TOKEN" "$APP_NAME"
    return 0
}


init_moviepilot_v2_pt() {
    iyuu_keys=(
        "IYUU30780T7a8c6fe94b419a49e3622cfca0eef9f8c4fce0af"
        "IYUU63661T999fe5e841ccc18e8789ae21eb7adec851e96f6a"
        "IYUU60348T5dd79edeee3fe54a54180bd8628d46bea608787c"
        "IYUU58629Tf8205354160cdaf0a85051a30f0e982b482df220"
        "IYUU60620T618188826799cccd9182f311f27ec6dcb450d014"
        "IYUU57154T8f70606de83160b4fe6633e56be108caaf2c8a54"
        "IYUU49366Td4f1825199719b9b144fb2e6be87d78abe309f8d"
        "IYUU59122Td9da6c6d60d8360599728969adde2a38f840c7bc"
        "IYUU57327T958bd01b181be18512c4305e60e2d6081e9e338b"
        "IYUU57294T883c746777f1a16b09f5d37d6d8c22b0992f92ab"
        "IYUU57308T02860d4294d9224d11a99e7ef4411f24a154f25f"
        "IYUU57155T60804655a5ca6045fd4cd336fbb32d3136e42c14"
        "IYUU57240Tfb094d8fa3196ecfc2a651a8bd408999593efbaf"
    )

    # 生成随机索引
    random_iyuu_index=$((RANDOM % ${#iyuu_keys[@]}))
    default_iyuu_key=${iyuu_keys[$random_iyuu_index]}

    # 处理IYUU TOKEN输入
    IYUU_TOKEN="${IYUU_TOKEN:-$default_iyuu_key}"
    read -p "请输入 IYUU TOKEN ($IYUU_TOKEN): " input_token
    IYUU_TOKEN="${input_token:-$IYUU_TOKEN}"

    # PT模式核心配置
    APP_NAME="moviepilot_v2_pt"
    PORT_NUMBER=53000  # 与115模式区分端口
    PORT=13001
    echo "当前使用【PT模式】（适配qbittorrent/transmission等PT工具）"
    echo "初始化 MoviePilot PT模式"

    # 网络模式选择
    while true; do
        read -p "请选择网络模式 (h: host, b: bridge，默认 host): " NETWORK_CHOICE
        NETWORK_CHOICE=${NETWORK_CHOICE:-h}
        if [[ "$NETWORK_CHOICE" == "h" || "$NETWORK_CHOICE" == "b" ]]; then
            break
        else
            echo "无效的选择，请输入 'h' 或 'b'。"
        fi
    done
    echo "已选择网络模式: $NETWORK_CHOICE"

    # 网络参数设置
    if [ "$NETWORK_CHOICE" == "b" ]; then
        NETWORK_SETTING="--network bridge"
        PORT_MAPPING="-p $PORT_NUMBER:$PORT_NUMBER"
    else
        NETWORK_SETTING="--network host"
        PORT_MAPPING=""
    fi

    # Hosts自动更新设置
    while true; do
        read -p "是否自动更新 hosts（使用 MOUNT_HOSTS）？(y/n，默认 n): " UPDATE_HOSTS_CHOICE
        UPDATE_HOSTS_CHOICE=${UPDATE_HOSTS_CHOICE:-n}
        if [[ "$UPDATE_HOSTS_CHOICE" == "y" || "$UPDATE_HOSTS_CHOICE" == "n" ]]; then
            break
        else
            echo "无效的选择，请输入 'y' 或 'n'。"
        fi
    done
    if [ "$UPDATE_HOSTS_CHOICE" == "y" ]; then
        if [ -z "$PROXY_HOST" ]; then
            MOUNT_HOSTS="-v $TEMP_HOSTS_FILE:/etc/hosts:ro"
        else
            MOUNT_HOSTS=""
        fi
    else
        MOUNT_HOSTS=""
    fi

    # 自动更新设置
    local result
    while true; do
        read -p "是否开启 MoviePilot 自动更新？(y/n，默认 n): " AUTO_UPDATE_CHOICE
        AUTO_UPDATE_CHOICE=${AUTO_UPDATE_CHOICE:-n}
        if [[ "$AUTO_UPDATE_CHOICE" == "y" || "$AUTO_UPDATE_CHOICE" == "n" ]]; then
            result="$([ "$AUTO_UPDATE_CHOICE" == "y" ] && echo "true" || echo "false")"
            break
        else
            echo "无效的选择，请输入 'y' 或 'n'。"
        fi
    done

    # GitHub代理设置
    GITHUB_PROXY="https://ghproxy.cn"
    read -p "是否修改 github 代理地址（默认值为 $GITHUB_PROXY，直接回车使用默认值，输入新地址则使用新地址，输入 n 不使用代理）？ " choice
    if [[ "$choice" == "n" ]]; then
        GITHUB_PROXY=""
    elif [ -n "$choice" ]; then
        GITHUB_PROXY="$choice"
    fi

    # GitHub Token设置（默认不使用）
    GITHUB_TOKEN=""  # 默认不使用Token
    while true; do
        read -p "是否使用默认 GitHub Token？(y/n，默认 n): " use_default
        use_default=${use_default:-n}  # 默认选择n（不使用）
        if [[ "$use_default" == "y" || "$use_default" == "n" ]]; then
            if [ "$use_default" == "y" ]; then
                GITHUB_TOKEN="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"
            else
                read -p "请输入自定义 GitHub Token (留空则不使用): " input_github_token
                GITHUB_TOKEN="$input_github_token"
            fi
            break
        else
            echo "无效的选择，请输入 'y' 或 'n'。"
        fi
    done

    # PT模式目录结构（适配qbittorrent/transmission）
    mkdir -p "$DOCKER_ROOT_PATH/$APP_NAME/"{main,config,core}
    mkdir -p "$DOCKER_ROOT_PATH/qb_mo/qBittorrent/BT_backup"  # qbittorrent备份目录
    mkdir -p "$DOCKER_ROOT_PATH/transmission_mo/torrents"     # transmission种子目录
    mkdir -p "$VIDEO_ROOT_PATH/downloads/电影" "$VIDEO_ROOT_PATH/downloads/电视剧"  # PT下载目录
    mkdir -p "$VIDEO_ROOT_PATH/links/电影" "$VIDEO_ROOT_PATH/links/电视剧"          # 软链接目录

    # 处理目标文件夹（下载/解压）
    handle_target_directory "$DOCKER_ROOT_PATH/$APP_NAME" "${APP_NAME}.tgz"
    local handle_result=$?
    if [ $handle_result -eq 0 ]; then
        echo "开始下载 $APP_NAME.tgz 文件..."
        if ! curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/${APP_NAME}.tgz -o "$CURRENT_DIR/${APP_NAME}.tgz"; then
            echo "下载 ${APP_NAME}.tgz 文件失败，但将继续执行后续步骤"
        else
            echo "解压 ${APP_NAME}.tgz 文件..."
            if ! tar --strip-components=1 -zxvf "$CURRENT_DIR/${APP_NAME}.tgz" -C "$DOCKER_ROOT_PATH/$APP_NAME/"; then
                echo "解压 ${APP_NAME}.tgz 文件失败，但将继续执行后续步骤"
            fi
        fi
    elif [ $handle_result -eq 1 ]; then
        echo "使用现有文件继续后续流程..."
    else
        echo "跳过文件处理步骤，继续执行后续操作"
    fi

    # 调试信息输出
    echo "调试信息:"
    echo "NETWORK_CHOICE: $NETWORK_CHOICE"
    echo "PORT_MAPPING: $PORT_MAPPING"
    echo "NETWORK_SETTING: $NETWORK_SETTING"

    # TMDB域名设置
    TMDB_IMAGE_DOMAIN=$([ -n "$PROXY_HOST" ] && echo 'image.tmdb.org' || echo 'image.tmdb.org')

    # 生成应用配置文件
    cat <<EOF > "$DOCKER_ROOT_PATH/$APP_NAME/config/app.env"
COOKIECLOUD_HOST='http://$HOST_IP:58088'
COOKIECLOUD_KEY='moling1992'
COOKIECLOUD_PASSWORD='moling1992'
SEARCH_SOURCE='themoviedb'
TMDB_API_DOMAIN='api.tmdb.org'
TMDB_IMAGE_DOMAIN='$TMDB_IMAGE_DOMAIN'
GLOBAL_IMAGE_CACHE='True'
EOF

    # 拉取Docker镜像
    echo "拉取 Docker 镜像..."
    docker pull "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}moviepilot-v2:latest" || {
        echo "下载 Docker 镜像失败"
        return 1
    }
    check_and_remove_container "$APP_NAME" || {
        echo "准备容器环境失败"
        return 1
    }

    # 启动PT模式容器（挂载PT工具相关目录）
    echo "启动 $APP_NAME 容器..."
    if [ -n "$PROXY_HOST" ]; then
        docker run -d \
          --name $APP_NAME \
          --restart always \
          --privileged \
          $NETWORK_SETTING \
          $PORT_MAPPING \
          $MOUNT_HOSTS \
          $VOLUME_MOUNTS \
          -v "$DOCKER_ROOT_PATH/$APP_NAME/config:/config" \
          -v "$DOCKER_ROOT_PATH/$APP_NAME/core:/moviepilot/.cache/ms-playwright" \
          -v /var/run/docker.sock:/var/run/docker.sock \
          -v "$DOCKER_ROOT_PATH/transmission_mo/torrents/:/tr" \
          -v "$DOCKER_ROOT_PATH/qb_mo/qBittorrent/BT_backup/:/qb_mo" \
          -e MOVIEPILOT_AUTO_UPDATE=$result \
          -e NGINX_PORT=$PORT_NUMBER \
          -e PORT=$PORT \
          -e PUID="$PUID" \
          -e PGID="$PGID" \
          -e UMASK="$UMASK"  \
          -e TZ=Asia/Shanghai \
          -e AUTH_SITE=iyuu \
          -e IYUU_SIGN=$IYUU_TOKEN \
          -e SUPERUSER="admin" \
          -e API_TOKEN="moling1992moling1992" \
          -e PROXY_HOST="$PROXY_HOST" \
          ${GITHUB_TOKEN:+-e GITHUB_TOKEN="$GITHUB_TOKEN"} \
          "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}moviepilot-v2:latest" || {
            echo "启动容器失败"
            return 1
        }
    else
        docker run -d \
          --name $APP_NAME \
          --restart always \
          --privileged \
          $NETWORK_SETTING \
          $PORT_MAPPING \
          $MOUNT_HOSTS \
          $VOLUME_MOUNTS \
          -v "$DOCKER_ROOT_PATH/$APP_NAME/config:/config" \
          -v "$DOCKER_ROOT_PATH/$APP_NAME/core:/moviepilot/.cache/ms-playwright" \
          -v /var/run/docker.sock:/var/run/docker.sock \
          -v "$DOCKER_ROOT_PATH/transmission_mo/torrents/:/tr" \
          -v "$DOCKER_ROOT_PATH/qb_mo/qBittorrent/BT_backup/:/qb_mo" \
          -e MOVIEPILOT_AUTO_UPDATE=$result \
          -e NGINX_PORT=$PORT_NUMBER \
          -e PORT=$PORT \
          -e PUID="$PUID" \
          -e PGID="$PGID" \
          -e UMASK="$UMASK"  \
          -e TZ=Asia/Shanghai \
          -e AUTH_SITE=iyuu \
          -e IYUU_SIGN=$IYUU_TOKEN \
          -e SUPERUSER="admin" \
          -e API_TOKEN="moling1992moling1992" \
          -e GITHUB_PROXY="$GITHUB_PROXY" \
          -e PLUGIN_MARKET="https://github.com/jxxghp/MoviePilot-Plugins" \
          ${GITHUB_TOKEN:+-e GITHUB_TOKEN="$GITHUB_TOKEN"} \
          "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}moviepilot-v2:latest" || {
            echo "启动容器失败"
            return 1
        }
    fi

    # 检测容器初始化（等待user.db生成）
    echo "检测容器初始化状态..."
    local TIMEOUT=30
    local SECONDS=0
    while [ $SECONDS -lt $TIMEOUT ]; do
        sleep 5
        FILE_EXISTS=$(docker exec $APP_NAME test -f "/config/user.db" && echo "exists" || echo "not exists")
        if [ "$FILE_EXISTS" == "exists" ]; then
            echo "user.db 文件已生成，初始化完成。"
            break
        else
            echo -ne "初始化中... $SECONDS 秒 \r"
        fi
    done
    if [ $SECONDS -ge $TIMEOUT ]; then
        echo "超时：$TIMEOUT 秒内未检测到 user.db"
        return 1
    fi

    # 初始化数据库（PT模式适配）
    init_database_pt "$IYUU_TOKEN" "$APP_NAME"
    return 0
}


init_moviepilot_v2_115() {
    iyuu_keys=(
        "IYUU30780T7a8c6fe94b419a49e3622cfca0eef9f8c4fce0af"
        "IYUU63661T999fe5e841ccc18e8789ae21eb7adec851e96f6a"
        "IYUU60348T5dd79edeee3fe54a54180bd8628d46bea608787c"
        "IYUU58629Tf8205354160cdaf0a85051a30f0e982b482df220"
        "IYUU60620T618188826799cccd9182f311f27ec6dcb450d014"
        "IYUU57154T8f70606de83160b4fe6633e56be108caaf2c8a54"
        "IYUU49366Td4f1825199719b9b144fb2e6be87d78abe309f8d"
        "IYUU59122Td9da6c6d60d8360599728969adde2a38f840c7bc"
        "IYUU57327T958bd01b181be18512c4305e60e2d6081e9e338b"
        "IYUU57294T883c746777f1a16b09f5d37d6d8c22b0992f92ab"
        "IYUU57308T02860d4294d9224d11a99e7ef4411f24a154f25f"
        "IYUU57155T60804655a5ca6045fd4cd336fbb32d3136e42c14"
        "IYUU57240Tfb094d8fa3196ecfc2a651a8bd408999593efbaf"
    )

    # 生成随机IYUU索引
    random_iyuu_index=$((RANDOM % ${#iyuu_keys[@]}))
    default_iyuu_key=${iyuu_keys[$random_iyuu_index]}

    # 处理IYUU TOKEN输入
    IYUU_TOKEN="${IYUU_TOKEN:-$default_iyuu_key}"
    read -p "请输入 IYUU TOKEN ($IYUU_TOKEN): " input_token
    IYUU_TOKEN="${input_token:-$IYUU_TOKEN}"

    # 115模式核心配置
    APP_NAME="moviepilot_v2_115"
    PORT_NUMBER=52000  # 115模式独立端口
    PORT=13002
    echo "当前使用【115模式】（适配115网盘下载）"
    echo "初始化 MoviePilot 115模式"

    # 网络模式选择（默认bridge模式）
    while true; do
        read -p "请选择网络模式 (h: host, b: bridge，默认 bridge): " NETWORK_CHOICE
        NETWORK_CHOICE=${NETWORK_CHOICE:-b}  # 默认bridge模式
        if [[ "$NETWORK_CHOICE" == "h" || "$NETWORK_CHOICE" == "b" ]]; then
            break
        else
            echo "无效的选择，请输入 'h' 或 'b'。"
        fi
    done
    echo "已选择网络模式: $NETWORK_CHOICE"

    # 网络参数设置
    if [ "$NETWORK_CHOICE" == "b" ]; then
        NETWORK_SETTING="--network bridge"
        PORT_MAPPING="-p $PORT_NUMBER:$PORT_NUMBER -p 56066:56066"
    else
        NETWORK_SETTING="--network host"
        PORT_MAPPING=""  # host模式无需显式映射端口
    fi

    # 自动更新设置
    local result
    while true; do
        read -p "是否开启自动更新？(y/n，默认 n): " AUTO_UPDATE_CHOICE
        AUTO_UPDATE_CHOICE=${AUTO_UPDATE_CHOICE:-n}
        if [[ "$AUTO_UPDATE_CHOICE" == "y" || "$AUTO_UPDATE_CHOICE" == "n" ]]; then
            result="$([ "$AUTO_UPDATE_CHOICE" == "y" ] && echo "true" || echo "false")"
            break
        else
            echo "无效的选择，请输入 'y' 或 'n'。"
        fi
    done

    # 使用默认GitHub Token（不再询问）
    GITHUB_TOKEN="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"
    echo "使用默认 GitHub Token"

    # 115模式目录结构
    mkdir -p "$DOCKER_ROOT_PATH/$APP_NAME/"{main,config,core}
    mkdir -p "$VIDEO_ROOT_PATH/整理库/电影" "$VIDEO_ROOT_PATH/整理库/电视剧" "$VIDEO_ROOT_PATH/整理库/媒体信息"
    mkdir -p "$VIDEO_ROOT_PATH/原始库"                              

    # 处理目标文件夹（下载/解压）
    handle_target_directory "$DOCKER_ROOT_PATH/$APP_NAME" "${APP_NAME}.tgz"
    local handle_result=$?
    if [ $handle_result -eq 0 ]; then
        echo "下载 $APP_NAME.tgz 文件..."
        if ! curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/${APP_NAME}.tgz -o "$CURRENT_DIR/${APP_NAME}.tgz"; then
            echo "下载 ${APP_NAME}.tgz 失败，但将继续执行后续步骤"
        else
            echo "解压 ${APP_NAME}.tgz 文件..."
            if ! tar --strip-components=1 -zxvf "$CURRENT_DIR/${APP_NAME}.tgz" -C "$DOCKER_ROOT_PATH/$APP_NAME/"; then
                echo "解压 ${APP_NAME}.tgz 失败，但将继续执行后续步骤"
            fi
        fi
    elif [ $handle_result -eq 1 ]; then
        echo "使用现有文件继续..."
    else
        echo "跳过文件处理步骤，继续执行后续操作"
    fi

    # 调试信息
    echo "调试信息:"
    echo "NETWORK_CHOICE: $NETWORK_CHOICE"
    echo "PORT_MAPPING: $PORT_MAPPING"

    # TMDB域名设置
    TMDB_IMAGE_DOMAIN=$([ -n "$PROXY_HOST" ] && echo 'image.tmdb.org' || echo 'image.tmdb.org')

    # 生成115模式配置文件
    cat <<EOF > "$DOCKER_ROOT_PATH/$APP_NAME/config/app.env"
COOKIECLOUD_HOST='http://$HOST_IP:58088'
COOKIECLOUD_KEY='moling1992'
COOKIECLOUD_PASSWORD='moling1992'
SEARCH_SOURCE='themoviedb'
TMDB_API_DOMAIN='api.tmdb.org'
TMDB_IMAGE_DOMAIN='$TMDB_IMAGE_DOMAIN'
GLOBAL_IMAGE_CACHE='True'
EOF

    # 拉取Docker镜像
    echo "拉取 Docker 镜像..."
    docker pull "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}moviepilot-v2:latest" || {
        echo "下载镜像失败"
        return 1
    }
    check_and_remove_container "$APP_NAME" || {
        echo "准备容器环境失败"
        return 1
    }

    # 启动115模式容器（统一插件市场配置）
    echo "启动 $APP_NAME 容器..."
    docker run -d \
      --name $APP_NAME \
      --restart always \
      --privileged \
      $NETWORK_SETTING \
      $PORT_MAPPING \
      $VOLUME_MOUNTS \
      -v "$DOCKER_ROOT_PATH/$APP_NAME/config:/config" \
      -v "$DOCKER_ROOT_PATH/$APP_NAME/core:/moviepilot/.cache/ms-playwright" \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -e MOVIEPILOT_AUTO_UPDATE=$result \
      -e NGINX_PORT=$PORT_NUMBER \
      -e PORT=$PORT \
      -e PUID="$PUID" \
      -e PGID="$PGID" \
      -e UMASK="$UMASK"  \
      -e TZ=Asia/Shanghai \
      -e AUTH_SITE=iyuu \
      -e IYUU_SIGN=$IYUU_TOKEN \
      -e SUPERUSER="admin" \
      -e API_TOKEN="moling1992moling1992" \
      ${PROXY_HOST:+-e PROXY_HOST="$PROXY_HOST"} \
      -e GITHUB_TOKEN="$GITHUB_TOKEN" \
      -e PLUGIN_MARKET=https://github.com/jxxghp/MoviePilot-Plugins/,https://github.com/DDS-Derek/MoviePilot-Plugins/,https://github.com/madrays/MoviePilot-Plugins/,https://github.com/DzAvril/MoviePilot-Plugins/ \
      "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}moviepilot-v2:latest" || {
        echo "启动容器失败"
        return 1
    }

    # 检测容器初始化
    echo "检测115模式容器初始化..."
    local TIMEOUT=30
    local SECONDS=0
    while [ $SECONDS -lt $TIMEOUT ]; do
        sleep 5
        FILE_EXISTS=$(docker exec $APP_NAME test -f "/config/user.db" && echo "exists" || echo "not exists")
        if [ "$FILE_EXISTS" == "exists" ]; then
            echo "user.db 生成，初始化完成。"
            break
        else
            echo -ne "初始化中... $SECONDS 秒 \r"
        fi
    done
    if [ $SECONDS -ge $TIMEOUT ]; then
        echo "超时：未检测到 user.db"
        return 1
    fi

    # 初始化115模式数据库
    init_database_115 "$IYUU_TOKEN" "$APP_NAME"
    return 0
}

# 115模式数据库初始化（保持原始逻辑）
init_database_115() {
    local IYUU_TOKEN="$1"
    local APP_NAME="$2"
    local SQL_FILE="$DOCKER_ROOT_PATH/$APP_NAME/config/script.sql"

    # 写入115模式数据库调整SQL
    echo "UPDATE systemconfig SET value = REPLACE(value, '192.168.66.27', '$HOST_IP') WHERE value LIKE '%192.168.66.27%';" >> "$SQL_FILE"
    echo "UPDATE systemconfig SET value = REPLACE(value, 'IYUU59122Td9da6c6d60d8360599728969adde2a38f840c7bc', '$IYUU_TOKEN') WHERE value LIKE '%IYUU59122Td9da6c6d60d8360599728969adde2a38f840c7bc%';" >> "$SQL_FILE"

    # 执行SQL脚本
    echo "执行115模式数据库初始化..."
    [ -f "$SQL_FILE" ] || {
        echo "SQL文件不存在"
        exit 1
    }
    docker exec -i -w /config $APP_NAME python -c "
import sqlite3
conn = sqlite3.connect('user.db')
cur = conn.cursor()
with open('script.sql', 'r') as f:
    cur.executescript(f.read())
conn.commit()
conn.close()
    " || {
        echo "数据库初始化失败"
        exit 1
    }

    # 重启容器
    docker restart $APP_NAME
    local SECONDS=0
    while [ $SECONDS -lt 20 ]; do
        STATUS=$(docker inspect --format '{{.State.Status}}' $APP_NAME)
        if [ "$STATUS" == "running" ]; then
            echo "容器 $APP_NAME 重启成功"
            return 0
        fi
        sleep 2
        SECONDS=$((SECONDS + 2))
    done
    echo "容器重启超时"
    exit 1
}

init_embypt_mo() {
    local mode="pt"
    local version="k"

    # 提示用户选择模式（带超时功能）
    echo "请选择模式 (pt/115) [默认: pt]"
    read -t 10 -p "(10秒后自动选择 pt): " input_mode
    input_mode=${input_mode:-pt}
    if [[ $input_mode == "pt" || $input_mode == "115" ]]; then
        mode=$input_mode
        echo "已选择: $mode"
    else
        echo "无效的模式选项，使用默认值 pt"
        mode="pt"
    fi

    # 提示用户选择版本（带超时功能）
    echo "请选择版本 (k: 开新版, z: 正版) [默认: k]"
    read -t 10 -p "(10秒后自动选择 k): " input_version
    input_version=${input_version:-k}
    if [[ $input_version == "k" || $input_version == "z" ]]; then
        version=$input_version
        echo "已选择: $version"
    else
        echo "无效的版本选项，使用默认值 k"
        version="k"
    fi

    local container_name
    local package_name
    local image_name

    if [[ $mode == "115" ]]; then
        container_name="emby115_mo"
    else
        container_name="embypt_mo"
    fi

    echo "初始化 $container_name"
    mkdir -p "$DOCKER_ROOT_PATH/$container_name"

    # 根据架构和版本选择包名
    if [[ $ARCHITECTURE == "armv7l" || $ARCHITECTURE == "aarch64" ]]; then
        if [[ $version == "k" ]]; then
            if [[ $mode == "pt" ]]; then
                package_name="embypt_mo_arm.tgz"
            else
                package_name="emby115_mo_arm.tgz"
            fi
        else
            if [[ $mode == "pt" ]]; then
                package_name="embyptzb_mo.tgz"
            else
                package_name="emby115zb_mo.tgz"
            fi
        fi
    else
        if [[ $version == "k" ]]; then
            if [[ $mode == "pt" ]]; then
                package_name="embypt_mo.tgz"
            else
                package_name="emby115_mo.tgz"
            fi
        else
            if [[ $mode == "pt" ]]; then
                package_name="embyptzb_mo.tgz"
            else
                package_name="emby115zb_mo.tgz"
            fi
        fi
    fi

    local download_url="https://moling7882.oss-cn-beijing.aliyuncs.com/999/${package_name}"

    # 下载文件
    if ! curl -L "$download_url" -o "$CURRENT_DIR/${package_name}"; then
        echo "下载 ${package_name} 失败，但仍尝试继续"
    fi

    # 解压文件
    if ! tar --strip-components=1 -zxvf "$CURRENT_DIR/${package_name}" -C "$DOCKER_ROOT_PATH/$container_name/"; then
        echo "解压 ${package_name} 失败，但仍尝试继续"
    fi

    # 删除临时文件
    rm -f "$CURRENT_DIR/${package_name}"

    # 根据架构和版本选择镜像名称
    if [[ $ARCHITECTURE == "armv7l" || $ARCHITECTURE == "aarch64" ]]; then
        if [[ $version == "k" ]]; then
            image_name="embyserver_arm64v8"
        else
            image_name="emby"
        fi
    else
        if [[ $version == "k" ]]; then
            image_name="embyserver"
        else
            image_name="emby"
        fi
    fi

    local port_http
    local port_https
    if [[ $mode == "pt" ]]; then
        port_http=58096
        port_https=58920
    else
        port_http=38096
        port_https=38920
    fi

    # 运行 Docker 容器
    if ! docker run -d \
        --name $container_name \
        --restart always\
        --device /dev/dri:/dev/dri \
        --network bridge \
        --privileged \
        -e PUID="$PUID" \
        -e PGID="$PGID" \
        -e UMASK="$UMASK" \
        -e TZ=Asia/Shanghai \
        -v "$DOCKER_ROOT_PATH/$container_name:/config" \
        $VOLUME_MOUNTS \
        -p $port_http:8096 \
        -p $port_https:8920 \
        -e NO_PROXY="172.17.0.1,127.0.0.1,localhost" \
        -e ALL_PROXY="$PROXY_HOST" \
        -e HTTP_PROXY="$PROXY_HOST" \
        "${DOCKER_REGISTRY}/${image_name}:latest"; then
        echo "启动 $container_name 容器失败"
        return 1
    fi

    echo "$container_name 初始化成功"
    return 0
}

init_csf_mo() {
    echo "初始化 csf_mo"
    mkdir -p "$DOCKER_ROOT_PATH/csf_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/csf_mo.tgz -o "$CURRENT_DIR/csf_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/csf_mo.tgz" -C "$DOCKER_ROOT_PATH/csf_mo/"
    sed -i "s/192.168.66.220/$HOST_IP/g" "$DOCKER_ROOT_PATH/csf_mo/config/ChineseSubFinderSettings.json"
    docker run -d --name csf_mo --restart always\
        -v "$DOCKER_ROOT_PATH/csf_mo:/config" \
        $VOLUME_MOUNTS \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        --network bridge --privileged \
        -p 59035:19035 \
        -p 59037:19037 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}chinesesubfinder:latest"
}

init_frpc_mo() {
    # 随机选择一个IP
    VPS_IP=$(select_random_ip)

    # 提示用户输入 VPS_IP，设置超时时间为 10 秒
    read -t 10 -p "请输入 VPS_IP ($VPS_IP): " input_vps_ip

    # 如果用户没有输入内容，则使用随机选取的IP
    if [ -z "$input_vps_ip" ]; then
        VPS_IP=$(select_random_ip)
    else
        VPS_IP=$input_vps_ip
    fi

    # 简单的IP格式验证
    if [[ ! "$VPS_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "输入的内容不是一个有效的IP地址，将使用默认生成的IP。"
        VPS_IP=$(select_random_ip)
    fi

    echo "最终使用的 VPS_IP 是: $VPS_IP"

    # 后续初始化代码保持不变...
    echo "初始化 frpc_mo"
    mkdir -p "$DOCKER_ROOT_PATH/frpc_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/frpc_mo.tgz -o "$CURRENT_DIR/frpc_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/frpc_mo.tgz" -C "$DOCKER_ROOT_PATH/frpc_mo/"
    sed -i "s/192.168.66.26/$HOST_IP/g" "$DOCKER_ROOT_PATH/frpc_mo/frpc.toml"
    sed -i "s/130.162.246.23/$VPS_IP/g" "$DOCKER_ROOT_PATH/frpc_mo/frpc.toml"
    sed -i "s/10114/$RANDOM_NUMBER/g" "$DOCKER_ROOT_PATH/frpc_mo/frpc.toml"
    sed -i "s/9999/$RANDOM_VARIABLE/g" "$DOCKER_ROOT_PATH/frpc_mo/frpc.toml"
    docker run -d --name frpc_mo --restart always\
        -v "$DOCKER_ROOT_PATH/frpc_mo/frpc.toml:/etc/frp/frpc.toml" \
        --network host --privileged \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}frpc:latest"
}

init_calibre_mo() {
    echo "初始化 calibre_mo"
    mkdir -p "$DOCKER_ROOT_PATH/calibre_mo/config"
    mkdir -p "$VIDEO_ROOT_PATH/books/upload"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/calibre_mo.tgz -o "$CURRENT_DIR/calibre_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/calibre_mo.tgz" -C "$DOCKER_ROOT_PATH/calibre_mo/"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/books.tgz -o "$CURRENT_DIR/books.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/books.tgz" -C "$VIDEO_ROOT_PATH/books/"
    docker run -d --name calibre_mo --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -v "$DOCKER_ROOT_PATH/calibre_mo/config":/config \
        -v "$VIDEO_ROOT_PATH/books":/books \
        -v "$VIDEO_ROOT_PATH/books/upload":/upload \
        -p 57089:8083 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}calibre-web:latest"
}

init_uptime_kuma_mo() {
    echo "初始化 uptime_kuma_mo"
    mkdir -p "$DOCKER_ROOT_PATH/uptime_kuma_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/uptime_kuma_mo.tgz -o "$CURRENT_DIR/uptime_kuma_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/uptime_kuma_mo.tgz" -C "$DOCKER_ROOT_PATH/uptime_kuma_mo/"
    docker run -d --name uptime_kuma_mo --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -v $DOCKER_ROOT_PATH/uptime_kuma_mo:/app/data \
        -p 53001:3001 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}uptime-kuma:latest"
}

init_audiobookshelf_mo() {
    echo "初始化 audiobookshelf_mo"
    mkdir -p "$DOCKER_ROOT_PATH/audiobookshelf_mo"
    mkdir -p "$VIDEO_ROOT_PATH/audiobook"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/audiobookshelf_mo.tgz -o "$CURRENT_DIR/audiobookshelf_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/audiobookshelf_mo.tgz" -C "$DOCKER_ROOT_PATH/audiobookshelf_mo/"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/audiobook.tgz -o "$CURRENT_DIR/audiobook.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/audiobook.tgz" -C "$VIDEO_ROOT_PATH/audiobook/"
    docker run -d --name audiobookshelf_mo --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 57758:80 \
        $VOLUME_MOUNTS \
        -v $DOCKER_ROOT_PATH/audiobookshelf_mo/config:/config \
        -v $DOCKER_ROOT_PATH/audiobookshelf_mo/metadata:/metadata \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}audiobookshelf:latest"
}

init_easy_itv_mo() {
    echo "初始化 easy_itv_mo"
    docker run -d --name easy_itv_mo --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 58126:8123 \
        -e token=moling1992 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}easy-itv:latest"
}    

init_cloudbak_mo() {
    echo "初始化 cloudbak_mo"
    mkdir -p "$DOCKER_ROOT_PATH/cloudbak_mo/data"
    docker run -d --name cloudbak_mo --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 56332:9527 \
        -v $DOCKER_ROOT_PATH/cloudbak_mo/data:/app/data \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}cloudbak:latest"
}

init_komga_mo() {
    echo "初始化 komga_mo"
    mkdir -p "$DOCKER_ROOT_PATH/komga_mo"
    mkdir -p "$VIDEO_ROOT_PATH/comic"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/komga_mo.tgz -o "$CURRENT_DIR/komga_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/komga_mo.tgz" -C "$DOCKER_ROOT_PATH/komga_mo/"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/comic.tgz -o "$CURRENT_DIR/comic.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/comic.tgz" -C "$VIDEO_ROOT_PATH/comic/"
    docker run -d --name komga_mo --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 55600:25600 \
        $VOLUME_MOUNTS \
        -v $DOCKER_ROOT_PATH/komga_mo/config:/config \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}komga:latest"
}

init_bili_sync_rs_mo() {
    echo "初始化 bili_sync_rs_mo"
    mkdir -p "$DOCKER_ROOT_PATH/bili_sync_rs_mo"
    mkdir -p "$VIDEO_ROOT_PATH/bili_sync"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/bili_sync_rs_mo.tgz -o "$CURRENT_DIR/bili_sync_rs_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/bili_sync_rs_mo.tgz" -C "$DOCKER_ROOT_PATH/bili_sync_rs_mo/"
    docker run -d \
        --name bili_sync_rs_mo \
        --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -v $DOCKER_ROOT_PATH/bili_sync_rs_mo:/app/.config/bili-sync/ \
        -v $VIDEO_ROOT_PATH/bili_sync:/videos \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}bili-sync-rs:latest"
}

init_emulatorjs_mo() {
    echo "初始化 emulatorjs_mo"
    mkdir -p "$DOCKER_ROOT_PATH/emulatorjs_mo/config"
    mkdir -p "$VIDEO_ROOT_PATH/game"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/emulatorjs_mo.tgz -o "$CURRENT_DIR/emulatorjs_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/emulatorjs_mo.tgz" -C "$DOCKER_ROOT_PATH/emulatorjs_mo/"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/game.tgz -o "$CURRENT_DIR/game.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/game.tgz" -C "$VIDEO_ROOT_PATH/game/"
    docker run -d --name emulatorjs_mo --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 51239:80 \
        -p 58087:3000 \
        -v $DOCKER_ROOT_PATH/emulatorjs_mo/config:/config \
        -v $VIDEO_ROOT_PATH/game:/data \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}emulatorjs:latest"
}

init_playlistdl_mo() {
    echo "初始化 playlistdl_mo"
    mkdir -p "$DOCKER_ROOT_PATH/playlistdl_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/playlistdl_mo.tgz -o "$CURRENT_DIR/playlistdl_mo.tgz"
    tar --strip-components=1 -zxvf "$CURRENT_DIR/playlistdl_mo.tgz" -C "$DOCKER_ROOT_PATH/playlistdl_mo/"
    docker run -d \
        --name playlistdl_mo \
        --restart always\
		--network bridge \
		-e ADMIN_USERNAME=666666 \
		-e ADMIN_PASSWORD=666666 \
		-e AUDIO_DOWNLOAD_PATH=/download \
		-e CLEANUP_INTERVAL=300 \
		-p 50015:5000 \
		-v $VIDEO_ROOT_PATH/music/download:/download\
        $VOLUME_MOUNTS \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}playlistdl:v2"
}

init_musicn_mo() {
    echo "初始化 musicn_mo"
    mkdir -p "$DOCKER_ROOT_PATH/musicn_mo"
    mkdir -p "$VIDEO_ROOT_PATH/music"
    docker run -d \
        --name musicn_mo \
        --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -v "$DOCKER_ROOT_PATH/musicn_mo":/data \
        -v "$VIDEO_ROOT_PATH/music":/music \
        -p 57478:7478 \
        --entrypoint "/sbin/tini" \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}musicn-container:latest" -- msc -q
}

init_navidrome_mo() {
    echo "初始化 navidrome_mo"
    mkdir -p "$DOCKER_ROOT_PATH/navidrome_mo"
    mkdir -p "$VIDEO_ROOT_PATH/music/download" "$VIDEO_ROOT_PATH/music/musicok"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/navidrome_mo.tgz -o "$CURRENT_DIR/navidrome_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/navidrome_mo.tgz" -C "$DOCKER_ROOT_PATH/navidrome_mo/"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/musicok.tgz -o "$CURRENT_DIR/musicok.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/musicok.tgz" -C "$VIDEO_ROOT_PATH/music/musicok"
    docker run -d --name navidrome_mo --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 54533:4533 \
        -e ND_SCANSCHEDULE="1h" \
        -e ND_LOGLEVEL="info" \
        -e ND_BASEURL="" \
        -e ND_SPOTIFY_ID="d5fffcb6f90040f2a817430d85694ba7" \
        -e ND_SPOTIFY_SECRET="172ee57bd6aa4b9d9f30f8a9311b91ed" \
        -e ND_LASTFM_APIKEY="842597b59804a3c4eb4f0365db458561" \
        -e ND_LASTFM_SECRET="aee9306d8d005de81405a37ec848983c" \
        -e ND_LASTFM_LANGUAGE="zh" \
        -v $DOCKER_ROOT_PATH/navidrome_mo/data:/data \
        -v $VIDEO_ROOT_PATH/music/musicok:/music \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}navidrome:latest"
}

init_cloudsaver_mo() {
    echo "初始化 cloudsaver_mo"
    mkdir -p "$DOCKER_ROOT_PATH/cloudsaver_mo/data" "$DOCKER_ROOT_PATH/cloudsaver_mo/config"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/cloudsaver_mo.tgz -o "$CURRENT_DIR/cloudsaver_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/cloudsaver_mo.tgz" -C "$DOCKER_ROOT_PATH/cloudsaver_mo/"
    docker run -d --name cloudsaver_mo --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 58032:8008 \
        -v $DOCKER_ROOT_PATH/cloudsaver_mo/data:/app/data \
        -v $DOCKER_ROOT_PATH/cloudsaver_mo/config:/app/config \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}cloudsaver:latest"
}

init_urbackup_mo() {
    echo "初始化 urbackup_mo"
    mkdir -p "$DOCKER_ROOT_PATH/urbackup_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/urbackup_mo.tgz -o "$CURRENT_DIR/urbackup_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/urbackup_mo.tgz" -C "$DOCKER_ROOT_PATH/urbackup_mo/"
    docker run -d --name urbackup_mo --restart always\
        --network host --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        $VOLUME_MOUNTS \
        -v $VIDEO_ROOT_PATH/urbackup_mo:/backups \
        -v $DOCKER_ROOT_PATH/urbackup_mo:/var/urbackup \
        -v $DOCKER_ROOT_PATH:/docker \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}urbackup-server:latest"
}

init_qrding_mo () {
    echo "初始化 qrding_mo "
    docker run -d --name qrding_mo --restart always\
        --network bridge  \
        -p 50026:3000 \
        "ccr.ccs.tencentyun.com/moling7882/qrding:latest"
}

init_dockports_mo () {
    echo "初始化 dockports_mo "
    mkdir -p "$DOCKER_ROOT_PATH/dockports_mo/config"
    docker run -d --name dockports_mo --restart always\
        --network host  \
        -v /var/run/docker.sock:/var/run/docker.sock:ro \
        -v $DOCKER_ROOT_PATH/dockports_mo/config:/app/config \
        "ccr.ccs.tencentyun.com/moling7882/dockports:latest"
}

init_vertex_mo() {
    echo "初始化 vertex_mo"
    mkdir -p "$DOCKER_ROOT_PATH/vertex_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/vertex_mo.tgz -o "$CURRENT_DIR/vertex_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/vertex_mo.tgz" -C "$DOCKER_ROOT_PATH/vertex_mo/"
    docker run -d --name vertex_mo --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 53800:3000 \
        -p 53443:3443 \
        -v $DOCKER_ROOT_PATH/vertex_mo:/vertex \
        $VOLUME_MOUNTS \
        -e TZ=Asia/Shanghai \
        -e HTTPS_ENABLE=true \
        -e HTTPS_PORT=3443 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}vertex:latest"
}

init_handbrake_mo () {
    echo "初始化 handbrake_mo "
    mkdir -p "$DOCKER_ROOT_PATH/handbrake_mo/config"
    mkdir -p "$VIDEO_ROOT_PATH/handbrake_mo/output"
    mkdir -p "$VIDEO_ROOT_PATH/handbrake_mo/watch"
    mkdir -p "$VIDEO_ROOT_PATH/handbrake_mo/storage"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/handbrake_mo.tgz -o "$CURRENT_DIR/handbrake_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/handbrake_mo.tgz" -C "$DOCKER_ROOT_PATH/handbrake_mo/"
    docker run -d --name handbrake_mo --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -e "LANG=zh_CN.UTF-8" \
        -p 50020:5800 \
        -v "$DOCKER_ROOT_PATH/handbrake_mo/songti.ttc:/usr/share/fonts/songti.ttc" \
        -v "$DOCKER_ROOT_PATH/handbrake_mo/config:/config:rw" \
        -v "$VIDEO_ROOT_PATH/handbrake_mo/output:/output:rw" \
        -v "$VIDEO_ROOT_PATH/handbrake_mo/storage:/storage:ro" \
        -v "$VIDEO_ROOT_PATH/handbrake_mo/watch:/watch:rw" \
        $VOLUME_MOUNTS \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}handbrake:latest"
}

init_wallos_mo () {
    echo "初始化 wallos_mo "
    mkdir -p "$DOCKER_ROOT_PATH/wallos_mo/db"
    mkdir -p "$DOCKER_ROOT_PATH/wallos_mo/app/logos"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/wallos_mo.tgz -o "$CURRENT_DIR/wallos_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/wallos_mo.tgz" -C "$DOCKER_ROOT_PATH/wallos_mo/"
    docker run -d --name wallos_mo --restart always \
        --network bridge --privileged \
        -p 58282:80/tcp \
        -e PUID=1000 -e PGID=1000 -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -v $DOCKER_ROOT_PATH/wallos_mo/db:/var/www/html/db \
        -v $DOCKER_ROOT_PATH/wallos_mo/logos:/var/www/html/images/uploads/logos \
        "ccr.ccs.tencentyun.com/moling7882/wallos:latest"
}

init_mealie_mo () {
    echo "初始化 mealie_mo "
    mkdir -p "$DOCKER_ROOT_PATH/mealie_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/mealie_mo.tgz -o "$CURRENT_DIR/mealie_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/mealie_mo.tgz" -C "$DOCKER_ROOT_PATH/mealie_mo/"
    docker run -d --name mealie_mo --restart always \
        --network bridge --privileged \
        -p 59925:9000 \
        -v $DOCKER_ROOT_PATH/mealie_mo:/app/data/ \
        -e ALLOW_SIGNUP=true \
        -e TZ=Asia/Shanghai \
        -e DB_ENGINE=sqlite \
        ccr.ccs.tencentyun.com/moling7882/mealie:latest
}

init_pyload_mo () {
    echo "初始化 pyload_mo "
    mkdir -p "$DOCKER_ROOT_PATH/pyload_mo/config"
    mkdir -p "$VIDEO_ROOT_PATH/pyload"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/pyload_mo.tgz -o "$CURRENT_DIR/pyload_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/pyload_mo.tgz" -C "$DOCKER_ROOT_PATH/pyload_mo/"
    docker run -d --name pyload_mo --restart always \
        --network bridge --privileged \
        -v $DOCKER_ROOT_PATH/pyload_mo/config:/config \
        -v $VIDEO_ROOT_PATH/pyload:/downloads \
        -p 58000:8000 \
        -p 59666:9666 \
        ccr.ccs.tencentyun.com/moling7882/pyload:latest
}

init_trilium_mo () {
    echo "初始化 trilium_mo "
    mkdir -p "$DOCKER_ROOT_PATH/trilium_mo/trilium-data"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/trilium_mo.tgz -o "$CURRENT_DIR/trilium_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/trilium_mo.tgz" -C "$DOCKER_ROOT_PATH/trilium_mo/"
    docker run -d --name trilium_mo --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 50051:8080 \
        -v $DOCKER_ROOT_PATH/trilium_mo/trilium-data:/root/trilium-data \
        -e TRILIUM_DATA_DIR=/root/trilium-data \
        ccr.ccs.tencentyun.com/moling7882/trilium-cn:latest
}

init_nzbget_mo () {
    echo "初始化 nzbget_mo "
    mkdir -p "$DOCKER_ROOT_PATH/nzbget_mo/config"
    mkdir -p "$VIDEO_ROOT_PATH/nzbget"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/nzbget_mo.tgz -o "$CURRENT_DIR/nzbget_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/nzbget_mo.tgz" -C "$DOCKER_ROOT_PATH/nzbget_mo/"
    docker run -d --name nzbget_mo --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -e NZBGET_USER=admin `#optional` \
        -e NZBGET_PASS=admin666 `#optional` \
        -p 46789:6789 \
        -v $DOCKER_ROOT_PATH/nzbget_mo/config:/config \
        -v $VIDEO_ROOT_PATH/nzbget:/downloads `#optional` \
        ccr.ccs.tencentyun.com/moling7882/nzbget:latest
}

init_scrutiny_mo () {
    echo "初始化 scrutiny_mo "
    mkdir -p "$DOCKER_ROOT_PATH/scrutiny_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/scrutiny_mo.tgz -o "$CURRENT_DIR/scrutiny_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/scrutiny_mo.tgz" -C "$DOCKER_ROOT_PATH/scrutiny_mo/"
    docker run -d --name scrutiny_mo --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 50052:8080 \
        -p 50053:8086 \
        -v $DOCKER_ROOT_PATH/scrutiny_mo:/opt/scrutiny/config \
        -v /run/udev:/run/udev:ro \
        ccr.ccs.tencentyun.com/moling7882/scrutiny:latest
}

init_kopia_mo () {
    echo "初始化 kopia_mo "
    mkdir -p "$DOCKER_ROOT_PATH/kopia_mo/"{config,cache,logs}
    mkdir -p "$VIDEO_ROOT_PATH/kopia/tmp"
    docker run -d --name kopia_mo --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 51515:51515 \
        -e KOPIA_PASSWORD="admin666" \
        -e USER="admin" \
        -v $DOCKER_ROOT_PATH/kopia_mo/config:/app/config \
        -v $DOCKER_ROOT_PATH/kopia_mo/cache:/app/cache \
        -v $DOCKER_ROOT_PATH/kopia_mo/logs:/app/logs \
        -v $DOCKER_ROOT_PATH:/data:ro \
        -v $VIDEO_ROOT_PATH/kopia:/repository \
        -v $VIDEO_ROOT_PATH/kopia/tmp:/tmp:shared \
        ccr.ccs.tencentyun.com/moling7882/kopia:latest \
        server start --disable-csrf-token-checks --insecure --address=0.0.0.0:51515 --server-username=admin --server-password=admin666
}

init_jdownloader_mo () {
    echo "初始化 jdownloader_mo"
    
    # 创建必要的目录
    mkdir -p "$DOCKER_ROOT_PATH/jdownloader_mo/config"
    mkdir -p "$VIDEO_ROOT_PATH/jdownloader"
    
    # 下载配置文件压缩包
    curl -L "https://moling7882.oss-cn-beijing.aliyuncs.com/999/jdownloader_mo.tgz" \
         -o "$CURRENT_DIR/jdownloader_mo.tgz"
    
    # 解压配置文件到指定目录
    tar --strip-components=1 \
        -zxvf "$CURRENT_DIR/jdownloader_mo.tgz" \
        -C "$DOCKER_ROOT_PATH/jdownloader_mo/"
    
    # 启动 JDownloader 容器
    docker run -d \
        --init \
        --name jdownloader_mo \
        --restart always \
        --network bridge \
        --privileged \
        -e PUID="$PUID" \
        -e PGID="$PGID" \
        -e UMASK="$UMASK" \
        -e TZ=Asia/Shanghai \
        -v "$VIDEO_ROOT_PATH/jdownloader:/opt/JDownloader/Downloads" \
        -v "$DOCKER_ROOT_PATH/jdownloader_mo/config:/opt/JDownloader/app/cfg" \
        -u $(id -u) \
        -p 53129:3129 \
        -e MYJD_USER=admin \
        -e MYJD_PASSWORD=admin666 \
        -e MYJD_DEVICE_NAME=godlike \
        ccr.ccs.tencentyun.com/moling7882/jdownloader:latest
}

init_kspeeder_mo () {
    echo "初始化 kspeeder_mo "
    mkdir -p "$DOCKER_ROOT_PATH/kspeeder_mo/kspeeder-data"
    mkdir -p "$DOCKER_ROOT_PATH/kspeeder_mo/kspeeder-config"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/kspeeder_mo.tgz -o "$CURRENT_DIR/kspeeder_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/kspeeder_mo.tgz" -C "$DOCKER_ROOT_PATH/kspeeder_mo/"
    docker run -d --name kspeeder_mo --restart always \
        --network bridge --privileged \
        -p 55443:5443 \
        -p 55003:5003 \
        -v $DOCKER_ROOT_PATH/kspeeder_mo/kspeeder-data:/kspeeder-data \
        -v $DOCKER_ROOT_PATH/kspeeder_mo/kspeeder-config:/kspeeder-config \
        ccr.ccs.tencentyun.com/moling7882/kspeeder:latest
}

init_xianyu_auto_reply_mo () {
    echo "初始化 xianyu_auto_reply_mo "
    mkdir -p "$DOCKER_ROOT_PATH/xianyu_auto_reply_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/xianyu_auto_reply_mo.tgz -o "$CURRENT_DIR/xianyu_auto_reply_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/xianyu_auto_reply_mo.tgz" -C "$DOCKER_ROOT_PATH/xianyu_auto_reply_mo/"
    docker run -d --name xianyu_auto_reply_mo --restart always \
        --network bridge --privileged \
        -p 50101:8080 \
        -v DOCKER_ROOT_PATH/xianyu_auto_reply_mo:/app/data \
        ccr.ccs.tencentyun.com/moling7882/xianyu-auto-reply:1.0
}

init_netalertx_mo () {
    echo "初始化 netalertx_mo "
    mkdir -p "$DOCKER_ROOT_PATH/netalertx_mo/config"
    mkdir -p "$DOCKER_ROOT_PATH/netalertx_mo/db"
    mkdir -p "$DOCKER_ROOT_PATH/netalertx_mo/app/log"
    mkdir -p "$DOCKER_ROOT_PATH/netalertx_mo/app/api"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/netalertx_mo.tgz -o "$CURRENT_DIR/netalertx_mo.tgz"
    tar --strip-components=1 -zxvf "$CURRENT_DIR/netalertx_mo.tgz" -C "$DOCKER_ROOT_PATH/netalertx_mo/"
    docker run -d --name netalertx_mo --restart always \
        --network host --privileged \
        -e PUID=1000 -e PGID=1000 -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -e "LANG=zh_CN.UTF-8" \
        -e PORT=50211 \
        -v "$DOCKER_ROOT_PATH/netalertx_mo/config:/app/config" \
        -v "$DOCKER_ROOT_PATH/netalertx_mo/db:/app/db" \
        -v "$DOCKER_ROOT_PATH/netalertx_mo/app/log:/app/log" \
        -v "$DOCKER_ROOT_PATH/netalertx_mo/app/api:/app/api" \
        ccr.ccs.tencentyun.com/moling7882/netalertx:latest
}

init_noname_game_mo () {
    echo "初始化 noname_game_mo "
    # 创建必要的目录（如果需要）
    mkdir -p "$DOCKER_ROOT_PATH/noname_game_mo/"
    # 下载并解压配置文件
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/noname_game_mo.tgz -o "$CURRENT_DIR/noname_game_mo.tgz"
    tar --strip-components=1 -zxvf "$CURRENT_DIR/noname_game_mo.tgz" -C "$DOCKER_ROOT_PATH/noname_game_mo/"
    # 启动容器（修正端口参数格式）
    docker run -d --name noname_game_mo --restart always \
        --network bridge \
        -p 50111:8080 \
        -p 50112:8089 \
        ccr.ccs.tencentyun.com/moling7882/noname-game:latest
}

init_n8n_mo () {
    echo "初始化 n8n_mo "
    mkdir -p "$DOCKER_ROOT_PATH/n8n_mo/"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/n8n_mo.tgz -o "$CURRENT_DIR/n8n_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/n8n_mo.tgz" -C "$DOCKER_ROOT_PATH/n8n_mo/"
    docker run -d --name n8n_mo --restart always \
        --network bridge \
        -p 55679:5678 \
        -v $DOCKER_ROOT_PATH/n8n_mo:/home/node/.n8n \
        ccr.ccs.tencentyun.com/moling7882/whats-up-docker:latest
}

init_whats_up_docker_mo () {
    echo "初始化 whats_up_docker_mo "
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/whats_up_docker_mo.tgz -o "$CURRENT_DIR/whats_up_docker_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/whats_up_docker_mo.tgz" -C "$DOCKER_ROOT_PATH/whats_up_docker_mo/"
    docker run -d --init --name whats_up_docker_mo --restart always \
        --network bridge \
        -p 23000:3000 \
        -e TZ=Asia/Shanghai \
        -v /var/run/docker.sock:/var/run/docker.sock:ro \
        ccr.ccs.tencentyun.com/moling7882/whats-up-docker:latest
}

init_pairdrop_mo () {
    echo "初始化 pairdrop_mo "
    docker run -d --name pairdrop_mo --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 53049:3000 \
        -e WS_FALLBACK=true \
        -e RATE_LIMIT=false \
        -e RTC_CONFIG=false \
        -e DEBUG_MODE=false \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}pairdrop:latest"
}

init_bytestash_mo () {
    echo "初始化 bytestash_mo "
    mkdir -p "$DOCKER_ROOT_PATH/bytestash_mo/data"
    docker run -d --name bytestash_mo --restart always\
        --network bridge --privileged \
        -v "$DOCKER_ROOT_PATH/bytestash_mo/data:/data/snippets" \
        -p 55908:5000 \
        -e BASE_PATH="" \
        -e JWT_SECRET=Aga2cNBCyPHe6ZdY5DMLMDV7GbTHQCZzi2owCfk5yZs2zRtCV6Lu8vLeGmQ7TjPZ \
        -e TOKEN_EXPIRY=24h \
        -e ALLOW_NEW_ACCOUNTS="true" \
        -e DEBUG="true" \
        -e DISABLE_ACCOUNTS="false" \
        -e DISABLE_INTERNAL_ACCOUNTS="false" \
        -e OIDC_ENABLED="false" \
        -e OIDC_DISPLAY_NAME="" \
        -e OIDC_ISSUER_URL="" \
        -e OIDC_CLIENT_ID="" \
        -e OIDC_CLIENT_SECRET="" \
        -e OIDC_SCOPES="" \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}bytestash:latest"
}

init_teleport_mo () {
    echo "初始化 teleport_mo "
    mkdir -p "$DOCKER_ROOT_PATH/teleport_mo/config"
    mkdir -p "$VIDEO_ROOT_PATH/teleport_mo/data"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/teleport_mo.tgz -o "$CURRENT_DIR/teleport_mo.tgz"
    tar --strip-components=1 -zxvf "$CURRENT_DIR/teleport_mo.tgz" -C "$DOCKER_ROOT_PATH/teleport_mo/"
    
    # 修正：使用半角空格和冒号
    docker run -d --name teleport_mo --restart always \
        --network bridge --privileged \
        --hostname localhost \  # 修正：使用半角空格
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 3023:3023 \  # 修正：使用半角冒号
        -p 3024:3024 \
        -p 3025:3025 \
        -p 50028:3080 \
        -v "$DOCKER_ROOT_PATH/teleport_mo/config/teleport.yaml:/etc/teleport/teleport.yaml" \  # 修正：使用半角冒号
        -v "$VIDEO_ROOT_PATH/teleport_mo/data:/var/lib/teleport" \
        $VOLUME_MOUNTS \
        "ccr.ccs.tencentyun.com/moling7882/teleport:14.3.19"
}

init_onestrm_mo () {
    echo "初始化 onestrm_mo "
    mkdir -p "$DOCKER_ROOT_PATH/onestrm_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/onestrm_mo.tgz -o "$CURRENT_DIR/onestrm_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/onestrm_mo.tgz" -C "$DOCKER_ROOT_PATH/onestrm_mo/"
    docker run -d --name onestrm_mo --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 58013:18003 \
        -p 58302:18302 \
        -v $DOCKER_ROOT_PATH/onestrm_mo:/app/config \
        -v $VIDEO_ROOT_PATH/media/strm:/movie_strm \
        ccr.ccs.tencentyun.com/moling7882/onestrm:latest
}

init_yt_dlp_web_mo () {
    echo "初始化 yt_dlp_web_mo "
    mkdir -p "$VIDEO_ROOT_PATH/yt_dlp_web/cache"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/yt_dlp_web_mo.tgz -o "$CURRENT_DIR/yt_dlp_web_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/yt_dlp_web_mo.tgz" -C "$DOCKER_ROOT_PATH/yt_dlp_web_mo/"
    docker run -d --init --name yt_dlp_web_mo --restart always \
        --network bridge --privileged \
        -e CREDENTIAL_USERNAME="admin" \
        -e CREDENTIAL_PASSWORD="admin666" \
        -v $VIDEO_ROOT_PATH/yt_dlp_web:/downloads \
        -v $VIDEO_ROOT_PATH/yt_dlp_web/cache:/cache \
        -p 53981:3000 \
        ccr.ccs.tencentyun.com/moling7882/yt-dlp-web:latest
}

init_vikunja_mo () {
    echo "初始化 vikunja_mo "
    mkdir -p "$DOCKER_ROOT_PATH/vikunja_mo/files"
    mkdir -p "$DOCKER_ROOT_PATH/vikunja_mo/data"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/vikunja_mo.tgz -o "$CURRENT_DIR/vikunja_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/vikunja_mo.tgz" -C "$DOCKER_ROOT_PATH/vikunja_mo/"
    docker run -d --name vikunja_mo --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 50107:3456 \
        -v $DOCKER_ROOT_PATH/vikunja_mo/files:/app/vikunja/files \
        -v $DOCKER_ROOT_PATH/vikunja_mo/data:/db \
        ccr.ccs.tencentyun.com/moling7882/vikunja:latest
}

init_dockpeek_mo () {
    echo "初始化 dockpeek_mo "
    docker run -d --name dockpeek_mo --restart always\
        --network bridge --privileged \
        -p 58644:8000 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -e SECRET_KEY=my_secret_key \
        -e USERNAME=666666 \
        -e PASSWORD=666666 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}dockpeek:latest"
}

init_flink_mo () {
    echo "初始化 flink_mo "
    docker run -d --name flink_mo --restart always \
        --network bridge \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 58287:8080 \
        "ccr.ccs.tencentyun.com/moling7882/flink:latest"
}

init_nav_mo () {
    echo "初始化 nav_mo "
    mkdir -p "$DOCKER_ROOT_PATH/nav_mo"
    docker run -d --name nav_mo --restart always \
        --network bridge \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 50024:7777 \
        -v "$DOCKER_ROOT_PATH/nav_mo:/nav" \
        "ccr.ccs.tencentyun.com/moling7882/nav:latest"
}

init_h5_mo () {
    echo "初始化 h5_mo "
    docker run -d --name h5_mo --restart always\
        --network bridge \
        -p 50025:3080 \
        "ccr.ccs.tencentyun.com/moling7882/80h5:latest"
}

init_ispyagentdvr_mo () {
    echo "初始化 ispyagentdvr_mo "
    mkdir -p "$DOCKER_ROOT_PATH/ispyagentdvr_mo/config"
    mkdir -p "$DOCKER_ROOT_PATH/ispyagentdvr_mo/commands"
    mkdir -p "$VIDEO_ROOT_PATH/ispyagentdvr_mo"
    docker run -d --name ispyagentdvr_mo --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 50023:8090 \
        -p 3478:3478/udp \
        -p 50000-50100:50000-50100/udp \
        -v $DOCKER_ROOT_PATH/ispyagentdvr_mo/config:/agent/Media/XML/ \
        -v $VIDEO_ROOT_PATH/ispyagentdvr_mo:/agent/Media/WebServerRoot/Media/ \
        -v $DOCKER_ROOT_PATH/ispyagentdvr_mo/commands:/agent/Commands/ \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}ispyagentdvr:latest"
}

init_docker_login() {
    echo "执行 Docker 仓库登录操作"
    read -s -p "请输入 Docker 仓库的密码: " PASSWORD
    echo
    
    # 登录阿里云 Docker 仓库
    echo "$PASSWORD" | docker login --username=aliyun4118146718 --password-stdin crpi-dt5pygtutdf9o78k.cn-shanghai.personal.cr.aliyuncs.com
    ALIYUN_SUCCESS=$?
    if [ $ALIYUN_SUCCESS -eq 0 ]; then
        echo "成功登录阿里云 Docker 仓库"
    else
        echo "登录阿里云 Docker 仓库失败"
    fi
    
    # 登录腾讯云 Docker 仓库
    echo "$PASSWORD" | docker login --username=100029677001 --password-stdin ccr.ccs.tencentyun.com
    TENCENT_SUCCESS=$?
    if [ $TENCENT_SUCCESS -eq 0 ]; then
        echo "成功登录腾讯云 Docker 仓库"
    else
        echo "登录腾讯云 Docker 仓库失败"
    fi
    
    unset PASSWORD  # 清除内存中的密码
    
    # 判断总体结果
    if [ $ALIYUN_SUCCESS -eq 0 ] && [ $TENCENT_SUCCESS -eq 0 ]; then
        return 0  # 全部成功
    else
        return 1  # 至少有一个失败
    fi
}

init_reader_mo() {
    echo "初始化 reader_mo"
    mkdir -p "$DOCKER_ROOT_PATH/reader_mo/logs"
    mkdir -p "$DOCKER_ROOT_PATH/reader_mo/storage"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/reader_mo.tgz -o "$CURRENT_DIR/reader_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/reader_mo.tgz" -C "$DOCKER_ROOT_PATH/reader_mo/"
    docker run -d --name reader_mo --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -e "SPRING_PROFILES_ACTIVE=prod" \
        -e "READER_APP_SECURE=true" \
        -e "READER_APP_SECUREKEY=1992111kL" \
        -e "READER_APP_INVITECODE=123456" \
        -v $DOCKER_ROOT_PATH/reader_mo/logs:/logs \
        -v $DOCKER_ROOT_PATH/reader_mo/storage:/storage \
        -p 57777:8080 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}reader:latest"
}

init_freshrss_mo() {
    echo "初始化 freshrss_mo"
    mkdir -p "$DOCKER_ROOT_PATH/freshrss_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/freshrss_mo.tgz -o "$CURRENT_DIR/freshrss_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/freshrss_mo.tgz" -C "$DOCKER_ROOT_PATH/freshrss_mo/"
    docker run -d --name freshrss_mo --restart always\
        --network bridge --privileged \
        -e PUID=1000 -e PGID=1000 -e TZ=Asia/Shanghai \
        -v $DOCKER_ROOT_PATH/freshrss_mo/config:/config \
        -p 58350:80 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}freshrss:latest"
}

init_easyimage_mo() {
    echo "初始化 easyimage_mo"
    mkdir -p "$DOCKER_ROOT_PATH/easyimage_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/easyimage_mo.tgz -o "$CURRENT_DIR/easyimage_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/easyimage_mo.tgz" -C "$DOCKER_ROOT_PATH/easyimage_mo/"
    sed -i "s/192.168.31.218/$HOST_IP/g" "$DOCKER_ROOT_PATH/easyimage_mo/config/config.php"
    docker run -d --name easyimage_mo --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 58631:80 \
        -e DEBUG=false \
        -v $DOCKER_ROOT_PATH/easyimage_mo/config:/app/web/config \
        -v $DOCKER_ROOT_PATH/easyimage_mo/i:/app/web/i \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}easyimage:latest"
}

init_homepage_mo() {
    echo "初始化 homepage_mo"
    local attempt=1
    local PUBLIC_IP_CITY="上海"
    local LONGITUDE="121.4737"
    local LATITUDE="31.2304"
    local fetch_success=0  # 标记是否获取成功

    echo "默认尝试获取公网 IP 所在城市、经度和纬度信息（最多尝试 $MAX_RETRIES 次）..."
    
    # 循环尝试获取公网信息，使用全局定义的 MAX_RETRIES
    while [ $attempt -le $MAX_RETRIES ]; do
        echo "第 $attempt 次尝试获取..."
        
        # 获取公网 IP 所在城市（结合全局 CURL_TIMEOUT 控制超时）
        PUBLIC_IP_CITY_TEMP=$(fetch_info "http://ip-api.com/json" '"city":"\K[^"]*')
        # 获取经度
        LONGITUDE_TEMP=$(fetch_info "http://ip-api.com/json" '"lon":\K[-+]?[0-9]*\.?[0-9]+')
        # 获取纬度
        LATITUDE_TEMP=$(fetch_info "http://ip-api.com/json" '"lat":\K[-+]?[0-9]*\.?[0-9]+')

        # 验证获取结果是否有效
        if [ -n "$PUBLIC_IP_CITY_TEMP" ] && [ -n "$LONGITUDE_TEMP" ] && [ -n "$LATITUDE_TEMP" ]; then
            PUBLIC_IP_CITY="$PUBLIC_IP_CITY_TEMP"
            LONGITUDE="$LONGITUDE_TEMP"
            LATITUDE="$LATITUDE_TEMP"
            fetch_success=1
            echo "获取成功！"
            echo "公网 IP 所在城市: $PUBLIC_IP_CITY"
            echo "该城市的经度: $LONGITUDE"
            echo "该城市的纬度: $LATITUDE"
            break
        else
            echo "第 $attempt 次获取失败，$(if [ $attempt -lt $MAX_RETRIES ]; then echo "将重试"; else echo "已达最大尝试次数"; fi)"
            attempt=$((attempt + 1))
            if [ $attempt -le $MAX_RETRIES ]; then
                sleep 2  # 重试前等待2秒
            fi
        fi
    done

    # 若多次尝试均失败，使用默认值
    if [ $fetch_success -eq 0 ]; then
        echo "无法获取公网信息，使用默认值："
        echo "城市：上海，纬度：31.2304，经度：121.4737"
    fi

    # 后续初始化流程（保持不变）
    mkdir -p "$DOCKER_ROOT_PATH/homepage_mo"
    curl -L --max-time $CURL_TIMEOUT https://moling7882.oss-cn-beijing.aliyuncs.com/999/homepage_mo.tgz -o "$CURRENT_DIR/homepage_mo.tgz"
    tar --strip-components=1 -zxvf "$CURRENT_DIR/homepage_mo.tgz" -C "$DOCKER_ROOT_PATH/homepage_mo/"
    sed -i "s/192.168.66.27/$HOST_IP/g" "$DOCKER_ROOT_PATH/homepage_mo/config/services.yaml"
    sed -i "s/192.168.66.1/$GATEWAY/g" "$DOCKER_ROOT_PATH/homepage_mo/config/services.yaml"
    sed -i "s/192.168.66.27/$HOST_IP/g" "$DOCKER_ROOT_PATH/homepage_mo/config/settings.yaml"
    sed -i "s/192.168.66.27/$HOST_IP/g" "$DOCKER_ROOT_PATH/homepage_mo/config/widgets.yaml"
    sed -i "s/Shenyang/$PUBLIC_IP_CITY/g" "$DOCKER_ROOT_PATH/homepage_mo/config/widgets.yaml"
    sed -i "s/41.8357/$LATITUDE/g" "$DOCKER_ROOT_PATH/homepage_mo/config/widgets.yaml"
    sed -i "s/123.429/$LONGITUDE/g" "$DOCKER_ROOT_PATH/homepage_mo/config/widgets.yaml"
    docker run -d --name homepage_mo --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -e HOMEPAGE_ALLOWED_HOSTS="*" \
        -p 53010:3000 \
        -v $DOCKER_ROOT_PATH/homepage_mo/config:/app/config \
        -v /var/run/docker.sock:/var/run/docker.sock:ro \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}homepage:latest"
}

init_dockerCopilot_mo() {
    echo "初始化 dockerCopilot_mo"
    mkdir -p "$DOCKER_ROOT_PATH/dockerCopilot_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/dockerCopilot_mo.tgz -o "$CURRENT_DIR/dockerCopilot_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/dockerCopilot_mo.tgz" -C "$DOCKER_ROOT_PATH/dockerCopilot_mo/"
    docker run -d --name dockerCopilot_mo --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 52712:12712 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v $DOCKER_ROOT_PATH/dockerCopilot_mo/data:/data \
        -e secretKey=666666mmm \
        -e DOCKER_HOST=unix:///var/run/docker.sock \
        -e hubURL=$DOCKER_REGISTRY \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}dockercopilot:1.0"
}

init_memos_mo() {
    echo "初始化 memos_mo"
    mkdir -p "$DOCKER_ROOT_PATH/memos_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/memos_mo.tgz -o "$CURRENT_DIR/memos_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/memos_mo.tgz" -C "$DOCKER_ROOT_PATH/memos_mo/"
    docker run -d --name memos_mo --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 55230:5230 \
        -v $DOCKER_ROOT_PATH/memos_mo/:/var/opt/memos_mo \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}memos:latest"
}

init_myspeed_mo() {
    echo "初始化 myspeed_mo"
    mkdir -p "$DOCKER_ROOT_PATH/myspeed_mo/data"
    docker run -d --name myspeed_mo --restart always\
        --network bridge --privileged \
        -e TZ=Asia/Shanghai \
        -p 53007:5216 \
        -v $DOCKER_ROOT_PATH/myspeed_mo/data:/myspeed/data \
        ccr.ccs.tencentyun.com/moling7882/myspeed:latest
}

#!/bin/bash

# 153号服务：删除预设数组中指定的容器
init_remove_container_array() {
    echo "初始化 按预设数组删除容器服务（153）"
    
    # ==========================
    # 在此处定义需要删除的容器数组
    # ==========================
    containers_to_remove=(
        "csf_mo"
        "qb_mo"
        "embypt_mo"
        # 在此处添加更多需要删除的容器名称
        # "container_name_1"
        # "container_name_2"
    )
    # ==========================
    
    # 检查数组是否为空
    if [ ${#containers_to_remove[@]} -eq 0 ]; then
        echo "容器数组为空，未指定需要删除的容器"
        return 0
    fi
    
    # 显示将要删除的容器列表
    echo "预设需要删除的容器列表："
    for container in "${containers_to_remove[@]}"; do
        echo "- $container"
    done
    
    # 确认删除操作
    read -p "确定要删除这些容器吗？(y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "删除操作已取消"
        return 0
    fi
    
    # 遍历数组并删除容器
    for container in "${containers_to_remove[@]}"; do
        echo -n "处理 $container..."
        
        # 检查容器是否存在
        if docker inspect "$container" >/dev/null 2>&1; then
            # 停止容器
            if docker stop "$container" >/dev/null 2>&1; then
                echo -n " 已停止"
            fi
            
            # 删除容器
            if docker rm "$container" >/dev/null 2>&1; then
                echo -e " ${GREEN}已删除${NC}"
            else
                echo -e " ${RED}删除失败${NC}"
            fi
        else
            echo -e " ${YELLOW}不存在${NC}"
        fi
    done
    
    echo "预设数组容器删除操作完成"
}


#!/bin/bash

# 151号服务：删除所有名称包含_mo的容器
init_remove_mo_containers() {
    echo "初始化 删除所有含_mo的容器服务（151）"
    
    # 查找所有名称包含_mo的容器ID
    mo_containers=$(docker ps -aq --filter "name=_mo")
    
    if [ -z "$mo_containers" ]; then
        echo "未找到名称包含_mo的容器"
        return 0
    fi
    
    # 显示即将删除的容器列表
    echo "找到以下含_mo的容器："
    docker ps -a --filter "name=_mo" --format "{{.Names}}"
    
    # 确认删除操作
    read -p "确定要删除这些容器吗？(y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "删除操作已取消"
        return 0
    fi
    
    # 停止并删除容器
    echo "正在停止容器..."
    docker stop $mo_containers >/dev/null 2>&1
    
    echo "正在删除容器..."
    docker rm $mo_containers >/dev/null 2>&1
    
    echo "所有名称包含_mo的容器已删除"
}


init_owjdxb_mo() {
    echo "初始化 owjdxb_mo"
    mkdir -p "$DOCKER_ROOT_PATH/store"
    docker run -d --name owjdxb_mo --restart always\
        -v "$DOCKER_ROOT_PATH/store:/data/store" \
        --network host --privileged \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}owjdxb:latest"
}

init_iptv_hls_mo() {
    echo "初始化 iptv_hls_mo"
    mkdir -p "$DOCKER_ROOT_PATH/iptv_hls_mo/config"
    mkdir -p "$DOCKER_ROOT_PATH/iptv_hls_mo/hls"
    mkdir -p "$DOCKER_ROOT_PATH/iptv_hls_mo/logs"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/iptv_hls_mo.tgz -o "$CURRENT_DIR/iptv_hls_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/iptv_hls_mo.tgz" -C "$DOCKER_ROOT_PATH/iptv_hls_mo/"
    docker run -d \
        --name iptv_hls_mo \
        --restart unless-stopped \
        --network bridge --privileged \
        -v "$DOCKER_ROOT_PATH/iptv_hls_mo/config":/app/config \
        -v "$DOCKER_ROOT_PATH/iptv_hls_mo/hls":/app/hls \
        -v "$DOCKER_ROOT_PATH/iptv_hls_mo/logs":/app/logs \
        -p 50086:50086 \
        "ccr.ccs.tencentyun.com/moling7882/iptv-hls:latest"
}    

init_convertx_mo() {
    echo "初始化 convertx_mo"
    mkdir -p "$DOCKER_ROOT_PATH/convertx_mo/data"
    docker run -d \
        --name convertx_mo \
        --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 53410:3000 \
        -e HTTP_ALLOWED=true \
        -e ALLOW_UNAUTHENTICATED=false \
        -e AUTO_DELETE_EVERY_N_HOURS=48 \
        -e ACCOUNT_REGISTRATION=false \
        -v "$DOCKER_ROOT_PATH/convertx_mo/data":/app/data \
        "crpi-dt5pygtutdf9o78k.cn-shanghai.personal.cr.aliyuncs.com/moling7882/convertx:latest"
}    

init_myicon_mo() {
    echo "初始化 myicon_mo"
    mkdir -p "$DOCKER_ROOT_PATH/myicon_mo/configData"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/myicon_mo.tgz -o "$CURRENT_DIR/myicon_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/myicon_mo.tgz" -C "$DOCKER_ROOT_PATH/myicon_mo/"
    docker run -d \
        --name myicon_mo \
        --restart always \
        --network bridge --privileged \
        -v "$DOCKER_ROOT_PATH/myicon_mo/configData":/app/public/configData \
        -p 53333:3000 \
        "ccr.ccs.tencentyun.com/moling7882/myicon:latest"
}    

init_drawnix_mo () {
    echo "初始化 drawnix_mo "
    docker run -d --name drawnix_mo  --restart always \
        -p 58411:80 \
        -p 57200:7200 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}drawnix:latest"
}

init_libretv_mo() {
    echo "初始化 libretv_mo"
    docker run -d \
        --name libretv_mo \
        --restart always \
        --network bridge --privileged \
        -e PASSWORD=admin666 \
        -p 58899:8080 \
        "ccr.ccs.tencentyun.com/moling7882/libretv:latest"
}

   
init_cookiecloud_mo() {
    echo "初始化 cookiecloud_mo"
    mkdir -p "$DOCKER_ROOT_PATH/cookiecloud_mo"
    docker run -d --name cookiecloud_mo --restart always\
        --network bridge --privileged \
        -v "$DOCKER_ROOT_PATH/cookiecloud_mo:/data/api/data" \
        -p 58088:8088 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}cookiecloud:latest"
}

init_newsnow_mo() {
    echo "初始化 newsnow_mo"
    mkdir -p "$DOCKER_ROOT_PATH/newsnow_mo"
    docker run -d --name newsnow_mo --restart always \
        --network bridge --privileged \
        -e G_CLIENT_ID= \
        -e G_CLIENT_SECRET= \
        -e JWT_SECRET= \
        -e INIT_TABLE=true \
        -e ENABLE_CACHE=true \
        -p 56959:4444 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}newsnow:latest"
}

# 150号服务：设置目录权限
init_set_permissions_mo() {
    echo "初始化 目录权限设置服务"
    
    # 为两个根路径设置777权限（递归应用）
    echo "正在为 $DOCKER_ROOT_PATH 设置777权限..."
    chmod -R 777 "$DOCKER_ROOT_PATH"
    
    echo "正在为 $VIDEO_ROOT_PATH 设置777权限..."
    chmod -R 777 "$VIDEO_ROOT_PATH"
    
    # 反馈结果
    echo "目录权限设置操作完成"
}
    
    
	
init_metube_mo() {
    echo "初始化 metube_mo"
    mkdir -p "$DOCKER_ROOT_PATH/metube_mo"
    mkdir -p "$VIDEO_ROOT_PATH/metube_mo"
    docker run -d --name metube_mo --restart always\
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        --network bridge --privileged \
        -p 58581:8081 \
        -v $VIDEO_ROOT_PATH/metube_mo:/downloads \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}metube:latest"
}

init_xunlei_mo() {
    echo "初始化 xunlei_mo"
    mkdir -p "$DOCKER_ROOT_PATH/xunlei_mo"
    mkdir -p "$VIDEO_ROOT_PATH/downloads"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/xunlei_mo.tgz -o "$CURRENT_DIR/xunlei_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/xunlei_mo.tgz" -C "$DOCKER_ROOT_PATH/xunlei_mo/"
    docker run -d --name xunlei_mo --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -v $VIDEO_ROOT_PATH/downloads:/xunlei/downloads \
        -v $DOCKER_ROOT_PATH/xunlei_mo:/xunlei/data \
        $VOLUME_MOUNTS \
        -p 50070:2345 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}xunlei:latest"
}

init_tachidesk_mo() {
    echo "初始化 tachidesk_mo"
    mkdir -p "$DOCKER_ROOT_PATH/tachidesk_mo/data"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/tachidesk_mo.tgz -o "$CURRENT_DIR/tachidesk_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/tachidesk_mo.tgz" -C "$DOCKER_ROOT_PATH/tachidesk_mo/"
    sed -i "s/192.168.66.27/$HOST_IP/g" "$DOCKER_ROOT_PATH/tachidesk_mo/data/server.conf"
    docker run -d --name tachidesk_mo --restart always\
        --network bridge  \
        -e TZ=Asia/Shanghai \
        -e FLARESOLVERR_URL=http://$HOST_IP:18191 \
        -p 14567:4567 \
        -v $DOCKER_ROOT_PATH/tachidesk_mo/data:/home/suwayomi/.local/share/Tachidesk \
        -v $VIDEO_ROOT_PATH/comic:/home/suwayomi/.local/share/Tachidesk/downloads \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}tachidesk:latest"
}

init_flaresolverr_mo() {
    echo "初始化 flaresolverr_mo"
    mkdir -p "$DOCKER_ROOT_PATH/flaresolverr_mo"
    docker run -d --name flaresolverr_mo --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -e LOG_LEVEL=info \
        -p 18191:8191 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}flaresolverr:latest"
}

init_easy_vdl_mo() {
    echo "初始化 easy_vdl_mo"
    mkdir -p "$DOCKER_ROOT_PATH/easy_vdl_mo/database"
    mkdir -p "$DOCKER_ROOT_PATH/easy_vdl_mo/logs"
    mkdir -p "$VIDEO_ROOT_PATH/easy_vdl_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/easy_vdl_mo.tgz -o "$CURRENT_DIR/easy_vdl_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/easy_vdl_mo.tgz" -C "$DOCKER_ROOT_PATH/easy_vdl_mo/"
    docker run -d --name easy_vdl_mo --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
		-e COMMUNITY_API_KEY="Qw8n2kLz5Xv1Tg9sJr4Yb6Vh3Pq7Zx2C" \
        -p 50004:80 \
        -v $DOCKER_ROOT_PATH/easy_vdl_mo/database:/app/database \
        -v $DOCKER_ROOT_PATH/easy_vdl_mo/logs:/app/logs \
        -v $VIDEO_ROOT_PATH/easy_vdl_mo:/app/downloads \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}easy-vdl:latest"
}

init_mediamaster_mo() {
    echo "初始化 mediamaster_mo"
    mkdir -p "$VIDEO_ROOT_PATH/downloads"
    mkdir -p "$VIDEO_ROOT_PATH/mediamaster"
    mkdir -p "$DOCKER_ROOT_PATH/mediamaster_mo/config"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/mediamaster_mo.tgz -o "$CURRENT_DIR/mediamaster_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/mediamaster_mo.tgz" -C "$DOCKER_ROOT_PATH/mediamaster_mo/"
    docker run -d --name mediamaster_mo --restart always\
        --network bridge --privileged \
        -p 50034:8888 \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -v $VIDEO_ROOT_PATH/downloads:/Downloads \
        -v $DOCKER_ROOT_PATH/mediamaster_mo/config:/config \
        -v $VIDEO_ROOT_PATH/mediamaster:/Media \
        "ccr.ccs.tencentyun.com/moling7882/mediamaster-v2:latest"
}

init_nullbr115_mo() {
    echo "初始化 nullbr115_mo"
    mkdir -p "$DOCKER_ROOT_PATH/nullbr115_mo/config"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/nullbr115_mo.tgz -o "$CURRENT_DIR/nullbr115_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/nullbr115_mo.tgz" -C "$DOCKER_ROOT_PATH/nullbr115_mo/"
    docker run -d --name nullbr115_mo --restart always \
        --network bridge --privileged \
        -e API_KEY=j4LFVqdf8gadvRn8WgVzrPZeMY798QlF \
        -p 58115:8115 \
        -v $DOCKER_ROOT_PATH/nullbr115_mo/config:/config \
        -v $VIDEO_ROOT_PATH:/media \
        ccr.ccs.tencentyun.com/moling7882/nullbr115:latest
}

init_moontv_mo() {
    echo "初始化 moontv_mo"
    mkdir -p "$DOCKER_ROOT_PATH/moontv_mo"
    docker run -d --name moontv_mo --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 50003:3000 \
        -e PASSWORD=666666 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}moontv:latest"
}

init_pt_accelerator_mo() {
    echo "初始化 pt_accelerator_mo"
    mkdir -p "$DOCKER_ROOT_PATH/pt_accelerator_mo/database"
    mkdir -p "$DOCKER_ROOT_PATH/pt_accelerator_mo/logs"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/pt_accelerator_mo.tgz -o "$CURRENT_DIR/pt_accelerator_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/pt_accelerator_mo.tgz" -C "$DOCKER_ROOT_PATH/pt_accelerator_mo/"
    docker run -d --name pt_accelerator_mo --restart always\
        --network host \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -v /etc/hosts:/etc/hosts \
        -v $DOCKER_ROOT_PATH/pt_accelerator_mo/config:/app/config \
        -v $DOCKER_ROOT_PATH/pt_accelerator_mo/logs:/app/logs \
        "ccr.ccs.tencentyun.com/moling7882/pt-accelerator:latest"
}

init_ubooquity_mo() {
    echo "初始化 ubooquity_mo"
    mkdir -p "$DOCKER_ROOT_PATH/ubooquity_mo/config"
    mkdir -p "$VIDEO_ROOT_PATH/files"
    mkdir -p "$VIDEO_ROOT_PATH/books"
    mkdir -p "$VIDEO_ROOT_PATH/comic"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/ubooquity_mo.tgz -o "$CURRENT_DIR/ubooquity_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/ubooquity_mo.tgz" -C "$DOCKER_ROOT_PATH/ubooquity_mo/"
    docker run -d --name ubooquity_mo --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 52202:2202 \
        -p 52203:2203 \
        -v $DOCKER_ROOT_PATH/ubooquity_mo/config:/config \
        -v $VIDEO_ROOT_PATH/books:/books \
        -v $VIDEO_ROOT_PATH/comic:/comics \
        -v $VIDEO_ROOT_PATH/files:/files \
        ccr.ccs.tencentyun.com/moling7882/ubooquity:latest
}

init_koodo_reader_mo() {
    echo "初始化 koodo_reader_mo"
    mkdir -p "$DOCKER_ROOT_PATH/koodo_reader_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/koodo_reader_mo.tgz -o "$CURRENT_DIR/koodo_reader_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/koodo_reader_mo.tgz" -C "$DOCKER_ROOT_PATH/koodo_reader_mo/"
    docker run -d --name koodo_reader_mo --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 50001:80 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}koodo-reader:master"
}

init_mediago_mo() {
    echo "初始化 mediago_mo"
    mkdir -p "$VIDEO_ROOT_PATH/mediago_mo"
    docker run -d --name mediago_mo --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 50006:8899 \
        -v $VIDEO_ROOT_PATH/mediago_mo:/root/mediago \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}mediago:latest"
}

init_cinemore_mo() {
    echo "初始化 cinemore_mo"
    mkdir -p "$DOCKER_ROOT_PATH/cinemore_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/cinemore_mo.tgz -o "$CURRENT_DIR/cinemore_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/cinemore_mo.tgz" -C "$DOCKER_ROOT_PATH/cinemore_mo/"
    docker run -d --name cinemore_mo --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 50002:8000 \
        -v $DOCKER_ROOT_PATH/cinemore_mo:/app/data \
        -v $VIDEO_ROOT_PATH:/media \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}cinemore-server:latest"
}

init_navipage_mo() {
    echo "初始化 navipage_mo"
    mkdir -p "$DOCKER_ROOT_PATH/navipage_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/navipage_mo.tgz -o "$CURRENT_DIR/navipage_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/navipage_mo.tgz" -C "$DOCKER_ROOT_PATH/navipage_mo/"
    docker run -d --name navipage_mo --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 50007:80 \
        -v "$DOCKER_ROOT_PATH/navipage_mo/html:/usr/share/nginx/html" \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}navipage:latest"
}

init_GSManager_mo() {
    echo "初始化 gsmanager_mo"
    mkdir -p "$DOCKER_ROOT_PATH/GSManager_mo/GSManager_mogame_data"
    mkdir -p "$DOCKER_ROOT_PATH/GSManager_mo/GSManager_mogame_file"
    mkdir -p "$DOCKER_ROOT_PATH/GSManager_mo/GSManager_mogame_file"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/GSManager_mo.tgz -o "$CURRENT_DIR/GSManager_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/GSManager_mo.tgz" -C "$DOCKER_ROOT_PATH/GSManager_mo/"
    docker run -d --name GSManager_mo --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -e USE_GUNICORN=true \
        -e GUNICORN_WORKERS=1 \
        -e GUNICORN_TIMEOUT=120 \
        -e GUNICORN_PORT=5000 \
        -p 50008:5000/tcp \
        -v "$DOCKER_ROOT_PATH/GSManager_mo/game_data:/home/steam/games" \
        -v "$DOCKER_ROOT_PATH/GSManager_mo/game_file:/home/steam/.config" \
        -v "$DOCKER_ROOT_PATH/GSManager_mo/game_file:/home/steam/.local" \
        --user root \
        --stdin-open \
        --tty \
        --restart always \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}gameservermanager:latest"
        /home/steam/start_web.sh
}

init_filecodebox_mo() {
    echo "初始化 filecodebox_mo "
    mkdir -p "$DOCKER_ROOT_PATH/filecodebox_mo"
    docker run -d --name filecodebox_mo --restart always\
        --network bridge --privileged \
        -p 52346:12345 \
        -v $DOCKER_ROOT_PATH/filecodebox_mo/:/app/data \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}filecodebox:beta"
}

init_fivefilters_mo () {
    echo "初始化 fivefilters_mo "
    mkdir -p "$DOCKER_ROOT_PATH/fivefilters_mo/data"
    docker run -d --name fivefilters_mo  --restart always\
        --network bridge --privileged \
        -p 58412:80 \
        -v $DOCKER_ROOT_PATH/fivefilters_mo/data:/var/www/html/cache/rss \
        -e FTR_ADMIN_PASSWORD=123456 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}fivefilters-full-text-rss:latest"   

}

init_whiper_mo () {
    echo "初始化 whiper_mo "
    mkdir -p "$DOCKER_ROOT_PATH/whiper_mo"
    docker run -d --name whiper_mo  --restart always \
        --network bridge --privileged \
        -p 39000:9000 \
        -v $DOCKER_ROOT_PATH/whiper_mo/:/root/.cache/whisper \
        -e ASR_MODEL=base \
        "ccr.ccs.tencentyun.com/moling7882/openai-whisper-asr-webservice:latest"
}     

init_d2c_mo () {
    echo "初始化 d2c_mo "
    mkdir -p "$DOCKER_ROOT_PATH/d2c_mo"
    docker run -d --name d2c_mo \
        -v /var/run/docker.sock:/var/run/docker.sock:ro \
        -v $DOCKER_ROOT_PATH/d2c_mo:/app/compose \
        "ccr.ccs.tencentyun.com/moling7882/d2c:latest"
}       

init_myip_mo() {
    echo "初始化 myip_mo "
    mkdir -p "$DOCKER_ROOT_PATH/myip_mo"
    docker run -d --name myip_mo --restart always\
        --network bridge --privileged \
        -p 58966:18966 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}myip:latest"
}

init_rsshub () {
    echo "初始化 rsshub "
    docker run -d --name myspeed_mo-rsshub  --restart always \
        --network bridge --privileged \
        -p 1200:1200 \
        -e NODE_ENV=production \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}rsshub:latest"
}    


init_notepad_mo () {
    echo "初始化 notepad_mo "
    mkdir -p "$DOCKER_ROOT_PATH/notepad_mo/public"
    mkdir -p "$DOCKER_ROOT_PATH/notepad_mo/storage"
    docker run -d --name notepad_mo  --restart always \
        --network bridge --privileged \
        -e NODE_ENV=production \
        -v "$DOCKER_ROOT_PATH/notepad_mo/public":/app/backend/public \
        -v "$DOCKER_ROOT_PATH/notepad_mo/storage":/app/backend/storage \
        -p 58760:3000 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}notepad:latest"
}    

init_iptv_api_mo () {
    echo "初始化 iptv_api_mo "
    mkdir -p "$DOCKER_ROOT_PATH/iptv_api_mo/config"
    mkdir -p "$DOCKER_ROOT_PATH/iptv_api_mo/output"
    docker run -d --name iptv_api_mo  --restart unless-stopped\
        --network bridge --privileged \
        -p 58755:8000 \
        -v $DOCKER_ROOT_PATH/iptv_api_mo/config:/iptv-api/config \
        -v $DOCKER_ROOT_PATH/iptv_api_mo/output:/iptv-api/output \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}iptv-api:latest"
}

init_photopea_mo () {
    echo "初始化 photopea_mo "
    docker run -d --name photopea_mo  --restart unless-stopped\
        --network bridge \
        -p 58887:8887 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}photopea:latest"
}

init_rsshub_mo () {
    echo "初始化 rsshub_mo "
    docker run -d --name rsshub_mo  --restart always\
        --network bridge --privileged \
        -p 51200:1200 \
        -e CACHE_EXPIRE=3600 \
        -e GITHUB_ACCESS_TOKEN=example \
        -e NODE_ENV=production \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}rsshub:latest"
}

init_easynode_mo() {
    echo "初始化 easynode_mo"
    mkdir -p "$DOCKER_ROOT_PATH/easynode_mo/db"
    docker run -d --name easynode_mo --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 58082:8082 \
        -v $DOCKER_ROOT_PATH/easynode_mo/db:/easynode/app/db\
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}easynode:latest"
}

init_portainer_mo() {
    echo "初始化 portainer_mo"
    mkdir -p "$DOCKER_ROOT_PATH/portainer_mo"
    docker run -d --name portainer_mo --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 59000:9000 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v $DOCKER_ROOT_PATH/portainer_mo:/data\
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}portainer-ce:latest"
}

init_cd2_mo() {    
	echo "初始化 cd2_mo"
    mkdir -p "$DOCKER_ROOT_PATH/cd2_mo"  
    docker run -d \
        --name cd2_mo \
        --restart always\
        --env CLOUDDRIVE_HOME=/Config \
        -v $DOCKER_ROOT_PATH/cd2_mo:/Config \
        -v $VIDEO_ROOT_PATH:/media:shared \
        --network host \
        --pid host \
        --privileged \
        --device /dev/fuse:/dev/fuse \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}clouddrive2:latest"
}

init_lucky_mo() {
    echo "初始化 lucky_mo"
    mkdir -p "$DOCKER_ROOT_PATH/lucky_mo"  
    docker run -d \
        --name lucky_mo \
        --restart=always \
        --net=host \
        -v $DOCKER_ROOT_PATH/lucky_mo:/goodluck \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}lucky:latest"
}

init_openlist_mo() {
    echo "初始化 openlist_mo"
    mkdir -p "$DOCKER_ROOT_PATH/openlist_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/openlist_mo.tgz -o "$CURRENT_DIR/openlist_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/openlist_mo.tgz" -C "$DOCKER_ROOT_PATH/openlist_mo/"    
    docker run -d \
        --restart=always\
        --network bridge --privileged \
        -v $DOCKER_ROOT_PATH/openlist_mo:/opt/openlist/data \
        $VOLUME_MOUNTS \
        -p 55244:5244 \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        --name="openlist_mo" \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}openlist:latest"
}

init_glances_mo() {
    docker run -d \
        --network bridge \
        --restart=always \
        --name "glances_mo" \
        --pid host \
		-e GLANCES_OPT="-w" \
        -p 61208-61209:61208-61209 \
        -v /var/run/docker.sock:/var/run/docker.sock:ro \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}glances:latest-full"
}


init_docker_autocompose_mo() {
    echo "初始化 docker_autocompose_mo"
    # 创建目录并赋予 755 权限
    mkdir -p -m 755 "$DOCKER_ROOT_PATH/docker_autocompose_mo"
    # 创建空的 compose.yml 文件
    touch "$DOCKER_ROOT_PATH/docker_autocompose_mo/compose.yml"
    # 给 compose.yml 文件赋予 644 权限
    chmod 644 "$DOCKER_ROOT_PATH/docker_autocompose_mo/compose.yml"
    # 运行 docker-autocompose 并将输出写入 compose.yml 文件
    docker run --rm \
        -v /var/run/docker.sock:/var/run/docker.sock \
        ${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}docker-autocompose:latest \
        $(docker ps -aq) > "$DOCKER_ROOT_PATH/docker_autocompose_mo/compose.yml"
    echo "compose.yml 文件生成完成"
}

init_bililive_go_mo() {
    echo "初始化 bililive_go_mo"
    mkdir -p "$DOCKER_ROOT_PATH/bililive_go_mo"
    mkdir -p "$VIDEO_ROOT_PATH/bililive_go"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/bililive_go_mo.tgz -o "$CURRENT_DIR/bililive_go_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/bililive_go_mo.tgz" -C "$DOCKER_ROOT_PATH/bililive_go_mo/"  
    docker run -d \
        --name bililive_go_mo \
        --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -v $DOCKER_ROOT_PATH/bililive_go_mo/config.yml:/etc/bililive-go/config.yml \
        -v $VIDEO_ROOT_PATH/bililive_go:/srv/bililive \
        -p 51235:8080 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}bililive-go:latest"
}


init_allinone_mo() {
    docker run -d \
        --name allinone_mo \
        --privileged \
        --restart=always\
        -p 55101:35455 \
        --network bridge --privileged \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}allinone:latest" \
        -tv=true \
        -aesKey=swj6pnb4h6xyvhpq69fgae2bbpjlb8y2 \
        -userid=5892131247 \
        -token=9209187973c38fb7ee461017e1147ebe43ef7d73779840ba57447aaa439bac301b02ad7189d2f1b58d3de8064ba9d52f46ec2de6a834d1373071246ac0eed55bb3ff4ccd79d137		
}

init_allinone_format_mo() {
    docker run -d \
        --name allinone_format_mo \
        --restart=always \
        -p 55102:35456 \
        --network bridge --privileged \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}allinone_format:latest"		
}

init_watchtower_mo() {
    docker run -d \
        --name watchtower_mo \
        --restart always \
        -e TZ=Asia/Shanghai \
        -e WATCHTOWER_SCHEDULE="0 0 4 * * *" \
        -e WATCHTOWER_CLEANUP=true \
        -e WATCHTOWER_HTTP_API_TOKEN=moling1992 \
        -e WATCHTOWER_HTTP_API_METRICS=true \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -p 50009:8080 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}watchtower:latest"
} 

init_tailscale_mo() {
    # 定义默认的 Tailscale 认证密钥
    DEFAULT_TS_AUTHKEY="tskey-auth-kfJUMp7t8D11CNTRL-ABW7Lz3gPVVzt3gdQZ7oVVEqEe35oR4R1"

    # 提示用户输入 Tailscale 认证密钥，若用户未输入则使用默认值
    get_input "TS_AUTHKEY" "请输入 Tailscale 认证密钥" "$DEFAULT_TS_AUTHKEY"

    echo "初始化 tailscale_mo"
    mkdir -p "$DOCKER_ROOT_PATH/tailscale_mo/var/lib" "$DOCKER_ROOT_PATH/tailscale_mo/dev/net/tun"

    docker run -d \
        --name tailscale_mo \
        --network host \
        --restart always\
        -e TS_AUTHKEY="$TS_AUTHKEY" \
        -e TS_EXTRA_ARGS=--advertise-exit-node \
        -e TS_ROUTES="$NEW_ROUTE" \
        -e TS_HOSTNAME="$RANDOM_VARIABLE" \
        -e TS_STATE_DIR=./state/ \
        -v $DOCKER_ROOT_PATH/tailscale_mo/var/lib:/var/lib \
        -v $DOCKER_ROOT_PATH/tailscale_mo/dev/net/tun:/dev/net/tun \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}tailscale:latest"
}


init_cms_mo() {
    # 定义捐赠码数组
    donate_codes=(
        "CMS_GTIYZECP_E5D4CBB05F3B4755B78D4322FEAE5545"
        "CMS_H8CVTK86_04E199570C634D5CA282666A11EBCAD3"
        "CMS_H8HOCFQI_E6FB7A8D28284F758C45DB619EE0E27B"
        "CMS_IVC4T7TK_9DBED5EC15204740AB2342B4FCDD5FD3"
        "CMS_JF64W92P_686D048D92F04D3582E7A021B72775DC"
        "CMS_JICH8WSU_6380C1CE854E4B1FB35A0C64CDFE6AFE"
        "CMS_3D76TPUK_1A77541FDE6848FFB96C82ADA45217A1"
        "CMS_ANF7PQWK_39EEAACF548144E1A3951DF9A376451D"
        "CMS_PN2XBIIO_8F8F1068059E42EDB7E390DE37CCE27C"
        "CMS_OA1ET1L6_11990F6C1B664391852160D79C0ED6F4"
        "CMS_ANF7PQWK_39EEAACF548144E1A3951DF9A376451D"
        "CMS_MVKK5DPR_65CD8A7922A44828B962A020618E9B4B"
		"CMS_XMF4JH4E_BE2D20392F3B414BBE779E3ADDADA345"
    )

    # 生成随机索引
    random_index=$((RANDOM % ${#donate_codes[@]}))

    # 获取随机默认捐赠码
    default_donate_code=${donate_codes[$random_index]}

    # 让用户输入 DONATE_CODE
    DONATE_CODE="${DONATE_CODE:-$default_donate_code}"
    read -p "请输入 DONATE_CODE ($DONATE_CODE): " input_donate_code
    DONATE_CODE="${input_donate_code:-$DONATE_CODE}"

    echo "初始化 cms_mo"
    mkdir -p "$DOCKER_ROOT_PATH/cms_mo/"{cache,config,logs}
    docker run -d --name cms_mo --restart always\
      --network bridge --privileged \
      -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
      -p 9527:9527 \
      -p 9096:9096 \
      -v $DOCKER_ROOT_PATH/cms_mo/config:/config \
      -v $DOCKER_ROOT_PATH/cms_mo/logs:/logs \
      -v $DOCKER_ROOT_PATH/cms_mo/cache:/var/cache/nginx/emby \
        $VOLUME_MOUNTS \
      -e RUN_ENV=online \
      -e ADMIN_USERNAME=666666 \
      -e ADMIN_PASSWORD=666666 \
      -e EMBY_HOST_PORT=http://$HOST_IP:38096 \
      -e EMBY_API_KEY=da40f811ae1040e6b653cc8a35f1af72 \
      -e IMAGE_CACHE_POLICY=3 \
      -e DONATE_CODE=$DONATE_CODE \
      "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}cloud-media-sync:latest"
}

init_chromium_mo() {
    echo "初始化 chromium_mo"
    mkdir -p "$DOCKER_ROOT_PATH/chromium_mo"
    docker run -d \
        --name chromium_mo \
        --shm-size=512m \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 56901:6901 \
        -e VNC_PW=666666 \
        --network bridge --privileged \
        $VOLUME_MOUNTS \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}chrome:latest"
}

init_music_tag_web_mo() {
    echo "初始化 music_tag_web_mo"
    mkdir -p "$DOCKER_ROOT_PATH/music_tag_web_mo"
    mkdir -p "$VIDEO_ROOT_PATH/music/download" "$VIDEO_ROOT_PATH/music/musicok"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/music_tag_web_mo.tgz -o "$CURRENT_DIR/music_tag_web_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/music_tag_web_mo.tgz" -C "$DOCKER_ROOT_PATH/music_tag_web_mo/"
    docker run -d \
        --name music_tag_web_mo \
        --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 58002:8002 \
        -v "$DOCKER_ROOT_PATH/music_tag_web_mo:/app/data" \
        -v "$VIDEO_ROOT_PATH/music:/app/media" \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}music_tag_web:latest"
}

init_bangumikomga_mo() {
    echo "初始化 bangumikomga_mo"
    mkdir -p "$DOCKER_ROOT_PATH/bangumikomga_mo" 
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/bangumikomga_mo.tgz -o "$CURRENT_DIR/bangumikomga_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/bangumikomga_mo.tgz" -C "$DOCKER_ROOT_PATH/bangumikomga_mo/"
    sed -i "s/192.168.66.109/$HOST_IP/g" "$DOCKER_ROOT_PATH/bangumikomga_mo/config.py"
    docker run -d \
        --name bangumikomga_mo \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -v "$DOCKER_ROOT_PATH/bangumikomga_mo/config.py:/app/config/config.py" \
        -v "$DOCKER_ROOT_PATH/bangumikomga_mo/recordsRefreshed.db:/app/recordsRefreshed.db" \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}bangumikomga:main"
}

init_tissue_mo() {
    echo "初始化 tissue_mo"
    mkdir -p "$DOCKER_ROOT_PATH/tissue_mo/config"
    mkdir -p "$DOCKER_ROOT_PATH/tissue_mo/file"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/tissue_mo.tgz -o "$CURRENT_DIR/tissue_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/tissue_mo.tgz" -C "$DOCKER_ROOT_PATH/tissue_mo/"
    docker run -d \
        --name tissue_mo \
        --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
		-e http_proxy="$PROXY_HOST" \
        -v $DOCKER_ROOT_PATH/tissue_mo/config:/app/config \
        -v $DOCKER_ROOT_PATH/tissue_mo/file:/data/file \
        $VOLUME_MOUNTS \
        -p 59193:9193 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}tissue:latest"
}

init_sun_panel_mo() {
    echo "初始化 sun_panel_mo"
    mkdir -p "$DOCKER_ROOT_PATH/sun_panel_mo/conf"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/sun_panel_mo.tgz -o "$CURRENT_DIR/sun_panel_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/sun_panel_mo.tgz" -C "$DOCKER_ROOT_PATH/sun_panel_mo/"
    docker run -d \
        --name sun_panel_mo \
        --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -v $DOCKER_ROOT_PATH/sun_panel_mo/conf:/app/conf \
        $VOLUME_MOUNTS \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -p 53002:3002 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}sun-panel:latest"
}

init_sun_panel_helper_mo() {
    echo "初始化 sun_panel_helper_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/sun_panel_helper_mo.tgz -o "$CURRENT_DIR/sun_panel_helper_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/sun_panel_helper_mo.tgz" -C "$DOCKER_ROOT_PATH/sun_panel_helper_mo/"
    docker run -d \
        --name sun_panel_helper_mo \
        --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -e BACKEND_PORT=53001 \
        -v $DOCKER_ROOT_PATH/sun_panel_mo/conf/custom:/app/backend/custom \
        $VOLUME_MOUNTS \
        -p 53003:80 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}sun-panel-helper:latest"
}

init_mdc_mo() {
    echo "初始化 mdc_mo"
    mkdir -p "$DOCKER_ROOT_PATH/mdc_mo"
    mkdir -p "$VIDEO_ROOT_PATH/xjj" "$VIDEO_ROOT_PATH/xjjgx"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/mdc_mo.tgz -o "$CURRENT_DIR/mdc_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/mdc_mo.tgz" -C "$DOCKER_ROOT_PATH/mdc_mo/"
    sed -i "s/192.168.66.31/$HOST_IP/g" "$DOCKER_ROOT_PATH/mdc_mo/config.json"
    docker run -d \
        --name mdc_mo \
        --restart always\
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 59208:9208 \
        -v "$DOCKER_ROOT_PATH/mdc_mo:/config" \
        $VOLUME_MOUNTS \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}mdc:latest"
}

init_wewe_rss_sqlite_mo() {
    echo "初始化 wewe_rss_sqlite_mo"
    mkdir -p "$DOCKER_ROOT_PATH/wewe_rss_sqlite_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/wewe_rss_sqlite_mo.tgz -o "$CURRENT_DIR/wewe_rss_sqlite_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/wewe_rss_sqlite_mo.tgz" -C "$DOCKER_ROOT_PATH/wewe_rss_sqlite_mo/"
    docker run -d \
        --name wewe_rss_sqlite_mo \
        --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 54000:4000 \
        -v "$DOCKER_ROOT_PATH/wewe_rss_sqlite_mo:/app/data" \
        -e AUTH_CODE=666666 \
        -e DATABASE_TYPE=sqlite \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}wewe-rss-sqlite:latest"
}

init_melody_mo() {
    echo "初始化 melody_mo"
    mkdir -p "$DOCKER_ROOT_PATH/melody_mo/profile"
    mkdir -p "$DOCKER_ROOT_PATH/melody_mo/data"
    mkdir -p "$VIDEO_ROOT_PATH/music/download"
    docker run -d \
        --name melody_mo \
        --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 55566:5566 \
        -v $DOCKER_ROOT_PATH/melody_mo/profile:/app/backend/.profile \
        -v $DOCKER_ROOT_PATH/melody_mo/data:/app/melody-data \
        -v "$VIDEO_ROOT_PATH/music:/music" \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}melody:latest"
}

init_frps_mo() {
    echo "初始化 frps_mo"
    mkdir -p "$DOCKER_ROOT_PATH/frps_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/frps.tgz -o "$CURRENT_DIR/frps.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/frps.tgz" -C "$DOCKER_ROOT_PATH/frps_mo/"
    docker run -d \
        --name frps_mo \
        --restart always \
        --network host \
        -v "$DOCKER_ROOT_PATH/frps_mo/frps.toml:/etc/frp/frps.toml" \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}frps:latest"
}

init_metatube_mo() {
    echo "初始化 metatube_mo"
    mkdir -p "$DOCKER_ROOT_PATH/metatube_mo/config"
    docker run -d \
        --name metatube_mo \
        --restart always \
        --network bridge \
        -p 59999:8080 \
        -v "$DOCKER_ROOT_PATH/metatube_mo/config:/config" \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}metatube-server" -dsn /config/metatube.db
}

init_wxchat_mo() {
    echo "初始化 wxchat_mo"
    mkdir -p "$DOCKER_ROOT_PATH/wxchat_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/wxchat_mo.tgz -o "$CURRENT_DIR/wxchat_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/wxchat_mo.tgz" -C "$DOCKER_ROOT_PATH/wxchat_mo/"
    docker run -d \
        --name wxchat_mo \
        --restart always \
        --network bridge \
        -p 29280:80 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}wxchat:latest"
}

init_onenav_mo() {
    echo "初始化 onenav_mo"
    mkdir -p "$DOCKER_ROOT_PATH/onenav_mo"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/onenav_mo.tgz -o "$CURRENT_DIR/onenav_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/onenav_mo.tgz" -C "$DOCKER_ROOT_PATH/onenav_mo/"
    docker run -d \
        --name onenav_mo \
        --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -v $DOCKER_ROOT_PATH/onenav_mo:/data/wwwroot/default/data \
        -p 52908:80 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}onenav:latest"
}

init_linkding_mo() {
    echo "初始化 linkding_mo"
    mkdir -p "$DOCKER_ROOT_PATH/linkding_mo/data"
    curl -L https://moling7882.oss-cn-beijing.aliyuncs.com/999/linkding_mo.tgz -o "$CURRENT_DIR/linkding_mo.tgz"
    tar  --strip-components=1 -zxvf "$CURRENT_DIR/linkding_mo.tgz" -C "$DOCKER_ROOT_PATH/linkding_mo/"
    docker run -d \
        --name linkding_mo \
        --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -v $DOCKER_ROOT_PATH/linkding_mo/data:/etc/linkding/data \
        -p 59395:9090 \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}linkding:latest"
}

init_upsnap_mo() {
    echo "初始化 upsnap_mo"
    mkdir -p "$DOCKER_ROOT_PATH/upsnap_mo"
    docker run -d \
        --name upsnap_mo \
        --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -v $DOCKER_ROOT_PATH/upsnap_mo:/app/pb_data \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}upsnap:latest"
}

init_lyricapi_mo() {
    echo "初始化 lyricapi_mo"
    mkdir -p "$VIDEO_ROOT_PATH/music/download" "$VIDEO_ROOT_PATH/music/musicok"
    docker run -d \
        --name lyricapi_mo \
        --restart always \
        --network bridge --privileged \
        -e PUID="$PUID" -e PGID="$PGID" -e UMASK="$UMASK" -e TZ=Asia/Shanghai \
        -p 58883:28883 \
        -v "$VIDEO_ROOT_PATH/music/musicok:/music" \
        "${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}lyricapi:latest"
}

init_database115() {
    echo "UPDATE systemconfig SET value = REPLACE(value, '192.168.66.31', '$HOST_IP') WHERE value LIKE '%192.168.66.31%';" >> "$DOCKER_ROOT_PATH/moviepilot_115_mo/config/script.sql"
    echo "初始化数据库..."
    # SQL 文件路径
    SQL_FILE="$DOCKER_ROOT_PATH/moviepilot_115_mo/config/script.sql"
    # 确保 SQL 文件存在
    if [ ! -f "$SQL_FILE" ]; then
        echo "错误: SQL 文件 $SQL_FILE 不存在。请确认文件路径是否正确。"
        exit 1
    fi
    # 在容器中通过 Python 执行 SQL 文件
    docker exec -i  -w /config moviepilot_115_mo python -c "
import sqlite3

# 连接数据库
conn = sqlite3.connect('user.db')
# 创建游标
cur = conn.cursor()
# 读取 SQL 文件
with open('/config/script.sql', 'r') as file:
    sql_script = file.read()
# 执行 SQL 脚本
cur.executescript(sql_script)
# 提交事务
conn.commit()
# 关闭连接
conn.close()
    "
    echo "SQL 文件已在容器中执行并修改数据库。"
    echo "SQL 脚本已执行完毕"
    echo "数据库初始化完成！"

      # 重启容器
    docker restart moviepilot_115_mo

    echo "正在检查容器是否成功重启..."
    sleep 1  # 等待容器重新启动
    SECONDS=0
# 持续检查容器状态，直到容器运行或失败
    while true; do
        CONTAINER_STATUS=$(docker inspect --format '{{.State.Status}}' moviepilot_115_mo)

        if [ "$CONTAINER_STATUS" == "running" ]; then
            echo "容器 moviepilot_115_mo 重启成功！"
            break
        elif [ "$CONTAINER_STATUS" == "starting" ]; then
        # 追加输出，确保前面的信息不变
        echo -ne "正在初始化moviepilot_115_mo... $SECONDS 秒 \r"
            sleep 1 # 等待2秒后再次检查
        else
            echo "错误: 容器 moviepilot_115_mo 重启失败！状态：$CONTAINER_STATUS"
            exit 1
        fi
    done
}

view_moviepilot_logs() {
    echo "查看 moviepilot_v2_pt 容器日志..."
    docker logs -f moviepilot_v2_pt
}

# 定义服务和 Docker 镜像的对应数组
declare -A SERVICE_IMAGE_MAP=(
    ["csf_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}chinesesubfinder:latest"
    ["qb_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}qbittorrent:4.6.7"
    ["qb_shua"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}qbittorrent:4.6.7"
    ["embypt_mo"]="${DOCKER_REGISTRY}/${IMAGE_NAME}:latest"
    ["moviepilot_v2_pt"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}moviepilot-v2:latest"
    ["cookiecloud_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}cookiecloud:latest"
    ["frpc_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}frpc:latest"
    ["transmission_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}transmission:4.0.5"
    ["audiobookshelf_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}audiobookshelf:latest"
    ["komga_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}komga:latest"
    ["navidrome_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}navidrome:latest"
    ["vertex_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}vertex:latest"
    ["freshrss_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}freshrss:latest"
    ["easyimage_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}easyimage:latest"
    ["homepage_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}homepage:latest"
    ["dockerCopilot_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}dockercopilot:1.0"
    ["memos_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}memos:latest"
    ["owjdxb_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}owjdxb:latest"
    ["metube_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}metube:latest"
    ["filecodebox_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}filecodebox:beta"
    ["myip_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}myip:latest"
    ["photopea_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}photopea:1.0"
    ["rsshub_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}rsshub:latest"
    ["easynode_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}easynode:latest"
    ["portainer_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}portainer-ce:latest"
    ["lucky_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}lucky:latest"
    ["cd2_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}clouddrive2:latest"
    ["openlist_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}openlist:latest"
    ["glances_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}glances:latest"
    ["moviepilot_v2_go"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}moviepilot-v2:latest"
    ["allinone_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}allinone:latest"
    ["allinone_format_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}allinone_format:latest"
    ["watchtower_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}watchtower:latest"
    ["cms_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}cloud-media-sync:latest"
    ["chromium_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}chrome:latest"
    ["clash_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}clash-and-dashboard:latest"
    ["noname_game_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}clash-and-dashboard:latest"
    ["music_tag_web_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}music_tag_web:latest"
    ["mdc_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}mdc:latest"
    ["lyricapi_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}lyricapi:latest"	
    ["bangumikomga_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}bangumikomga:latest"		
    ["tailscale_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}tailscale:latest"
    ["reader_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}reader:latest"
    ["newsnow_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}newsnow:latest"
    ["calibre_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}calibre-web:latest"	
    ["emulatorjs_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}emulatorjs:latest"
    ["easy_itv_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}easy_itv:latest"
    ["cloudbak_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}cloudbak:latest"
    ["cloudsaver_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}cloudsaver:latest"
    ["uptime_kuma_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}uptime_kuma:latest"
    ["qd_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}qd:latest"
    ["stirling_pdf_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}stirling_pdf:latest"
    ["huntly_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}huntly_:latest"
    ["roon_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}docker-roonserver:latest"
    ["wewe_rss_sqlite_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}wewe-rss-sqlite:latest"
    ["v2raya_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}v2raya:latest"
    ["docker_autocompose_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}docker-autocompose:latest"
    ["upsnap_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}upsnap:latest"
    ["melody_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}melody:latest"
    ["onenav_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}onenav:latest"
    ["linkding_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}linkding:latest"
    ["bili_sync_rs_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}bili-sync-rs:latest"
    ["musicn_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}musicn:latest"
    ["tissue_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}tissue:latest"
    ["bililive_go_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}bililive-go:latest"
    ["sun_panel_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}sun-panel:latest"		
    ["sun_panel_helper_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}sun_panel_helper_mo"	
    ["frps_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}frps_mo"
    ["metatube_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}metatube_mo"
    ["wxchat_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}wxchat_mo"
    ["iptv_hls_mo"]="ccr.ccs.tencentyun.com/moling7882/iptv-hls:latest"
    ["convertx_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}convertx:latest"
    ["myicon_mo"]="ccr.ccs.tencentyun.com/moling7882/myicon:latest"
    ["drawnix_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}drawnix:latest"
    ["libretv_mo"]="ccr.ccs.tencentyun.com/moling7882/libretv:latest"
    ["fivefilters_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}fivefilters-full-text-rss:latest "
    ["whiper_mo"]="ccr.ccs.tencentyun.com/moling7882/openai-whisper-asr-webservice:latest"
    ["d2c_mo"]="ccr.ccs.tencentyun.com/moling7882/d2c:latest"		
    ["notepad_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}notepad:latest "	
    ["rsshub"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}rsshub:2024-12-14"
    ["myspeed_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}myspeed_mo:latest"
    ["playlistdl_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}playlistdl:v2"	
    ["iptv_api_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}iptv-api:latest"
    ["dsm_mo"]="ccr.ccs.tencentyun.com/moling7882/virtual-dsm:latest"
    ["wps_office_mo"]="ccr.ccs.tencentyun.com/moling7882/wps-office:chinese"
    ["squoosh_mo"]="ccr.ccs.tencentyun.com/moling7882/squoosh:latest"
    ["hivision_mo"]="ccr.ccs.tencentyun.com/moling7882/hivision_idphotos:latest"
    ["image_watermark_tool_mo"]="ccr.ccs.tencentyun.com/moling7882/image-watermark-tool:master"
    ["easyvoice_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}easyvoice:latest"		
    ["hatsh_mo"]="ccr.ccs.tencentyun.com/moling7882/hat.sh:latest "	
    ["autopiano_mo"]="ccr.ccs.tencentyun.com/moling7882/autopiano:latest"
    ["g_box_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}g-box:hostmode"
    ["byte_muse_mo"]="ccr.ccs.tencentyun.com/moling7882/byte-muse:latest"	
    ["md_mo"]="ccr.ccs.tencentyun.com/moling7882/md:latest"
    ["xiuxian_mo"]="ccr.ccs.tencentyun.com/moling7882/vue-xiuxiangame:latest"
    ["moviepilot_v2_115"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}moviepilot-v2:latest"
    ["tachidesk_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}tachidesk:latest"
    ["flaresolverr_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}flaresolverr:latest"
    ["easy_vdl_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}easy-vdl:latest"
    ["moontv_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}moontv:latest"		
    ["koodo_reader_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}koodo-reader:master "	
    ["mediago_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}mediago:latest"
    ["cinemore_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}cinemore-server:hostmode"
    ["navipage_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}navipage:latest"	
    ["GSManager_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}gameservermanager:latest"
    ["mdcx_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}mdcx-builtin-gui-base:latest"	
    ["neko_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}neko:microsoft-edge"	
    ["handbrake_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}handbrake:latest"
    ["pairdrop_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}pairdrop:latest"
    ["bytestash_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}bytestash:latest"
    ["teleport_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}teleport:latest"
    ["dockpeek_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}dockpeek:latest"		
    ["flink_mo"]="ccr.ccs.tencentyun.com/moling7882/flink:latest "	
    ["nav_mo"]="ccr.ccs.tencentyun.com/moling7882/nav:latest"
    ["h5_mo"]="ccr.ccs.tencentyun.com/moling7882/h5:latest"
    ["ispyagentdvr_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}ispyagentdvr:latest"	
    ["dockports_mo"]="ccr.ccs.tencentyun.com/moling7882/dockports:latest"
    ["urbackup_mo"]="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}urbackup:latest"	
    ["qrding_mo"]="ccr.ccs.tencentyun.com/moling7882/qrding:latest"	
    ["enclosed_mo_mo"]="ccr.ccs.tencentyun.com/moling7882/enclosed:latest"
    ["ghosthub_mo"]="ccr.ccs.tencentyun.com/moling7882/ghosthub:latest"		
    ["xunlei_mo"]="ccr.ccs.tencentyun.com/moling7882/xunlei:latest"		
    ["mediamaster_mo"]="ccr.ccs.tencentyun.com/moling7882/mediamaster-v2:latest"	
    ["nullbr115_mo"]="ccr.ccs.tencentyun.com/moling7882/nullbr115:latest"
    ["pt_accelerator_mo"]="ccr.ccs.tencentyun.com/moling7882/pt-accelerator:latest"		
    ["ubooquity_mo"]="ccr.ccs.tencentyun.com/moling7882/ubooquity:latest"			

)

# 定义列数
columns=3

# 新增函数：将范围字符串转换为数字列表
parse_range() {
    local range=$1
    local start=$(echo "$range" | cut -d'-' -f1)
    local end=$(echo "$range" | cut -d'-' -f2)
    
    # 验证输入是否有效
    if [[ ! "$start" =~ ^[0-9]+$ || ! "$end" =~ ^[0-9]+$ || "$start" -gt "$end" ]]; then
        echo "无效的范围: $range" >&2
        return 1
    fi
    
    # 生成数字列表
    local numbers=""
    for ((i = start; i <= end; i++)); do
        numbers+=" $i"
    done
    
    echo "$numbers"
}

# 新增函数：解析用户输入的选择，支持单个数字和范围
parse_selections() {
    local selections=$1
    local parsed_selections=""
    
    # 分割输入为多个部分
    for part in $selections; do
        # 检查是否为范围格式
        if [[ "$part" =~ ^[0-9]+\-[0-9]+$ ]]; then
            local range_numbers=$(parse_range "$part")
            parsed_selections+=" $range_numbers"
        # 检查是否为单个数字
        elif [[ "$part" =~ ^[0-9]+$ ]]; then
            parsed_selections+=" $part"
        else
            echo "无效的选择: $part" >&2
        fi
    done
    
    echo "$parsed_selections"
}

while true; do
    # 获取各服务的安装状态（严格对应install_service函数的1-149号顺序）
    csf_mo_status=$(get_service_status "csf_mo")
    qb_mo_status=$(get_service_status "qb_mo")
    embypt_mo_status=$(get_service_status "embypt_mo")
    moviepilot_v2_pt_status=$(get_service_status "moviepilot_v2_pt")
    cookiecloud_mo_status=$(get_service_status "cookiecloud_mo")
    frpc_mo_status=$(get_service_status "frpc_mo")
    transmission_mo_status=$(get_service_status "transmission_mo")
    audiobookshelf_mo_status=$(get_service_status "audiobookshelf_mo")
    komga_mo_status=$(get_service_status "komga_mo")
    navidrome_mo_status=$(get_service_status "navidrome_mo")
    homepage_mo_status=$(get_service_status "homepage_mo")
    dockerCopilot_mo_status=$(get_service_status "dockerCopilot_mo")
    memos_mo_status=$(get_service_status "memos_mo")
    vertex_mo_status=$(get_service_status "vertex_mo")
    freshrss_mo_status=$(get_service_status "freshrss_mo")
    rsshub_mo_status=$(get_service_status "rsshub_mo")
    metube_mo_status=$(get_service_status "metube_mo")
    filecodebox_mo_status=$(get_service_status "filecodebox_mo")
    myip_mo_status=$(get_service_status "myip_mo")
    photopea_mo_status=$(get_service_status "photopea_mo")
    easyimage_mo_status=$(get_service_status "easyimage_mo")
    myicon_mo_status=$(get_service_status "myicon_mo")
    easynode_mo_status=$(get_service_status "easynode_mo")
    qb_shua_status=$(get_service_status "qb_shua")
    lucky_mo_status=$(get_service_status "lucky_mo")
    pt_accelerator_mo_status=$(get_service_status "pt_accelerator_mo")
    openlist_mo_status=$(get_service_status "openlist_mo")
    vikunja_mo_status=$(get_service_status "vikunja_mo")
    allinone_mo_status=$(get_service_status "allinone_mo")
    allinone_format_mo_status=$(get_service_status "allinone_format_mo")
    watchtower_mo_status=$(get_service_status "watchtower_mo")
    reader_mo_status=$(get_service_status "reader_mo")
    newsnow_mo_status=$(get_service_status "newsnow_mo")
    calibre_mo_status=$(get_service_status "calibre_mo")
    uptime_kuma_mo_status=$(get_service_status "uptime_kuma_mo")
    convertx_mo_status=$(get_service_status "convertx_mo")
    stirling_pdf_mo_status=$(get_service_status "stirling_pdf_mo")
    wewe_rss_sqlite_mo_status=$(get_service_status "wewe_rss_sqlite_mo")
    melody_mo_status=$(get_service_status "melody_mo")
    bililive_go_mo_status=$(get_service_status "bililive_go_mo")
    libretv_mo_status=$(get_service_status "libretv_mo")
    fivefilters_mo_status=$(get_service_status "fivefilters_mo")
    notepad_mo_status=$(get_service_status "notepad_mo")
    playlistdl_mo_status=$(get_service_status "playlistdl_mo")
    squoosh_mo_status=$(get_service_status "squoosh_mo")
    easyvoice_mo_status=$(get_service_status "easyvoice_mo")
    tachidesk_mo_status=$(get_service_status "tachidesk_mo")
    flaresolverr_mo_status=$(get_service_status "flaresolverr_mo")
    easy_vdl_mo_status=$(get_service_status "easy_vdl_mo")
    moontv_mo_status=$(get_service_status "moontv_mo")
    mediago_mo_status=$(get_service_status "mediago_mo")
    handbrake_mo_status=$(get_service_status "handbrake_mo")
    pairdrop_mo_status=$(get_service_status "pairdrop_mo")
    xunlei_mo_status=$(get_service_status "xunlei_mo")
    dockports_mo_status=$(get_service_status "dockports_mo")
    flink_mo_status=$(get_service_status "flink_mo")
    wallos_mo_status=$(get_service_status "wallos_mo")
    trilium_mo_status=$(get_service_status "trilium_mo")
    nzbget_mo_status=$(get_service_status "nzbget_mo")
    scrutiny_mo_status=$(get_service_status "scrutiny_mo")
    netalertx_mo_status=$(get_service_status "netalertx_mo")
    yt_dlp_web_mo_status=$(get_service_status "yt_dlp_web_mo")
    kspeeder_mo_status=$(get_service_status "kspeeder_mo")
    myspeed_mo_status=$(get_service_status "myspeed_mo")
    image_watermark_tool_mo_status=$(get_service_status "image_watermark_tool_mo")
    noname_game_mo_status=$(get_service_status "noname_game_mo")
    roon_mo_status=$(get_service_status "roon_mo")
    emulatorjs_mo_status=$(get_service_status "emulatorjs_mo")
    v2raya_mo_status=$(get_service_status "v2raya_mo")
    docker_autocompose_mo_status=$(get_service_status "docker_autocompose_mo")
    upsnap_mo_status=$(get_service_status "upsnap_mo")
    qd_mo_status=$(get_service_status "qd_mo")
    onenav_mo_status=$(get_service_status "onenav_mo")
    linkding_mo_status=$(get_service_status "linkding_mo")
    bili_sync_rs_mo_status=$(get_service_status "bili_sync_rs_mo")
    musicn_mo_status=$(get_service_status "musicn_mo")
    tissue_mo_status=$(get_service_status "tissue_mo")
    cloudbak_mo_status=$(get_service_status "cloudbak_mo")
    sun_panel_mo_status=$(get_service_status "sun_panel_mo")
    sun_panel_helper_mo_status=$(get_service_status "sun_panel_helper_mo")
    frps_mo_status=$(get_service_status "frps_mo")
    metatube_mo_status=$(get_service_status "metatube_mo")
    wxchat_mo_status=$(get_service_status "wxchat_mo")
    iptv_hls_mo_status=$(get_service_status "iptv_hls_mo")
    easy_itv_mo_status=$(get_service_status "easy_itv_mo")
    glances_mo_status=$(get_service_status "glances_mo")
    drawnix_mo_status=$(get_service_status "drawnix_mo")
    d2c_mo_status=$(get_service_status "d2c_mo")
    iptv_api_mo_status=$(get_service_status "iptv_api_mo")
    dsm_mo_status=$(get_service_status "dsm_mo")
    wps_office_mo_status=$(get_service_status "wps_office_mo")
    whiper_mo_status=$(get_service_status "whiper_mo")
    hivision_mo_status=$(get_service_status "hivision_mo")
    rsshub_status=$(get_service_status "rsshub")
    hatsh_mo_status=$(get_service_status "hatsh_mo")
    autopiano_mo_status=$(get_service_status "autopiano_mo")
    g_box_mo_status=$(get_service_status "g_box_mo")
    byte_muse_mo_status=$(get_service_status "byte_muse_mo")
    md_mo_status=$(get_service_status "md_mo")
    xiuxian_mo_status=$(get_service_status "xiuxian_mo")
    moviepilot_v2_115_status=$(get_service_status "moviepilot_v2_115")
    docker_login_status=$(get_service_status "docker_login")
    mdcx_mo_status=$(get_service_status "mdcx_mo")
    neko_mo_status=$(get_service_status "neko_mo")
    koodo_reader_mo_status=$(get_service_status "koodo_reader_mo")
    cinemore_mo_status=$(get_service_status "cinemore_mo")
    bytestash_mo_status=$(get_service_status "bytestash_mo")
    teleport_mo_status=$(get_service_status "teleport_mo")
    dockpeek_mo_status=$(get_service_status "dockpeek_mo")
    nav_mo_status=$(get_service_status "nav_mo")
    h5_mo_status=$(get_service_status "h5_mo")
    ispyagentdvr_mo_status=$(get_service_status "ispyagentdvr_mo")
    GSManager_mo_status=$(get_service_status "GSManager_mo")
    urbackup_mo_status=$(get_service_status "urbackup_mo")
    qrding_mo_status=$(get_service_status "qrding_mo")
    enclosed_mo_status=$(get_service_status "enclosed_mo")
    ghosthub_mo_status=$(get_service_status "ghosthub_mo")
    navipage_mo_status=$(get_service_status "navipage_mo")
    mediamaster_mo_status=$(get_service_status "mediamaster_mo")
    nullbr115_mo_status=$(get_service_status "nullbr115_mo")
    cd2_mo_status=$(get_service_status "cd2_mo")
    ubooquity_mo_status=$(get_service_status "ubooquity_mo")
    jdownloader_mo_status=$(get_service_status "jdownloader_mo")
    xianyu_auto_reply_mo_status=$(get_service_status "xianyu_auto_reply_mo")
    n8n_mo_status=$(get_service_status "n8n_mo")
    moviepilot_v2_go_status=$(get_service_status "moviepilot_v2_go")
    cms_mo_status=$(get_service_status "cms_mo")
    chromium_mo_status=$(get_service_status "chromium_mo")
    portainer_mo_status=$(get_service_status "portainer_mo")
    epub_to_audiobook_mo_status=$(get_service_status "epub_to_audiobook_mo")
    clash_mo_status=$(get_service_status "clash_mo")
    owjdxb_mo_status=$(get_service_status "owjdxb_mo")
    music_tag_web_mo_status=$(get_service_status "music_tag_web_mo")
    mdc_mo_status=$(get_service_status "mdc_mo")
    lyricapi_mo_status=$(get_service_status "lyricapi_mo")
    bangumikomga_mo_status=$(get_service_status "bangumikomga_mo")
    tailscale_mo_status=$(get_service_status "tailscale_mo")
    onestrm_mo_status=$(get_service_status "onestrm_mo")
    set_permissions_mo_status=$(get_service_status "set_permissions_mo")
    remove_mo_containers_status=$(get_service_status "remove_mo_containers")
    remove_container_array_status=$(get_service_status "remove_container_array")
    reserved4_mo_status=$(get_service_status "reserved4_mo")
    reserved5_mo_status=$(get_service_status "reserved5_mo")
    kopia_mo_status=$(get_service_status "kopia_mo")
    pyload_mo_status=$(get_service_status "pyload_mo")
    cloudsaver_mo_status=$(get_service_status "cloudsaver_mo")
    mealie_mo_status=$(get_service_status "mealie_mo")
    huntly_mo_status=$(get_service_status "huntly_mo")
    whats_up_docker_mo_status=$(get_service_status "whats_up_docker_mo")

    echo "请选择要安装的服务（输入数字，支持范围如1-4,6-7）："

    # 服务列表（与install_service函数1-149号顺序完全一致）
    service_list=(
        "1. csf $csf_mo_status"
        "2. qb $qb_mo_status"
        "3. embypt $embypt_mo_status"
        "4. moviepilot_v2_pt $moviepilot_v2_pt_status"
        "5. cookiecloud $cookiecloud_mo_status"
        "6. frpc $frpc_mo_status"
        "7. transmission $transmission_mo_status"
        "8. audiobookshelf $audiobookshelf_mo_status"
        "9. komga $komga_mo_status"
        "10. navidrome $navidrome_mo_status"
        "11. homepage $homepage_mo_status"
        "12. dockerCopilot $dockerCopilot_mo_status"
        "13. memos $memos_mo_status"
        "14. vertex $vertex_mo_status"
        "15. freshrss $freshrss_mo_status"
        "16. rsshub $rsshub_mo_status"
        "17. metube $metube_mo_status"
        "18. filecodebox $filecodebox_mo_status"
        "19. myip $myip_mo_status"
        "20. photopea $photopea_mo_status"
        "21. easyimage $easyimage_mo_status"
        "22. myicon $myicon_mo_status"
        "23. easynode $easynode_mo_status"
        "24. qb_shua $qb_shua_status"
        "25. lucky $lucky_mo_status"
        "26. pt_accelerator $pt_accelerator_mo_status"
        "27. openlist $openlist_mo_status"
        "28. vikunja $vikunja_mo_status"
        "29. allinone $allinone_mo_status"
        "30. allinone_format $allinone_format_mo_status"
        "31. watchtower $watchtower_mo_status"
        "32. reader $reader_mo_status"
        "33. newsnow $newsnow_mo_status"
        "34. calibre $calibre_mo_status"
        "35. uptime_kuma $uptime_kuma_mo_status"
        "36. convertx $convertx_mo_status"
        "37. stirling_pdf $stirling_pdf_mo_status"
        "38. wewe_rss_sqlite $wewe_rss_sqlite_mo_status"
        "39. melody $melody_mo_status"
        "40. bililive_go $bililive_go_mo_status"
        "41. libretv $libretv_mo_status"
        "42. fivefilters $fivefilters_mo_status"
        "43. notepad $notepad_mo_status"
        "44. playlistdl $playlistdl_mo_status"
        "45. squoosh $squoosh_mo_status"
        "46. easyvoice $easyvoice_mo_status"
        "47. tachidesk $tachidesk_mo_status"
        "48. flaresolverr $flaresolverr_mo_status"
        "49. easy_vdl $easy_vdl_mo_status"
        "50. moontv $moontv_mo_status"
        "51. mediago $mediago_mo_status"
        "52. handbrake $handbrake_mo_status"
        "53. pairdrop $pairdrop_mo_status"
        "54. xunlei $xunlei_mo_status"
        "55. dockports $dockports_mo_status"
        "56. flink $flink_mo_status"
        "57. wallos $wallos_mo_status"
        "58. trilium $trilium_mo_status"
        "59. nzbget $nzbget_mo_status"
        "60. scrutiny $scrutiny_mo_status"
        "61. netalertx $netalertx_mo_status"
        "62. yt_dlp_web $yt_dlp_web_mo_status"
        "63. kspeeder $kspeeder_mo_status"
        "64. myspeed_mo $myspeed_mo_status"
        "65. image_watermark_tool $image_watermark_tool_mo_status"
        "66. noname_game $noname_game_mo_status"
        "67. roon $roon_mo_status"
        "68. emulatorjs $emulatorjs_mo_status"
        "69. v2raya $v2raya_mo_status"
        "70. docker_autocompose $docker_autocompose_mo_status"
        "71. upsnap $upsnap_mo_status"
        "72. qd $qd_mo_status"
        "73. onenav $onenav_mo_status"
        "74. linkding $linkding_mo_status"
        "75. bili_sync_rs $bili_sync_rs_mo_status"
        "76. musicn $musicn_mo_status"
        "77. tissue $tissue_mo_status"
        "78. cloudbak $cloudbak_mo_status"
        "79. sun_panel $sun_panel_mo_status"
        "80. sun_panel_helper $sun_panel_helper_mo_status"
        "81. frps $frps_mo_status"
        "82. metatube $metatube_mo_status"
        "83. wxchat $wxchat_mo_status"
        "84. iptv_hls $iptv_hls_mo_status"
        "85. easy_itv $easy_itv_mo_status"
        "86. glances $glances_mo_status"
        "87. drawnix $drawnix_mo_status"
        "88. d2c $d2c_mo_status"
        "89. iptv_api $iptv_api_mo_status"
        "90. dsm $dsm_mo_status"
        "91. wps_office $wps_office_mo_status"
        "92. whiper $whiper_mo_status"
        "93. hivision $hivision_mo_status"
        "94. rsshub $rsshub_status"
        "95. hatsh $hatsh_mo_status"
        "96. autopiano $autopiano_mo_status"
        "97. g_box $g_box_mo_status"
        "98. byte_muse $byte_muse_mo_status"
        "99. md $md_mo_status"
        "100. xiuxian $xiuxian_mo_status"
        "101. moviepilot_v2_115 $moviepilot_v2_115_status"
        "102. docker_login $docker_login_status"
        "103. mdcx $mdcx_mo_status"
        "104. neko $neko_mo_status"
        "105. koodo_reader $koodo_reader_mo_status"
        "106. cinemore $cinemore_mo_status"
        "107. bytestash $bytestash_mo_status"
        "108. teleport $teleport_mo_status"
        "109. dockpeek $dockpeek_mo_status"
        "110. nav $nav_mo_status"
        "111. h5 $h5_mo_status"
        "112. ispyagentdvr $ispyagentdvr_mo_status"
        "113. GSManager $GSManager_mo_status"
        "114. urbackup $urbackup_mo_status"
        "115. qrding $qrding_mo_status"
        "116. enclosed $enclosed_mo_status"
        "117. ghosthub $ghosthub_mo_status"
        "118. navipage $navipage_mo_status"
        "119. mediamaster $mediamaster_mo_status"
        "120. nullbr115 $nullbr115_mo_status"
        "121. cd2 $cd2_mo_status"
        "122. ubooquity $ubooquity_mo_status"
        "123. jdownloader $jdownloader_mo_status"
        "124. xianyu_auto_reply $xianyu_auto_reply_mo_status"
        "125. n8n $n8n_mo_status"
        "126. moviepilot_v2_go $moviepilot_v2_go_status"
        "127. cms $cms_mo_status"
        "128. chromium $chromium_mo_status"
        "129. portainer $portainer_mo_status"
        "130. epub_to_audiobook $epub_to_audiobook_mo_status"
        "131. clash $clash_mo_status"
        "132. owjdxb $owjdxb_mo_status"
        "133. music_tag_web $music_tag_web_mo_status"
        "134. mdc $mdc_mo_status"
        "135. lyricapi $lyricapi_mo_status"
        "136. bangumikomga $bangumikomga_mo_status"
        "137. tailscale $tailscale_mo_status"
        "138. onestrm $onestrm_mo_status"
        "139. set_permissions_mo $set_permissions_mo_status"
        "140. remove_mo_containers_status $remove_mo_containers_status"
        "141. remove_container_array $remove_container_array_status"
        "142. reserved4 $reserved4_mo_status"
        "143. reserved5 $reserved5_mo_status"
        "144. kopia $kopia_mo_status"
        "145. pyload $pyload_mo_status"
        "146. cloudsaver $cloudsaver_mo_status"
        "147. mealie $mealie_mo_status"
        "148. huntly $huntly_mo_status"
        "149. whats_up_docker $whats_up_docker_mo_status"
        "0. 退出"
    )



    # 定义列数
    columns=3

    # 找出每列最长元素的长度
    max_lengths=()
    for ((i = 0; i < columns; i++)); do
        max_length=0
        for ((j = i; j < ${#service_list[@]}; j += columns)); do
            item="${service_list[$j]}"
            length=${#item}
            if (( length > max_length )); then
                max_length=$length
            fi
        done
        max_lengths[$i]=$max_length
    done

    # 计算行数
    rows=$(( (${#service_list[@]} + columns - 1) / columns ))

    # 循环打印多列，确保左对齐
    for ((i = 0; i < rows; i++)); do
        for ((j = 0; j < columns; j++)); do
            index=$(( i + j * rows ))
            if [ $index -lt ${#service_list[@]} ]; then
                item="${service_list[$index]}"
                printf "%-${max_lengths[$j]}s  " "$item"
            fi
        done
        echo
    done

    # 修改后的用户输入处理逻辑
    read -p "请输入选择的服务数字(支持范围如1-4,6-7)： " service_choices
    
    # 解析用户输入的范围选择
    parsed_choices=$(parse_selections "$service_choices")
    
    for service_choice in $parsed_choices; do
        if [[ "$service_choice" == "0" ]]; then
            OUTPUT_FILE="$DOCKER_ROOT_PATH/安装信息.txt"
            : > "$OUTPUT_FILE"
            echo "服务安装已完成，以下是每个服务的访问信息：" | tee -a "$OUTPUT_FILE"

            # 定义服务名称和对应的配置信息数组，修改分隔符为 |
            declare -A service_info=(
                ["csf_mo"]="http://$HOST_IP:59035|666666|666666"
                ["qb_mo"]="http://$HOST_IP:58080|666666|666666"
                ["qb_shua"]="http://$HOST_IP:58181|666666|666666"
                ["embypt_mo"]="http://$HOST_IP:58096|admin|666666"
                ["moviepilot_v2_pt"]="http://$HOST_IP:53000|admin|666666m"
                ["cookiecloud_mo"]="http://$HOST_IP:58088|666666|666666"
                ["frpc_mo"]="无|无|无"
                ["transmission_mo"]="http://$HOST_IP:59091|666666|666666"
                ["owjdxb_mo"]="http://$HOST_IP:9118|无|无"
                ["audiobookshelf_mo"]="http://$HOST_IP:57758|root|666666"
                ["komga_mo"]="http://$HOST_IP:55600|admin@admin.com|666666"
                ["navidrome_mo"]="http://$HOST_IP:54533|666666|666666"
                ["dockerCopilot_mo"]="http://$HOST_IP:52172|无|666666mmm"
                ["memos_mo"]="http://$HOST_IP:55230|666666|666666"
                ["homepage_mo"]="http://$HOST_IP:53010|无|无"
                ["vertex_mo"]="http://$HOST_IP:53800|666666|666666"
                ["freshrss_mo"]="http://$HOST_IP:58350|666666|666666m"
                ["rsshub_mo"]="http://$HOST_IP:51200|无|无"
                ["metube_mo"]="http://$HOST_IP:58581|无|无"
                ["filecodebox_mo"]="http://$HOST_IP:52346|无|无"
                ["myip_mo"]="http://$HOST_IP:58966|无|无"
                ["photopea_mo"]="http://$HOST_IP:58887|无|无"
                ["easyimage_mo"]="http://$HOST_IP:58631|无|无"
                ["clash_mo"]="http://$HOST_IP:38080|无|无"
                ["easynode_mo"]="http://$HOST_IP:58082|admin|admin666"
                ["portainer_mo"]="http://$HOST_IP:59000|admin|666666666666"
                ["lucky_mo"]="http://$HOST_IP:16601|666|666"
                ["cd2_mo"]="http://$HOST_IP:19798|无|无"
                ["openlist_mo"]="http://$HOST_IP:55244|admin|666666"
                ["glances_mo"]="http://$HOST_IP:61208|无|无"
                ["moviepilot_v2_go"]="http://$HOST_IP:53000|admin|666666m"
                ["allinone_mo"]="http://$HOST_IP:55101|无|无"
                ["allinone_format_mo"]="http://$HOST_IP:55102|无|无"
                ["watchtower_mo"]="无|无|无"
                ["epub_to_audiobook_mo"]="http://$HOST_IP:50013|无|无"
                ["cms_mo"]="http://$HOST_IP:9527|666666|666666"
                ["emby115_mo"]="http://$HOST_IP:56066|666666|666666"
                ["moviepilot_115_mo"]="http://$HOST_IP:52000|admin|666666m"
                ["chromium_mo"]="http://$HOST_IP:56901|kasm_user|666666"
                ["embyptzb_mo"]="http://$HOST_IP:58096|666666|666666"
                ["emby115zb_mo"]="http://$HOST_IP:38096|666666|666666"
                ["music_tag_web_mo"]="http://$HOST_IP:58002|admin|admin"
                ["mdc_mo"]="http://$HOST_IP:59208|无|无"
                ["lyricapi_mo"]="http://$HOST_IP:58883|无|无"
                ["bangumikomga_mo"]="无|无|无"
                ["tailscale_mo"]="无|无|无"
                ["reader_mo"]="http://$HOST_IP:57777|666666|66666666"
                ["newsnow_mo"]="http://$HOST_IP:56959|无|无"
                ["calibre_mo"]="http://$HOST_IP:57089|admin|admin123"
                ["emulatorjs_mo"]="http://$HOST_IP:51239|无|无"
                ["easy_itv_mo"]="http://$HOST_IP:58123|无|无"
                ["cloudbak_mo"]="http://$HOST_IP:56332|无|无"
                ["cloudsaver_mo"]="http://$HOST_IP:58032|666666|666666"
                ["uptime_kuma_mo"]="http://$HOST_IP:53001|666666|666666m"
                ["qd_mo"]="http://$HOST_IP:58923|666666|666666"
                ["stirling_pdf_mo"]="http://$HOST_IP:56080|无|无"
                ["huntly_mo"]="http://$HOST_IP:53232|666666|666666"
                ["roon_mo"]="http://$HOST_IP:55000|无|无"
                ["wewe_rss_sqlite_mo"]="http://$HOST_IP:54000|无|666666"
                ["v2raya_mo"]="http://$HOST_IP:52017|666666|666666"
                ["upsnap_mo"]="http://$HOST_IP:8090|666666|666666"
                ["melody_mo"]="http://$HOST_IP:55566|666666|666666"
                ["onenav_mo"]="http://$HOST_IP:52908|666666|666666"
                ["linkding_mo"]="http://$HOST_IP:59395|666666|666666"
                ["bili_sync_rs_mo"]="无|无|无"
                ["musicn_mo"]="http://$HOST_IP:57478|666666|666666"
                ["tissue_mo"]="http://$HOST_IP:59193|666666|666666"
                ["bililive_go_mo"]="http://$HOST_IP:51235|666666|666666"
                ["sun_panel_mo"]="http://$HOST_IP:53002|666666|666666"
                ["sun_panel_helper_mo"]="http://$HOST_IP:53003|666666|666666"
                ["frps_mo"]="无|无|无"
                ["metatube_mo"]="http://$HOST_IP:59999|666666|666666"
                ["wxchat_mo"]="http://$HOST_IP:29280|666666|666666"
                ["iptv_hls_mo"]="http://$HOST_IP:50086|无|无"
                ["convertx_mo"]="http://$HOST_IP:53410|无|无"
                ["myicon_mo"]="http://$HOST_IP:59395|无|无"
                ["drawnix_mo"]="http://$HOST_IP:57200|无|无"
                ["libretv_mo"]="http://$HOST_IP:58899|无|admin666"
                ["fivefilters_mo"]="http://$HOST_IP:58412|无|无"
                ["whiper_mo"]="http://$HOST_IP:39000|无|无"
                ["d2c_mo"]="无|无|无"
                ["notepad_mo"]="http://$HOST_IP:58760|无|无"
                ["rsshub"]="http://$HOST_IP:1200|无|无"
                ["myspeed_mo"]="http://$HOST_IP:53007|无|无"
                ["playlistdl_mo"]="http://$HOST_IP:50015|666666|666666"
                ["iptv_api_mo"]="http://$HOST_IP:58755|无|无"                
                ["dsm_mo"]="http://$HOST_IP:35000|dsm|666666m"
                ["wps_office_mo"]="http://$HOST_IP:43000|无|无"
                ["squoosh_mo"]="http://$HOST_IP:57080|无|无"
                ["hivision_mo"]="http://$HOST_IP:57860|无|无"
                ["image_watermark_tool_mo"]="http://$HOST_IP:53300|无|无"
                ["easyvoice_mo"]="$HOST:43333|无|无"
                ["hatsh_mo"]="http://$HOST_IP:38002|无|无"
                ["autopiano_mo"]="http://$HOST_IP:38003|无|无"
                ["g_box_mo"]="http://$HOST_IP:54567|无|无"
                ["byte_muse_mo"]="http://$HOST_IP:58043|无|无"
                ["md_mo"]="http://$HOST_IP:42222|无|无"    
                ["xiuxian_mo"]="http://$HOST_IP:42221|无|无"  
                ["moviepilot_v2_115"]="http://$HOST_IP:53000|admin|666666m"	
                ["tachidesk_mo"]="http://$HOST_IP:14567|无|无"
                ["flaresolverr_mo"]="http://$HOST_IP:18191|无|无"
                ["easy_vdl_mo"]="http://$HOST_IP::50004|无|无"
                ["moontv_mo"]="http://$HOST_IP:50003|无|666666"
                ["koodo_reader_mo"]="http://$HOST_IP:50001|无|无"
                ["mediago_mo"]="http://$HOST_IP:50006|无|无"
                ["cinemore_mo"]="http://$HOST_IP:50002|无|无"
                ["navipage_mo"]="http://$HOST_IP:50007|无|无"
                ["GSManager_mo"]="http://$HOST_IP:50008|无|无"  
                ["mdcx_mo"]="http://$HOST_IP:50010|无|无"
                ["neko_mo"]="http://$HOST_IP:50012|无|无"  
                ["handbrake_mo"]="http://$HOST_IP:50020|无|无"    
                ["pairdrop_mo"]="http://$HOST_IP:53049|无|无"  
                ["bytestash_mo"]="http://$HOST_IP:55908|666666|666666"	
                ["teleport_mo"]="http://$HOST_IP:50028|无|无"
                ["dockpeek_mo"]="http://$HOST_IP:58644|无|无"
                ["flink_mo"]="http://$HOST_IP::58287|无|无"
                ["h5_mo"]="http://$HOST_IP:50025|无|666666"
                ["ispyagentdvr_mo"]="http://$HOST_IP:50023|无|无"
                ["dockports_mo"]="http://$HOST_IP:50006|无|无"
                ["urbackup_mo"]="http://$HOST_IP:55414|无|无"
                ["qrding_mo"]="http://$HOST_IP:50026|无|无"
                ["enclosed_mo"]="http://$HOST_IP:50027|66666666|66666666"  
                ["ghosthub_mo"]="http://$HOST_IP:55211|无|无"			
                ["xunlei_mo"]="http://$HOST_IP:50070|无|无"		
                ["mediamaster_mo"]="http://$HOST_IP:50034|666666|666666"
                ["nullbr115_mo"]="http://$HOST_IP:58115|admin|admin666"  
                ["pt_accelerator_mo"]="http://$HOST_IP:23333|admin|admin666"			
                ["ubooquity_mo"]="http://$HOST_IP:52202|无|无"			
                ["onestrm_mo"]="http://$HOST_IP:58013|admin|admin666"
                ["yt_dlp_web_mo"]="http://$HOST_IP:53981|admin|admin666"
                ["wallos_mo"]="http://$HOST_IP::58282|admin|admin666"
                ["mealie_mo"]="http://$HOST_IP:59925|admin|admin666"
                ["pyload_mo"]="http://$HOST_IP:58000|admin|admin666"
                ["trilium_mo"]="http://$HOST_IP:50051|admin|admin666"
                ["nzbget_mo"]="http://$HOST_IP:46789|admin|admin666"
                ["scrutiny_mo"]="http://$HOST_IP:50052|admin|admin666"
                ["kopia_mo"]="http://$HOST_IP:51515|admin|admin666"  
                ["jdownloader_mo"]="http://$HOST_IP:53129|admin|admin666"			
                ["kspeeder_mo"]="http://$HOST_IP:55443|admin|admin666"		
                ["xianyu_auto_reply_mo"]="http://$HOST_IP:50101|admin|admin666"
                ["netalertx_mo"]="http://$HOST_IP:50211|admin|admin666"  
                ["n8n_mo"]="http://$HOST_IP:55679|admin|admin666"			
                ["whats_up_docker_mo"]="http://$HOST_IP:23000|admin|admin666"
                ["vikunja_mo"]="http://$HOST_IP:50107|admin666|admin666"							
				
            )

            # 遍历服务信息数组，根据安装状态输出
            for service in "${!service_info[@]}"; do
                if [[ "$(get_service_status "$service")" == *"[✔]"* ]]; then
                    echo "服务名称：$service" | tee -a "$OUTPUT_FILE"
                    IFS='|' read -ra parts <<< "${service_info[$service]}"
                    echo "  地址：${parts[0]}" | tee -a "$OUTPUT_FILE"
                    echo "  账号：${parts[1]}" | tee -a "$OUTPUT_FILE"
                    echo "  密码：${parts[2]}" | tee -a "$OUTPUT_FILE"
                    echo "" | tee -a "$OUTPUT_FILE"
                fi
            done

            echo | tee -a "$OUTPUT_FILE"
            history -c
            echo "安装流程结束！配置信息已保存到 $OUTPUT_FILE" | tee -a "$OUTPUT_FILE"
            exit 0
        elif [[ "$service_choice" == "200" ]]; then
            read -p "请输入要卸载的服务序号或不包含 _mo 后缀的服务名称： " service_name_input
            # 检查输入是否为数字（序号）
            if [[ "$service_name_input" =~ ^[0-9]+$ ]]; then
                service_name="${SERVICE_INDEX_MAP[$service_name_input]}"
                if [ -z "$service_name" ]; then
                    echo "无效的序号，请输入正确的序号。"
                    continue
                fi
            else
                service_name="${service_name_input}_mo"
            fi

            if [[ "$(get_service_status "$service_name")" == *"[✔]"* ]]; then
                uninstall_service "$service_name"
            else
                echo "该服务未安装，无法卸载。"
            fi
        else
            install_service "$service_choice"
        fi
    done
done
