# Custom Chat Colors Menu

A SourceMod plugin that allows players to customize their chat appearance with colored tags, name colors, and chat text colors. All preferences are saved in a database and automatically applied when players rejoin the server.

## Installation

1. Upload all files to your server's `addons/sourcemod` directory
2. Configure a database connection named "cccm" in your `databases.cfg` file
3. Restart your server

## Usage

- Players can use the `!ccc` command to open the customization menu
- Admins can control which features are available to different player groups via admin flags

## Configuration

The plugin creates a `cccm.cfg` file in your `cfg/sourcemod` directory with the following settings:

```
// Admin flag required to modify tag text. Leave empty for public access.
sm_cccm_tag_text_flag ""

// Admin flag required to modify tag color. Leave empty for public access.
sm_cccm_tag_color_flag ""

// Admin flag required to modify name color. Leave empty for public access.
sm_cccm_name_color_flag ""

// Admin flag required to modify chat color. Leave empty for public access.
sm_cccm_chat_color_flag ""

// Admin flag required to hide tag. Leave empty for public access.
sm_cccm_hide_tag_flag ""
```

To restrict a feature, set the appropriate ConVar to an admin flag letter. For example:
- `sm_cccm_tag_text_flag "b"` would restrict tag text changes to users with the generic admin flag
- `sm_cccm_name_color_flag "o"` would restrict name color changes to users with the custom1 flag

Color options are defined in `configs/custom-chatcolors-menu.cfg`.

## Credits

Originally by ReFlexPoison, modified by JoinedSenses, further customized by ampere.