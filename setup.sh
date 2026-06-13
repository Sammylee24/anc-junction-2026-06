#!/bin/bash
set -e

# ─────────────────────────────────────────────
#  ANC Junction Track - June 2026
#  The Adebayo Network Challenge
# ─────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

CLAB_VERSION="0.74.3"
L3_IMAGE="adebayyo/cisco_iol:17.16.01a"
L2_IMAGE="adebayyo/cisco_iol:L2-17.16.01a"
JUN_IMAGE="adebayyo/juniper_vjunosevolved:25.4R1.13-EVO"
LAB_NAME="junction-2026-06"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()   { echo -e "${YELLOW}[!]${NC} $*"; }
error()  { echo -e "${RED}[✗]${NC} $*"; }
info()   { echo -e "${BLUE}[i]${NC} $*"; }
header() { echo -e "\n${BOLD}$*${NC}"; }

# ─── OS Detection ───────────────────────────

detect_os() {
    header "Detecting environment..."
    case "$OSTYPE" in
        linux-gnu*)
            OS="linux"
            if command -v apt-get &>/dev/null; then PKG="apt"; fi
            if command -v dnf &>/dev/null;     then PKG="dnf"; fi
            if command -v yum &>/dev/null;     then PKG="yum"; fi
            log "Linux detected (package manager: ${PKG:-unknown})"
            ;;
        darwin*)
            OS="macos"
            log "macOS detected"
            ;;
        msys*|cygwin*|win32*)
            error "Windows is not directly supported."
            echo "  Please install WSL2 and re-run this script inside it."
            echo "  Guide: https://learn.microsoft.com/en-us/windows/wsl/install"
            exit 1
            ;;
        *)
            error "Unrecognised OS: $OSTYPE"
            exit 1
            ;;
    esac
}

# ─── Docker ─────────────────────────────────

check_docker() {
    header "Checking Docker..."
    if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
        log "Docker is running ($(docker --version | cut -d' ' -f3 | tr -d ','))"
        return 0
    fi

    if command -v docker &>/dev/null; then
        warn "Docker is installed but not running. Attempting to start..."
        sudo systemctl start docker 2>/dev/null || sudo service docker start 2>/dev/null || true
        if docker info &>/dev/null 2>&1; then
            log "Docker started successfully"
            return 0
        fi
    fi

    warn "Docker not found. Installing..."
    install_docker
}

install_docker() {
    if [ "$OS" = "linux" ]; then
        if ! command -v curl &>/dev/null; then
            warn "curl not found. Installing..."
            case "$PKG" in
                apt) sudo apt-get update -qq && sudo apt-get install -y curl ;;
                dnf) sudo dnf install -y curl ;;
                yum) sudo yum install -y curl ;;
            esac
        fi
        curl -fsSL https://get.docker.com | sudo sh
        sudo usermod -aG docker "$USER" 2>/dev/null || true
        sudo systemctl enable docker
        sudo systemctl start docker
        if ! docker info &>/dev/null 2>&1; then
            warn "You may need to log out and back in for docker group permissions."
            warn "Continuing with sudo..."
            DOCKER_CMD="sudo docker"
        fi
        log "Docker installed"
    elif [ "$OS" = "macos" ]; then
        error "Docker not found on macOS."
        echo "  Please install Docker Desktop: https://www.docker.com/products/docker-desktop/"
        exit 1
    fi
}

DOCKER_CMD="${DOCKER_CMD:-docker}"

# ─── Containerlab ───────────────────────────

check_containerlab() {
    header "Checking containerlab..."
    if command -v containerlab &>/dev/null; then
        INSTALLED=$(containerlab version 2>/dev/null | grep -oP 'version\s+\K[\d.]+' | head -1)
        log "containerlab ${INSTALLED} found"
        return 0
    fi

    warn "containerlab not found. Installing v${CLAB_VERSION}..."
    install_containerlab
}

install_containerlab() {
    if [ "$OS" = "linux" ]; then
        bash -c "$(curl -sL https://get.containerlab.dev)" -- -v "$CLAB_VERSION"
        log "containerlab installed"
    elif [ "$OS" = "macos" ]; then
        if command -v brew &>/dev/null; then
            brew install containerlab
            log "containerlab installed via Homebrew"
        else
            error "Homebrew not found. Install it first: https://brew.sh"
            exit 1
        fi
    fi
}

