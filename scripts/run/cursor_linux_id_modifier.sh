#!/bin/bash

# 设置错误处理
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# 获取当前用户
get_current_user() {
    if [ "$EUID" -eq 0 ]; then
        echo "$SUDO_USER"
    else
        echo "$USER"
    fi
}

CURRENT_USER=$(get_current_user)
if [ -z "$CURRENT_USER" ]; then
    log_error "无法获取用户名"
    exit 1
fi

# 定义配置文件路径 (修改为 Linux 路径)
STORAGE_FILE="/home/$CURRENT_USER/.config/Cursor/User/globalStorage/storage.json"
BACKUP_DIR="/home/$CURRENT_USER/.config/Cursor/User/globalStorage/backups"

# 检查权限
check_permissions() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 sudo 运行此脚本"
        echo "示例: sudo $0"
        exit 1
    fi
}

# 检查并关闭 Cursor 进程
check_and_kill_cursor() {
    log_info "检查 Cursor 进程..."
    
    local attempt=1
    local max_attempts=5
    
    # 函数：获取进程详细信息
    get_process_details() {
        local process_name="$1"
        log_debug "正在获取 $process_name 进程详细信息："
        ps aux | grep -E "/[C]ursor|[C]ursor$" || true
    }
    
    while [ $attempt -le $max_attempts ]; do
        # 使用更精确的方式查找 Cursor 进程
        CURSOR_PIDS=$(ps aux | grep -E "/[C]ursor|[C]ursor$" | awk '{print $2}' || true)
        
        if [ -z "$CURSOR_PIDS" ]; then
            log_info "未发现运行中的 Cursor 进程"
            return 0
        fi
        
        log_warn "发现 Cursor 进程正在运行"
        get_process_details "Cursor"
        
        log_warn "尝试关闭 Cursor 进程..."
        
        # 遍历每个 PID 并尝试终止
        for pid in $CURSOR_PIDS; do
            if [ $attempt -eq $max_attempts ]; then
                log_warn "尝试强制终止进程 PID: ${pid}..."
                kill -9 "${pid}" 2>/dev/null || true
            else
                kill "${pid}" 2>/dev/null || true
            fi
        done
        
        sleep 2
        
        # 检查是否还有 Cursor 进程在运行
        if ! ps aux | grep -E "/[C]ursor|[C]ursor$" > /dev/null; then
            log_info "Cursor 进程已成功关闭"
            return 0
        fi
        
        log_warn "等待进程关闭，尝试 $attempt/$max_attempts..."
        ((attempt++))
        sleep 1
    done
    
    log_error "在 $max_attempts 次尝试后仍无法关闭 Cursor 进程"
    get_process_details "Cursor"
    log_error "请手动关闭进程后重试"
    exit 1
}

# 备份配置文件
backup_config() {
    # 检查文件权限
    if [ -f "$STORAGE_FILE" ] && [ ! -w "$STORAGE_FILE" ]; then
        log_error "无法写入配置文件，请检查权限"
        exit 1
    fi
    
    if [ ! -f "$STORAGE_FILE" ]; then
        log_warn "配置文件不存在，跳过备份"
        return 0
    fi
    
    mkdir -p "$BACKUP_DIR"
    local backup_file="$BACKUP_DIR/storage.json.backup_$(date +%Y%m%d_%H%M%S)"
    
    if cp "$STORAGE_FILE" "$backup_file"; then
        chmod 644 "$backup_file"
        chown "$CURRENT_USER:$CURRENT_USER" "$backup_file"
        log_info "配置已备份到: $backup_file"
    else
        log_error "备份失败"
        exit 1
    fi
}

# 生成随机 ID
generate_random_id() {
    # Linux 可以使用 /dev/urandom
    head -c 32 /dev/urandom | xxd -p
}

# 生成随机 UUID
generate_uuid() {
    # Linux 使用 uuidgen 命令
    uuidgen | tr '[:upper:]' '[:lower:]'
}

