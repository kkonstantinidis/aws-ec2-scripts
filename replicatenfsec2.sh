#Script configec2.sh AS WELL AS COMPILATION AND SPLITTING OF TERASORT should run first. See comments there
#Project directory should be located under ~/EC2_WORKSPACE on the master
#Comment the NFS alternative code and uncomment the NFS code if you will be using NFS

#Read the AWS parameters of your cluster from file lines
username=$(sed '5!d' "awsconf.txt")
masterHostname=$(sed '6!d' "awsconf.txt")
slavePrefix=$(sed '7!d' "awsconf.txt")
rootname=$(sed '8!d' "awsconf.txt")

#Used for imposing the limit
masterNetworkInterface="ens3"; #r3.large, x1e.2xlarge
#masterNetworkInterface="ens5"; #r5d.2xlarge
slaveNetworkInterface="eth0"; #m3.large, m1.medium
#slaveNetworkInterface="ens3"; #r3.large, c3.large, r4.2xlarge, m4.large
#slaveNetworkInterface="ens5"; #r5d.2xlarge


aws ec2 describe-instances --query "Reservations[*].Instances[*].[Tags]" --output=text | grep -vwE "None" | grep -E $slavePrefix | sed 's/Name\t//g' | grep -v -e '^[[:space:]]*$' | sort --version-sort > 'mpi_slaves_tags.txt';