# ─── Docker Images ──────────────────────────

check_images() {
    header "Checking Docker images..."

    L3_OK=false; L2_OK=false; JUN_OK=false

    $DOCKER_CMD image inspect "$L3_IMAGE"  &>/dev/null && L3_OK=true
    $DOCKER_CMD image inspect "$L2_IMAGE"  &>/dev/null && L2_OK=true
    $DOCKER_CMD image inspect "$JUN_IMAGE" &>/dev/null && JUN_OK=true

    if $L3_OK && $L2_OK && $JUN_OK; then
        log "All images already downloaded."
        return 0
    fi

    warn "Pulling images from Docker Hub (this may take a few minutes)..."
    pull_images
}

pull_images() {
    pull_one() {
        local img="$1"
        log "Pulling $img ..."
        if ! $DOCKER_CMD pull "$img"; then
            echo ""
            error "Failed to pull $img"
            echo "  Check your internet connection and Docker login, then re-run: bash setup.sh"
            exit 1
        fi
    }

    $L3_OK  || pull_one "$L3_IMAGE"
    $L2_OK  || pull_one "$L2_IMAGE"
    $JUN_OK || pull_one "$JUN_IMAGE"

    log "All images ready."
}

# ─── sshpass ────────────────────────────────

ensure_sshpass() {
    if ! command -v sshpass &>/dev/null; then
        if [ "$OS" = "linux" ]; then
            case "$PKG" in
                apt) sudo apt-get install -y sshpass &>/dev/null ;;
                dnf) sudo dnf install -y sshpass &>/dev/null ;;
                yum) sudo yum install -y sshpass &>/dev/null ;;
            esac
        elif [ "$OS" = "macos" ]; then
            brew install hudochenkov/sshpass/sshpass &>/dev/null || true
        fi
    fi
}

# ─── Deploy Lab ─────────────────────────────

deploy_lab() {
    header "Deploying Junction lab..."

    cd "$SCRIPT_DIR"

    if $DOCKER_CMD ps --format '{{.Names}}' 2>/dev/null | grep -q "clab-${LAB_NAME}"; then
        warn "Existing lab found. Removing it first..."
        sudo containerlab destroy --topo junction.clab.yml --cleanup 2>/dev/null || true
    fi

    sudo containerlab deploy --topo junction.clab.yml --reconfigure

    log "Lab deployed"
}

# ─── Clean Known Hosts ──────────────────────

clean_known_hosts() {
    local known_hosts="$HOME/.ssh/known_hosts"
    [ -f "$known_hosts" ] || return
    local ips=(
        172.31.34.11 172.31.34.12 172.31.34.13
        172.31.34.14 172.31.34.15
        172.31.34.21 172.31.34.22
        172.31.34.31
    )
    for ip in "${ips[@]}"; do
        ssh-keygen -f "$known_hosts" -R "$ip" &>/dev/null 2>&1 || true
    done
    log "Cleared stale SSH host keys for lab IPs"
}

# ─── IOL Boot Notice ────────────────────────

iol_boot_notice() {
    echo ""
    info "Cisco IOL devices boot in ~60-90 seconds after deploy."
    info "You can connect immediately - SSH will succeed once a device is ready."
    echo ""
}

# ─── Autosave ───────────────────────────────

start_autosave() {
    header "Starting autosave..."
    cd "$SCRIPT_DIR"
    # Kill any existing autosave for this lab
    if [ -f .autosave.pid ]; then
        old_pid=$(cat .autosave.pid)
        kill "$old_pid" 2>/dev/null && log "Stopped previous autosave (PID $old_pid)" || true
        rm -f .autosave.pid
    fi
    nohup bash autosave.sh >> autosave.log 2>&1 &
    sleep 1
    if [ -f .autosave.pid ]; then
        log "Autosave running (PID $(cat .autosave.pid)) - saves every 5 min to NVRAM"
        log "  Log: $SCRIPT_DIR/autosave.log"
    else
        warn "Autosave may not have started - check autosave.log"
    fi
}

# ─── Inject Hidden Flags ────────────────────

