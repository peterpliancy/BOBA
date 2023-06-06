# Temporarily bypass the execution policy
Set-ExecutionPolicy Bypass -Scope Process -Force

try {
    # Check if the HWID directory exists
    If(Test-Path "C:\HWID") {
        Write-Host "Script has already run on this machine. Exiting."
        Exit 0
    }

    #Install MSAL.ps module if not currently installed
    If(!(Get-Module MSAL.ps)){
        
        Write-Host "Installing Nuget"
        Install-PackageProvider -Name NuGet -Force

        Write-Host "Installing module"
        Install-Module MSAL.ps -Force 

        Write-Host "Importing module"
        Import-Module MSAL.ps -Force
    }    

    #Use a client secret to authenticate to Microsoft Graph using MSAL
    $authparams = @{
        ClientId    = 'Application (client) ID from Step 13'
        TenantId    = 'clientwebsite.com'
        ClientSecret = ('Client Secret Value from Step 12' | ConvertTo-SecureString -AsPlainText -Force )
    }

    $auth = Get-MsalToken @authParams

    #Set Access token variable for use when making API calls
    $AccessToken = $Auth.AccessToken

    #Function to make Microsoft Graph API calls
    Function Invoke-MsGraphCall {

        [cmdletBinding()]
        param(
            [Parameter(Mandatory=$True)]
            [string]$AccessToken,
            [Parameter(Mandatory=$True)]
            [string]$URI,
            [Parameter(Mandatory=$True)]
            [string]$Method,
            [Parameter(Mandatory=$False)]
            [string]$Body
        )

        #Create Splat hashtable
        $graphSplatParams = @{
            Headers     = @{
                "Content-Type"  = "application/json"
                "Authorization" = "Bearer $($AccessToken)"
            }
            Method = $Method
            URI = $URI
            ErrorAction = "SilentlyContinue"
            #StatusCodeVariable = "scv"
        }

        #If method requires body, add body to splat
        If($Method -in ('PUT','PATCH','POST')){

            $graphSplatParams["Body"] = $Body

        }

        #Return API call result to script
        $MSGraphResult = Invoke-RestMethod @graphSplatParams

        #Return status code variable to script
        Return $SCV, $MSGraphResult

    }

    #Gather Autopilot details
    $session = New-CimSession
    $serial = (Get-CimInstance -CimSession $session -Class Win32_BIOS).SerialNumber
    $devDetail = (Get-CimInstance -CimSession $session -Namespace root/cimv2/mdm/dmmap -Class MDM_DevDetail_Ext01 -Filter "InstanceID='Ext' AND ParentID='./DevDetail'")
    $hash = $devDetail.DeviceHardwareData

    #Create required variables
    #The following example will update the management name of the device at the following URI
    $URI = "https://graph.microsoft.com/beta/deviceManagement/importedWindowsAutopilotDeviceIdentities"
    $Body = @{ "serialNumber" = "$serial"; "hardwareIdentifier" = "$hash" } | ConvertTo-Json
    $Method = "POST"

    Try{

        #Call Invoke-MsGraphCall
        $MSGraphCall = Invoke-MsGraphCall -AccessToken $AccessToken -URI $URI -Method $Method -Body $Body

    } Catch {

        Write-Output "An error occurred:"
        Write-Output $_
        Exit 1

    }

    If($MSGraphCall){

        Write-Output $MSGraphCall

        # Add a "HWID" folder under the C drive when the script has run
        New-Item -ItemType Directory -Path "C:\HWID" -Force

        Exit 0
    }

} 
finally {
    # This code will be executed regardless of whether an error occurred or if the script completed successfully
    # Reset the execution policy to its default state
    Set-ExecutionPolicy Default -Scope Process -Force
}
