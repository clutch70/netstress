########################################################################
#
#	Script Title: netstress.ps1
#	Author: Brennan Custard
#	Date: 9/4/2022
#	Description: This script simulates network activity from a
#	workstation. It will copy to and from a specified shared folder,
#   if one is provided and perform some basic validation on returned
#   data from URI configured in targets.json. targets-template.json
#   is used if targets.json cannot be found.
#
#
#
########################################################################

########################################################################



param ($sharedFolder="none", $durationMinutes=1, [Switch]$Verbose=$False, [Switch]$updateFiles, $testSite="https://www.google.com", [Switch]$getSiteContent)

$templateTargets = "targets-template.json"
$targetsFile = "targets.json"
IF (!($sharedFolder -eq 'none'))
{
    IF (Test-Path $PSScriptRoot\files)
    {
        $files = Get-ChildItem $PSScriptRoot\files
    }ELSE
    {
        $i = New-Item -Path $env:TEMP\files -ItemType Directory -Force
        Invoke-WebRequest -UseBasicParsing -Uri https://github.com/clutch70/netstress/raw/master/files/book.xlsx -OutFile $env:TEMP\files\book.xlsx
        Invoke-WebRequest -UseBasicParsing -Uri https://github.com/clutch70/netstress/raw/master/files/book2.xlsx -OutFile $env:TEMP\files\book2.xlsx
        Invoke-WebRequest -UseBasicParsing -Uri https://github.com/clutch70/netstress/raw/master/files/lorem.docx -OutFile $env:TEMP\files\lorem.docx
        Invoke-WebRequest -UseBasicParsing -Uri https://github.com/clutch70/netstress/raw/master/files/lorem2-Copy.docxx -OutFile $env:TEMP\files\lorem2-Copy.docxx
        Invoke-WebRequest -UseBasicParsing -Uri https://github.com/clutch70/netstress/raw/master/files/lorem2.docx -OutFile $env:TEMP\files\lorem2.docx
        Invoke-WebRequest -UseBasicParsing -Uri https://github.com/clutch70/netstress/raw/master/files/new.txt -OutFile $env:TEMP\files\new.txt
        $files = Get-ChildItem $env:TEMP\files
    }

}

