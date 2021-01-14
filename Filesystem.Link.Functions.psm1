function Resolve-Error
{
    <#
    .SYNOPSIS
        Resolves an Error records various properties, and outputs it in verbose format.

    .DESCRIPTION
        Resolves an Error records various properties, and outputs it in verbose format.
        
        It will also unwind Exception chain.

        NOTE:
        All output will be piped through Out-String, with a preset width, in order to
        make custom logging easier to implement - default width is 160
        
    .PARAMETER ErrorRecord
        The ErrorRecord to resolve, will use last error by default.

    .PARAMETER Width
        The width of the console/output to which the ErrorRecord will be formatted.

        Default is 160

    .EXAMPLE
        Resolve-Error -ErrorRecord $Error[1]

        Will resolve the 2nd error in the list of errors.

    .EXAMPLE
        try {
            Throw "this is a test error!"
        } catch {
            Resolve-Error -ErrorRecord $_
        }

        Will resolve the error that was thrown.

    .EXAMPLE
        try {
            Throw "this is a test error!"
        } catch {
            Resolve-Error -ErrorRecord $_ -Width 200
        }

        Will resolve the error that was thrown width a custom Width

    .OUTPUTS
        ErrorRecord(s) in string formatted output.

    .NOTES
        Author.: Kenneth Nielsen (sharzas @ GitHub.com)
        Version: 1.0

        Credit goes to MSFT Jeffrey Snower who made the source version I used
        as base for this function!

        Link under links to his original version.

    .LINK
        https://devblogs.microsoft.com/powershell/resolve-error/
    #>
    [CmdletBinding()]
    Param (
        [Parameter(ValueFromPipeline)]
        $ErrorRecord=$Error[0],

        [Parameter()]
        $Width = 140
    )

    $ExceptionChainIndent = 3
    
    $Property = ("*",($ErrorRecord|Get-Member -MemberType Properties -Name "HResult"|Where-Object {$_}|ForEach-Object {@{n="HResult"; e={"0x{0:x}" -f $_.HResult}}})|Where-Object {$_})

    $ErrorRecord|Select-Object -Property $Property -ExcludeProperty HResult |Format-List -Force|Out-String -Stream -Width $Width
    $ErrorRecord.InvocationInfo|Format-List *|Out-String -Stream -Width $Width
    $Exception = $ErrorRecord.Exception

    for ($i = 0; $Exception; $i++, ($Exception = $Exception.InnerException))
    {   
        # Build Exception Separator with respect for Width
        $ExceptionSeparator = " [Exception Chain - Exception #{0}] " -f [string]$i
        $ExceptionSeparator = "{0}{1}{2}" -f ("-"*$ExceptionChainIndent),$ExceptionSeparator,("-"*($Width - ($ExceptionChainIndent + $ExceptionSeparator.Length)))

        $ExceptionSeparator|Out-String -Stream -Width $Width
        $Exception|Select-Object -Property *,@{n="HResult"; e={"0x{0:x}" -f $_.HResult}} -ExcludeProperty HResult|Format-List * -Force|Out-String -Stream -Width $Width
    }
} # function Resolve-Error



function Get-Link
{
    <#
    .SYNOPSIS
        Get all file/directory objects that are either symbolic links, hardlinks or junctions

    .DESCRIPTION
        Get all file/directory objects that are either symbolic links, hardlinks or junctions        
        
    .PARAMETER Path
        The path for which to enumerate link contents.

    .PARAMETER Filter
        The filter to apply on top of the link list. This filter is passed on to Get-ChildItem.

    .EXAMPLE
        Get-Link -Path C:\test
        
        Get all links/junctions in C:\test
        
    .EXAMPLE
        Get-Link -Path C:\test -Filter "mylink*.*"
        
        Get all links/junctions in C:\test starting with "mylink"

    .OUTPUTS
        DirectoryInfo or FileInfo type objects, where the attributes reflect
        its a link or a junction.

    .NOTES
        Author.: Kenneth Nielsen (sharzas @ GitHub.com)
        Version: 1.0

    .LINK
        https://github.com/sharzas/Powershell-Filesystem.Link.Functions
    #>
    [CmdletBinding()]
    Param (
        $Path,
        $Filter
    )

    Get-ChildItem @PSBoundParameters|Where-Object {
        ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq [System.IO.FileAttributes]::ReparsePoint
    }
}


