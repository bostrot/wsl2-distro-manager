<#

Copyright https://github.com/MattiasC85/Scripts/blob/master/OSD/Download-AppxFromStore.ps1

#>

Param (
   [Parameter(Mandatory=$True)]
   [string] $StoreURL
   )

#

if ($StoreURL.EndsWith("/"))
{
    #write-host "Ends with '/'"
    $StoreURL=$StoreURL.Remove($StoreUrl.Length-1,1)
}

$wchttp=[System.Net.WebClient]::new()
$URI = "https://store.rg-adguard.net/api/GetFiles"
$myParameters = "type=url&url=$($StoreURL)"
#&ring=Retail&lang=sv-SE"

$wchttp.Headers[[System.Net.HttpRequestHeader]::ContentType]="application/x-www-form-urlencoded"
$HtmlResult = $wchttp.UploadString($URI, $myParameters)

$Start=$HtmlResult.IndexOf("<p>The links were successfully received from the Microsoft Store server.</p>")
#write-host $start

if ($Start -eq -1)
{
    write-host "Could not get the links, please check the StoreURL."
    exit 1
}

$TableEnd=($HtmlResult.LastIndexOf("</table>")+8)


$SemiCleaned=$HtmlResult.Substring($start,$TableEnd-$start)

#https://stackoverflow.com/questions/46307976/unable-to-use-ihtmldocument2
$newHtml=New-Object -ComObject "HTMLFile"
try {
    # This works in PowerShell with Office installed
    $newHtml.IHTMLDocument2_write($SemiCleaned)
}
catch {
    # This works when Office is not installed    
    $src = [System.Text.Encoding]::Unicode.GetBytes($SemiCleaned)
    $newHtml.write($src)
}

$ToDownload=$newHtml.getElementsByTagName("a") | Select-Object textContent, href

$SavePathRoot=$([System.Environment]::ExpandEnvironmentVariables("$SavePathRoot"))

$LastFrontSlash=$StoreURL.LastIndexOf("/")
$ProductID=$StoreURL.Substring($LastFrontSlash+1,$StoreURL.Length-$LastFrontSlash-1)

if ([regex]::IsMatch("$SavePathRoot\$ProductID","([,!@?#$%^&*()\[\]]+|\\\.\.|\\\\\.|\.\.\\\|\.\\\|\.\.\/|\.\/|\/\.\.|\/\.|;|(?<![A-Za-z]):)|^\w+:(\w|.*:)"))
{
    write-host "Invalid characters in path"$SavePathRoot\$ProductID""
    exit 1
}

Foreach ($Download in $ToDownload)
{
    Write-host "Name:$($Download.textContent)"
}
exit 0