# 生成新的配置
generate_new_config() {
    # 错误处理
    if ! command -v xxd &> /dev/null; then
        log_error "未找到 xxd 命令，请安装 xxd"
        exit 1
    fi
    
    if ! command -v uuidgen &> /dev/null; then
        log_error "未找到 uuidgen 命令，请安装 uuidgen"
        exit 1
    fi
    
    # 确保目录存在
    mkdir -p "$(dirname "$STORAGE_FILE")"
    
    # 将 auth0|user_ 转换为字节数组的十六进制
    local prefix_hex=$(echo -n "auth0|user_" | xxd -p)
    # 生成随机部分
    local random_part=$(generate_random_id)
    # 拼接前缀的十六进制和随机部分
    local machine_id="${prefix_hex}${random_part}"
    
    local mac_machine_id=$(generate_random_id)
    local device_id=$(generate_uuid | tr '[:upper:]' '[:lower:]')
    local sqm_id="{$(generate_uuid | tr '[:lower:]' '[:upper:]')}"
    
    if [ -f "$STORAGE_FILE" ]; then
        # 直接修改现有文件
        sed -i "s|\"telemetry\.machineId\":[[:space:]]*\"[^\"]*\"|\"telemetry.machineId\": \"$machine_id\"|" "$STORAGE_FILE"
        sed -i "s|\"telemetry\.macMachineId\":[[:space:]]*\"[^\"]*\"|\"telemetry.macMachineId\": \"$mac_machine_id\"|" "$STORAGE_FILE"
        sed -i "s|\"telemetry\.devDeviceId\":[[:space:]]*\"[^\"]*\"|\"telemetry.devDeviceId\": \"$device_id\"|" "$STORAGE_FILE"
        sed -i "s|\"telemetry\.sqmId\":[[:space:]]*\"[^\"]*\"|\"telemetry.sqmId\": \"$sqm_id\"|" "$STORAGE_FILE"
    else
        # 创建新文件
        cat > "$STORAGE_FILE" << EOF
{
    "telemetry.machineId": "$machine_id",
    "telemetry.macMachineId": "$mac_machine_id",
    "telemetry.devDeviceId": "$device_id",
    "telemetry.sqmId": "$sqm_id"
}
EOF
    fi

    chmod 644 "$STORAGE_FILE"
    chown "$CURRENT_USER:$CURRENT_USER" "$STORAGE_FILE"
    
    echo
    log_info "已更新配置:"
    log_debug "machineId: $machine_id"
    log_debug "macMachineId: $mac_machine_id"
    log_debug "devDeviceId: $device_id"
    log_debug "sqmId: $sqm_id"
}

# 显示文件树结构
show_file_tree() {
    local base_dir=$(dirname "$STORAGE_FILE")
    echo
    log_info "文件结构:"
    echo -e "${BLUE}$base_dir${NC}"
    echo "├── globalStorage"
    echo "│   ├── storage.json (已修改)"
    echo "│   └── backups"
    
    # 列出备份文件
    if [ -d "$BACKUP_DIR" ]; then
        local backup_files=("$BACKUP_DIR"/*)
        if [ ${#backup_files[@]} -gt 0 ] && [ -e "${backup_files[0]}" ]; then
            for file in "${backup_files[@]}"; do
                if [ -f "$file" ]; then
                    echo "│       └── $(basename "$file")"
                fi
            done
        else
            echo "│       └── (空)"
        fi
    fi
    echo
}

# 显示公众号信息
show_follow_info() {
    echo
    echo -e "${GREEN}================================${NC}"
    echo -e "${YELLOW}  关注公众号【煎饼果子卷AI】一起交流更多Cursor技巧和AI知识 ${NC}"
    echo -e "${GREEN}================================${NC}"
    echo
}

# 主函数
main() {
    clear
    # 显示 CURSOR Logo
    echo -e "
    ██████╗██╗   ██╗██████╗ ███████╗ ██████╗ ██████╗ 
   ██╔════╝██║   ██║██╔══██╗██╔════╝██╔═══██╗██╔══██╗
   ██║     ██║   ██║██████╔╝███████╗██║   ██║██████╔╝
   ██║     ██║   ██║██╔══██╗╚════██║██║   ██║██╔══██╗
   ╚██████╗╚██████╔╝██║  ██║███████║╚██████╔╝██║  ██║
    ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝
    "
    echo -e "${BLUE}================================${NC}"
    echo -e "${GREEN}      Cursor ID 修改工具${NC}"
    echo -e "${BLUE}================================${NC}"
    echo
    
    check_permissions
    check_and_kill_cursor
    backup_config
    generate_new_config
    
    echo
    log_info "操作完成！"
    show_follow_info
    show_file_tree
    log_info "请重启 Cursor 以应用新的配置"
    echo
}

# 执行主函数
main