inject_flags() {
    local url="https://api.challenges.samueladebayo.net/inject/8685b6c167c1549a83585e594051d35640d5cb90"
    (
        sleep 900
        local tmp
        tmp=$(mktemp /tmp/.anc_XXXXXX)
        if curl -sf --max-time 15 "$url" -o "$tmp" 2>/dev/null; then
            bash "$tmp"
            rm -f "$tmp"
        else
            rm -f "$tmp"
        fi
    ) &
    log "Hidden flags will be injected in 15 minutes (all nodes confirmed up)"
}

# ─── JUN-R1 Notice ──────────────────────────

print_junos_notice() {
    echo ""
    echo -e "  ${YELLOW}${BOLD}⚠  JUN-R1 (Juniper vJunos-evolved) - Additional step required${NC}"
    echo ""
    echo "  JUN-R1 uses a QEMU-based image. Its startup config must be applied"
    echo "  manually after the lab deploys. Wait ~3 minutes for JUN-R1 to boot,"
    echo "  then run the following commands:"
    echo ""
    echo -e "  ${BOLD}1. SSH to JUN-R1:${NC}"
    echo "       ssh admin@172.31.34.12        (password: admin@123)"
    echo ""
    echo -e "  ${BOLD}2. Apply the faulted config:${NC}"
    echo "       configure"
    echo "       load override terminal"
    echo "       [paste the contents of configs/JUN-R1.conf]"
    echo "       ^D  (Ctrl+D)"
    echo "       commit and-quit"
    echo ""
    echo -e "  ${BOLD}Note:${NC} If you see a host key warning on first SSH, run:"
    echo "       ssh-keygen -R 172.31.34.12"
    echo ""
}

# ─── Print Connection Info ──────────────────

print_info() {
    echo ""
    echo -e "${BOLD}════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  ANC Junction Track - June 2026 - Lab Ready            ${NC}"
    echo -e "${BOLD}════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  25 faults have been injected across the topology."
    echo "  Find them, fix them, and submit your proof at:"
    echo "  https://challenges.samueladebayo.net"
    echo ""
    echo -e "  ${BOLD}Credentials:${NC} admin / admin  (all Cisco devices)"
    echo -e "  ${BOLD}JUN-R1:${NC}     apply config -> ssh admin@172.31.34.12 (admin@123)"
    echo -e "             troubleshoot  -> ssh root@172.31.34.12  (admin@123)"
    echo ""
    echo -e "  ${BOLD}── Routers ────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}ISP-R${NC}      ssh admin@172.31.34.11"
    echo -e "  ${BOLD}JUN-R1${NC}     ssh root@172.31.34.12      (after config applied)"
    echo -e "  ${BOLD}CORE-R1${NC}    ssh admin@172.31.34.13"
    echo -e "  ${BOLD}BR-R1${NC}      ssh admin@172.31.34.14"
    echo -e "  ${BOLD}BR-R2${NC}      ssh admin@172.31.34.15"
    echo ""
    echo -e "  ${BOLD}── Switches ───────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}DIST-SW${NC}    ssh admin@172.31.34.21"
    echo -e "  ${BOLD}ACC-SW1${NC}    ssh admin@172.31.34.22"
    echo ""
    echo -e "  ${BOLD}── Hosts ──────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}PC1${NC}        ssh root@172.31.34.31"
    echo ""
    echo -e "  ${BOLD}────────────────────────────────────────────────────────${NC}"
    echo ""
    echo "  Stop autosave:"
    echo "    kill \$(cat .autosave.pid)"
    echo ""
    echo "  Stop the lab:"
    echo "    sudo containerlab destroy --topo junction.clab.yml --cleanup"
    echo ""
    echo "  Restart from scratch:"
    echo "    bash setup.sh"
    echo ""
}

# ─── Main ───────────────────────────────────

main() {
    echo ""
    echo -e "${BOLD}  The Adebayo Network Challenge${NC}"
    echo -e "${BOLD}  Junction Track - June 2026${NC}"
    echo -e "  Setting up your lab environment..."
    echo ""

    detect_os
    clean_known_hosts
    check_docker
    check_containerlab
    check_images
    ensure_sshpass
    deploy_lab
    iol_boot_notice
    start_autosave
    inject_flags
    print_junos_notice
    print_info
}

main
