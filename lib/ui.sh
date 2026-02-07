#!/bin/bash

# Colors (using $'...' for actual escape sequences)
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
MAGENTA=$'\033[0;35m'
NC=$'\033[0m'

# Icons
CHECK="✓"
CROSS="✗"
ARROW="→"
BULLET="•"

print_header() {
    local width=60
    local text="$1"
    local padding=$(( (width - ${#text} - 2) / 2 ))
    echo ""
    echo -e "${BLUE}$(printf '═%.0s' {1..60})${NC}"
    printf "${BLUE}║${NC}%*s${CYAN}%s${NC}%*s${BLUE}║${NC}\n" $padding "" "$text" $padding ""
    echo -e "${BLUE}$(printf '═%.0s' {1..60})${NC}"
    echo ""
}

print_step() {
    echo -e "${MAGENTA}[$1]${NC} ${CYAN}$2${NC}"
}

print_success() {
    echo -e "  ${GREEN}${CHECK}${NC} $1"
}

print_error() {
    echo -e "  ${RED}${CROSS}${NC} $1"
}

print_info() {
    echo -e "  ${BLUE}${BULLET}${NC} $1"
}

print_warn() {
    echo -e "  ${YELLOW}${BULLET}${NC} $1"
}

ask_yes_no() {
    local question="$1"
    local default="${2:-y}"

    if [[ $default == "y" ]]; then
        read -p "  $question (Y/n): " answer
        [[ -z $answer || $answer =~ ^[Yy] ]]
    else
        read -p "  $question (y/N): " answer
        [[ $answer =~ ^[Yy] ]]
    fi
}
