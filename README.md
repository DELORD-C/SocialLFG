# SocialLFG - World of Warcraft Addon

## Overview

SocialLFG is a social Looking for Group addon for World of Warcraft that allows guild members and friends to easily share their availability for group activities and coordinate group recruitment.

## Features

- **Registration System**: Register with specific categories (Raid, Mythic+, Questing) and roles (Tank, Heal, DPS)
- **Real-time Status Sharing**: Automatically broadcast your LFG status to guildmates and friends
- **Member List Display**: View all players looking for groups with:
  - Player names
  - Available roles with visual icons
  - Content categories
  - Item level (iLvl)
  - Raider.IO account score
- **Quick Invite**: One-click invites directly from the list
- **Minimap Button**: Convenient access via LibDataBroker integration
- **Smart Role Restrictions**: Automatically restricts available roles based on your class capabilities
- **Group Status Awareness**: Automatically manages registration when joining/leaving groups

## How to Use

1. Open the SocialLFG window using `/slfg` or `/sociallfg` command
2. Select your desired content categories (Raid, Mythic+, Questing, Dungeon)
3. Select your roles (Tank, Heal, DPS) - only available roles for your class are shown
4. Click "Register LFG" to share your status
5. View all registered guild members and friends in the list
6. Click "Invite" to invite players to your group

## Display Information

The addon displays the following information for each registered player:
- **Name**: Character name
- **Roles**: Visual role icons (Tank, Heal, DPS)
- **Categories**: Content categories they're looking for
- **iLvL**: Average item level
- **Rio Score**: Raider.IO account-wide Mythic+ score (requires Raider.IO addon)

## Requirements

- World of Warcraft (Retail)
- Optional: Raider.IO addon for displaying Mythic+ scores

## Dependencies

- LibDataBroker-1.1 (embedded)
- LibDBIcon-1.0 (embedded)
- LibStub (embedded)

## Configuration

The addon stores preferences automatically. No manual configuration needed - just select your categories and roles to get started.

## Changelog

### v1.0 Beta
- Initial release
- Core LFG functionality
- Guild and friends integration
- Raider.IO integration
- Item level tracking
- Role-based filtering

## Support

For bug reports and feature requests, please use the appropriate channels on CurseForge.

## License

This addon is provided as-is for use with World of Warcraft.
