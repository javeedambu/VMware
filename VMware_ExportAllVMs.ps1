Clear-Host

# All vCenters
$AllVcenters = "vcenter1"

# Connect to vCenter
#Connect-VIServer "vcenter1"

# Initialise variable
$report = @()

# Define a variables to check script progress
$i=0; $j=0; $k=0


foreach ($vCenter in $AllVcenters) {
    # Connect to vCenter
    Connect-VIServer $vCenter

    # Counter for progress bar
    $i = $i+1
    Write-Progress -Id 1 -Activity Updating -Status 'Progress->' -PercentComplete ($i/$AllVcenters.Count*100) -CurrentOperation "Scanning vCenter: $($vCenter)"
    Write-Host "Search the vCenter : $($vCenter)"

    # Extract all Clusters
    $AllClusters = Get-Cluster | Sort-Object Name

    foreach ($cluster in $AllClusters) {

        # Counter for progress bar
        $j = $j+1
        Write-Progress -Id 2 -Activity Updating -Status 'Progress->->' -PercentComplete ($i/$AllClusters.Count*100) -CurrentOperation "Scanning Cluster: $($cluster.Name)"
        Write-Host "Search the Cluster : $($cluster.Name)"

        $AllVms = Get-VM -Location $cluster -Server $vCenter | Get-View | Sort-Object Name

        foreach ($vm in $AllVms){
            # Counter for progress bar
            $k = $k+1
            Write-Progress -Id 3 -Activity Updating -Status 'Progress->->->' -PercentComplete ($i/$AllVms.Count*100) -CurrentOperation "Scanning VM: $($vm.Name)"
            Write-Host "Gathering VM Info : $($vm.Name)"

            # Extrat PortGroupKeys for the VMs NIC
            $portGroupKeys = ((($vm.Config.Hardware.Device) | where {$_.gettype().BaseType -like "*net*" }).backing.port.PortGroupKey)
            
            $vmVLans = foreach ($portGroupKey in $portGroupKeys){
                ((Get-View -ViewType DistributedVirtualPortgroup -Property Config -Server $vCenter `
                | Where-Object {$_.Config.Key -eq $portGroupKey}).config.DefaultPortConfig.Vlan.VlanId) `
                | foreach {
                    if ($_ -match "\d+") { $_} Else {"$($_.start)-$($_.end)"}
                }
            }

            # Add VM info to the Report
            $report += [PSCustomObject]@{
                vCenter = $vCenter
                Cluster = $cluster
                Name = $vm.Name
                PowerState =$vm.Runtime.PowerState
                Hostname = $vm.Guest.HostName
                IPAddress = ($vm.Guest.Net.ipconfig.IpAddress | ? {$_.Ipaddress -notmatch ":" -and $_.Ipaddress -notlike "" } | % {"$($_.Ipaddress) /$($_.Prefixlength)"}) -join ", `n"
                DNSIPAddress = ($vm.Guest.Net.DNSConfig.IpAddress | ?{$_ -notmatch ":" -and  $_ -notlike ''}) -join ", `n"
                OS = $vm.Config.GuestFullName
                CPUs = $vm.Summary.Config.NumCpu
                RAM_GB = $vm.Summary.Config.MemorySizeMB/1024
                NICs = $vm.Summary.Config.NumEthernetCards
                #VLANs =(Get-View -ViewType DistributedVirtualPortgroup -Property Config -Server $vCenter | Where-Object {$_.Config.Key -eq (($vm.Config.Hardware.Device | ? {$_.gettype().Name -like "*net*" }).backing.port.PortGroupKey)}).config.DefaultPortConfig.Vlan.VlanId -join ", "
                VLANs = $vmVLans -join ", `n"
                Disks = $vm.Layout.Disk.Count
                Provisioned_Disks = ($vm.Config.Hardware.Device | Where{$_.GetType().Name -eq 'VirtualDisk'} | %{"$($_.CapacityInKB/1MB)GB"}) -join ", `n"
                TotalDisks_GB = [math]::Round(($vm.Summary.Storage.Committed + $vm.Summary.Storage.Uncommitted)/1GB)
                DrivePartitions = ($vm.GUest.Disk | sort DiskPath | %{"$($_.DiskPath) $([math]::Round($_.Capacity/1GB)) GB"}) -join ", `n"
                VMToolStatuse = $vm.Guest.ToolsStatus
                VMToolVersion = $vm.Guest.ToolsVersion
            }
            
        } # End AllVMs loop
        $k = 0
    } # End AllClusters loop
    $j = 0
   # Disconnect-VIServer $vCenter -Confirm:$false -ErrorAction SilentlyContinue
} # End AllVcenters Loop
$i = 0

$report | Export-Csv ".\VMWare_VMs_$(Get-Date -format yyyy-MM-dd-HHmmss).csv" -NoTypeInformation


