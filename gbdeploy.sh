#!/bin/bash
# ==========================================
# GameBanana Deployment Suite © 2026 BONE
# ==========================================

# ==========================================
# DEPENDENCY CHECKS
# ==========================================
for cmd in curl jq tr awk sed find whiptail; do
    if ! command -v "$cmd" &> /dev/null; then
        echo -e "\033[0;31m [!] Error: '$cmd' is required but not installed.\033[0m"
        echo "Please install it (e.g., sudo apt install whiptail jq curl)"
        exit 1
    fi
done

if ! command -v 7zz &> /dev/null && ! command -v 7z &> /dev/null; then
    echo -e "\033[0;31m [!] Error: 7-Zip is not installed. Please install '7zip' or 'p7zip-full'.\033[0m"
    exit 1
fi

# ==========================================
# CONFIGURATION & THEME
# ==========================================
CONFIG_FILE="$HOME/.config/gb_manager.conf"
USER_AGENT="GameBanana-Manager/3.2 (Bash/Whiptail-Advanced)"

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
    # Using a literal newline for the two-row top header
    BACKTITLE=" GameBanana Deployment Suite © 2026 BONE | Target Game: $GAME_ID"$'\n'" Content Path: $EXTRACT_DIR "
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
    local length="${#1}"
    for (( i = 0; i < length; i++ )); do
        local c="${1:i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf "$c" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done
}

pause_msg() {
    whiptail --backtitle "$BACKTITLE" --title " Information " --msgbox "\n$1" 14 65
}

