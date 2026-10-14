#!/bin/bash

# Human-readable, read-only views of the management API's app-state contract.

harness_heading() {
    echo -e "${CYAN}$1${NC}"
}

harness_value() {
    local response_file="$1"
    local expression="$2"

    jq -r "$expression | if . == null then \"Unavailable\" else tostring end" "$response_file"
}

harness_print_count() {
    local response_file="$1"
    local label="$2"
    local expression="$3"
    local value

    value="$(harness_value "$response_file" "$expression")"
    if [[ "$value" == "Unavailable" ]]; then
        print_warn "$label: Unavailable"
    else
        print_info "$label: $value"
    fi
}

harness_print_warnings() {
    local response_file="$1"
    local warning_count

    warning_count="$(jq -r '.appState.warnings | length' "$response_file")"
    harness_heading "Warnings"
    if [[ "$warning_count" == "0" ]]; then
        print_success "No harness warnings"
        return
    fi

    while IFS= read -r warning; do
        print_warn "$warning"
    done < <(jq -r '.appState.warnings[]' "$response_file")
}

harness_fetch_status() {
    local response_file="$1"
    local error_file="${response_file}.err"
    local message

    if ! command -v jq >/dev/null 2>&1; then
        print_error "jq is required to render harness status"
        return 69
    fi

    if ! "$MANAGEMENT_API_BIN" app-state >"$response_file" 2>"$error_file"; then
        message="$(tail -1 "$error_file" 2>/dev/null || true)"
        rm -f "$error_file"
        print_error "Could not read harness status${message:+: $message}"
        return 1
    fi
    rm -f "$error_file"

    if ! jq -e '.appState | type == "object"' "$response_file" >/dev/null 2>&1; then
        print_error "The management API response does not include app-state status"
        return 65
    fi
}

harness_render_status() {
    local response_file="$1"
    local engine_available engine_version apply_status apply_status_label apply_time apply_message

    engine_available="$(jq -r '.appState.engine.available' "$response_file")"
    engine_version="$(harness_value "$response_file" '.appState.engine.version')"
    apply_status="$(harness_value "$response_file" '.appState.lastApply.status')"
    apply_time="$(harness_value "$response_file" '.appState.lastApply.time')"
    apply_message="$(harness_value "$response_file" '.appState.lastApply.message')"
    case "$apply_status" in
        succeeded) apply_status_label="Succeeded" ;;
        partial) apply_status_label="Partially succeeded" ;;
        failed) apply_status_label="Failed" ;;
        *) apply_status_label="$apply_status" ;;
    esac

    print_header "Application State Harness"
    harness_heading "Engine"
    if [[ "$engine_available" == "true" ]]; then
        print_success "Availability: Available"
    else
        print_warn "Availability: Unavailable"
    fi
    if [[ "$engine_version" == "Unavailable" ]]; then
        print_warn "Version: Unavailable"
    else
        print_info "Version: $engine_version"
    fi
    echo ""

    harness_heading "Recipes and verification"
    harness_print_count "$response_file" "Configured recipes" '.appState.configuredRecipeCount'
    harness_print_count "$response_file" "Verified recipes" '.appState.verification.verifiedRecipeCount'
    harness_print_count "$response_file" "Unverified recipes" '.appState.verification.unverifiedRecipeCount'
    echo ""

    harness_heading "Diff"
    harness_print_count "$response_file" "Configuration drift" '.appState.driftCount'
    harness_print_count "$response_file" "Manual residue" '.appState.manualResidueCount'
    echo ""

    harness_heading "Last apply"
    if [[ "$apply_status" == "Unavailable" ]]; then
        print_warn "Result: Unavailable"
    else
        print_info "Result: $apply_status_label"
    fi
    if [[ "$apply_time" == "Unavailable" ]]; then
        print_warn "Time: Unavailable"
    else
        print_info "Time: $apply_time"
    fi
    if [[ "$apply_message" == "Unavailable" ]]; then
        print_warn "Message: Unavailable"
    else
        print_info "Message: $apply_message"
    fi
    echo ""

    harness_print_warnings "$response_file"
}

harness_render_diff() {
    local response_file="$1"
    local drift residue

    drift="$(harness_value "$response_file" '.appState.driftCount')"
    residue="$(harness_value "$response_file" '.appState.manualResidueCount')"

    print_header "Application State Diff"
    harness_heading "Differences"
    harness_print_count "$response_file" "Configuration drift" '.appState.driftCount'
    harness_print_count "$response_file" "Manual residue" '.appState.manualResidueCount'

    if [[ "$drift" == "Unavailable" || "$residue" == "Unavailable" ]]; then
        print_warn "The read-only diff is incomplete because one or more counts are unavailable"
    elif [[ "$drift" == "0" && "$residue" == "0" ]]; then
        print_success "No drift or manual residue detected"
    else
        print_warn "Harness differences detected"
    fi
    echo ""

    harness_print_warnings "$response_file"
    echo ""
    print_info "This is a read-only API summary; 'nix-me apps' remains the explicit engine interface"
}

cmd_harness() {
    local subcommand="${1:-status}"
    local response_file status

    if (( $# > 1 )); then
        print_error "Usage: nix-me harness [status|diff]"
        return 64
    fi

    case "$subcommand" in
        status|diff) ;;
        *)
            print_error "Unknown harness subcommand: $subcommand"
            echo "Usage: nix-me harness [status|diff]"
            return 64
            ;;
    esac

    response_file="$(mktemp "${TMPDIR:-/tmp}/nix-me-harness.XXXXXX")" || return 1
    harness_fetch_status "$response_file"
    status=$?
    if (( status != 0 )); then
        rm -f "$response_file"
        return "$status"
    fi

    if [[ "$subcommand" == "diff" ]]; then
        harness_render_diff "$response_file"
    else
        harness_render_status "$response_file"
    fi
    rm -f "$response_file"
}
