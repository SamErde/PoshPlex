# PoshPlex

Manage your Plex Media Server with PowerShell!

## Overview

The PoshPlex module utilizes the official Plex Media Server API to perform all of its functions. It is designed to be a simple and efficient wrapper that makes it easier for PowerShell users to manage their Plex media servers, libraries, and media items.

## To Do

**Pick a name for the project:**

- PSPlex
- PoshPlex
- Plush

**Define goals for the project:**

- Authenticate using Plex
- Connect to Plex Media Server (PMS)
- List Libraries, collections, and media items
- Define filters for media items that vary depending on the media type or library type (e.g., Type, Title, Collection, Genre, Year)
- Make it easy to compare metadata for a media item in the database with the source media file's metadata in the file system

**Implement Caching:**

- Create a session object and cache to minimize repeated calls to the API for the same information
  - Use a C# code block to create a custom class for the cache so it can be reliably used via the command line
  - Use cache to return information about libraries and collections unless:
    - Refresh the cache if commands that modify a library (`Set-Library`) are ever used
    - Refresh the cache if commands that modify a collection ('Set-Collection') are ever used
    - A `Get-*` command is run with a parameter that forces a cache bypass or refresh (e.g., **-NoCache** or **-Refresh**.)

**Create Community Files:**

- Write a disclaimer and notice regarding no relationship with Plex official
- Create community files
- Create a logo

**Define Initial Commands and Aliases:**

- Start-PlexAuth
- New-PlexAuthToken
- Get-PlexAuthToken
- Connect-PlexMediaServer
- Get-Library
- Get-Collection
- Get-Item / Get-MediaItem

## Installation

The PoshPlex module can be installed on Linux, macOS, or Windows using the following command.

```powershell
Install-PSResource -Name 'PoshPlex' -Scope CurrentUser
```

Note: If you receive an error that the command `Install-PSResource` is not recognized, you may be running an older version of Windows PowerShell. The `Install-Module` cmdlet will work fine, however, the **Microsoft.PowerShell.PSResourceGet** module brings better functionality and performance than the original **PowerShellGet** module.

## Examples

Obtain a Plex authentication token and connect using:

```powershell
New-PlexAuthenticationToken
Connect-PlexServer
```

