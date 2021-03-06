<#
.NOTES
	Name: Get-MRMRoamingXMLData.ps1
	Authors: Agustin Gallegos
    
	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
	BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
	NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
	DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
.SYNOPSIS
    Get MRM setting stamped in a user's mailbox.
.DESCRIPTION
    Get MRM setting stamped in a user's mailbox.
    Output will be parsed from XML to readable text.
.PARAMETER DeleteConfigurationMessage
    Using this parameter, deletes the IPM.Configuration.MRM message from the user mailbox.
    An Administrator should run 'Start-ManagedFolderAssistant' to issue MRM service and recreate the message.
.EXAMPLE 
    PS C:\> Get-MRMRoamingXMLData.ps1
.EXAMPLE 
    PS C:\> Get-MRMRoamingXMLData.ps1 -DeleteConfigurationMessage

.COMPONENT
   STORE, MRM
.ROLE
   Support
#>
[CmdletBinding()]
param(
    [Switch]
    $DeleteConfigurationMessage
)
$disclaimer = @"
#################################################################################
#
# The sample scripts are not supported under any Microsoft standard support
# program or service. The sample scripts are provided AS IS without warranty
# of any kind. Microsoft further disclaims all implied warranties including, without
# limitation, any implied warranties of merchantability or of fitness for a particular
# purpose. The entire risk arising out of the use or performance of the sample scripts 
# and documentation remains with you. In no event shall Microsoft, its authors, or
# anyone else involved in the creation, production, or delivery of the scripts be liable
# for any damages whatsoever (including, without limitation, damages for loss of business
# profits, business interruption, loss of business information, or other pecuniary loss) 
# arising out of the use of or inability to use the sample scripts or documentation,
# even if Microsoft has been advised of the possibility of such damages.
#
#################################################################################
"@
Write-Host $disclaimer -foregroundColor Yellow
Write-Host " " 
write-host " " 
Write-Host "This script requires at least EWS API 2.1" -ForegroundColor Yellow 

# Locating DLL location either in working path, in EWS API 2.1 path or in EWS API 2.2 path
$Directory = ".\"
$EWS = Join-Path $Directory "Microsoft.Exchange.WebServices.dll"
$test = Test-Path -Path $EWS
if ($test -eq $False){
    Write-Host "EWS DLL in local path not found" -ForegroundColor Cyan
    $test2 = Test-Path -Path "C:\Program Files (x86)\Microsoft\Exchange\Web Services\2.*\Microsoft.Exchange.WebServices.dll"
    if ($test2 -eq $False){
        Write-Host "EWS 2.1 not found" -ForegroundColor Cyan
        $test3 = Test-Path -Path "C:\Program Files\Microsoft\Exchange\Web Services\2.*\Microsoft.Exchange.WebServices.dll"
        if ($test3 -eq $False) {
            Write-Host "EWS 2.2 not found" -ForegroundColor Cyan
        }else{
            Write-Host "EWS 2.2 found" -ForegroundColor Cyan
        }
    }else{
        Write-Host "EWS 2.1 found" -ForegroundColor Cyan
    }        
}else{
    Write-Host "EWS DLL found in local path" -ForegroundColor Cyan
}


if($test -eq $False -and $test2 -eq $False -and $test3 -eq $False){
    Write-Host " "
    Write-Host "You don't seem to have EWS API dll file 'Microsoft.Exchange.WebServices.dll' in the same Directory of this script" -ForegroundColor Red
    Write-Host "please get a copy of the file or download the whole API from: " -ForegroundColor Red -NoNewline
    Write-Host "https://www.microsoft.com/en-us/download/details.aspx?id=42951" -ForegroundColor Cyan
 
    return
}

Write-host "EWS API detected. All good!" -ForegroundColor Cyan
        
if ($test -eq $True){
    Add-Type -Path $EWS
    Write-Host "Using EWS DLL in local path" -ForegroundColor Cyan
    }
elseif($test2 -eq $True){
    Add-Type -Path "C:\Program Files (x86)\Microsoft\Exchange\Web Services\2.*\Microsoft.Exchange.WebServices.dll"
    Write-Host "Using EWS 2.1" -ForegroundColor Cyan
    }
elseif ($test3 -eq $True){
    Add-Type -Path "C:\Program Files\Microsoft\Exchange\Web Services\2.*\Microsoft.Exchange.WebServices.dll"
    Write-Host "Using EWS 2.2" -ForegroundColor Cyan
    }
write-host " "

