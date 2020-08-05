function ConvertTo-XMLGenericPolicy {
    [cmdletBinding()]
    param(
        [PSCustomObject] $GPO,
        [string[]] $Category
    )
    $CreateGPO = [ordered]@{
        DisplayName = $GPO.DisplayName
        DomainName  = $GPO.DomainName
        GUID        = $GPO.GUID
        GpoType     = $GPO.GpoType
        #GpoCategory = $GPOEntry.GpoCategory
        #GpoSettings = $GPOEntry.GpoSettings
    }
    $UsedNames = [System.Collections.Generic.List[string]]::new()

    [Array] $Policies = foreach ($Cat in $Category) {
        $GPO.DataSet | Where-Object { $_.Category -like $Cat }
    }
    if ($Policies.Count -gt 0) {
        foreach ($Policy in $Policies) {
            #if ($Policy.Category -notlike $Category) {
            # We check again for Category because one GPO can have multiple categories
            # First check checks GPO globally,
            #    continue
            #}
            $Name = Format-ToTitleCase -Text $Policy.Name -RemoveWhiteSpace -RemoveChar ',', '-', "'", '\(', '\)', ':'
            $CreateGPO[$Name] = $Policy.State

            foreach ($Setting in @('DropDownList', 'Numeric', 'EditText', 'Text', 'CheckBox', 'ListBox')) {
                if ($Policy.$Setting) {
                    foreach ($Value in $Policy.$Setting) {
                        if ($Value.Name) {
                            $SubName = Format-ToTitleCase -Text $Value.Name -RemoveWhiteSpace -RemoveChar ',', '-', "'", '\(', '\)', ':'
                            $SubName = -join ($Name, $SubName)
                            if ($SubName -notin $UsedNames) {
                                $UsedNames.Add($SubName)
                            } else {
                                $TimesUsed = $UsedNames | Group-Object | Where-Object { $_.Name -eq $SubName }
                                $NumberToUse = $TimesUsed.Count + 1
                                # We add same name 2nd and 3rd time to make sure we count properly
                                $UsedNames.Add($SubName)
                                # We now build property name based on amnount of times
                                $SubName = -join ($SubName, "$NumberToUse")
                            }
                            if ($Value.Value -is [string]) {
                                $CreateGPO["$SubName"] = $Value.Value
                            } elseif ($Value.Value -is [System.Xml.XmlElement]) {

                                <#
                                if ($null -eq $Value.Value.Name) {
                                    # Shouldn't happen but lets see
                                    Write-Verbose $Value
                                } else {
                                    $CreateGPO["$SubName"] = $Value.Value.Name
                                }

                                #>
                                if ($Value.Value.Element) {
                                    $CreateGPO["$SubName"] = $Value.Value.Element.Data -join '; '
                                } elseif ($null -eq $Value.Value.Name) {
                                    # Shouldn't happen but lets see
                                    Write-Verbose "Tracking $Value"
                                } else {
                                    $CreateGPO["$SubName"] = $Value.Value.Name
                                }

                            } elseif ($Value.State) {
                                $CreateGPO["$SubName"] = $Value.State
                            } elseif ($null -eq $Value.Value) {
                                # This is most likely Setting 'Text
                                # Do nothing, usually it's just a text to display
                                #Write-Verbose "Skipping value for display because it's empty. Name: $($Value.Name)"
                            } else {
                                # shouldn't happen
                                Write-Verbose $Value
                            }
                        }
                    }
                }
            }
        }
        $CreateGPO['Linked'] = $GPO.Linked
        $CreateGPO['LinksCount'] = $GPO.LinksCount
        $CreateGPO['Links'] = $GPO.Links
        [PSCustomObject] $CreateGPO
        #}
    }
}