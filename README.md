# GameBanana Deployment Suite

A terminal-based package manager and deployment suite for [GameBanana](https://gamebanana.com/). Written in Bash and utilizing `whiptail` for an intuitive TUI (Text User Interface).
This tool allows you to search, download, install, and manage mods and maps for thousands of games directly from your Linux CLI.

© 2026 BONE

## ✨ Features

* **Direct API Integration:** Search for and install maps and mods natively without leaving the terminal.
* **Smart Game Selection:** Dynamically search and paginate through GameBanana's entire library of supported games to set your target environment.
* **URL Installation:** Paste a GameBanana item URL directly to fetch, extract, and deploy it.
* **Clean Uninstalls:** The suite tracks exactly which files and directories are added during installation, allowing for 100% clean uninstalls without leaving junk behind in your game folders.
* **Import / Export (Batch Deploy):** Export your installed mod list to a text file, or import a list of URLs to batch-install an entire modpack at once.
* **Custom UI Theme:** Features a clean, custom "Flat Dark Mode" Whiptail theme for easy reading.

## 📦 Dependencies

The script relies on a few common Linux utilities to handle API requests, parse JSON, extract archives, and render the UI. 

Make sure the following are installed on your system:
* `curl` (for API requests and downloading files)
* `jq` (for parsing JSON responses)
* `whiptail` (for the interactive menu UI)
* `7z` or `7zz` (7-Zip, for extracting downloaded `.zip`, `.rar`, and `.7z` files)
* `unrar` for RAR compression
* Standard GNU coreutils (`tr`, `awk`, `sed`, `find`)

**Debian / Ubuntu Installation:**
```bash
sudo apt update
sudo apt install curl jq whiptail p7zip-full
(Note: standard coreutils like sed, awk, and find are usually pre-installed on most Linux distributions).
```
🚀 How to Run & Initial Setup
Make the script executable:


```bash
chmod +x gb_manager.sh
```
Launch the suite:

```bash
./gb_manager.sh
```

⚠️ IMPORTANT: Initial Configuration
Before deploying any mods or maps, you must configure the script so it knows which game you are modding and where to put the files.

When you run the script for the first time, navigate to 3. Configuration / Settings from the Main Menu and set the following:

Change Target Game ID: * Select this option to browse or search the GameBanana API for your specific game (e.g., Counter-Strike 1.6, Half-Life, Celeste). Setting this ensures the in-app search only pulls mods for your game.

Change Content Folder: * Provide the absolute path to your game's content/mod directory.

Example: ```/home/user/.steam/steam/steamapps/common/Half-Life/cstrike/```

This is where all downloaded files will be extracted.

Change Database Folder: * Provide an absolute path to a folder where the script will store its tracking files (this defaults to ~/map_manager). This database tracks installed files so they can be safely uninstalled later.

Once these three settings are configured, you can return to the Main Menu and safely begin searching for and installing content!
