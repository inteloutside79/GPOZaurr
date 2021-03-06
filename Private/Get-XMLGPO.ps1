﻿function Get-XMLGPO {
    [cmdletBinding()]
    param(
        [XML] $XMLContent,
        [Microsoft.GroupPolicy.Gpo] $GPO,
        [switch] $PermissionsOnly,
        [switch] $OwnerOnly,
        [System.Collections.IDictionary] $ADAdministrativeGroups,
        [string] $Splitter = [System.Environment]::NewLine,
        [switch] $ReturnObject,
        [System.Collections.IDictionary] $ExcludeGroupPolicies,
        [string[]] $Type,
        [System.Collections.IDictionary] $LinksSummaryCache
    )
    if ($LinksSummaryCache) {
        $SearchGUID = -join ($XMLContent.GPO.Identifier.Domain.'#text', $XMLContent.GPO.Identifier.Identifier.InnerText -replace '{' -replace '}')
        if ($LinksSummaryCache[$SearchGUID]) {
            $Linked = $LinksSummaryCache[$SearchGUID].Linked
            $LinksEnabledCount = $LinksSummaryCache[$SearchGUID].LinksEnabledCount
            $LinksDisabledCount = $LinksSummaryCache[$SearchGUID].LinksDisabledCount
            $LinksTotalCount = $LinksSummaryCache[$SearchGUID].LinksCount
            $Links = $LinksSummaryCache[$SearchGUID].Links
            $LinksObjects = $LinksSummaryCache[$SearchGUID].LinksObjects
        } else {
            $Linked = $false
            $LinksEnabledCount = 0
            $LinksDisabledCount = 0
            $LinksTotalCount = 0
            $Links = $null
            $LinksObjects = $null
        }
    } else {
        if ($XMLContent.GPO.LinksTo) {
            $LinkSplit = ([Array] $XMLContent.GPO.LinksTo).Where( { $_.Enabled -eq $true }, 'Split')
            [Array] $LinksEnabled = $LinkSplit[0]
            [Array] $LinksDisabled = $LinkSplit[1]
            $LinksEnabledCount = $LinksEnabled.Count
            $LinksDisabledCount = $LinksDisabled.Count
            $LinksTotalCount = ([Array] $XMLContent.GPO.LinksTo).Count
            if ($LinksEnabledCount -eq 0) {
                $Linked = $false
            } else {
                $Linked = $true
            }
            $Links = @(
                $XMLContent.GPO.LinksTo | ForEach-Object -Process {
                    if ($_) {
                        $_.SOMPath
                    }
                }
            ) -join $Splitter
            $LinksObjects = $XMLContent.GPO.LinksTo | ForEach-Object -Process {
                if ($_) {
                    [PSCustomObject] @{
                        CanonicalName = $_.SOMPath
                        Enabled       = $_.Enabled
                        NoOverride    = $_.NoOverride
                    }
                }
            }
        } else {
            $Linked = $false
            $LinksEnabledCount = 0
            $LinksDisabledCount = 0
            $LinksTotalCount = 0
            $Links = $null
            $LinksObjects = $null
        }
    }
    # Find proper values for enabled/disabled user/computer settings
    if ($XMLContent.GPO.Computer.Enabled -eq 'False') {
        $ComputerEnabled = $false
    } elseif ($XMLContent.GPO.Computer.Enabled -eq 'True') {
        $ComputerEnabled = $true
    } else {
        Write-Warning "Get-XMLGPO - Computer enabled not set to true or false. Weird."
        $ComputerEnabled = $null
    }
    if ($XMLContent.GPO.User.Enabled -eq 'False') {
        $UserEnabled = $false
    } elseif ($XMLContent.GPO.User.Enabled -eq 'True') {
        $UserEnabled = $true
    } else {
        Write-Warning "Get-XMLGPO - User enabled not set to true or false. Weird."
        $UserEnabled = $null
    }
    # Translate Enabled to same as GPO GUI
    if ($UserEnabled -eq $True -and $ComputerEnabled -eq $true) {
        $EnabledBool = $true
        $Enabled = 'Enabled'
    } elseif ($UserEnabled -eq $false -and $ComputerEnabled -eq $false) {
        $EnabledBool = $false
        $Enabled = 'All settings disabled'
    } elseif ($UserEnabled -eq $true -and $ComputerEnabled -eq $false) {
        $EnabledBool = $True
        $Enabled = 'Computer configuration settings disabled'
    } elseif ($UserEnabled -eq $false -and $ComputerEnabled -eq $true) {
        $EnabledBool = $True
        $Enabled = 'User configuration settings disabled'
    }

    # This is kind of old way of doing things, but it's superseded by other way below
    $ComputerSettingsAvailable = if ($null -eq $XMLContent.GPO.Computer.ExtensionData) { $false } else { $true }
    $UserSettingsAvailable = if ($null -eq $XMLContent.GPO.User.ExtensionData) { $false } else { $true }

    if ($ComputerSettingsAvailable -eq $false -and $UserSettingsAvailable -eq $false) {
        $NoSettings = $true
    } else {
        $NoSettings = $false
    }

    # $OutputUser = $XMLContent.GPO.User.ExtensionData.Extension | Where-Object { $_.PSObject.Properties.TypeNameOfValue -in 'System.Xml.XmlElement', 'System.Object[]' }
    # $OutputComputer = $XMLContent.GPO.Computer.ExtensionData.Extension | Where-Object { $_.PSObject.Properties.TypeNameOfValue -in 'System.Xml.XmlElement', 'System.Object[]' }

    $OutputUser = foreach ($ExtensionType in $XMLContent.GPO.User.ExtensionData.Extension) {
        if ($ExtensionType) {
            $GPOSettingTypeSplit = ($ExtensionType.type -split ':')
            try {
                $KeysToLoop = $ExtensionType | Get-Member -MemberType Properties -ErrorAction Stop | Where-Object { $_.Name -notin 'type', $GPOSettingTypeSplit[0] -and $_.Name -notin @('Blocked') }
            } catch {
                Write-Warning "Get-XMLGPO - things went sideways $($_.Exception.Message)"
                continue
            }
        }
        $KeysToLoop
    }
    $OutputComputer = foreach ($ExtensionType in $XMLContent.GPO.Computer.ExtensionData.Extension) {
        if ($ExtensionType) {
            $GPOSettingTypeSplit = ($ExtensionType.type -split ':')
            try {
                $KeysToLoop = $ExtensionType | Get-Member -MemberType Properties -ErrorAction Stop | Where-Object { $_.Name -notin 'type', $GPOSettingTypeSplit[0] -and $_.Name -notin @('Blocked') }
            } catch {
                Write-Warning "Get-XMLGPO - things went sideways $($_.Exception.Message)"
                continue
            }
        }
        $KeysToLoop
    }

    $ComputerSettingsAvailable = if ($OutputComputer) { $true } else { $false }
    $UserSettingsAvailable = if ($OutputUser) { $true } else { $false }

    if (-not $ComputerSettingsAvailable -and -not $UserSettingsAvailable) {
        $Empty = $true
    } else {
        $Empty = $false
    }

    $ComputerProblem = $false
    if ($ComputerEnabled -eq $true -and $ComputerSettingsAvailable -eq $true) {
        $ComputerOptimized = $true
    } elseif ($ComputerEnabled -eq $true -and $ComputerSettingsAvailable -eq $false) {
        $ComputerOptimized = $false
    } elseif ($ComputerEnabled -eq $false -and $ComputerSettingsAvailable -eq $false) {
        $ComputerOptimized = $true
    } else {
        # Enabled $false, but ComputerData is there.
        $ComputerOptimized = $false
        $ComputerProblem = $true
    }

    $UserProblem = $false
    if ($UserEnabled -eq $true -and $UserSettingsAvailable -eq $true) {
        $UserOptimized = $true
    } elseif ($UserEnabled -eq $true -and $UserSettingsAvailable -eq $false) {
        $UserOptimized = $false
    } elseif ($UserEnabled -eq $false -and $UserSettingsAvailable -eq $false) {
        $UserOptimized = $true
    } else {
        # Enabled $false, but UserData is there.
        $UserOptimized = $false
        $UserProblem = $true
    }

    if ($UserProblem -or $ComputerProblem) {
        $Problem = $true
    } else {
        $Problem = $false
    }
    if ($UserOptimized -and $ComputerOptimized) {
        $Optimized = $true
    } else {
        $Optimized = $false
    }

    if (-not $PermissionsOnly) {
        if ($ADAdministrativeGroups -and $XMLContent.GPO.SecurityDescriptor.Owner.Name.'#text') {
            $AdministrativeGroup = $ADAdministrativeGroups['ByNetBIOS']["$($XMLContent.GPO.SecurityDescriptor.Owner.Name.'#text')"]
            $WellKnown = ConvertFrom-SID -SID $XMLContent.GPO.SecurityDescriptor.Owner.SID.'#text' -OnlyWellKnown
            if ($AdministrativeGroup) {
                $OwnerType = 'Administrative'
            } elseif ($WellKnown.Name) {
                $OwnerType = 'WellKnown'
            } else {
                $OwnerType = 'NotAdministrative'
            }
        } elseif ($ADAdministrativeGroups) {
            $OwnerType = 'Unknown'
        } else {
            $OwnerType = 'Unable to asses (local files?)'
        }
    }
    # Mark GPO as excluded
    $Exclude = $false
    if ($ExcludeGroupPolicies) {
        $PolicyWithDomain = -join ($XMLContent.GPO.Identifier.Domain.'#text', $XMLContent.GPO.Name)
        if ($ExcludeGroupPolicies[$XMLContent.GPO.Name] -or $ExcludeGroupPolicies[$PolicyWithDomain]) {
            $Exclude = $true
        }
    }
    if ($PermissionsOnly) {
        $GPOOutput = [PsCustomObject] @{
            'DisplayName'          = $XMLContent.GPO.Name
            'DomainName'           = $XMLContent.GPO.Identifier.Domain.'#text'
            'GUID'                 = $XMLContent.GPO.Identifier.Identifier.InnerText -replace '{' -replace '}'
            'Enabled'              = $Enabled
            'Name'                 = $XMLContent.GPO.SecurityDescriptor.Owner.Name.'#text'
            'Sid'                  = $XMLContent.GPO.SecurityDescriptor.Owner.SID.'#text'
            #'SidType'        = if (($XMLContent.GPO.SecurityDescriptor.Owner.SID.'#text').Length -le 10) { 'WellKnown' } else { 'Other' }
            'PermissionType'       = 'Allow'
            'Inherited'            = $false
            'Permissions'          = 'Owner'
            'GPODistinguishedName' = $GPO.Path
        }
        $XMLContent.GPO.SecurityDescriptor.Permissions.TrusteePermissions | ForEach-Object -Process {
            if ($_) {
                [PsCustomObject] @{
                    'DisplayName'          = $XMLContent.GPO.Name
                    'DomainName'           = $XMLContent.GPO.Identifier.Domain.'#text'
                    'GUID'                 = $XMLContent.GPO.Identifier.Identifier.InnerText -replace '{' -replace '}'
                    'Enabled'              = $Enabled
                    'Name'                 = $_.trustee.name.'#Text'
                    'Sid'                  = $_.trustee.SID.'#Text'
                    #'SidType'        = if (($XMLContent.GPO.SecurityDescriptor.Owner.SID.'#text').Length -le 10) { 'WellKnown' } else { 'Other' }
                    'PermissionType'       = $_.type.PermissionType
                    'Inherited'            = if ($_.Inherited -eq 'false') { $false } else { $true }
                    'Permissions'          = $_.Standard.GPOGroupedAccessEnum
                    'GPODistinguishedName' = $GPO.Path
                }
            }
        }
    } elseif ($OwnerOnly) {
        $GPOOutput = [PsCustomObject] @{
            'DisplayName'          = $XMLContent.GPO.Name
            'DomainName'           = $XMLContent.GPO.Identifier.Domain.'#text'
            'GUID'                 = $XMLContent.GPO.Identifier.Identifier.InnerText -replace '{' -replace '}'
            'Enabled'              = $Enabled
            'Owner'                = $XMLContent.GPO.SecurityDescriptor.Owner.Name.'#text'
            'OwnerSID'             = $XMLContent.GPO.SecurityDescriptor.Owner.SID.'#text'
            'OwnerType'            = $OwnerType
            'GPODistinguishedName' = $GPO.Path
        }
    } else {
        $GPOOutput = [PsCustomObject] @{
            'DisplayName'                       = $XMLContent.GPO.Name
            'DomainName'                        = $XMLContent.GPO.Identifier.Domain.'#text'
            'GUID'                              = $XMLContent.GPO.Identifier.Identifier.InnerText -replace '{' -replace '}'
            'Days'                              = (New-TimeSpan -Start ([DateTime] $XMLContent.GPO.ModifiedTime) -End (Get-Date)).Days
            'Empty'                             = $Empty
            'Linked'                            = $Linked
            'Enabled'                           = $EnabledBool
            'Optimized'                         = $Optimized
            'Problem'                           = $Problem
            'ApplyPermission'                   = $null
            'Exclude'                           = $Exclude
            'ComputerPolicies'                  = $XMLContent.GPO.Computer.ExtensionData.Name -join ", "
            'UserPolicies'                      = $XMLContent.GPO.User.ExtensionData.Name -join ", "
            'LinksCount'                        = $LinksTotalCount
            'LinksEnabledCount'                 = $LinksEnabledCount
            'LinksDisabledCount'                = $LinksDisabledCount
            'EnabledDetails'                    = $Enabled
            'ComputerProblem'                   = $ComputerProblem
            'ComputerOptimized'                 = $ComputerOptimized
            'UserProblem'                       = $UserProblem
            'UserOptimized'                     = $UserOptimized
            'ComputerSettingsAvailable'         = $ComputerSettingsAvailable
            'UserSettingsAvailable'             = $UserSettingsAvailable
            #'ComputerSettingsAvailableReal'         = $ComputerSettingsAvailableReal
            #'UserSettingsAvailableReal'             = $UserSettingsAvailableReal
            'ComputerSettingsTypes'             = $OutputComputer.Name
            'UserSettingsTypes'                 = $OutputUser.Name
            'ComputerEnabled'                   = $ComputerEnabled
            'UserEnabled'                       = $UserEnabled
            'ComputerSettingsStatus'            = if ($XMLContent.GPO.Computer.VersionDirectory -eq 0 -and $XMLContent.GPO.Computer.VersionSysvol -eq 0) { "NeverModified" } else { "Modified" }
            'ComputerSetttingsVersionIdentical' = if ($XMLContent.GPO.Computer.VersionDirectory -eq $XMLContent.GPO.Computer.VersionSysvol) { $true } else { $false }
            'ComputerSettings'                  = $XMLContent.GPO.Computer.ExtensionData.Extension
            'UserSettingsStatus'                = if ($XMLContent.GPO.User.VersionDirectory -eq 0 -and $XMLContent.GPO.User.VersionSysvol -eq 0) { "NeverModified" } else { "Modified" }
            'UserSettingsVersionIdentical'      = if ($XMLContent.GPO.User.VersionDirectory -eq $XMLContent.GPO.User.VersionSysvol) { $true } else { $false }
            'UserSettings'                      = $XMLContent.GPO.User.ExtensionData.Extension
            'NoSettings'                        = $NoSettings
            'CreationTime'                      = [DateTime] $XMLContent.GPO.CreatedTime
            'ModificationTime'                  = [DateTime] $XMLContent.GPO.ModifiedTime
            'ReadTime'                          = [DateTime] $XMLContent.GPO.ReadTime
            'WMIFilter'                         = $GPO.WmiFilter.name
            'WMIFilterDescription'              = $GPO.WmiFilter.Description
            'GPODistinguishedName'              = $GPO.Path
            'SDDL'                              = if ($Splitter -ne '') { $XMLContent.GPO.SecurityDescriptor.SDDL.'#text' -join $Splitter } else { $XMLContent.GPO.SecurityDescriptor.SDDL.'#text' }
            'Owner'                             = $XMLContent.GPO.SecurityDescriptor.Owner.Name.'#text'
            'OwnerSID'                          = $XMLContent.GPO.SecurityDescriptor.Owner.SID.'#text'
            'OwnerType'                         = $OwnerType
            'ACL'                               = @(
                [PsCustomObject] @{
                    'Name'           = $XMLContent.GPO.SecurityDescriptor.Owner.Name.'#text'
                    'Sid'            = $XMLContent.GPO.SecurityDescriptor.Owner.SID.'#text'
                    'PermissionType' = 'Allow'
                    'Inherited'      = $false
                    'Permissions'    = 'Owner'
                }
                $XMLContent.GPO.SecurityDescriptor.Permissions.TrusteePermissions | ForEach-Object -Process {
                    if ($_) {
                        [PsCustomObject] @{
                            'Name'           = $_.trustee.name.'#Text'
                            'Sid'            = $_.trustee.SID.'#Text'
                            'PermissionType' = $_.type.PermissionType
                            'Inherited'      = if ($_.Inherited -eq 'false') { $false } else { $true }
                            'Permissions'    = $_.Standard.GPOGroupedAccessEnum
                        }
                    }
                }
            )
            'Auditing'                          = if ($XMLContent.GPO.SecurityDescriptor.AuditingPresent.'#text' -eq 'true') { $true } else { $false }
            'Links'                             = $Links
            'LinksObjects'                      = $LinksObjects
            'GPOObject'                         = $GPO
        }
        if ($GPOOutput.ACL) {
            $GPOOutput.ApplyPermission = $false
            foreach ($Permission in $GPOOutput.ACL) {
                if ($Permission.Permissions -eq 'Apply Group Policy') {
                    $GPOOutput.ApplyPermission = $true
                }
            }
        }

    }
    if ($PermissionsOnly -or $OwnerOnly) {
        $GPOOutput
    } else {
        if (-not $Type -or $Type -contains 'All') {
            $GPOOutput
        } else {
            if ($Type -contains 'Empty') {
                if ($GPOOutput.Empty -eq $true) {
                    $GPOOutput
                }
            }
            if ($Type -contains 'Unlinked') {
                if ($GPOOutput.Linked -eq $false) {
                    $GPOOutput
                }
            }
            if ($Type -contains 'Disabled') {
                if ($GPOOutput.Enabled -eq $false) {
                    $GPOOutput
                }
            }
            if ($Type -contains 'NoApplyPermission') {
                if ($GPOOutput.ApplyPermission -eq $false) {
                    $GPOOutput
                }
            }
        }
    }
}