# if EWS DLL is missing, we will exit the Process
if ($test -eq $False -and $test2 -eq $False -and $test3 -eq $False) {
    return
}
$ExchangeVersion = [Microsoft.Exchange.WebServices.Data.ExchangeVersion]::Exchange2016
$Service = New-Object Microsoft.Exchange.WebServices.Data.ExchangeService($ExchangeVersion) 

#Getting oauth credentials
if ( !(Get-Module AzureAD -ListAvailable) -and !(Get-Module AzureAD) ) 
{
    Install-Module AzureAD -Force -ErrorAction Stop
}
$Folderpath = (Get-Module azuread -ListAvailable | Sort-Object Version -Descending)[0].Path
$path = join-path (split-path $Folderpath -parent) 'Microsoft.IdentityModel.Clients.ActiveDirectory.dll'
Add-Type -Path $path

$authenticationContext = New-Object Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext("https://login.windows.net/common", $False)
$platformParameters = New-Object Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters([Microsoft.IdentityModel.Clients.ActiveDirectory.PromptBehavior]::Always)
$resourceUri = "https://outlook.office365.com"
$AppId = "8799ab60-ace5-4bda-b31f-621c9f6668db"
$redirectUri = New-Object Uri("http://localhost/code")

$authenticationResult = $authenticationContext.AcquireTokenSilentAsync($resourceUri, $AppId)
while ($authenticationResult.IsCompleted -ne $true) { Start-Sleep -Milliseconds 500 }

# Check if we failed to get the token
if (!($authenticationResult.IsFaulted -eq $false))
{
    switch ($authenticationResult.Exception.InnerException.ErrorCode) {
        failed_to_acquire_token_silently {
            # do nothing since we pretty much expect this to fail
            $authenticationResult = $authenticationContext.AcquireTokenAsync($resourceUri, $AppId, $redirectUri, $platformParameters)
            while ($authenticationResult.IsCompleted -ne $true) { Start-Sleep -Milliseconds 500 }
        }
        multiple_matching_tokens_detected {
            # we could clear the cache here since we don't have a UPN, but we are just going to move on to prompting
            $authenticationResult = $authenticationContext.AcquireTokenAsync($resourceUri, $AppId, $redirectUri, $platformParameters)
            while ($authenticationResult.IsCompleted -ne $true) { Start-Sleep -Milliseconds 500 }
        }
        Default { Write-host "Unknown Token Error $($authenticationResult.Exception.InnerException.ErrorCode). Error message: $_" }
    }
}
$Global:email = $authenticationResult.Result.UserInfo.DisplayableId
$exchangeCredentials = New-Object Microsoft.Exchange.WebServices.Data.OAuthCredentials($authenticationResult.Result.AccessToken)
$service.Url = New-Object Uri("https://outlook.office365.com/ews/exchange.asmx")
$Service.credentials = $exchangeCredentials


if ( $DeleteConfigurationMessage )
{
    try
    {
        $folderid= new-object Microsoft.Exchange.WebServices.Data.FolderId([Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::Inbox,$SmtpAddress)
        $UsrConfig = [Microsoft.Exchange.WebServices.Data.UserConfiguration]::Bind($service, "MRM", $folderid, [Microsoft.Exchange.WebServices.Data.UserConfigurationProperties]::All)  
        $UsrConfig.Delete()
        write-host "Successfully deleted the MRM Configuration message." -ForegroundColor Green
    }
    catch
    {
        write-host "Configuration message does not exists, or it failed to be deleted." -ForegroundColor Red
    }
}
else
{
    try {
        # following script block can read the PR_ROAMING_XMLSTREAM text and parse it in a readable way
        $folderid= new-object Microsoft.Exchange.WebServices.Data.FolderId([Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::Inbox,$SmtpAddress)
        $UsrConfig = [Microsoft.Exchange.WebServices.Data.UserConfiguration]::Bind($service, "MRM", $folderid, [Microsoft.Exchange.WebServices.Data.UserConfigurationProperties]::All)
        $ConfXML = [System.Text.Encoding]::UTF8.GetString($UsrConfig.XmlData)
        [XML]$ConfXML = $ConfXML
        write-host "Following are current 'Delete' TAGs" -ForegroundColor Green
        $ConfXML.UserConfiguration.Info.Data.PolicyTag
        write-host ""
        write-host "Following are current 'Move to Archive' TAGs" -ForegroundColor Green
        $ConfXML.UserConfiguration.Info.Data.ArchiveTag
        write-host ""
        write-host "Following are current 'Default Archive TAGs" -ForegroundColor Green
        $ConfXML.UserConfiguration.Info.Data.DefaultArchiveTag
    }
    catch {
        write-host "Configuration message does not exists, or it failed to be read." -ForegroundColor Red
    }
}