# ==========================================
# CORE INSTALLER LOGIC
# ==========================================
install_item() {
    local TYPE="$1"
    local ID="$2"
    local SOURCE_URL="$3"

    clear
    echo -e "\n \033[1;36m::\033[0m \033[1;37mInstalling Content\033[0m"
    echo -e " \033[1;34m====================================================\033[0m\n"

    if grep -q "^${ID}|" "$INSTALLED_LIST" 2>/dev/null; then
        echo -e " \033[1;33m[!] Notice: Item ID $ID is already installed. Skipping...\033[0m"
        sleep 2
        return
    fi

    echo -e " \033[1;34m[i]\033[0m Fetching metadata for $TYPE ID: $ID..."

    local API_URL="https://api.gamebanana.com/Core/Item/Data?itemtype=${TYPE}&itemid=${ID}&fields=name,Files().aFiles()"
    local RESPONSE=$(curl -s -A "$USER_AGENT" "$API_URL")

    if [[ "$RESPONSE" == "null" || -z "$RESPONSE" ]]; then
        echo -e " \033[1;31m[x] Error: Received empty response. Invalid ID or API down.\033[0m"
        sleep 3; return
    fi

    local ITEM_NAME=$(echo "$RESPONSE" | jq -r '.[0]' 2>/dev/null)
    readarray -t FILES < <(echo "$RESPONSE" | jq -r '.[1] | to_entries[] | .value._sFile' 2>/dev/null)
    readarray -t URLS < <(echo "$RESPONSE" | jq -r '.[1] | to_entries[] | .value._sDownloadUrl' 2>/dev/null)

    if [ ${#FILES[@]} -eq 0 ] || [ -z "${FILES[0]}" ]; then
        echo -e " \033[1;31m[x] Error: No valid downloads found for this item.\033[0m"
        sleep 3; return
    fi

    local SELECTED_URL="${URLS[0]}"
    local SELECTED_FILE="${FILES[0]}"

    echo -e " \033[1;32m[✓]\033[0m Found: \033[1;37m$ITEM_NAME\033[0m"
    echo -e " \033[1;36m[↓]\033[0m Downloading \033[0;37m($SELECTED_FILE)\033[0m..."
    
    local DL_TMP_DIR=$(mktemp -d)
    local EXTRACT_TMP_DIR=$(mktemp -d)
    
    curl -L -# -A "$USER_AGENT" "$SELECTED_URL" -o "$DL_TMP_DIR/$SELECTED_FILE" | sed 's/^/     /'

    echo -e " \033[1;33m[⚙]\033[0m Extracting files..."
    if command -v 7zz &> /dev/null; then
        7zz x "$DL_TMP_DIR/$SELECTED_FILE" -o"$EXTRACT_TMP_DIR" -y > /dev/null
    else
        7z x "$DL_TMP_DIR/$SELECTED_FILE" -o"$EXTRACT_TMP_DIR" -y > /dev/null
    fi

    echo -e " \033[1;35m[⟳]\033[0m Moving to content directory..."
    find "$EXTRACT_TMP_DIR" -depth | while read -r path; do
        if [ "$path" == "$EXTRACT_TMP_DIR" ]; then continue; fi
        dir=$(dirname "$path")
        base=$(basename "$path")
        lower_base=$(echo "$base" | tr '[:upper:]' '[:lower:]')
        if [ "$base" != "$lower_base" ]; then
            mv "$path" "$dir/$lower_base" 2>/dev/null
        fi
    done

    find "$EXTRACT_TMP_DIR" -type f -printf "%P\n" > "$DB_DIR/${ID}.files"
    find "$EXTRACT_TMP_DIR" -type d -printf "%P\n" | sort -r > "$DB_DIR/${ID}.dirs"

    cp -a "$EXTRACT_TMP_DIR/." "$EXTRACT_DIR/"
    echo "${ID}|${ITEM_NAME}|${SOURCE_URL}" >> "$INSTALLED_LIST"
    
    rm -rf "$DL_TMP_DIR" "$EXTRACT_TMP_DIR"

    echo -e "\n \033[1;32m[★] Install complete.\033[0m"
    sleep 2
}

# ==========================================
# MENU: SEARCH & INSTALL
# ==========================================
menu_search() {
    QUERY=$(whiptail --backtitle "$BACKTITLE" --title " Search " --inputbox "\nEnter search query (Game ID $GAME_ID):" 14 65 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$QUERY" ]; then return; fi

    local QUERY_ENC=$(urlencode "$QUERY")
    
    whiptail --backtitle "$BACKTITLE" --title " Searching " --infobox "\nFetching results from GameBanana...\nPlease wait." 12 65
    
    local API_PAGE=1
    local MAP_DONE=false
    local MOD_DONE=false
    ALL_SEARCH_LINES=()

    while [ "$MAP_DONE" = false ] || [ "$MOD_DONE" = false ]; do
        if [ "$MAP_DONE" = false ]; then
            local URL_MAP="https://gamebanana.com/apiv11/Util/Search/Results?_sModelName=Map&_idGameRow=${GAME_ID}&_sSearchString=${QUERY_ENC}&_nPage=${API_PAGE}&_nPerpage=50"
            local MAP_RES=$(curl -s -A "$USER_AGENT" -H "Accept: application/json" "$URL_MAP")
            local MAP_DATA=$(echo "$MAP_RES" | jq -r '._aRecords[]? | "Map|\(._idRow // .id)|\(._sName // .name)"' 2>/dev/null)
            if [ -n "$MAP_DATA" ]; then
                while IFS= read -r line; do [ -n "$line" ] && ALL_SEARCH_LINES+=("$line"); done <<< "$MAP_DATA"
            fi
            local M_COMP=$(echo "$MAP_RES" | jq -r '._aMetadata._bIsComplete // true' 2>/dev/null)
            if [ "$M_COMP" == "true" ] || [ -z "$MAP_DATA" ]; then MAP_DONE=true; fi
        fi

        if [ "$MOD_DONE" = false ]; then
            local URL_MOD="https://gamebanana.com/apiv11/Util/Search/Results?_sModelName=Mod&_idGameRow=${GAME_ID}&_sSearchString=${QUERY_ENC}&_nPage=${API_PAGE}&_nPerpage=50"
            local MOD_RES=$(curl -s -A "$USER_AGENT" -H "Accept: application/json" "$URL_MOD")
            local MOD_DATA=$(echo "$MOD_RES" | jq -r '._aRecords[]? | "Mod|\(._idRow // .id)|\(._sName // .name)"' 2>/dev/null)
            if [ -n "$MOD_DATA" ]; then
                while IFS= read -r line; do [ -n "$line" ] && ALL_SEARCH_LINES+=("$line"); done <<< "$MOD_DATA"
            fi
            local MOD_COMP=$(echo "$MOD_RES" | jq -r '._aMetadata._bIsComplete // true' 2>/dev/null)
            if [ "$MOD_COMP" == "true" ] || [ -z "$MOD_DATA" ]; then MOD_DONE=true; fi
        fi
        ((API_PAGE++))
        if [ "$API_PAGE" -gt 5 ]; then break; fi
    done

    local TOTAL_RESULTS=${#ALL_SEARCH_LINES[@]}
    if [ "$TOTAL_RESULTS" -eq 0 ]; then
        pause_msg "No results found matching '$QUERY'."
        return
    fi

    local ITEMS_PER_PAGE=15
    local TOTAL_PAGES=$(( (TOTAL_RESULTS + ITEMS_PER_PAGE - 1) / ITEMS_PER_PAGE ))
    local CURRENT_PAGE=1

    while true; do
        local START_IDX=$(( (CURRENT_PAGE - 1) * ITEMS_PER_PAGE ))
        local END_IDX=$(( START_IDX + ITEMS_PER_PAGE - 1 ))
        if [ "$END_IDX" -ge "$TOTAL_RESULTS" ]; then END_IDX=$(( TOTAL_RESULTS - 1 )); fi

        local MENU_ARGS=()
        for i in $(seq "$START_IDX" "$END_IDX"); do
            IFS='|' read -r TYPE ID NAME <<< "${ALL_SEARCH_LINES[$i]}"
            MENU_ARGS+=("$ID" "[${TYPE}] ${NAME:0:55}")
        done

        if [ "$CURRENT_PAGE" -lt "$TOTAL_PAGES" ]; then MENU_ARGS+=("NEXT" "--> Next Page"); fi
        if [ "$CURRENT_PAGE" -gt 1 ]; then MENU_ARGS+=("PREV" "<-- Previous Page"); fi

        SEL=$(whiptail --backtitle "$BACKTITLE" --title " Search Results: '$QUERY' " --menu "Page $CURRENT_PAGE of $TOTAL_PAGES ($TOTAL_RESULTS total)" 26 85 15 "${MENU_ARGS[@]}" 3>&1 1>&2 2>&3)
        
        if [ $? -ne 0 ]; then return; fi

        if [[ "$SEL" == "NEXT" ]]; then ((CURRENT_PAGE++))
        elif [[ "$SEL" == "PREV" ]]; then ((CURRENT_PAGE--))
        else
            for line in "${ALL_SEARCH_LINES[@]}"; do
                IFS='|' read -r TARGET_TYPE TARGET_ID TARGET_NAME <<< "$line"
                if [[ "$TARGET_ID" == "$SEL" ]]; then
                    local URL_TYPE=$(echo "${TARGET_TYPE}s" | tr '[:upper:]' '[:lower:]')
                    install_item "$TARGET_TYPE" "$TARGET_ID" "https://gamebanana.com/${URL_TYPE}/$TARGET_ID"
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
            MENU_ARGS+=("$ID" "${NAME:0:60}")
        done

        SEL=$(whiptail --backtitle "$BACKTITLE" --title " Installed Content " --menu "Select an item to completely uninstall:" 26 85 15 "${MENU_ARGS[@]}" 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then return; fi

        for i in "${!LINES[@]}"; do
            IFS='|' read -r ID NAME URL <<< "${LINES[$i]}"
            if [[ "$ID" == "$SEL" ]]; then
                if whiptail --backtitle "$BACKTITLE" --title " Confirm Uninstall " --yesno "\nAre you sure you want to delete:\n\n'$NAME'\n\nThis will remove it from your content folder." 16 70; then
                    clear
                    echo -e "\n \033[1;31m[x]\033[0m Uninstalling: \033[1;37m$NAME\033[0m..."
                    
                    if [ -f "$DB_DIR/${ID}.files" ]; then
                        while read -r f; do [ -n "$f" ] && rm -f "$EXTRACT_DIR/$f"; done < "$DB_DIR/${ID}.files"
                    fi
                    
                    if [ -f "$DB_DIR/${ID}.dirs" ]; then
                        while read -r d; do 
                            if [ -n "$d" ] && [ "$d" != "." ]; then rmdir "$EXTRACT_DIR/$d" 2>/dev/null; fi
                        done < "$DB_DIR/${ID}.dirs"
                    fi
                    
                    rm -f "$DB_DIR/${ID}.files" "$DB_DIR/${ID}.dirs"
                    sed -i "$((i+1))d" "$INSTALLED_LIST"
                    echo -e " \033[1;32m[✓]\033[0m Successfully uninstalled."
                    sleep 2
                fi
                break
            fi
        done
    done
}

# ==========================================
# MENU: IMPORT / EXPORT
# ==========================================
menu_export() {
    if [ ! -s "$INSTALLED_LIST" ]; then
        pause_msg "Nothing to export! Install some content first."
        return
    fi
    
    EXPORT_PATH=$(whiptail --backtitle "$BACKTITLE" --title " Export List " --inputbox "\nEnter full path to save the text file:" 14 75 "$HOME/gb_export_list.txt" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$EXPORT_PATH" ]; then return; fi

    cut -d'|' -f3 "$INSTALLED_LIST" > "$EXPORT_PATH"
    pause_msg "Success!\n\nYour list has been saved to:\n$EXPORT_PATH"
}

menu_import() {
    IMPORT_PATH=$(whiptail --backtitle "$BACKTITLE" --title " Import List " --inputbox "\nEnter full path to the text file:" 14 75 "$HOME/gb_export_list.txt" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$IMPORT_PATH" ]; then return; fi

    if [ ! -f "$IMPORT_PATH" ]; then
        pause_msg "Error: File not found at '$IMPORT_PATH'."
        return
    fi

    while IFS= read -r url; do
        [ -z "$url" ] && continue
        if [[ "$url" =~ gamebanana\.com/([a-zA-Z]+)/([0-9]+) ]]; then
            local ITEM_TYPE=$(echo "${BASH_REMATCH[1]}" | sed 's/s$//' | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
            local ITEM_ID="${BASH_REMATCH[2]}"
            install_item "$ITEM_TYPE" "$ITEM_ID" "$url"
        fi
    done < "$IMPORT_PATH"

    pause_msg "Batch Import Complete!"
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

        SEL=$(whiptail --backtitle "$BACKTITLE" --title "$TITLE" --menu "Select a game:" 24 75 15 "${MENU_ARGS[@]}" 3>&1 1>&2 2>&3)

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
