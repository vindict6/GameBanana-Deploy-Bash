#!/bin/bash
# ==========================================
# GameBanana Deployment Suite © 2026 BONE
# ==========================================

# ==========================================
# DEPENDENCY CHECKS
# ==========================================
for cmd in curl jq tr awk sed find whiptail xargs; do
    if ! command -v "$cmd" &> /dev/null; then
        echo -e "\033[0;31m [!] Error: '$cmd' is required but not installed.\033[0m"
        echo "Please install it (e.g., sudo apt install whiptail jq curl findutils)"
        exit 1
    fi
done

# 7-Zip is required. Prefer '7zz' (7-Zip 21.02+), which natively handles RAR5
# and the newer compression methods that legacy p7zip ('7z') cannot decode and
# reports as "ERROR: Unsupported Method" on many GameBanana uploads.
if ! command -v 7zz &> /dev/null; then
    if command -v 7z &> /dev/null; then
        echo -e "\033[0;33m [!] Notice: Only legacy '7z' (p7zip) found.\033[0m"
        echo -e "     Some .rar downloads use compression methods p7zip cannot decode."
        echo -e "     Install a modern 7-Zip build to fix this:"
        echo -e "       Debian/Ubuntu: sudo apt install 7zip        (provides '7zz')"
        echo -e "       Arch:          sudo pacman -S 7zip          (provides '7zz')"
        echo -e "       Fedora:        sudo dnf install 7zip        (provides '7zz')"
        echo -e "       Manual:        https://www.7-zip.org/download.html"
        echo
    else
        echo -e "\033[0;31m [!] Error: 7-Zip is not installed. Please install the '7zip' package (provides '7zz').\033[0m"
        exit 1
    fi
fi

# ==========================================
# CONFIGURATION & THEME
# ==========================================
CONFIG_FILE="$HOME/.config/gb_manager.conf"
USER_AGENT="GameBanana-Manager/3.4 (Bash/Whiptail-Advanced)"

# Advanced "Flat Dark Mode" Theme
export NEWT_COLORS="
root=white,black
window=white,black
shadow=black,black
border=blue,black
title=cyan,black
button=cyan,black
actbutton=black,cyan
listbox=white,black
actlistbox=black,cyan
sellistbox=white,black
actsellistbox=black,cyan
textbox=white,black
entry=black,cyan
"

# Load or Create Configuration
if [ ! -f "$CONFIG_FILE" ]; then
    mkdir -p "$(dirname "$CONFIG_FILE")"
    echo "EXTRACT_DIR=\"$HOME/content\"" > "$CONFIG_FILE"
    echo "DB_DIR=\"$HOME/map_manager\"" >> "$CONFIG_FILE"
    echo "GAME_ID=\"4254\"" >> "$CONFIG_FILE"
fi
source "$CONFIG_FILE"