#Exit if not enough arguments are given. $# returns the number of arguments
if [ $# -lt 3 ]; then
    echo "You have not provided enough arguments.";
    exit 1;
fi

#echo "Enter the project folder under NFS you want to replicate: "
#echo "Enter the project folder under ~/EC2_WORKSPACE you want to replicate: "
#read project
project=$1

#read -p "Do you want to delete existing splits at slaves (y/n)? Splits in master WON'T be deleted: " deleteSplits
deleteSplits=$2

#read -p "Set the desired rate limit for master/slaves in Mbps (0: unlimited): " limit
limit=$3

#read -p "Set the desired MTU size in bytes (0: default = 9001): " mtu

##Replicate project folder (NFS) locally at master. We won't delete existing files, only any extra files that the user might have created later and are not in source, rsync will update changed files.
#ssh $username@$masterHostname "mkdir -p EC2_WORKSPACE/$project && rsync --delete -avzh /EC2_NFS/$project/* EC2_WORKSPACE/$project"

#Replicate at each slave
while read line
do

#### 1ST WAY TO DO IT (NFS) ###
#    #Remove previous folders and create new ones based on user answer. rsync won't delete existing files, only any extra files that the user might have created later and are not in source and will update changed files.
#if [ "$deleteSplits" = "y" ]; then
#    ssh -n $username@$masterHostname "ssh -t $username@$line << 'EOF'
#rm -rf EC2_WORKSPACE/$project InputUSC InputISU OutputUSC OutputISU PartitionUSC PartitionISU
#mkdir -p EC2_WORKSPACE/$project InputUSC InputISU OutputUSC OutputISU PartitionUSC PartitionISU
#rsync --delete -avzh /EC2_NFS/$project/* EC2_WORKSPACE/$project
#EOF"
#else
#    ssh -n $username@$masterHostname "ssh -t $username@$line << 'EOF'
#rm -rf EC2_WORKSPACE/$project OutputUSC OutputISU PartitionUSC PartitionISU
#mkdir -p EC2_WORKSPACE/$project InputUSC InputISU OutputUSC OutputISU PartitionUSC PartitionISU
#rsync --delete -avzh /EC2_NFS/$project/* EC2_WORKSPACE/$project
#EOF"
#fi


### 2ND WAY TO DO IT (NFS) ### 
#Remove previous folders and create new ones. We won't delete existing files, only any extra files that the user might have created later and are not in source, rsync will update changed files.
#if [ "$deleteSplits" = "y" ]; then
#    ssh -n $username@$masterHostname "ssh -t -t $username@$line "rm -rf InputUSC InputISU OutputUSC OutputISU PartitionUSC PartitionISU""
#    ssh -n $username@$masterHostname "ssh -t -t $username@$line "mkdir -p EC2_WORKSPACE/$project InputUSC InputISU OutputUSC OutputISU PartitionUSC PartitionISU""
#else
#    ssh -n $username@$masterHostname "ssh -t -t $username@$line "rm -rf OutputUSC OutputISU PartitionUSC PartitionISU""
#    ssh -n $username@$masterHostname "ssh -t -t $username@$line "mkdir -p EC2_WORKSPACE/$project InputUSC InputISU OutputUSC OutputISU PartitionUSC PartitionISU""  
#fi

#    #Copy everything from NFS but the data which is supposed to be sent later in the form of splits
#    ssh -n $username@$masterHostname "ssh -t -t $username@$line "rsync --delete -avzh /EC2_NFS/$project/* EC2_WORKSPACE/$project""


### 3RD WAY TO DO IT (NFS), also see https://unix.stackexchange.com/questions/381974/multiple-commands-during-an-ssh-inside-an-ssh-session/381979#381979 ###
#if [ "$deleteSplits" = "y" ]; then
#    ssh -n $username@$masterHostname "ssh -t -t $username@$line \"rm -rf InputUSC InputISU OutputUSC OutputISU PartitionUSC PartitionISU; mkdir -p EC2_WORKSPACE/$project InputUSC InputISU OutputUSC OutputISU PartitionUSC PartitionISU; rsync --delete -avzh /EC2_NFS/$project/* EC2_WORKSPACE/$project\""
#else
#    ssh -n $username@$masterHostname "ssh -t -t $username@$line \"rm -rf OutputUSC OutputISU PartitionUSC PartitionISU; mkdir -p EC2_WORKSPACE/$project InputUSC InputISU OutputUSC OutputISU PartitionUSC PartitionISU; rsync --delete -avzh /EC2_NFS/$project/* EC2_WORKSPACE/$project\""
#fi


### 4TH WAY TO DO IT (NON-NFS), also see https://unix.stackexchange.com/questions/381974/multiple-commands-during-an-ssh-inside-an-ssh-session/381979#381979 ###
if [ "$deleteSplits" = "y" ]; then
    ssh -n $username@$masterHostname "ssh -t -t $username@$line \"rm -rf InputUSC InputISU OutputUSC OutputISU PartitionUSC PartitionISU; mkdir -p EC2_WORKSPACE/$project InputUSC InputISU OutputUSC OutputISU PartitionUSC PartitionISU\"; rsync --delete -avzhe ssh ~/EC2_WORKSPACE/$project/* $username@$line:~/EC2_WORKSPACE/$project"
else
    ssh -n $username@$masterHostname "ssh -t -t $username@$line \"rm -rf OutputUSC OutputISU PartitionUSC PartitionISU; mkdir -p EC2_WORKSPACE/$project InputUSC InputISU OutputUSC OutputISU PartitionUSC PartitionISU\"; rsync --delete -avzhe ssh ~/EC2_WORKSPACE/$project/* $username@$line:~/EC2_WORKSPACE/$project"
fi


#Rate limit in slaves
if [ "$limit" -ne "0" ]; then

    #Delete any previous rule and add a new one imposing 100Mbps max rate. Below 600mbit is an estimate of the current rate and 100mbit is the new limit.
    ssh -n $username@$masterHostname "ssh $rootname@$line \"tc qdisc del dev $slaveNetworkInterface root; tc qdisc add dev $slaveNetworkInterface root handle 1: cbq avpkt 1000 bandwidth 600mbit; tc class add dev $slaveNetworkInterface parent 1: classid 1:1 cbq rate "$limit"mbit allot 1500 prio 5 bounded isolated; tc filter add dev $slaveNetworkInterface parent 1: protocol ip prio 16 u32 match ip dst 0.0.0.0/0 flowid 1:1
\""

else

    #Delete the rule
    ssh -n $username@$masterHostname "ssh $rootname@$line \"tc qdisc del dev $slaveNetworkInterface root\""

fi

###MTU size in slaves
##if [ "$mtu" -ne "0" ]; then

##    #Delete any previous rule and add a new one imposing 100Mbps max rate. Below 600mbit is an estimate of the current rate and 100mbit is the new limit.
##    ssh -n $username@$masterHostname "ssh $rootname@$line \"sudo ip link set dev $slaveNetworkInterface mtu $mtu\""

###else

##    #Reset to 9001 bytes (jumbo frames)
##    ssh -n $username@$masterHostname "ssh $rootname@$line \"sudo ip link set dev $slaveNetworkInterface mtu 9001\""

##fi

done < mpi_slaves_tags.txt 

#Rate limit in master
if [ "$limit" -ne "0" ]; then
    ssh -n $rootname@$masterHostname "tc qdisc del dev $masterNetworkInterface root; tc qdisc add dev $masterNetworkInterface root handle 1: cbq avpkt 1000 bandwidth 600mbit; tc class add dev $masterNetworkInterface parent 1: classid 1:1 cbq rate "$limit"mbit allot 1500 prio 5 bounded isolated; tc filter add dev $masterNetworkInterface parent 1: protocol ip prio 16 u32 match ip dst 0.0.0.0/0 flowid 1:1
"
else
    ssh -n $rootname@$masterHostname "tc qdisc del dev $masterNetworkInterface root"
fi

##MTU size in master
##if [ "$mtu" -ne "0" ]; then
##    ssh -n $rootname@$masterHostname "sudo ip link set dev $masterNetworkInterface mtu $mtu"
##else
##    ssh -n $rootname@$masterHostname "sudo ip link set dev $masterNetworkInterface mtu 9001"
##fi


#Done
rm mpi_slaves_tags.txt