$durationInteger = $durationMinutes
$durationMinutes = New-TimeSpan -Minutes $durationMinutes
IF (Test-Path -Path $PSScriptRoot\$targetsFile)
{
    $targets = Get-Content -raw $PSScriptRoot\$targetsFile | ConvertFrom-Json
}ELSE{
    Try{
        (Invoke-WebRequest -UseBasicParsing -Uri https://raw.githubusercontent.com/clutch70/netstress/master/targets-template.json).content | Out-File $env:TEMP\targets-template-test.json -ErrorAction Stop
    }catch{
        Write-Output "Failed to stage targets-template.json!!! Create your own targets.json in the same folder as the script or troubleshoot downloading of targets-template.json."
        exit
    }

    $targets = Get-Content -raw $env:TEMP\targets-template-test.json | ConvertFrom-Json
}
#$targets = Get-Content -raw $PSScriptRoot\$targetsFile | ConvertFrom-Json
$totalShareAttempts = 0
$totalSiteAttempts = 0
$ErrorActionPreference = 'SilentlyContinue'

Function updateFiles
{
    param($targets)
    foreach ($file in $files.name)
    {
        $targets = Get-Content -raw $PSScriptRoot\targets.json | ConvertFrom-Json
        IF (!($file -in $targets.files.fileName))
        {
            Write-Output "Found file $file not in targets.json"



            $block = "" | Select fileName,copyUpSuccess,copyUpFailure,copyDownSuccess,copyDownFailure
            $block.fileName = $file
            $block.copyDownFailure = 0
            $block.copyDownSuccess = 0
            $block.copyUpFailure = 0
            $block.copyUpSuccess = 0

            $targets.files += $block
            IF ($Verbose)
            {
                Write-Output "Starting with targets list $targets"
                Write-Output "Adding $block"
                Write-Output "New targets is $targets"
            }
            $targets | ConvertTo-Json -depth 100 | Out-File $PSScriptRoot\targets.json -Force -Encoding ascii
        }
    }
    foreach ($i in $targets.files)
    {
        IF (!($i.fileName -in $files.name))
        {
            $targetFileName = $i.fileName
            Write-Output "Found file $targetFileName in json that is not in the source directory."
            #$targets.files[i].PSObject.Properties.Remove()
            #$targets | ConvertTo-Json -depth 100 | Out-File $PSScriptRoot\targetsnew.json -Force -Encoding ascii
        }
    }

    Write-Output "targets.json updated"
}

Function copyFilesUp
{
    #Write-Output "starting copyFilesUp"
    param($targets)

    foreach ($i in $targets.files)
    {

        #Write-Output "working through this record"
        #$i
        $file = $i.fileName
        #$file
        #Write-Output "$PSScriptRoot\files\$file"
        Try{
            Copy-Item -Path "$PSScriptRoot\files\$file" -Destination $sharedFolder -Force -ErrorAction Stop
            $i.copyUpSuccess = $i.copyUpSuccess + 1
        }catch{
            $exception = $_
            $i.copyUpFailure = $i.copyUpFailure + 1
        }

    }
}

Function copyFilesDown
{
    param($targets)

    foreach ($i in $targets.files)
    {

        $file = $i.fileName
        Try{
            Copy-Item $sharedFolder\$file $env:TEMP -Force -ErrorAction Stop
            $i.copyDownSuccess = $i.copyDownSuccess + 1
        }catch{
            $exception = $_
            $i.copyDownFailure = $i.copyDownFailure + 1
        }

    }
}
Function removeFiles
{
    param($targets)
    foreach ($i in $targets.files)
    {
        $file = $i.fileName
        Remove-Item $sharedFolder\$file -Force
        Remove-Item $env:TEMP\$file -Force
    }
}
Function testSites{
    param($targets)
    #$percent = (($remaining / $durationInteger) * 100)
    #Write-Output ([int]$durationMinutes - [int]$remaining) / $durationInteger
    #$remaining
    #$durationMinutes
    #Write-Output "Percent complete is $percent"

    #iterate through each site definition
    foreach ($i in $targets.sites)
    {
        #Write-Progress -Activity Break -Status "$remaining seconds remaining..." -SecondsRemaining $remaining
        #$done = $false
        IF ($verbose)
        {
            Write-Output "Trying" + $i.URI
            Write-Output "Current success count is " $i.success
        }
        # This actually executes the HTTP test
        $req = Invoke-WebRequest -UseBasicParsing -URI $i.URI -UserAgent ([Microsoft.PowerShell.Commands.PSUserAgent]::FireFox)

        IF ($verbose)
        {
            Write-Output "Checking collected content against stored content"
            Write-Output "showing stored content"
            $i.goodContent
            Write-Output "showing collected content"
            $req
        }
        # Check if the data we got contains a defined excerpt
        IF ($req.content -like "*" + $i.goodContent + "*")
        {
            IF ($verbose)
            {
                Write-Output "Got good content for " $i.URI
            }
            $i.success = $i.success + 1
            #$done = $True This was stupid
        }
        ELSE
        {
            # Maybe its an exact match
            IF ($req.content -eq $goodContent)
            {
                IF ($verbose)
                {
                    Write-Output "Got good content for " $i.URI
                }
                $i.success = $i.success + 1
                #$done = $True
            }
            ELSE{
                # If its Perch00 just accept an HTTP200
                IF (($req.statusCode -eq 200) -and ($i.siteName -eq "Perch00"))
                {
                    IF ($verbose)
                    {
                        Write-Output "Got good status code for " $i.URI
                    }
                    $i.success = $i.success + 1
                }
                ELSE{
                    $i.failure = $i.failure + 1
                }

        }
        }

    }
}

Function reportFiles
{
    param($targets,$durationInteger)
    Write-Output "`n"
    Write-Output "======================================="
    Write-Output "   DISPLAYING SMB COPY TEST RESULTS"
    Write-Output "======================================="
    foreach ($i in $targets.files)
    {
        $name = $i.fileName
        $copyUpSuccess = $i.copyUpSuccess
        $copyUpFailure = $i.copyUpFailure
        $copyDownSuccess = $i.copyDownSuccess
        $copyDownFailure = $i.copyDownFailure
        $i.fileName
        $copyUpAttempts = $copyUpSuccess + $copyUpfailure
        $copyDownAttempts = $copyDownSuccess + $copyDownFailure
        IF ($Verbose)
        {
            Write-Output "Successful Send: $copyUpSuccess"
            Write-Output "Failed Send: $copyUpFailure"
            Write-Output "Successful Receive: $copyDownSuccess"
            Write-Output "Failed Receive: $copyDownFailure"
            Write-Output "Number of Copy Up Attempts: $copyUpAttempts"
            Write-Output "Number of Copy Down Attempts: $copyDownAttempts"
        }
        $copyUpRate = ($copyUpSuccess / $copyUpAttempts) * 100
        $copyDownRate = ($copyDownSuccess / $copyDownAttempts) * 100
        Write-Output "File Share Send Success Rate: $copyUpRate%"
        Write-Output "File Share Receive Success Rate: $copyDownRate%"
        $totalShareAttempts = $copyUpAttempts + $copyDownAttempts
        Write-Output "Total number of attempts: $totalShareAttempts"
        Write-Output "`n"
        Write-Output 'Ran for $durationInteger minutes.'
        Write-Output "`n"
    }
}

Function reportSites
{
    param($targets,$durationInteger)
        Write-Output "`n"
    Write-Output "======================================="
    Write-Output "     DISPLAYING HTTP TEST RESULTS"
    Write-Output "======================================="
    foreach ($i in $targets.sites)
    {
        $i.siteName
        $success = $i.success
        $failure = $i.failure

        $attempts = $success + $failure
        IF ($Verbose)
        {
            Write-Output "Successful Access: $success"
            Write-Output "Failed Access: $failure"
            Write-Output "Number of attempts: $attempts"
        }
        $rate = ($success / $attempts) * 100
        Write-Output "Site Access Success Rate: $rate%"
        Write-Output "Total number of attempts: $attempts"
        Write-Output "`n"
        Write-Output 'Ran for $durationInteger minutes.'
        Write-Output "`n"
    }
}

Function getTotal
{
    param([int]$success,[int]$failure)
    return $success + $failure
}

IF ($updateFiles)
{
    updateFiles($targets)
    exit
}

IF ($getSiteContent)
{
    $req = Invoke-WebRequest -UseBasicParsing 
}

Function webLoop
{
    param($targets)
    while ($sw.elapsed -lt $durationMinutes)
{

    testSites($targets)
    return $targets
}
}

$sw = [Diagnostics.stopwatch]::StartNew()
Write-Output "Running..."
#$webJob = Start-Job -ScriptBlock {webLoop($targets)}
while ($sw.elapsed -lt $durationMinutes)
{
    IF (!($sharedFolder -eq "none"))
    {
        copyFilesUp($targets)
        copyFilesDown($targets)
        removeFiles($targets)
    }
    testSites($targets)
}
#start-sleep 5 -Seconds

#$results = Receive-Job -Job $webJob
#$results

IF (!($sharedFolder -eq "none"))
{
    reportFiles($targets,$durationInteger)
}
reportSites($targets,$durationInteger)