update_globals() {
    INSTALLED_LIST="$DB_DIR/installed.txt"
    local cols
    cols=$(tput cols 2>/dev/null || echo 80)
    local line1=" GameBanana Deployment Suite © 2026 BONE | Target Game: $GAME_ID | Content: $EXTRACT_DIR"
    # Pad the backtitle so its highlight bar spans the full terminal width.
    # Note: ${#line1} counts bytes; the © multibyte char may leave 1 extra space, which is harmless.
    local pad=$(( cols - ${#line1} ))
    if [ "$pad" -gt 0 ]; then
        BACKTITLE="${line1}$(printf '%*s' "$pad" '')"
    else
        BACKTITLE="$line1"
    fi
}

save_config() {
    echo "EXTRACT_DIR=\"$EXTRACT_DIR\"" > "$CONFIG_FILE"
    echo "DB_DIR=\"$DB_DIR\"" >> "$CONFIG_FILE"
    echo "GAME_ID=\"$GAME_ID\"" >> "$CONFIG_FILE"
    
    mkdir -p "$EXTRACT_DIR"
    mkdir -p "$DB_DIR"
    touch "$DB_DIR/installed.txt"
    update_globals
}
save_config

# ==========================================
# HELPER FUNCTIONS
# ==========================================
urlencode() {
    # Use printf '%s' to avoid interpreting the char as a format string.
    local length="${#1}"
    for (( i = 0; i < length; i++ )); do
        local c="${1:i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf '%s' "$c" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done
}

pause_msg() {
    whiptail --backtitle "$BACKTITLE" --title " Information " --msgbox "\n$1" 14 72
}

# Lightweight progress infobox used during long-running API work.
progress_msg() {
    local title="$1"
    shift
    whiptail --backtitle "$BACKTITLE" --title " $title " --infobox "\n$*" 10 70
}

# Human-readable byte size (input: integer bytes).
format_bytes() {
    local b="${1:-0}"
    if ! [[ "$b" =~ ^[0-9]+$ ]]; then echo "?"; return; fi
    if   [ "$b" -ge 1073741824 ]; then awk -v x="$b" 'BEGIN{printf "%.2f GB", x/1073741824}'
    elif [ "$b" -ge 1048576 ];    then awk -v x="$b" 'BEGIN{printf "%.2f MB", x/1048576}'
    elif [ "$b" -ge 1024 ];       then awk -v x="$b" 'BEGIN{printf "%.1f KB", x/1024}'
    else echo "$b B"
    fi
}

# Extract an archive into a destination directory using a modern 7-Zip build.
# Prefers '7zz' (7-Zip 21.02+) which handles RAR, RAR5, zip, 7z, tar.*, etc.
# natively. Falls back to legacy '7z' (p7zip) only if 7zz is unavailable; this
# fallback cannot decode several RAR methods commonly found on GameBanana.
# Returns 0 on success, non-zero on failure.
extract_archive() {
    local ARCHIVE="$1"
    local DEST="$2"
    local LOG
    LOG=$(mktemp)

    local SEVENZ=""
    if   command -v 7zz &> /dev/null; then SEVENZ=7zz
    elif command -v 7z  &> /dev/null; then SEVENZ=7z
    fi

    local rc=1
    if [ -n "$SEVENZ" ]; then
        "$SEVENZ" x "$ARCHIVE" -o"$DEST" -y > "$LOG" 2>&1
        rc=$?
        # 7-Zip can return 0 even when individual entries failed with
        # "Unsupported Method" - treat that as a failure so we surface it.
        if [ "$rc" -eq 0 ] && grep -q "Unsupported Method" "$LOG"; then
            rc=2
            echo -e " \033[1;31m[x]\033[0m Your 7-Zip can't decode this archive's compression method."
            echo -e "     Install a modern 7-Zip build (provides the '7zz' command):"
            echo -e "       Debian/Ubuntu: sudo apt install 7zip"
            echo -e "       Arch:          sudo pacman -S 7zip"
            echo -e "       Fedora:        sudo dnf install 7zip"
        fi
    fi

    if [ "$rc" -ne 0 ]; then
        echo -e " \033[0;37m----- extractor output -----\033[0m"
        tail -n 20 "$LOG" | sed 's/^/     /'
        echo -e " \033[0;37m----------------------------\033[0m"
    fi
    rm -f "$LOG"
    return "$rc"
}

# ==========================================
# CORE INSTALLER LOGIC
# ==========================================
# install_item <Type> <Id> <SourceUrl> [ForceReinstall]
install_item() {
    local TYPE="$1"
    local ID="$2"
    local SOURCE_URL="$3"
    local FORCE="${4:-0}"

    clear
    echo -e "\n \033[1;36m::\033[0m \033[1;37mInstalling Content\033[0m"
    echo -e " \033[1;34m====================================================\033[0m\n"

    if [ "$FORCE" != "1" ] && grep -q "^${ID}|" "$INSTALLED_LIST" 2>/dev/null; then
        echo -e " \033[1;33m[!] Notice: Item ID $ID is already installed. Skipping...\033[0m"
        sleep 2
        return
    fi

    echo -e " \033[1;34m[i]\033[0m Fetching metadata for $TYPE ID: $ID..."

    # Use apiv11 ProfilePage: returns richer data (file sizes, download counts,
    # view counts) and works uniformly across Mod / Map / Sound / Wip / etc.
    local API_URL="https://gamebanana.com/apiv11/${TYPE}/${ID}/ProfilePage"
    local RESPONSE
    RESPONSE=$(curl -fsS -A "$USER_AGENT" -H "Accept: application/json" "$API_URL")
    if [ $? -ne 0 ] || [ -z "$RESPONSE" ] || [ "$RESPONSE" == "null" ]; then
        echo -e " \033[1;31m[x] Error: Could not fetch metadata (invalid ID, removed item, or API down).\033[0m"
        sleep 3; return
    fi

    local ITEM_NAME
    ITEM_NAME=$(echo "$RESPONSE" | jq -r '._sName // "Unknown"')
    local NUM_FILES
    NUM_FILES=$(echo "$RESPONSE" | jq -r '._aFiles | length // 0' 2>/dev/null)

    if [ -z "$NUM_FILES" ] || [ "$NUM_FILES" == "0" ] || [ "$NUM_FILES" == "null" ]; then
        echo -e " \033[1;31m[x] Error: No downloadable files are attached to this item.\033[0m"
        sleep 3; return
    fi

    # Build parallel arrays of files. Use control-char (TAB) separator since
    # filenames can contain spaces, parens, etc.
    local FILE_ROWS
    FILE_ROWS=$(echo "$RESPONSE" | jq -r '._aFiles[] | [._sFile, ._sDownloadUrl, (._nFilesize|tostring), (._nDownloadCount|tostring)] | @tsv')

    local -a F_NAMES F_URLS F_SIZES F_DLS
    while IFS=$'\t' read -r fn fu fs fd; do
        [ -z "$fn" ] && continue
        F_NAMES+=("$fn"); F_URLS+=("$fu"); F_SIZES+=("$fs"); F_DLS+=("$fd")
    done <<< "$FILE_ROWS"

    if [ ${#F_NAMES[@]} -eq 0 ]; then
        echo -e " \033[1;31m[x] Error: Parsed no files from API response.\033[0m"
        sleep 3; return
    fi

    local SELECTED_IDX=0
    if [ ${#F_NAMES[@]} -gt 1 ]; then
        # Let the user pick when multiple downloads exist.
        local PICK_ARGS=()
        for i in "${!F_NAMES[@]}"; do
            PICK_ARGS+=("$i" "$(printf '%-40s %10s | %s DLs' "${F_NAMES[$i]:0:40}" "$(format_bytes "${F_SIZES[$i]}")" "${F_DLS[$i]:-0}")")
        done
        local CHOICE
        CHOICE=$(whiptail --backtitle "$BACKTITLE" --title " Select File: $ITEM_NAME " --menu "This item has multiple downloads. Choose one:" 22 78 12 "${PICK_ARGS[@]}" 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            echo -e " \033[1;33m[!] Install cancelled.\033[0m"
            sleep 1; return
        fi
        SELECTED_IDX="$CHOICE"
        clear
        echo -e "\n \033[1;36m::\033[0m \033[1;37mInstalling Content\033[0m"
        echo -e " \033[1;34m====================================================\033[0m\n"
    fi

    local SELECTED_FILE="${F_NAMES[$SELECTED_IDX]}"
    local SELECTED_URL="${F_URLS[$SELECTED_IDX]}"
    local SELECTED_SIZE="${F_SIZES[$SELECTED_IDX]}"

    echo -e " \033[1;32m[✓]\033[0m Found: \033[1;37m$ITEM_NAME\033[0m"
    echo -e " \033[1;36m[↓]\033[0m Downloading \033[0;37m$SELECTED_FILE\033[0m ($(format_bytes "$SELECTED_SIZE"))..."

    local DL_TMP_DIR
    DL_TMP_DIR=$(mktemp -d)
    local EXTRACT_TMP_DIR
    EXTRACT_TMP_DIR=$(mktemp -d)

    # Let curl render its own progress bar (it writes to stderr by default).
    # Piping -# through sed was collapsing the display to nothing.
    if ! curl -L --fail --progress-bar -A "$USER_AGENT" "$SELECTED_URL" -o "$DL_TMP_DIR/$SELECTED_FILE"; then
        echo -e " \033[1;31m[x] Download failed.\033[0m"
        rm -rf "$DL_TMP_DIR" "$EXTRACT_TMP_DIR"
        sleep 3; return
    fi

    echo -e " \033[1;33m[⚙]\033[0m Extracting files..."
    if ! extract_archive "$DL_TMP_DIR/$SELECTED_FILE" "$EXTRACT_TMP_DIR"; then
        echo -e " \033[1;31m[x] Extraction failed.\033[0m"
        rm -rf "$DL_TMP_DIR" "$EXTRACT_TMP_DIR"
        sleep 3; return
    fi

    echo -e " \033[1;35m[⟳]\033[0m Normalising file names (lowercase)..."
    # Rename case-sensitively: only if the lowercase form differs AND doesn't
    # already exist (prevents clobbering when two entries collide).
    find "$EXTRACT_TMP_DIR" -depth | while read -r path; do
        [ "$path" == "$EXTRACT_TMP_DIR" ] && continue
        local dir base lower_base
        dir=$(dirname "$path")
        base=$(basename "$path")
        lower_base=$(echo "$base" | tr '[:upper:]' '[:lower:]')
        if [ "$base" != "$lower_base" ] && [ ! -e "$dir/$lower_base" ]; then
            mv "$path" "$dir/$lower_base" 2>/dev/null
        fi
    done

    find "$EXTRACT_TMP_DIR" -type f -printf "%P\n" > "$DB_DIR/${ID}.files"
    find "$EXTRACT_TMP_DIR" -type d -printf "%P\n" | sort -r > "$DB_DIR/${ID}.dirs"

    echo -e " \033[1;35m[⟳]\033[0m Deploying to content directory..."
    cp -a "$EXTRACT_TMP_DIR/." "$EXTRACT_DIR/"

    # Update the installed list: remove any pre-existing line for this ID
    # (reinstall/update case) then append fresh record.
    if [ -f "$INSTALLED_LIST" ]; then
        sed -i "/^${ID}|/d" "$INSTALLED_LIST"
    fi
    echo "${ID}|${ITEM_NAME}|${SOURCE_URL}" >> "$INSTALLED_LIST"

    rm -rf "$DL_TMP_DIR" "$EXTRACT_TMP_DIR"

    local N_FILES
    N_FILES=$(wc -l < "$DB_DIR/${ID}.files")
    echo -e "\n \033[1;32m[★] Install complete.\033[0m \033[0;37m($N_FILES files deployed)\033[0m"
    sleep 2
}

# ==========================================
# MENU: SEARCH & INSTALL
# ==========================================
menu_search() {
    QUERY=$(whiptail --backtitle "$BACKTITLE" --title " Search " --inputbox "\nEnter search query (Game ID $GAME_ID):" 14 65 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$QUERY" ]; then return; fi

    local QUERY_ENC=$(urlencode "$QUERY")

    progress_msg "Searching" "Query: '$QUERY'\nGame ID: $GAME_ID\n\nContacting GameBanana..."

    local MAP_PAGE=1
    local MOD_PAGE=1
    local MAP_DONE=false
    local MOD_DONE=false
    local RAW_RESULTS=()
    local MAP_TOTAL=0
    local MOD_TOTAL=0

    # apiv11 search records expose _nViewCount and _aSubmitter._sName directly,
    # so we grab them in the same request instead of making a second call per item.
    local JQ_MAP='._aRecords[]? | "\(._nViewCount // 0)|\(._aSubmitter._sName // ._aSubmitter._sUserTitle // "Unknown")|Map|\(._idRow // .id)|\(._sName // .name)"'
    local JQ_MOD='._aRecords[]? | "\(._nViewCount // 0)|\(._aSubmitter._sName // ._aSubmitter._sUserTitle // "Unknown")|Mod|\(._idRow // .id)|\(._sName // .name)"'

    # Safety cap: apiv11 actually returns ~15 records per page regardless of
    # _nPerpage. 100 pages is ~1500 results, far more than any real search.
    local MAX_PAGES=100

    while [ "$MAP_DONE" = false ] || [ "$MOD_DONE" = false ]; do
        progress_msg "Searching" "Query: '$QUERY'\n\nMaps : page $MAP_PAGE  ($MAP_TOTAL collected)\nMods : page $MOD_PAGE  ($MOD_TOTAL collected)\n\nDownloading results..."

        if [ "$MAP_DONE" = false ]; then
            local URL_MAP="https://gamebanana.com/apiv11/Util/Search/Results?_sModelName=Map&_idGameRow=${GAME_ID}&_sSearchString=${QUERY_ENC}&_nPage=${MAP_PAGE}&_nPerpage=50"
            local MAP_RES
            MAP_RES=$(curl -fsS -A "$USER_AGENT" -H "Accept: application/json" "$URL_MAP")
            local MAP_DATA=""
            [ -n "$MAP_RES" ] && MAP_DATA=$(echo "$MAP_RES" | jq -r "$JQ_MAP" 2>/dev/null)
            if [ -n "$MAP_DATA" ]; then
                while IFS= read -r line; do
                    [ -n "$line" ] && { RAW_RESULTS+=("$line"); ((MAP_TOTAL++)); }
                done <<< "$MAP_DATA"
            fi
            local M_COMP=$(echo "$MAP_RES" | jq -r '._aMetadata._bIsComplete // true' 2>/dev/null)
            if [ "$M_COMP" == "true" ] || [ -z "$MAP_DATA" ] || [ "$MAP_PAGE" -ge "$MAX_PAGES" ]; then
                MAP_DONE=true
            else
                ((MAP_PAGE++))
            fi
        fi

        if [ "$MOD_DONE" = false ]; then
            local URL_MOD="https://gamebanana.com/apiv11/Util/Search/Results?_sModelName=Mod&_idGameRow=${GAME_ID}&_sSearchString=${QUERY_ENC}&_nPage=${MOD_PAGE}&_nPerpage=50"
            local MOD_RES
            MOD_RES=$(curl -fsS -A "$USER_AGENT" -H "Accept: application/json" "$URL_MOD")
            local MOD_DATA=""
            [ -n "$MOD_RES" ] && MOD_DATA=$(echo "$MOD_RES" | jq -r "$JQ_MOD" 2>/dev/null)
            if [ -n "$MOD_DATA" ]; then
                while IFS= read -r line; do
                    [ -n "$line" ] && { RAW_RESULTS+=("$line"); ((MOD_TOTAL++)); }
                done <<< "$MOD_DATA"
            fi
            local MOD_COMP=$(echo "$MOD_RES" | jq -r '._aMetadata._bIsComplete // true' 2>/dev/null)
            if [ "$MOD_COMP" == "true" ] || [ -z "$MOD_DATA" ] || [ "$MOD_PAGE" -ge "$MAX_PAGES" ]; then
                MOD_DONE=true
            else
                ((MOD_PAGE++))
            fi
        fi
    done

    if [ ${#RAW_RESULTS[@]} -eq 0 ]; then
        pause_msg "No results found matching '$QUERY'."
        return
    fi

    progress_msg "Searching" "Collected ${#RAW_RESULTS[@]} results.\n\nSorting by view count..."

    # Sort by view count, numeric, descending.
    local ALL_SEARCH_LINES=()
    readarray -t ALL_SEARCH_LINES < <(printf '%s\n' "${RAW_RESULTS[@]}" | sort -t '|' -k1,1 -nr)

    local TOTAL_RESULTS=${#ALL_SEARCH_LINES[@]}
    local ITEMS_PER_PAGE=15
    local TOTAL_PAGES=$(( (TOTAL_RESULTS + ITEMS_PER_PAGE - 1) / ITEMS_PER_PAGE ))
    local CURRENT_PAGE=1

    while true; do
        local START_IDX=$(( (CURRENT_PAGE - 1) * ITEMS_PER_PAGE ))
        local END_IDX=$(( START_IDX + ITEMS_PER_PAGE - 1 ))
        if [ "$END_IDX" -ge "$TOTAL_RESULTS" ]; then END_IDX=$(( TOTAL_RESULTS - 1 )); fi

        local MENU_ARGS=()
        for i in $(seq "$START_IDX" "$END_IDX"); do
            IFS='|' read -r VIEWS SUBMITTER TYPE ID NAME <<< "${ALL_SEARCH_LINES[$i]}"

            if ! [[ "$VIEWS" =~ ^[0-9]+$ ]]; then VIEWS=0; fi

            local TRUNC_NAME="${NAME:0:30}"
            local TRUNC_SUBMITTER="${SUBMITTER:0:15}"

            local FORMATTED_ITEM
            FORMATTED_ITEM=$(printf "%-30s %-15s | %7d Vws" "$TRUNC_NAME" "$TRUNC_SUBMITTER" "$VIEWS")

            MENU_ARGS+=("$ID" "$FORMATTED_ITEM")
        done

        if [ "$CURRENT_PAGE" -lt "$TOTAL_PAGES" ]; then MENU_ARGS+=("NEXT" "--> Next Page"); fi
        if [ "$CURRENT_PAGE" -gt 1 ]; then MENU_ARGS+=("PREV" "<-- Previous Page"); fi

        # Leading spaces account for the whiptail tag (ID) column so the header columns
        # line up with the formatted item columns above.
        local HEADER="ID         NAME                           SUBMITTER       |   VIEWS"
        local MENU_TEXT="Page $CURRENT_PAGE of $TOTAL_PAGES ($TOTAL_RESULTS total)\n\n$HEADER\n------------------------------------------------------------------"

        SEL=$(whiptail --backtitle "$BACKTITLE" --title " Search Results: '$QUERY' " --menu "$MENU_TEXT" 22 78 12 "${MENU_ARGS[@]}" 3>&1 1>&2 2>&3)
        
        if [ $? -ne 0 ]; then return; fi

        if [[ "$SEL" == "NEXT" ]]; then ((CURRENT_PAGE++))
        elif [[ "$SEL" == "PREV" ]]; then ((CURRENT_PAGE--))
        else
            for line in "${ALL_SEARCH_LINES[@]}"; do
                IFS='|' read -r T_VIEWS T_SUB T_TYPE T_ID T_NAME <<< "$line"
                if [[ "$T_ID" == "$SEL" ]]; then
                    local URL_TYPE=$(echo "${T_TYPE}s" | tr '[:upper:]' '[:lower:]')
                    install_item "$T_TYPE" "$T_ID" "https://gamebanana.com/${URL_TYPE}/$T_ID"
                    break
                fi
            done
        fi
    done
}

menu_url() {
    GB_URL=$(whiptail --backtitle "$BACKTITLE" --title " Install from URL " --inputbox "\nPaste the full GameBanana URL:" 14 75 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$GB_URL" ]; then return; fi

    if [[ ! "$GB_URL" =~ gamebanana\.com/([a-zA-Z]+)/([0-9]+) ]]; then
        pause_msg "Invalid URL format."
        return
    fi
    local ITEM_TYPE=$(echo "${BASH_REMATCH[1]}" | sed 's/s$//' | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
    install_item "$ITEM_TYPE" "${BASH_REMATCH[2]}" "$GB_URL"
}

# ==========================================
# MENU: VIEW & UNINSTALL
# ==========================================
menu_uninstall() {
    if [ ! -s "$INSTALLED_LIST" ]; then
        pause_msg "No content is currently installed."
        return
    fi

    while true; do
        readarray -t LINES < "$INSTALLED_LIST"
        if [ ${#LINES[@]} -eq 0 ]; then return; fi

        local MENU_ARGS=()
        for i in "${!LINES[@]}"; do
            IFS='|' read -r ID NAME URL <<< "${LINES[$i]}"
            local FCOUNT="?"
            [ -f "$DB_DIR/${ID}.files" ] && FCOUNT=$(wc -l < "$DB_DIR/${ID}.files")
            MENU_ARGS+=("$ID" "$(printf '%-48s (%s files)' "${NAME:0:48}" "$FCOUNT")")
        done

        SEL=$(whiptail --backtitle "$BACKTITLE" --title " Installed Content (${#LINES[@]}) " --menu "Select an installed item:" 22 78 12 "${MENU_ARGS[@]}" 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then return; fi

        # Find the selection in LINES.
        local SEL_IDX=-1 SEL_NAME="" SEL_URL=""
        for i in "${!LINES[@]}"; do
            IFS='|' read -r ID NAME URL <<< "${LINES[$i]}"
            if [[ "$ID" == "$SEL" ]]; then
                SEL_IDX="$i"; SEL_NAME="$NAME"; SEL_URL="$URL"; break
            fi
        done
        [ "$SEL_IDX" -lt 0 ] && continue

        local ACTION
        ACTION=$(whiptail --backtitle "$BACKTITLE" --title " $SEL_NAME " --menu "What would you like to do?" 17 72 5 \
            "DETAILS"   "Show details" \
            "REINSTALL" "Reinstall / Update from GameBanana" \
            "UNINSTALL" "Uninstall (delete files)" \
            "BACK"      "Back" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && continue

        case "$ACTION" in
            DETAILS)
                local FCOUNT="?" DCOUNT="?"
                [ -f "$DB_DIR/${SEL}.files" ] && FCOUNT=$(wc -l < "$DB_DIR/${SEL}.files")
                [ -f "$DB_DIR/${SEL}.dirs"  ] && DCOUNT=$(wc -l < "$DB_DIR/${SEL}.dirs")
                pause_msg "Name : $SEL_NAME\nID   : $SEL\nURL  : $SEL_URL\nFiles: $FCOUNT\nDirs : $DCOUNT"
                ;;
            REINSTALL)
                if [[ "$SEL_URL" =~ gamebanana\.com/([a-zA-Z]+)/([0-9]+) ]]; then
                    local ITEM_TYPE
                    ITEM_TYPE=$(echo "${BASH_REMATCH[1]}" | sed 's/s$//' | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
                    # Remove old files first to avoid orphan leftovers, then install fresh.
                    uninstall_files "$SEL"
                    sed -i "$((SEL_IDX+1))d" "$INSTALLED_LIST"
                    install_item "$ITEM_TYPE" "$SEL" "$SEL_URL" 1
                else
                    pause_msg "Stored URL is not parseable: $SEL_URL"
                fi
                ;;
            UNINSTALL)
                if whiptail --backtitle "$BACKTITLE" --title " Confirm Uninstall " --yesno "\nDelete '$SEL_NAME' from your content folder?" 12 70; then
                    clear
                    echo -e "\n \033[1;31m[x]\033[0m Uninstalling: \033[1;37m$SEL_NAME\033[0m..."
                    uninstall_files "$SEL"
                    sed -i "$((SEL_IDX+1))d" "$INSTALLED_LIST"
                    echo -e " \033[1;32m[✓]\033[0m Successfully uninstalled."
                    sleep 2
                fi
                ;;
        esac
    done
}

# Remove files+dirs tracked for a given item ID. Does NOT touch $INSTALLED_LIST.
uninstall_files() {
    local ID="$1"
    if [ -f "$DB_DIR/${ID}.files" ]; then
        while read -r f; do [ -n "$f" ] && rm -f "$EXTRACT_DIR/$f"; done < "$DB_DIR/${ID}.files"
    fi
    if [ -f "$DB_DIR/${ID}.dirs" ]; then
        # Dirs file is already sorted deepest-first (-r).
        while read -r d; do
            if [ -n "$d" ] && [ "$d" != "." ]; then
                rmdir "$EXTRACT_DIR/$d" 2>/dev/null || true
            fi
        done < "$DB_DIR/${ID}.dirs"
    fi
    rm -f "$DB_DIR/${ID}.files" "$DB_DIR/${ID}.dirs"
}

# ==========================================
# MENU: IMPORT / EXPORT
# ==========================================
menu_export() {
    if [ ! -s "$INSTALLED_LIST" ]; then
        pause_msg "Nothing to export! Install some content first."
        return
    fi

    EXPORT_PATH=$(whiptail --backtitle "$BACKTITLE" --title " Export List " --inputbox "\nEnter full path to save the list (one URL per line):" 14 75 "$HOME/gb_export_list.txt" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$EXPORT_PATH" ]; then return; fi

    # Export the source URL (field 3), which is what menu_import expects.
    awk -F'|' '{print $3}' "$INSTALLED_LIST" > "$EXPORT_PATH"
    local COUNT
    COUNT=$(wc -l < "$EXPORT_PATH")
    pause_msg "Success! Exported $COUNT URL(s) to:\n$EXPORT_PATH"
}

menu_import() {
    IMPORT_PATH=$(whiptail --backtitle "$BACKTITLE" --title " Import List " --inputbox "\nEnter full path to the text file (one GameBanana URL per line):" 14 75 "$HOME/gb_export_list.txt" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$IMPORT_PATH" ]; then return; fi

    if [ ! -f "$IMPORT_PATH" ]; then
        pause_msg "Error: File not found at '$IMPORT_PATH'."
        return
    fi

    # Pre-count valid URLs for progress display.
    local TOTAL
    TOTAL=$(grep -cE 'gamebanana\.com/[a-zA-Z]+/[0-9]+' "$IMPORT_PATH")
    if [ "$TOTAL" -eq 0 ]; then
        pause_msg "No GameBanana URLs found in:\n$IMPORT_PATH"
        return
    fi

    local IDX=0
    local OK=0
    local SKIP=0
    while IFS= read -r url; do
        [ -z "$url" ] && continue
        if [[ "$url" =~ gamebanana\.com/([a-zA-Z]+)/([0-9]+) ]]; then
            ((IDX++))
            local ITEM_TYPE
            ITEM_TYPE=$(echo "${BASH_REMATCH[1]}" | sed 's/s$//' | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
            local ITEM_ID="${BASH_REMATCH[2]}"
            echo -e "\n\033[1;36m[$IDX/$TOTAL]\033[0m Processing $ITEM_TYPE $ITEM_ID"
            if grep -q "^${ITEM_ID}|" "$INSTALLED_LIST" 2>/dev/null; then
                echo -e " \033[1;33m[↷]\033[0m Already installed, skipping."
                ((SKIP++))
                continue
            fi
            if install_item "$ITEM_TYPE" "$ITEM_ID" "$url"; then
                ((OK++))
            fi
        fi
    done < "$IMPORT_PATH"

    pause_msg "Batch Import Complete!\n\nProcessed : $IDX\nInstalled : $OK\nSkipped   : $SKIP"
}

# ==========================================
# API GAME SELECTION (PAGINATED & SEARCHABLE)
# ==========================================
RET_GAME_ID=""
menu_select_game() {
    RET_GAME_ID=""
    local API_PAGE=1
    local ITEMS_PER_PAGE=50
    local SEARCH_QUERY=""
    local SEARCH_QUERY_ENC=""

    while true; do
        local URL=""
        if [ -n "$SEARCH_QUERY" ]; then
            whiptail --backtitle "$BACKTITLE" --title " Loading " --infobox "\nSearching games for '$SEARCH_QUERY' (Page $API_PAGE)..." 10 65
            URL="https://gamebanana.com/apiv11/Util/Search/Results?_sModelName=Game&_sSearchString=${SEARCH_QUERY_ENC}&_nPage=${API_PAGE}&_nPerpage=${ITEMS_PER_PAGE}"
        else
            whiptail --backtitle "$BACKTITLE" --title " Loading " --infobox "\nFetching games page $API_PAGE from GameBanana..." 10 65
            URL="https://gamebanana.com/apiv11/Game/Index?_nPage=${API_PAGE}&_nPerpage=${ITEMS_PER_PAGE}"
        fi

        local RES=$(curl -s -A "$USER_AGENT" -H "Accept: application/json" "$URL")

        local GAME_DATA=$(echo "$RES" | jq -r '._aRecords[]? | "\((._idRow // .id))|\((._sName // .name))"' 2>/dev/null)
        local IS_COMPLETE=$(echo "$RES" | jq -r '._aMetadata._bIsComplete // true' 2>/dev/null)

        local MENU_ARGS=()
        while IFS='|' read -r G_ID G_NAME; do
            if [ -n "$G_ID" ] && [ "$G_ID" != "null" ]; then
                MENU_ARGS+=("$G_ID" "${G_NAME:0:55}")
            fi
        done <<< "$GAME_DATA"

        if [ ${#MENU_ARGS[@]} -eq 0 ] && [ -n "$SEARCH_QUERY" ]; then
            pause_msg "No games found matching '$SEARCH_QUERY'."
            SEARCH_QUERY=""
            SEARCH_QUERY_ENC=""
            API_PAGE=1
            continue
        fi

        if [ "$IS_COMPLETE" != "true" ] && [ -n "$GAME_DATA" ]; then
            MENU_ARGS+=("NEXT" "--> Next Page")
        fi
        if [ "$API_PAGE" -gt 1 ]; then
            MENU_ARGS+=("PREV" "<-- Previous Page")
        fi
        
        MENU_ARGS+=("SEARCH" "[?] Search Game Title")
        
        if [ -n "$SEARCH_QUERY" ]; then
            MENU_ARGS+=("CLEAR" "[x] Clear Search")
        fi

        MENU_ARGS+=("CUSTOM" "[!] Enter Custom Game ID")
        MENU_ARGS+=("CANCEL" "Cancel")

        local TITLE=" Game Selection (Page $API_PAGE) "
        if [ -n "$SEARCH_QUERY" ]; then
            TITLE=" Search: '$SEARCH_QUERY' (Page $API_PAGE) "
        fi

        SEL=$(whiptail --backtitle "$BACKTITLE" --title "$TITLE" --menu "Select a game:" 22 75 12 "${MENU_ARGS[@]}" 3>&1 1>&2 2>&3)

        if [ $? -ne 0 ] || [[ "$SEL" == "CANCEL" ]]; then return 1; fi

        if [[ "$SEL" == "NEXT" ]]; then
            ((API_PAGE++))
        elif [[ "$SEL" == "PREV" ]]; then
            ((API_PAGE--))
        elif [[ "$SEL" == "SEARCH" ]]; then
            NEW_QUERY=$(whiptail --backtitle "$BACKTITLE" --title " Search Games " --inputbox "\nEnter game title to search for:" 14 65 3>&1 1>&2 2>&3)
            if [ $? -eq 0 ] && [ -n "$NEW_QUERY" ]; then
                SEARCH_QUERY="$NEW_QUERY"
                SEARCH_QUERY_ENC=$(urlencode "$SEARCH_QUERY")
                API_PAGE=1
            fi
        elif [[ "$SEL" == "CLEAR" ]]; then
            SEARCH_QUERY=""
            SEARCH_QUERY_ENC=""
            API_PAGE=1
        elif [[ "$SEL" == "CUSTOM" ]]; then
            NEW_GAME=$(whiptail --backtitle "$BACKTITLE" --title " Custom Game ID " --inputbox "\nEnter numeric Game ID:" 14 65 3>&1 1>&2 2>&3)
            if [[ "$NEW_GAME" =~ ^[0-9]+$ ]]; then
                RET_GAME_ID="$NEW_GAME"
                return 0
            fi
        else
            RET_GAME_ID="$SEL"
            return 0
        fi
    done
}

# ==========================================
# SUBMENUS
# ==========================================
submenu_install() {
    while true; do
        CHOICE=$(whiptail --backtitle "$BACKTITLE" --title " Install Menu " --menu "Select an option:" 18 70 5 \
            "1" "Search & Install" \
            "2" "Install from URL" \
            "3" "Import List (Batch Install)" \
            "4" "Export List (Backup)" \
            "0" "Back to Main Menu" 3>&1 1>&2 2>&3)
        
        if [ $? -ne 0 ]; then return; fi
        case $CHOICE in
            1) menu_search ;;
            2) menu_url ;;
            3) menu_import ;;
            4) menu_export ;;
            0) return ;;
        esac
    done
}

submenu_config() {
    while true; do
        CHOICE=$(whiptail --backtitle "$BACKTITLE" --title " Configuration " --menu "Modify script settings\nSaved at: $CONFIG_FILE" 20 85 5 \
            "1" "Change Target Game ID   (Current: $GAME_ID)" \
            "2" "Change Content Folder   (Current: $EXTRACT_DIR)" \
            "3" "Change Database Folder  (Current: $DB_DIR)" \
            "0" "Back to Main Menu" 3>&1 1>&2 2>&3)
        
        if [ $? -ne 0 ]; then return; fi
        case $CHOICE in
            1)
                menu_select_game
                if [ -n "$RET_GAME_ID" ]; then
                    GAME_ID="$RET_GAME_ID"
                    save_config
                    pause_msg "Target Game ID updated to: $GAME_ID"
                fi
                ;;
            2)
                NEW_DIR=$(whiptail --backtitle "$BACKTITLE" --title " Content Folder " --inputbox "\nEnter the absolute path to your game's content folder:" 14 80 "$EXTRACT_DIR" 3>&1 1>&2 2>&3)
                if [ $? -eq 0 ] && [ -n "$NEW_DIR" ]; then
                    EXTRACT_DIR="$NEW_DIR"
                    save_config
                    pause_msg "Content Folder updated to:\n$EXTRACT_DIR"
                fi
                ;;
            3)
                NEW_DB=$(whiptail --backtitle "$BACKTITLE" --title " Database Folder " --inputbox "\nEnter the absolute path for the script's tracking files:" 14 80 "$DB_DIR" 3>&1 1>&2 2>&3)
                if [ $? -eq 0 ] && [ -n "$NEW_DB" ]; then
                    DB_DIR="$NEW_DB"
                    save_config
                    pause_msg "Database Folder updated to:\n$DB_DIR"
                fi
                ;;
            0) return ;;
        esac
    done
}

# ==========================================
# MAIN MENU LOOP
# ==========================================
while true; do
    CHOICE=$(whiptail --backtitle "$BACKTITLE" --title " Main Menu " --menu "Select an option:" 18 75 5 \
        "1" "Install / Import Content" \
        "2" "Uninstall / View Content" \
        "3" "Configuration / Settings" \
        "4" "Exit" 3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ]; then clear; exit 0; fi

    case $CHOICE in
        1) submenu_install ;;
        2) menu_uninstall ;; 
        3) submenu_config ;;
        4) clear; exit 0 ;;
    esac
done
