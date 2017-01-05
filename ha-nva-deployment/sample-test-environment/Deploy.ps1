#
# Deploy_ReferenceArchitecture.ps1
#
param(
  [Parameter(Mandatory=$true)]
  $SubscriptionId,
  [Parameter(Mandatory=$false)]
  $Location = "West US 2"
)

$ErrorActionPreference = "Stop"

$buildingBlocksRootUriString = $env:TEMPLATE_ROOT_URI
if ($buildingBlocksRootUriString -eq $null) {
  $buildingBlocksRootUriString = "https://raw.githubusercontent.com/mspnp/template-building-blocks/master/"
}

if (![System.Uri]::IsWellFormedUriString($buildingBlocksRootUriString, [System.UriKind]::Absolute)) {
  throw "Invalid value for TEMPLATE_ROOT_URI: $env:TEMPLATE_ROOT_URI"
}

Write-Host
Write-Host "Using $buildingBlocksRootUriString to locate templates"
Write-Host

$templateRootUri = New-Object System.Uri -ArgumentList @($buildingBlocksRootUriString)
$virtualNetworkTemplate = New-Object System.Uri -ArgumentList @($templateRootUri, "templates/buildingBlocks/vnet-n-subnet/azuredeploy.json")
$loadBalancerTemplate = New-Object System.Uri -ArgumentList @($templateRootUri, "templates/buildingBlocks/loadBalancer-backend-n-vm/azuredeploy.json")
$multiVMsTemplate = New-Object System.Uri -ArgumentList @($templateRootUri, "templates/buildingBlocks/multi-vm-n-nic-m-storage/azuredeploy.json")
$extensionTemplate = New-Object System.Uri -ArgumentList @($templateRootUri, "templates/buildingBlocks/virtualMachine-extensions/azuredeploy.json")

$virtualNetworkParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "ha-nva-vnet.parameters.json")
$webSubnetLoadBalancerAndVMsParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "ha-nva-web.parameters.json")
$mgmtSubnetVMsParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "ha-nva-mgmt.parameters.json")
$nvaVMsParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "ha-nva-vms.parameters.json")
$extensionVMsParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "ha-nva-extension.parameters.json")

$networkResourceGroupName = "ha-nva-rg"

# Login to Azure and select your subscription
Login-AzureRmAccount -SubscriptionId $SubscriptionId | Out-Null

# Create the resource group
$networkResourceGroup = New-AzureRmResourceGroup -Name $networkResourceGroupName -Location $Location

Write-Host "Deploying virtual network..."
New-AzureRmResourceGroupDeployment -Name "ha-vnet-deployment" -ResourceGroupName $networkResourceGroup.ResourceGroupName `
    -TemplateUri $virtualNetworkTemplate.AbsoluteUri -TemplateParameterFile $virtualNetworkParametersFile

Write-Host "Deploying load balancer and virtual machines in web subnet..."
New-AzureRmResourceGroupDeployment -Name "ha-web-lb-vms-deployment" -ResourceGroupName $networkResourceGroup.ResourceGroupName `
    -TemplateUri $loadBalancerTemplate.AbsoluteUri -TemplateParameterFile $webSubnetLoadBalancerAndVMsParametersFile

Write-Host "Deploying jumpbox in mgmt subnet..."
New-AzureRmResourceGroupDeployment -Name "ha-mgmt-vms-deployment" -ResourceGroupName $networkResourceGroup.ResourceGroupName `
    -TemplateUri $multiVMsTemplate.AbsoluteUri -TemplateParameterFile $mgmtSubnetVMsParametersFile

Write-Host "Deploying generic nvas..."
New-AzureRmResourceGroupDeployment -Name "ha-nva-vms-deployment" -ResourceGroupName $networkResourceGroup.ResourceGroupName `
    -TemplateUri $multiVMsTemplate.AbsoluteUri -TemplateParameterFile $nvaVMsParametersFile

Write-Host "Deploying public IP..."
$pip = New-AzureRmPublicIpAddress -Name ha-nva-pip -ResourceGroupName $networkResourceGroup.ResourceGroupName -Location $Location -AllocationMethod Static
$nic = Get-AzureRmNetworkInterface -Name ha-nva-vm1-nic1 -ResourceGroupName $networkResourceGroup.ResourceGroupName 
$nic.IpConfigurations[0].PublicIpAddress = $pip
Set-AzureRmNetworkInterface -NetworkInterface $nic

Write-Host "Deploying UDRs..."
$nic2 = Get-AzureRmNetworkInterface -Name ha-nva-vm1-nic2 -ResourceGroupName $networkResourceGroup.ResourceGroupName 
$vnet = Get-AzureRmVirtualNetwork -Name ha-nva-vnet -ResourceGroupName $networkResourceGroup.ResourceGroupName
$route = New-AzureRmRouteConfig -Name default -AddressPrefix 0.0.0.0/0 -NextHopType VirtualAppliance -NextHopIpAddress $nic2.IpConfigurations[0].PrivateIpAddress
$udr = New-AzureRmRouteTable -Name ha-nva-udr -ResourceGroupName $networkResourceGroup.ResourceGroupName -Location $Location -Route $route
foreach($subnet in $vnet.Subnets)
{
    if($subnet.Name -eq "dmz-internal") { 
        $subnet.RouteTable = $udr
    }
}

$route2 = New-AzureRmRouteConfig -Name web -AddressPrefix 10.0.1.0/24 -NextHopType VirtualAppliance -NextHopIpAddress $nic2.IpConfigurations[0].PrivateIpAddress
$udr2 = New-AzureRmRouteTable -Name ha-nva-mgmt-udr -ResourceGroupName $networkResourceGroup.ResourceGroupName -Location $Location -Route $route2
foreach($subnet in $vnet.Subnets)
{
    if($subnet.Name -eq "web") { 
        $subnet.RouteTable = $udr2
    }
}
Set-AzureRmVirtualNetwork -VirtualNetwork $vnet

Write-Host "Deploying routing extension on NVA vms..."
New-AzureRmResourceGroupDeployment -Name "ha-nva-extension-deployment" -ResourceGroupName $networkResourceGroup.ResourceGroupName `
    -TemplateUri $extensionTemplate.AbsoluteUri -TemplateParameterFile $extensionVMsParametersFile