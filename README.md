# Custom Chat Colors Menu (CCCM)

A SourceMod plugin that provides a comprehensive menu system for managing custom chat colors and tags. This version is built upon JoinedSenses' fork of the original plugin by ReFlexPoison, with additional tag text management features.


## Features

- In-game menu system for managing chat customization (`!ccc`)
- Color customization for:
  - Tags
  - Names 
  - Chat messages
- Tag management:
  - Toggle tag visibility
  - Change tag colors
  - Change tag text
- MySQL/SQLite support for persistent settings
- Admin flag-based color restrictions
- Command-based direct color changes

## Commands

### Admin Commands
- `sm_ccc` - Opens the main chat colors menu
- `sm_reload_cccm` - Reloads the plugin configuration
- `sm_tagcolor <hex>` - Sets tag color directly
- `sm_tagtext <text>` - Sets tag text directly
- `sm_namecolor <hex>` - Sets name color directly 
- `sm_chatcolor <hex>` - Sets chat color directly

### User Commands
- `sm_resettag` - Resets tag color to default
- `sm_resetname` - Resets name color to default
- `sm_resetchat` - Resets chat color to default

## ConVars
```
sm_cccm_enabled "15" - Enable/disable features (Add numbers)
0 = Disabled
1 = Tag
2 = Name  
4 = Chat
8 = Hide Tag
```

## Installation

1. Download the zip from the latest release
2. Copy plugin files to your SourceMod installation
3. Configure your database in `addons/sourcemod/configs/databases.cfg`
4. Load the plugin or restart your server

## Database Configuration

Add to your `databases.cfg`:
```
"cccm"
{
    "driver"    "mysql" // or sqlite
    "host"      "localhost"
    "database"  "your_database"
    "user"      "your_username"
    "pass"      "your_password"
}
```

## Requirements

- SourceMod 1.11 or higher
- Custom Chat Colors (CCC) base plugin
- MySQL or SQLite (**optional for persistent storage, plugin will fallback to original `custom-chatcolors.cfg` file**)
