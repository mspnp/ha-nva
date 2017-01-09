param(
  [Parameter(Mandatory=$true)]
  $SubscriptionId,
  [Parameter(Mandatory=$false)]
  $Location = "West US 2",
  [Parameter(Mandatory=$false)]
  $ResourceGroupName = "ha-nva-rg"
)

# Login to Azure and select your subscription
Login-AzureRmAccount -SubscriptionId $SubscriptionId | Out-Null

$pip = Get-AzureRmPublicIpAddress -Name ha-nva-pip -ResourceGroupName $ResourceGroupName

$nic1 = Get-AzureRmNetworkInterface -ResourceGroupName $ResourceGroupName -Name ha-nva-vm2-nic1
$nic1.IpConfigurations[0].PublicIpAddress = $null
$nic1 | Set-AzureRmNetworkInterface

$nic2 = Get-AzureRmNetworkInterface -ResourceGroupName $ResourceGroupName -Name ha-nva-vm1-nic1
$nic2.IpConfigurations[0].PublicIpAddress = $pip
$nic2 | Set-AzureRmNetworkInterface

$rt = Get-AzureRmRouteTable -ResourceGroupName $ResourceGroupName -Name ha-nva-udr
$route = Get-AzureRmRouteConfig -RouteTable $rt -Name default
$route.NextHopIpAddress="10.0.0.68"
Set-AzureRmRouteConfig -Name $route.Name -RouteTable $rt -AddressPrefix $route.AddressPrefix -NextHopType $route.NextHopType -NextHopIpAddress $route.NextHopIpAddress
Set-AzureRmRouteTable -RouteTable $rt