function New-Link
{
    <#
    .SYNOPSIS
        Create symbolic link, hardlink or junction

    .DESCRIPTION
        Create symbolic link, hardlink or junction
        
    .PARAMETER Name
        The name of the new link/junction

    .PARAMETER Destination
        The destination to which the link points. This must be either a directory or a file
        depending on the LinkType:

        SymbolicLink: Local/Remote File/Directory
        Hardlink....: File in same volume as the new link.
        Junction....: Local Directory

    .PARAMETER LinkType
        Type of link.

    .EXAMPLE
        New-Link -Name MyNewLink -Destination C:\MyVideos
        
        Create a new link in current directory named "MyNewLink", pointing to the directory
        "C:\MyVideos". Type is the default of SymbolicLink
        
    .EXAMPLE
        New-Link -Name C:\LinkDir\MyNewLink.mov -Destination C:\MyVideos\MyVideoFile.mov
        
        Create a new link in C:\LinkDir named "MyNewLink.mov", pointing to the file
        "C:\MyVideos\MyVideoFile.mov". Type is the default of SymbolicLink.

    .EXAMPLE
        New-Link -Name MyNewLink -Destination C:\MyVideos -LinkType Junction
        
        Create a new link in current directory named "MyNewLink", pointing to the directory
        "C:\MyVideos". Type is Junction.
        
    .OUTPUTS
        Status object, containing various information, along with exitcode from cmd mklink
        which is used to actually create the links.

    .NOTES
        Author.: Kenneth Nielsen (sharzas @ GitHub.com)
        Version: 1.0

    .LINK
        https://github.com/sharzas/Powershell-Filesystem.Link.Functions
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    Param (
        [Parameter(Mandatory)]
        [String]$Name,

        [Parameter(Mandatory)]
        $Destination,

        [Parameter()]
        [ValidateSet('SymbolicLink', 'Junction', 'Hardlink')]
        [String]$LinkType = "SymbolicLink"
    )

    Write-Verbose ('New-Link(): Specified -Name..........: "{0}"' -f $Name)

    if (!($Name -match "^.*\\.+(\\$|[^\\]$)")) {
        # the Name does not contain a backslash somewhere in the middle, which means
        # it does not refer to an absolute/relative path. Since we call .NET methods
        # to spawn a command process later on, we need to resolve current path, and
        # make sure WE refer to an absolute path
        $Name = Join-Path -Path (Get-Location).Path -ChildPath $Name
    }

    Write-Verbose ('New-Link(): -Name after normalization: "{0}"' -f $Name)

    # get the path of the -Name - we will verify it exists.
    $ParentPath = Split-Path -Path $Name -Parent

    Write-Verbose ('New-Link(): -Name parent path........: "{0}"' -f $Name)


    try {
        Resolve-Path $ParentPath -ErrorAction Stop|Out-Null
    } catch {
        Write-Warning ('Could not resolve path where "{0}" will be created: "{1}"' -f (Split-Path -Path $Name -Leaf), $ParentPath)
        Resolve-Error $_|Out-String -Stream|Write-Warning
        $PSCmdlet.ThrowTerminatingError($_)
    }


    try {
        $Destination = (Resolve-Path $Destination -ErrorAction Stop).Path
    } catch {
        Resolve-Error $_|Out-String -Stream|Write-Warning
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # Get item in filesystem format.
    $Destination = Get-Item $Destination

    Write-Verbose ('New-Link(): Destination "{0}" is Container: {1}' -f $Destination.Fullname,$Destination.PSIsContainer)
    Write-Verbose ('New-Link(): LinkType is "{0}"' -f $LinkType)

    # initial arguments - we'll build on this
    $Arguments = @('/c','mklink')

    switch ($LinkType) {
        "SymbolicLink" {
            if ($Destination.PSisContainer) {
                # Destination is directory, so we need to add /D parameter to mklink
                $Arguments += '/d'
            }
            break
        }

        "Junction" {
            if (!$Destination.PSisContainer) {
                # Destination is NOT directory - not supported!
                try {
                    Throw "-LinkType Junction specified, but destination is NOT a directory!`nDestination MUST be a directory for this link type!"
                } catch {
                    $PSCmdlet.ThrowTerminatingError($_)
                }
            }

            $Arguments += '/j'
            break
        }

        "Hardlink" {
            if (!$Destination.PSisContainer) {
                # Destination is directory - not supported!
                try {
                    Throw "-LinkType Hardlink specified, but destination is a directory!`nDestination CANNOT be a directory for this link type!"
                } catch {
                    $PSCmdlet.ThrowTerminatingError($_)
                }
            }

            $Arguments += '/h'
            break
        }

        DEFAULT {
            # this should basically not be possible - but just in case!
            Write-Verbose ('New-Link(): LinkType is Unsupported: "{0}"' -f $LinkType)

            try {
                Throw ('Unsupported -LinkType "{0}" specified, this is a bug!' -f $LinkType)
            } catch {
                $PSCmdlet.ThrowTerminatingError($_)
            }
        }
    }

    $Arguments += ('"{0}"' -f $Name)
    $Arguments += ('"{0}"' -f $Destination.Fullname)

    $Arguments|ForEach-Object {
        Write-Verbose ('New-Link(Arguments for Cmd Process): [{0}]' -f $_)
    }

    Write-Verbose ('New-Link(): Complete command line: [{0} {1}]' -f $env:ComSpec, ($Arguments -join " "))

    $Status = [PSCustomObject]@{
        Status = "Not run yet"
        ExitCode = $null
        LinkCreated = $null
        LinkCommand = ('{0} {1}' -f $env:ComSpec,($Arguments -join " "))
        StdOut = $null
        StdErr = $null
    }

    # Set to custom type
    $Status.PSTypenames.Insert(0, "Filesystem.Link.Functions.StatusObject")

    # Update display properties for this custom type.
    Update-TypeData -TypeName "Filesystem.Link.Functions.StatusObject" -DefaultDisplayPropertySet "Status","ExitCode","LinkCreated" -Force


    # request confirmation
    if ($PSCmdlet.ShouldProcess($Destination.Fullname, ('Create Symbolic Link ''{0}''' -f $Name)))  {    
        # build process object, and start process.
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = "$($env:ComSpec)"
        $pinfo.RedirectStandardError = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.UseShellExecute = $false
        $pinfo.Arguments = $Arguments
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        
        try {
            $p.Start() | Out-Null
            $p.WaitForExit()

            # if termination was gracefull, record StdOut and StdErr + the ExitCode
            $Status.StdOut = $p.StandardOutput.ReadToEnd()
            $Status.StdErr = $p.StandardError.ReadToEnd()
            $Status.ExitCode = $p.ExitCode

            if ($p.ExitCode -ne 0) {
                # exitcode was not 0 - exit with an error.
                try {
                    $Status.Status = "Command FAILED!"
                    Throw ($Status|Format-List *|Out-String)
                } catch {
                    $PSCmdlet.ThrowTerminatingError($_)
                }    
            }

            # update status
            $Status.Status = "Command completed succesfully"
            $Status.LinkCreated = ('{0} ==> {1}' -f $Name, $Destination.FullName)
        } catch {
            # termination was not gracefull - output detailed error information, and re-throw using
            # statement terminating error.
            Resolve-Error $_|Out-String -Stream|Write-Warning
            $PSCmdlet.ThrowTerminatingError($_)
        }

        # exit gracefully and return status.
        return $status
    }
}

[Version]$Version = "1.0"
Export-ModuleMember -Function "*"
Write-Host ('Module {0} - Version {1} Loaded' -f (Split-Path -Path $PSCommandPath -Leaf), $Version)